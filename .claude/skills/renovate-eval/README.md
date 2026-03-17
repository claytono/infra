# renovate-eval

AI-powered evaluation of Renovate dependency update PRs. Produces structured
reports with risk assessments, evidence documentation, and GitHub labels.

## How It Works

```text
evaluate.sh
  ├── fetch-pr-data.sh      # Collect PR metadata, diff, CI status
  ├── check-ci-status.sh     # Check/wait for CI results
  │
  ├── Round 1: Evaluator (claude -p, opus)
  │   ├── Reads PR data, repo config, upstream release notes
  │   ├── Cross-references changes against local project config
  │   ├── Writes: eval-report.md, eval-meta.json, eval-evidence.md
  │   └── Runs validate-report.sh to catch mechanical errors
  │
  ├── Round 1: Auditor (claude -p, sonnet, no tools)
  │   ├── Reviews report against quality criteria
  │   ├── Checks evidence supports claims
  │   └── Outputs: PASS or FEEDBACK with specific issues
  │
  ├── Round 2+ (if FEEDBACK): Resume evaluator session
  │   ├── Reads auditor feedback + revision.md guidelines
  │   ├── Makes targeted fixes (doesn't re-research)
  │   └── Auditor re-reviews (resumes its session too)
  │
  └── Output
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
.claude/skills/renovate-eval/evaluate.sh --pr 1234 --dry-run --context local

# Post to GitHub (comment + labels)
.claude/skills/renovate-eval/evaluate.sh --pr 1234 --post --context local

# With custom instructions
.claude/skills/renovate-eval/evaluate.sh --pr 1234 --dry-run --context local \
    --instructions "Focus on security implications"
```

### GitHub Actions

The workflow at `.github/workflows/renovate-eval.yaml` runs via
`workflow_dispatch`. It uses the composite action at
`.claude/skills/renovate-eval/action.yaml`.

## Repo Context

Repos provide context via `.claude/renovate-eval.md`. This file tells the
evaluator where config files live, what tools are available, and what actions to
show in the interactive menu. See the file in this repo for an example.

## Labels

| Label                | Meaning                                      |
| -------------------- | -------------------------------------------- |
| `renovate:safe`      | No concerns, straightforward update          |
| `renovate:caution`   | Behavioral changes worth validating          |
| `renovate:breaking`  | Breaking changes, needs config rework        |
| `renovate:risk`      | Known issues, regressions, or low confidence |
| `renovate:evaluated` | PR has been evaluated (always added)         |

## Key Design Decisions

- **Evidence file**: The evaluator documents commands run and their output so
  the auditor can verify claims without tool access.
- **Self-validation**: A shell script catches mechanical errors (invalid labels,
  bare links, missing sections) before the auditor runs, reducing wasted rounds.
- **Session resume**: Round 2+ reuses the evaluator/auditor session for faster
  revisions with warm context.
- **Repo config drives behavior**: The generic skill has no repo-specific
  content. All repo-specific details (config paths, tools, actions menu) come
  from `.claude/renovate-eval.md`.
- **Conservative default**: When uncertain, the evaluator labels as
  `renovate:risk` with low confidence.
