#!/usr/bin/env python3
"""Renovate PR evaluation engine — single entry point with subcommands."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def cmd_evaluate(args: argparse.Namespace) -> None:
    """Run the full evaluate pipeline."""
    from lib.common import (
        VALID_LABELS,
        build_sentinel,
        compute_fingerprint,
        embed_eval_data,
        get_ci_status,
        log,
        require_gh_auth,
        setup_logging,
    )
    from lib.render import render_report
    from lib.validate import validate_eval_data

    setup_logging()

    # Auth
    require_gh_auth()

    # Paths
    repo_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()
    artifact_dir = tempfile.mkdtemp(
        prefix=f"renovate-eval-{args.pr}.", dir=os.environ.get("TMPDIR", "/tmp")
    )
    report_dir = os.path.join(os.environ.get("TMPDIR", "/tmp"), "renovate-eval")

    keep = args.keep_artifacts

    def cleanup():
        if not keep and os.path.isdir(artifact_dir):
            shutil.rmtree(artifact_dir, ignore_errors=True)

    total_start = _now()

    try:
        _run_evaluate(
            args,
            artifact_dir,
            report_dir,
            repo_root,
            keep,
            total_start,
            VALID_LABELS,
            build_sentinel,
            compute_fingerprint,
            embed_eval_data,
            get_ci_status,
            log,
            render_report,
            validate_eval_data,
        )
    finally:
        cleanup()


def _run_evaluate(
    args,
    artifact_dir,
    report_dir,
    repo_root,
    keep,
    total_start,
    VALID_LABELS,
    build_sentinel,
    compute_fingerprint,
    embed_eval_data,
    get_ci_status,
    log,
    render_report,
    validate_eval_data,
) -> None:
    """Inner evaluate logic, wrapped in try/finally for cleanup."""
    print("=== Renovate PR Evaluation ===")
    print(f"PR: #{args.pr}")
    print(f"Mode: {args.mode}")
    print(f"Context: {args.context}")
    print(f"Evaluator: {args.evaluator_model}")
    print(f"Auditor: {args.auditor_model}")
    print()

    # Fetch PR data
    print("--- Fetching PR data ---")
    from lib.fetch_pr_data import fetch_pr_data

    fetch_pr_data(args.pr, artifact_dir)

    # Check CI (#9: wrap in try/except so CI failure doesn't crash pipeline)
    print("--- Checking CI status ---")
    from lib.check_ci import check_ci

    ci_status_file = os.path.join(artifact_dir, "ci-status.md")
    if args.mode == "post":
        try:
            exit_code = check_ci(
                args.pr,
                wait=True,
                timeout=args.ci_timeout,
                output_file=ci_status_file,
            )
            if exit_code == 2:
                log.warning("CI check timed out — continuing with unknown status")
            elif exit_code != 0:
                log.warning("Failed to fetch CI status — continuing without it")
        except Exception:
            log.warning("CI check failed — continuing without it")
    else:
        try:
            check_ci(args.pr, output_file=ci_status_file)
        except Exception:
            log.warning("CI check failed — continuing without it")

    # Evaluation loop
    from lib.evaluator import run_evaluator
    from lib.auditor import run_auditor

    max_rounds = 3
    max_validation_retries = 3
    status = "FEEDBACK"
    eval_session_id = ""
    audit_session_id = ""
    auditor_has_run = False
    total_cost = 0.0
    eval_data = None
    final_round = 0

    print()
    print("--- Starting evaluation loop ---")

    for round_num in range(1, max_rounds + 1):
        print()
        print(f"=== Round {round_num} ===")

        # --- Evaluator (with validation retry loop) ---
        eval_data_valid = False
        for validation_attempt in range(1, max_validation_retries + 1):
            eval_start = _now()
            is_retry = validation_attempt > 1
            # #4: only use revision mode when we have a session to resume
            use_revision = (is_retry and bool(eval_session_id)) or (
                round_num > 1 and auditor_has_run
            )
            print()
            if not is_retry:
                print(f"--- Evaluator (round {round_num}) ---")
            else:
                print(
                    f"--- Evaluator (round {round_num}, validation retry {validation_attempt}) ---"
                )

            try:
                eval_output = run_evaluator(
                    round_num=round_num,
                    artifact_dir=artifact_dir,
                    model=args.evaluator_model,
                    context=args.context,
                    script_dir=SCRIPT_DIR,
                    repo_root=repo_root,
                    instructions=args.instructions,
                    session_id=eval_session_id,
                    is_revision=use_revision,
                    cost_suffix=f"-a{validation_attempt}"
                    if validation_attempt > 1
                    else "",
                )
            except Exception as e:
                print(f"ERROR: Evaluator failed — {e}", file=sys.stderr)
                break
            print(f"Evaluator completed in {_now() - eval_start}s")

            # Capture session ID from first successful evaluator run
            if not eval_session_id:
                eval_session_id = eval_output.get("session_id", "")
                if eval_session_id:
                    print(f"Evaluator session: {eval_session_id}")

            # #3: load into candidate, only promote after full validation
            eval_data_path = os.path.join(artifact_dir, "eval-data.json")
            candidate = None
            validation_error = None
            if (
                not os.path.isfile(eval_data_path)
                or os.path.getsize(eval_data_path) == 0
            ):
                validation_error = "no eval-data.json produced"
            else:
                try:
                    with open(eval_data_path) as f:
                        candidate = json.load(f)
                except json.JSONDecodeError:
                    validation_error = "eval-data.json is not valid JSON"

                if not validation_error:
                    if not isinstance(candidate, dict):
                        validation_error = "eval-data.json root must be a JSON object"
                    else:
                        label = candidate.get("label", "")
                        if label not in VALID_LABELS:
                            validation_error = f"invalid label '{label}'"

                # Mechanical validation (also triggers retry)
                if not validation_error:
                    errors = validate_eval_data(candidate)
                    if errors:
                        validation_error = "; ".join(errors)

            if validation_error:
                print(
                    f"ERROR: {validation_error} (round {round_num}, attempt {validation_attempt})",
                    file=sys.stderr,
                )
                # #1/#5: save per-attempt feedback file
                fb_file = os.path.join(
                    artifact_dir,
                    f"validation-feedback-r{round_num}-a{validation_attempt}.json",
                )
                if validation_attempt < max_validation_retries and eval_session_id:
                    synthetic = {
                        "status": "FEEDBACK",
                        "issues": [
                            {
                                "section": "Output",
                                "severity": "high",
                                "description": f"Validation error: {validation_error}. Fix your eval-data.json output.",
                                "action": "Re-read the eval-data-schema.md and produce valid JSON.",
                            }
                        ],
                    }
                    with open(fb_file, "w") as f:
                        json.dump(synthetic, f, indent=2)
                    # Also write as the "current" feedback for the revision prompt
                    shutil.copy2(
                        fb_file, os.path.join(artifact_dir, "validation-feedback.json")
                    )
                continue
            else:
                eval_data = candidate  # #3: promote only after validation
                eval_data_valid = True
                # #1: clean up validation-feedback.json so it doesn't poison later rounds
                vfb = os.path.join(artifact_dir, "validation-feedback.json")
                if os.path.isfile(vfb):
                    os.remove(vfb)
                break

        if not eval_data_valid:
            # All validation retries exhausted
            break

        # Render report (no ci_status — posted comment omits it)
        report_md = render_report(eval_data)
        report_path = os.path.join(artifact_dir, "eval-report.md")
        Path(report_path).write_text(report_md)

        # Preserve per-round artifacts (#10: include evaluator output log)
        _copy_artifact(artifact_dir, "eval-data.json", f"eval-data-r{round_num}.json")
        _copy_artifact(
            artifact_dir, "eval-evidence.md", f"eval-evidence-r{round_num}.md"
        )
        _copy_artifact(artifact_dir, "eval-report.md", f"eval-report-r{round_num}.md")
        _copy_artifact(
            artifact_dir, "evaluator-output.json", f"evaluator-r{round_num}.log"
        )

        # --- Auditor ---
        audit_start = _now()
        print()
        print(f"--- Auditor (round {round_num}) ---")

        # Use round 1 prompt if auditor hasn't run yet
        auditor_round = round_num if auditor_has_run else 1

        try:
            audit_result = run_auditor(
                round_num=auditor_round,
                artifact_dir=artifact_dir,
                model=args.auditor_model,
                script_dir=SCRIPT_DIR,
                session_id=audit_session_id if auditor_has_run else "",
            )
        except Exception as e:
            print(f"ERROR: Auditor failed — {e}", file=sys.stderr)
            break
        print(f"Auditor completed in {_now() - audit_start}s")

        auditor_has_run = True

        # Capture auditor session ID from first auditor run
        if not audit_session_id:
            auditor_output_path = os.path.join(artifact_dir, "auditor-output.json")
            if os.path.isfile(auditor_output_path):
                try:
                    with open(auditor_output_path) as f:
                        aud_out = json.load(f)
                    audit_session_id = aud_out.get("session_id", "")
                    if audit_session_id:
                        print(f"Auditor session: {audit_session_id}")
                except (json.JSONDecodeError, KeyError):
                    pass

        # Validate audit result
        audit_status = audit_result.get("status", "")
        if audit_status not in ("PASS", "FEEDBACK"):
            print(f"ERROR: invalid audit status '{audit_status}'", file=sys.stderr)
            break

        # Preserve per-round audit artifacts
        _copy_artifact(
            artifact_dir, "audit-result.json", f"audit-result-r{round_num}.json"
        )
        _copy_artifact(artifact_dir, "auditor-raw.log", f"auditor-r{round_num}.log")

        status = audit_status
        final_round = round_num
        print(f"Audit status: {status}")

        if status == "FEEDBACK":
            issues = audit_result.get("issues", [])
            print(f"Issues found: {len(issues)}")
            for issue in issues:
                sev = issue.get("severity", "?")
                sec = issue.get("section", "?")
                desc = issue.get("description", "?")
                print(f"  - [{sev}] {sec}: {desc}")
        else:
            break

    # Calculate costs
    for cost_file in Path(artifact_dir).glob("*-cost-r*.json"):
        try:
            with open(cost_file) as f:
                total_cost += json.load(f).get("cost_usd", 0)
        except (json.JSONDecodeError, KeyError):
            pass

    # (#1) If no valid eval-data was ever produced, bail out
    if eval_data is None:
        print()
        print(
            "ERROR: No valid evaluation data produced after all attempts",
            file=sys.stderr,
        )
        _write_error_result(artifact_dir, total_cost)
        print()
        elapsed = _now() - total_start
        print(f"=== Evaluation failed in {elapsed}s ===")
        print(f"Total cost: ${total_cost:.2f}")
        if keep:
            print(f"Artifacts: {artifact_dir}")
        sys.exit(1)

    # Handle failed audit
    if final_round == 0:
        final_round = 1
    if status != "PASS":
        print()
        print(f"WARNING: Report did not pass audit after {final_round} round(s)")
        eval_data["label"] = "renovate:risk"
        eval_data["verdict"] = "Automated audit failed. " + eval_data.get("verdict", "")
        eval_data_path = os.path.join(artifact_dir, "eval-data.json")
        with open(eval_data_path, "w") as f:
            json.dump(eval_data, f, indent=2)

        report_md = render_report(eval_data)
        banner = (
            "> \u26a0\ufe0f **This report did not pass automated quality review.** "
            "Treat with skepticism.\n\n"
        )
        report_md = banner + report_md
        Path(os.path.join(artifact_dir, "eval-report.md")).write_text(report_md)

    # Get live CI status (injected by script, not LLM)
    ci_status = get_ci_status(args.pr)

    label = eval_data.get("label", "renovate:risk")

    # Fingerprint
    diff_path = os.path.join(artifact_dir, "pr-diff.patch")
    fingerprint = os.environ.get("EVAL_FINGERPRINT", "")
    if not fingerprint and os.path.isfile(diff_path):
        fingerprint = compute_fingerprint(diff_path)

    # Eval count
    eval_count = 1
    if os.environ.get("EVAL_TRIGGER", "manual") != "manual":
        eval_count = _get_prev_eval_count(args.pr) + 1

    # Report output
    report_md = Path(os.path.join(artifact_dir, "eval-report.md")).read_text()

    if args.mode == "dry-run":
        # #7: re-render with CI status for local display
        display_md = render_report(eval_data, ci_status=ci_status)
        if status != "PASS":
            # failed audit banner was prepended — keep it
            banner = report_md.split("\n\n", 1)[0]
            display_md = banner + "\n\n" + display_md
        print()
        print("=== Report ===")
        print(display_md)
        print()
        print("=== Metadata ===")
        metadata = {**eval_data, "ci_status": ci_status}
        print(json.dumps(metadata, indent=2))
    elif args.mode == "post":
        sentinel = build_sentinel(
            label, final_round, ci_status, eval_count, fingerprint
        )
        eval_data_with_ci = {**eval_data, "ci_status": ci_status}
        comment_body = (
            sentinel + "\n\n" + report_md + "\n\n" + embed_eval_data(eval_data_with_ci)
        )
        _post_comment(args.pr, comment_body, artifact_dir)
        _manage_labels(args.pr, label)
        print(f"Posted comment and applied labels: {label}, renovate:evaluated")

    # Persist report
    _persist_report(report_dir, args.pr, artifact_dir)

    # Write result.json
    report_file = os.path.join(report_dir, f"PR-{args.pr}.md")
    result = {
        "artifact_dir": artifact_dir,
        "report_path": report_file if os.path.isfile(report_file) else None,
        "total_cost_usd": total_cost,
        "label": label,
        "ci_status": ci_status,
        "rounds": final_round,
        "status": status,
    }
    with open(os.path.join(artifact_dir, "result.json"), "w") as f:
        json.dump(result, f, indent=2)

    # Summary
    print()
    elapsed = _now() - total_start
    print(f"=== Evaluation complete in {elapsed}s ===")
    print(f"Total cost: ${total_cost:.2f}")
    if keep:
        print(f"Artifacts: {artifact_dir}")


def cmd_status(args: argparse.Namespace) -> None:
    """Quick PR status check."""
    from lib.common import setup_logging
    from lib.pr_status import pr_status

    setup_logging()
    print(pr_status(args.pr))


def cmd_render(args: argparse.Namespace) -> None:
    """Render eval-data.json to markdown."""
    from lib.render import render_report

    with open(args.file) as f:
        eval_data = json.load(f)

    print(render_report(eval_data, ci_status=args.ci_status))


def cmd_validate(args: argparse.Namespace) -> None:
    """Validate eval-data.json."""
    from lib.validate import validate_eval_data

    with open(args.file) as f:
        eval_data = json.load(f)

    errors = validate_eval_data(eval_data)
    if errors:
        print(f"ERRORS FOUND: {len(errors)}")
        for err in errors:
            print(f"  - {err}")
        sys.exit(1)
    else:
        print("VALID: All checks passed")


def cmd_init(args: argparse.Namespace) -> None:
    """Initialize session: detect environment, list Renovate PRs."""
    from lib.common import require_gh_auth, require_tools

    require_tools("gh")
    require_gh_auth()

    repo_root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()

    plannotator = shutil.which("plannotator") is not None
    repo_config = os.path.join(repo_root, ".claude", "renovate-eval.md")
    has_repo_config = os.path.isfile(repo_config)

    # Check automerge availability
    automerge_result = subprocess.run(
        ["gh", "api", "repos/{owner}/{repo}", "--jq", ".allow_auto_merge // false"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    automerge_available = automerge_result.stdout.strip() == "true"

    # Fetch Renovate PRs
    pr_result = subprocess.run(
        [
            "gh",
            "pr",
            "list",
            "--author",
            "app/renovate",
            "--state",
            "open",
            "--json",
            "number,title,createdAt,autoMergeRequest,statusCheckRollup,labels",
            "--limit",
            "100",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if pr_result.returncode != 0:
        print("ERROR: Failed to fetch PRs", file=sys.stderr)
        sys.exit(1)

    all_prs = json.loads(pr_result.stdout)

    # Filter: no automerge OR CI failing
    prs = []
    for pr in all_prs:
        has_automerge = pr.get("autoMergeRequest") is not None
        ci_failing = any(
            c.get("status") == "COMPLETED" and c.get("conclusion") == "FAILURE"
            for c in pr.get("statusCheckRollup") or []
        )
        if not has_automerge or ci_failing:
            labels = [lbl["name"] for lbl in pr.get("labels", [])]
            eval_label = next(
                (
                    lbl
                    for lbl in labels
                    if lbl.startswith("renovate:") and lbl != "renovate:evaluated"
                ),
                None,
            )
            prs.append(
                {
                    "number": pr["number"],
                    "title": pr["title"],
                    "automerge": has_automerge,
                    "ci_failing": ci_failing,
                    "eval_label": eval_label,
                    "evaluated": "renovate:evaluated" in labels,
                }
            )

    # Sort by createdAt descending (already sorted by gh)
    output = {
        "repo_root": repo_root,
        "plannotator_available": plannotator,
        "repo_config": repo_config if has_repo_config else None,
        "automerge_available": automerge_available,
        "prs": prs,
    }
    print(json.dumps(output, indent=2))


# --- Helpers ---


def _now() -> int:
    """Return current time in seconds (monotonic-ish)."""
    import time

    return int(time.time())


def _write_error_result(artifact_dir: str, total_cost: float) -> None:
    """Write a minimal result.json for failed evaluations."""
    result = {
        "artifact_dir": artifact_dir,
        "report_path": None,
        "total_cost_usd": total_cost,
        "label": None,
        "ci_status": "unknown",
        "rounds": 0,
        "status": "ERROR",
    }
    with open(os.path.join(artifact_dir, "result.json"), "w") as f:
        json.dump(result, f, indent=2)


def _copy_artifact(artifact_dir: str, src: str, dst: str) -> None:
    """Copy artifact file if it exists."""
    src_path = os.path.join(artifact_dir, src)
    if os.path.isfile(src_path):
        shutil.copy2(src_path, os.path.join(artifact_dir, dst))


def _get_prev_eval_count(pr_number: int | str) -> int:
    """Get previous eval_count from existing sentinel comment."""
    from lib.common import parse_sentinel

    result = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{{owner}}/{{repo}}/issues/{pr_number}/comments",
            "--paginate",
            "--jq",
            '[.[] | select(.body | contains("<!-- renovate-eval-skill:"))] | last | .body',
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    body = result.stdout.strip()
    if not body or body == "null":
        return 0
    sentinel = parse_sentinel(body)
    if sentinel:
        return sentinel.get("eval_count", 0)
    return 0


def _post_comment(pr_number: int | str, comment_body: str, artifact_dir: str) -> None:
    """Post or update comment on PR."""
    repo_nwo = subprocess.run(
        ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"],
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout.strip()

    # Find existing comment
    result = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{repo_nwo}/issues/{pr_number}/comments",
            "--paginate",
            "--jq",
            '[.[] | select(.body | contains("<!-- renovate-eval-skill:"))] '
            "| last | {id, body}",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    try:
        existing = json.loads(result.stdout) if result.stdout.strip() else {}
    except json.JSONDecodeError:
        existing = {}

    comment_id = existing.get("id")
    comment_file = os.path.join(artifact_dir, "comment-body.md")
    Path(comment_file).write_text(comment_body)

    if comment_id and str(comment_id) != "null":
        print(f"Updating existing comment {comment_id}")
        subprocess.run(
            [
                "gh",
                "api",
                "--method",
                "PATCH",
                f"repos/{repo_nwo}/issues/comments/{comment_id}",
                "-F",
                f"body=@{comment_file}",
            ],
            check=True,
            timeout=30,
        )
    else:
        print("Creating new comment")
        subprocess.run(
            ["gh", "pr", "comment", str(pr_number), "--body-file", comment_file],
            check=True,
            timeout=30,
        )


def _manage_labels(pr_number: int | str, label: str) -> None:
    """Ensure labels exist and apply correct ones."""
    from lib.common import LABEL_COLORS

    # Ensure labels exist
    for name, color in LABEL_COLORS.items():
        subprocess.run(
            ["gh", "label", "create", name, "--color", color],
            capture_output=True,
            timeout=10,
        )

    # Get current labels
    result = subprocess.run(
        [
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--json",
            "labels",
            "--jq",
            '[.labels[].name] | join(",")',
        ],
        capture_output=True,
        text=True,
        timeout=10,
    )
    current = result.stdout.strip()

    edit_args = ["gh", "pr", "edit", str(pr_number)]
    for old_label in (
        "renovate:safe",
        "renovate:caution",
        "renovate:breaking",
        "renovate:risk",
    ):
        if old_label != label and old_label in current:
            edit_args.extend(["--remove-label", old_label])
    if label not in current:
        edit_args.extend(["--add-label", label])
    if "renovate:evaluated" not in current:
        edit_args.extend(["--add-label", "renovate:evaluated"])

    if len(edit_args) > 4:  # has label changes
        subprocess.run(edit_args, check=True, timeout=10)


def _persist_report(report_dir: str, pr_number: int | str, artifact_dir: str) -> None:
    """Save report to REPORT_DIR with strict permissions."""
    report_src = os.path.join(artifact_dir, "eval-report.md")
    if not os.path.isfile(report_src):
        return

    try:
        os.makedirs(report_dir, mode=0o700, exist_ok=True)
        dest = os.path.join(report_dir, f"PR-{pr_number}.md")
        shutil.copy2(report_src, dest)
        os.chmod(dest, 0o600)
        print(f"Report: {dest}")
    except OSError as e:
        print(f"WARNING: failed to persist report — {e}", file=sys.stderr)


# --- Argument parsing ---


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="renovate_eval.py",
        description="Renovate PR evaluation engine",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # evaluate
    p_eval = sub.add_parser("evaluate", help="Run evaluation pipeline")
    p_eval.add_argument("--pr", required=True, type=int)
    mode_group = p_eval.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--dry-run", dest="mode", action="store_const", const="dry-run"
    )
    mode_group.add_argument("--post", dest="mode", action="store_const", const="post")
    p_eval.set_defaults(mode="dry-run")
    p_eval.add_argument("--context", default="local", choices=["local", "ci"])
    p_eval.add_argument("--evaluator-model", default="opus")
    p_eval.add_argument("--auditor-model", default="sonnet")
    p_eval.add_argument("--ci-timeout", type=int, default=300)
    p_eval.add_argument("--instructions", default="")
    p_eval.add_argument("--keep-artifacts", action="store_true")

    # status
    p_status = sub.add_parser("status", help="Quick PR status check")
    p_status.add_argument("--pr", required=True, type=int)

    # render
    p_render = sub.add_parser("render", help="Render eval-data.json to markdown")
    p_render.add_argument("file", help="Path to eval-data.json")
    p_render.add_argument("--ci-status", default=None)

    # validate
    p_validate = sub.add_parser("validate", help="Validate eval-data.json")
    p_validate.add_argument("file", help="Path to eval-data.json")

    # init
    sub.add_parser("init", help="Initialize session")

    args = parser.parse_args()

    dispatch = {
        "evaluate": cmd_evaluate,
        "status": cmd_status,
        "render": cmd_render,
        "validate": cmd_validate,
        "init": cmd_init,
    }
    dispatch[args.command](args)


if __name__ == "__main__":
    main()
