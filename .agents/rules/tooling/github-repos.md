# GitHub Repository Checklist

Use this checklist when creating a GitHub repo, making one public, or adding,
renaming or removing a pull-request workflow.

Set the repo once, then run the commands below. Each section has a command that
applies the setting and one that reads it back. Every command except creating
the ruleset is safe to re-run.

```bash
repo=claytono/NAME
```

## Security

Dependabot alerts are on and Dependabot security updates stay off. Renovate
handles dependency updates, including security fixes.

```bash
gh api -X PUT repos/$repo/vulnerability-alerts
gh api -X DELETE repos/$repo/automated-security-fixes
```

```bash
gh api repos/$repo/vulnerability-alerts -i | head -1   # 204 means on
gh api repos/$repo/automated-security-fixes            # enabled: false
```

Public repos only: secret scanning with push protection, and private
vulnerability reporting. GitHub does not offer these on private personal repos.

```bash
gh api -X PATCH repos/$repo \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
gh api -X PUT repos/$repo/private-vulnerability-reporting
```

```bash
gh api repos/$repo --jq '.security_and_analysis'
gh api repos/$repo/private-vulnerability-reporting
```

Do not enable CodeQL.

## Pull Requests From Others

Public repos only: anyone can open a pull request, and every workflow run from
an outside contributor waits for approval.

```bash
gh api -X PATCH repos/$repo -f pull_request_creation_policy=all
gh api -X PUT repos/$repo/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
```

```bash
gh api repos/$repo --jq '.pull_request_creation_policy'
gh api repos/$repo/actions/permissions/fork-pr-contributor-approval
```

## Merge Settings

Rebase and squash only, auto-merge on, delete branches after merge, and offer
"Update branch".

```bash
gh api -X PATCH repos/$repo \
  -F allow_merge_commit=false -F allow_squash_merge=true \
  -F allow_rebase_merge=true -F allow_auto_merge=true \
  -F delete_branch_on_merge=true -F allow_update_branch=true
```

```bash
gh api repos/$repo --jq '{allow_merge_commit, allow_squash_merge,
  allow_rebase_merge, allow_auto_merge, delete_branch_on_merge,
  allow_update_branch}'
```

## Ruleset

One ruleset named `main` on the default branch: a pull request is required with
no approvals, force-pushes and deletion are blocked, and the repo's CI jobs are
required checks. Leave `required_status_checks` out until the repo has CI.
Replace `CHECK_NAME` with one entry per required job, spelled exactly as it
appears in the checks list on one of the repo's pull requests.

First run `gh api repos/$repo/rulesets`. If a ruleset named `main` already
exists, update it as described below instead of creating another.

```bash
gh api -X POST repos/$repo/rulesets --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "pull_request", "parameters": {
      "allowed_merge_methods": ["rebase", "squash"],
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_approving_review_count": 0,
      "required_review_thread_resolution": false}},
    {"type": "required_status_checks", "parameters": {
      "do_not_enforce_on_create": false,
      "strict_required_status_checks_policy": false,
      "required_status_checks": [
        {"context": "CHECK_NAME", "integration_id": 15368}]}}
  ]
}
EOF
```

`15368` is the GitHub Actions app. To change an existing ruleset, fetch it, edit
the JSON and `PUT` it back to `repos/$repo/rulesets/ID`.

```bash
gh api repos/$repo/rulesets
gh api repos/$repo/rules/branches/main
```

## Pull-Request Workflows

When a workflow with `pull_request` or `merge_group` in its `on:` is added, or a
job in one is renamed or removed, decide which of its jobs are required checks
and update the ruleset to match.

- Required checks match by name. Renaming or removing a required job leaves the
  ruleset waiting for a check that never reports, which blocks every pull
  request.
- A required job in a workflow with a `paths:` filter blocks pull requests that
  do not touch those paths, because the check never runs. Keep such jobs
  optional, or filter inside the job with `dorny/paths-filter`.

## Workflow Token

New repos default to a read-only `GITHUB_TOKEN` that cannot approve pull
requests. Confirm it; this is a check, not a change.

```bash
gh api repos/$repo/actions/permissions/workflow
# default_workflow_permissions: read, can_approve_pull_request_reviews: false
```

## Renovate

The repo's Renovate config extends the shared preset and adds only rules
particular to the repo.

```json
{
  "extends": ["github>claytono/renovate-config"]
}
```

Add the repo to the list claytono/renovate-docker-datasource scans, so its
Docker image tags are dated for the 14-day wait:

```bash
list=$(gh variable get REPOSITORIES -R claytono/renovate-docker-datasource) &&
  printf '%s\n%s\n' "$list" "$repo" | tr -s ' ' '\n' | sort -u |
  gh variable set REPOSITORIES -R claytono/renovate-docker-datasource
```

```bash
gh variable get REPOSITORIES -R claytono/renovate-docker-datasource
```

Evaluate the repo's Renovate pull requests. Copy
`.github/workflows/renovate-eval.yaml` from claytono/health-hub unchanged; it
starts a pass when the workflow named `CI` finishes, so the repo's CI workflow
must have that name. Add the repo to `cachix_github_repositories` and
`renovate_eval_github_repositories` in `opentofu/github-repos.tf` and apply it,
which sets the `CACHIX_AUTH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` secrets and the
`RENOVATE_EVAL_PROVIDER` variable.

```bash
gh secret list -R $repo
gh variable get RENOVATE_EVAL_PROVIDER -R $repo
```

## Main Repos Only

infra, dotfiles, github-actions and go-unifi-mcp require SHA pinning. Once
Renovate has pinned every action, turn it on:

```bash
gh api -X PUT repos/$repo/actions/permissions \
  -F enabled=true -f allowed_actions=all -F sha_pinning_required=true
```

```bash
gh api repos/$repo/actions/permissions
```
