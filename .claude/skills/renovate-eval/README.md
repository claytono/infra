# renovate-eval

AI-powered evaluation of Renovate dependency update PRs. Produces structured
reports with risk assessments, evidence documentation, and GitHub labels.

## How It Works

```text
renovate_eval.py evaluate
  ├── fetch_pr_data      # Collect PR metadata, diff, CI status
  ├── check_ci           # Check/wait for CI results
  │
  ├── Round 1: Evaluator (claude -p, opus)
  │   ├── Reads PR data, repo config, upstream release notes
  │   ├── Cross-references changes against local project config
  │   ├── Writes: eval-data.json (structured), eval-evidence.md
  │   └── Validated against JSON schema (retries on failure)
  │
  ├── Round 1: Auditor (claude -p, sonnet, no tools)
  │   ├── Reviews rendered report against quality criteria
  │   ├── Checks evidence supports claims
  │   └── Outputs: PASS or FEEDBACK with specific issues
  │
  ├── Round 2+ (if FEEDBACK): Resume evaluator session
  │   ├── Reads auditor feedback + revision.md guidelines
  │   ├── Makes targeted fixes to eval-data.json
  │   └── Auditor re-reviews (resumes its session too)
  │
  └── Output
      ├── Template renders eval-data.json → markdown report
      ├── dry-run: Print report to stdout, clean up temp files
      └── post: Comment on PR, apply labels (renovate:safe/caution/breaking/risk)
```

## Usage

### Interactive (Claude Code skill)

```text
/renovate-eval
```

Lists open Renovate PRs, evaluates selected PR, shows actions menu.

### CLI

```bash
# Dry run (prints report, cleans up)
python3 .claude/skills/renovate-eval/renovate_eval.py evaluate --pr 1234 --dry-run --context local

# Post to GitHub (comment + labels)
python3 .claude/skills/renovate-eval/renovate_eval.py evaluate --pr 1234 --post --context local

# Quick status check (live CI + existing eval)
python3 .claude/skills/renovate-eval/renovate_eval.py status --pr 1234

# Validate eval-data.json
python3 .claude/skills/renovate-eval/renovate_eval.py validate path/to/eval-data.json

# Render eval-data.json to markdown
python3 .claude/skills/renovate-eval/renovate_eval.py render path/to/eval-data.json --ci-status passing
```

### GitHub Actions

The workflow at `.github/workflows/renovate-eval.yaml` runs via
`workflow_dispatch`. It uses the composite action at
`.claude/skills/renovate-eval/action.yaml`.

## Labels

| Label                | Meaning                                      |
| -------------------- | -------------------------------------------- |
| `renovate:safe`      | No concerns, straightforward update          |
| `renovate:caution`   | Behavioral changes worth validating          |
| `renovate:breaking`  | Breaking changes, needs config rework        |
| `renovate:risk`      | Known issues, regressions, or low confidence |
| `renovate:evaluated` | PR has been evaluated (always added)         |

## Key Design Decisions

- **Structured JSON output**: The evaluator produces `eval-data.json`; a Python
  template renders the markdown report deterministically.
- **Evidence file**: The evaluator documents commands run and their output so
  the auditor can verify claims without tool access.
- **Validation retries**: If the evaluator produces invalid JSON, it gets
  synthetic feedback and retries (up to 3 times) without counting as an audit
  round.
- **Session resume**: Round 2+ reuses the evaluator/auditor session for faster
  revisions with warm context.
- **Repo config drives behavior**: All repo-specific details (config paths,
  tools, actions menu) come from `.claude/renovate-eval.md`.
- **Conservative default**: When uncertain, the evaluator labels as
  `renovate:risk`.
