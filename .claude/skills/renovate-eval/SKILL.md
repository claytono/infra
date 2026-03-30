---
name: renovate-eval
description:
  Use when evaluating Renovate pull requests - performs deep analysis of changes
  including bundled dependencies, security advisories, community feedback, and
  CI status to provide actionable merge recommendations
---

# Renovate PR Evaluation

**Say:** "Using renovate-eval skill." then immediately start working.

**DO NOT** explain what this skill does. **DO NOT** ask what the user wants.
**START WORKING.**

## PR Selection

**Always run init first.** This detects environment capabilities and lists PRs:

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel)/.claude/skills/renovate-eval"
python3 "$SCRIPT_DIR/renovate_eval.py" init
```

The script outputs a JSON object:

```json
{
  "repo_root": "/path/to/repo",
  "plannotator_available": true,
  "repo_config": "/path/to/repo/.claude/renovate-eval.md",
  "automerge_available": true,
  "prs": [...]
}
```

Store `plannotator_available`, `repo_config`, and `automerge_available` for
later use. If `repo_config` is non-null, read it for custom actions and repo
context.

**If user specified a PR number:** Go to Evaluate or Present mode for that PR.

**Otherwise:** Format the `prs` array into a readable table. **IMPORTANT:** Bash
tool output is collapsed in the UI and the user cannot see it. You MUST print
the table as regular text output. Sort evaluated PRs first, then unevaluated:

```text
| #  | PR    | Title                            | Status              |
|----|-------|----------------------------------|---------------------|
| 1  | #1697 | Update Helm release grafana      | 🟡 renovate:caution |
| 2  | #1689 | Update Helm release valkey       | 🟢 renovate:safe    |
| 3  | #1704 | Update prom/prometheus Docker tag |                     |
| 4  | #1700 | Update Helm release velero       | ⚠️ CI FAILING       |
```

Emoji mapping for eval_label: renovate:safe = 🟢, renovate:caution = 🟡,
renovate:breaking = 🟠, renovate:risk = 🔴. Show CI FAILING with ⚠️ if
ci_failing is true.

Then ask: "Which PR would you like to evaluate? (number or 'all')"

## Present Mode (Check for Existing Evaluation)

Before running a new evaluation, check the PR status:

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel)/.claude/skills/renovate-eval"
python3 "$SCRIPT_DIR/renovate_eval.py" status --pr "$PR"
```

If the output contains a rendered report (starts with `#`), display it
**VERBATIM**. Do NOT summarize, edit, or rephrase any part of the report. Print
it exactly as written, then show the Actions Menu. This is "present mode."

If the output is just `CI_STATUS: <status>`, there is no existing v4 evaluation.
Proceed to "evaluate mode."

## Evaluate Mode (New Evaluation)

Run the evaluation engine in dry-run mode:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
python3 "$REPO_ROOT/.claude/skills/renovate-eval/renovate_eval.py" \
    evaluate --pr "$PR" --dry-run --context local
```

The script prints the report to stdout. Display the report **VERBATIM** — do NOT
summarize, condense, paraphrase, or omit any section of the report, regardless
of how many PRs have been evaluated in this session. Print it exactly as the
script output it. Then show the Actions Menu.

## Actions Menu

**IMPORTANT: Repo config overrides skill defaults.** If
`$REPO_ROOT/.claude/renovate-eval.md` exists, read its "Actions Menu" section.
Any actions defined there MUST be included in the menu you present to the user.
The repo config is authoritative — it may add actions, modify conditions for
showing them, or change how they work.

Extract CI status from the status output or the evaluate stdout. If in present
mode, the rendered report includes CI status. If in evaluate mode, parse the
Metadata JSON block printed to stdout.

**Merge action logic** (CI-aware):

When the user selects merge, check live CI status using the check-ci script:

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel)/.claude/skills/renovate-eval"
python3 "$SCRIPT_DIR/renovate_eval.py" status --pr "$PR"
```

