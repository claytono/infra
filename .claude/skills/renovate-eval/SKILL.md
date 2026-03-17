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

**If user specified a PR number:** Go to Evaluate or Present mode for that PR.

**Otherwise:** Run this script to get the JSON list of open Renovate PRs:

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel)/.claude/skills/renovate-eval"
"$SCRIPT_DIR/scripts/list-renovate-prs.sh"
```

The script outputs a JSON array. **IMPORTANT:** Bash tool output is collapsed in
the UI and the user cannot see it. You MUST format the JSON into a readable
table and print it as regular text output. Sort evaluated PRs first, then
unevaluated:

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

Before running a new evaluation, check if one already exists:

```bash
EVAL_COMMENT=$(gh pr view "$PR" --json comments --jq '
  .comments
  | map(select(.body | contains("<!-- renovate-eval-skill:")))
  | sort_by(.createdAt) | last | .body')
```

If non-empty, display the existing report (strip the HTML comment sentinel line)
and show the Actions Menu. This is "present mode."

If empty, proceed to "evaluate mode."

## Evaluate Mode (New Evaluation)

Run the evaluation engine in dry-run mode:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
"$REPO_ROOT/.claude/skills/renovate-eval/evaluate.sh" \
    --pr "$PR" --dry-run --context local
```

The script prints the report to stdout and the artifact directory path on the
last line (`Artifacts: /path/to/dir`). Read the report from the Bash output and
show the Actions Menu.

## Actions Menu

**IMPORTANT: Repo config overrides skill defaults.** If
`$REPO_ROOT/.claude/renovate-eval.md` exists, read its "Actions Menu" section.
Any actions defined there MUST be included in the menu you present to the user.
The repo config is authoritative — it may add actions, modify conditions for
showing them, or change how they work.

Extract CI status from the sentinel comment (if in present mode) or from the
evaluate.sh stdout output (if in evaluate mode — parse the Metadata JSON block
printed to stdout):

```bash
# From comment sentinel:
META=$(echo "$EVAL_COMMENT" | grep -o '<!-- renovate-eval-skill:{[^}]*}' | \
    sed 's/<!-- renovate-eval-skill://')
CI_STATUS=$(echo "$META" | jq -r '.ci_status // "unknown"')
```

**Default actions (always show):**

1. **Merge** — `gh pr merge $PR --auto --rebase`
2. **Review later** — no action, move on
3. **Close** — `gh pr close $PR` (warn: Renovate will NOT reopen for this
   version)

**Default conditional actions:**

- **Fix CI** — only if `CI_STATUS` is `"failing"`

**Then add any actions from `$REPO_ROOT/.claude/renovate-eval.md`.**

Print all actions as a numbered list. Wait for user selection.

## Handling Actions

- **Merge**: `gh pr merge $PR --auto --rebase`
- **Review later**: No action. If evaluating multiple PRs, move to next.
- **Close**: Warn first: "Closing tells Renovate to ignore this version
  permanently. Are you sure?" Then `gh pr close $PR`.
- **Deploy for testing**: Read `.claude/renovate-eval.md` and repo rules (e.g.,
  `.claude/rules/`) for deployment instructions specific to this repo.
- **Fix CI**: Investigate the CI failure and attempt to fix it.
- **Re-evaluate**: Run `evaluate.sh --pr $PR --post --context local` to
  regenerate and post updated evaluation.

## Multi-PR Flow

When evaluating 'all', process each PR sequentially: evaluate, show report and
actions menu, handle user selection, then move to next PR.