Then apply the appropriate merge strategy:

- **CI passing**: Merge immediately with `gh pr merge $PR --rebase`
- **CI pending + automerge available**: Use `gh pr merge $PR --auto --rebase`
  (GitHub will merge when checks pass)
- **CI pending + automerge NOT available**: Wait for CI using
  `gh pr checks $PR --required --watch`, then merge with
  `gh pr merge $PR --rebase`
- **CI failing/unknown**: Do NOT offer merge. Show "Fix CI" instead.

The `automerge_available` flag comes from init output. Read
`$REPO_ROOT/.claude/renovate-eval.md` for repo-specific merge flags (e.g.,
`--rebase`).

**Default actions (always show):**

1. **Merge** — only if CI is passing or pending (see merge logic above)
2. **Review later** — no action, move on
3. **Close** — `gh pr close $PR` (warn: Renovate will NOT reopen for this
   version)

**Default conditional actions:**

- **Fix CI** — only if CI is `"failing"` or `"unknown"`
- **View in Plannotator** — only if `plannotator_available` is `true`

**Then add any actions from `$REPO_ROOT/.claude/renovate-eval.md`.**

Print all actions as a numbered list. Wait for user selection.

## Handling Actions

- **Merge**: Follow CI-aware merge logic above.
- **Review later**: No action. If evaluating multiple PRs, move to next.
- **Close**: Warn first: "Closing tells Renovate to ignore this version
  permanently. Are you sure?" Then `gh pr close $PR`.
- **Deploy for testing**: Read `.claude/renovate-eval.md` and repo rules (e.g.,
  `.claude/rules/`) for deployment instructions specific to this repo.
- **Fix CI**: Investigate the CI failure and attempt to fix it.
- **Re-evaluate**: Run
  `python3 renovate_eval.py evaluate --pr $PR --post --context local` to
  regenerate and post updated evaluation.
- **View in Plannotator**: Open the evaluation report in plannotator's
  annotation UI. The LLM must NOT write report content to files — use shell
  commands to keep content out of the LLM's hands.

  **Present mode** — fetch the comment directly from GitHub to a temp file:

  ```bash
  REPORT_DIR="${TMPDIR:-/tmp}/renovate-eval"
  mkdir -p -m 0700 "$REPORT_DIR"
  gh pr view "$PR" --json comments --jq '
    .comments
    | map(select(.body | contains("<!-- renovate-eval-skill:")))
    | sort_by(.createdAt) | last | .body' | \
    sed '/<!-- renovate-eval-skill:/d' > "$REPORT_DIR/PR-${PR}.md"
  chmod 0600 "$REPORT_DIR/PR-${PR}.md"
  plannotator annotate "$REPORT_DIR/PR-${PR}.md"
  ```

  **Evaluate mode** — use the report file persisted by the evaluation script.
  Extract the path from the `Report:` line in output:

  ```bash
  plannotator annotate "$REPORT_PATH"
  ```

  In evaluate mode, only show this action if the script printed a `Report:` line
  (meaning the report was generated successfully).

  The command blocks until the user submits. If stdout is empty (user closed
  browser without annotating), return to the Actions Menu with no action. If
  non-empty, parse the structured markdown feedback and respond to each
  annotation. Then show the Actions Menu again.

## Multi-PR Flow

When evaluating 'all', process each PR sequentially: evaluate, show report and
actions menu, handle user selection, then move to next PR.

**IMPORTANT:** When the user asks to evaluate a different PR within the same
session (e.g., "do the next one", "evaluate #1704", or selecting another PR),
you MUST re-invoke this skill using the Skill tool. Do not continue from memory
— the skill instructions must be freshly loaded for each PR to ensure reports
are displayed verbatim. For these within-session re-invocations, skip the init
step and reuse the PR list already in context unless the user explicitly asks to
refresh it. On a new session, still run init first.
