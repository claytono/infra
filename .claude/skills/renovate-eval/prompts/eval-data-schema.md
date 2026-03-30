# eval-data.json Schema

Write your evaluation data as JSON to the `eval-data.json` path specified below.
This file is the structured input for the report renderer — you do NOT write
markdown reports. A template renders the report from your JSON.

## Schema

```json
{
  "packages": [
    {
      "name": "sonarr",
      "old_version": "4.0.16",
      "new_version": "4.0.17",
      "type": "docker"
    }
  ],
  "label": "renovate:safe",
  "update_scope": "Markdown text describing what is updating and version deltas.",
  "performance_stability": "Markdown text or null",
  "features_ux": "Markdown text or null",
  "security": "Markdown text or null",
  "key_fixes": "Markdown text or null",
  "newer_versions": "Markdown text or null",
  "hazards": "Markdown text (REQUIRED, even if 'None identified...')",
  "sources": [
    {
      "label": "Sonarr v4.0.17 release",
      "url": "https://github.com/Sonarr/Sonarr/releases/tag/v4.0.17"
    }
  ],
  "verdict": "1-2 sentence rationale for the label."
}
```

## Field Reference

### packages (required, non-empty array)

Each package being updated in this PR. Fields:

- `name` (string): Package name (e.g., "sonarr", "postgresql")
- `old_version` (string): Version before this PR
- `new_version` (string): Version after this PR
- `type` (string): One of: `docker`, `helm`, `ansible`, `terraform`,
  `pre-commit`, `github-action`, `dependency`

If multiple entries have the same (name, old_version, new_version, type), only
include one.

### label (required, string)

One of:

- `renovate:safe` — no concerns, straightforward update
- `renovate:caution` — behavioral changes worth validating
- `renovate:breaking` — breaking changes, needs config rework
- `renovate:risk` — known issues, regressions, or low confidence

### update_scope (required, string)

What is updating and what the version deltas are. Explicitly state unchanged
components. This renders as the first section under "The Deep Dive."

### performance_stability (string or null)

Performance improvements, stability fixes, resource usage changes. Link each
item to its PR or issue. Set to `null` if not applicable (section is omitted
from rendered report).

### features_ux (string or null)

For EACH new feature: (1) what it does, (2) whether the user's config uses it,
(3) how to enable it with specific config keys/commands. Set to `null` if not
applicable.

### security (string or null)

CVE IDs with CVSS scores as full markdown links, whether user is affected based
on their config. Set to `null` if not applicable.

### key_fixes (string or null)

Cross-reference bug fixes against actual config and usage patterns. Link each
item to its PR or issue. Set to `null` if not applicable.

### newer_versions (string or null)

Analysis of versions newer than what this PR proposes. Flag regressions in the
proposed version that are fixed later. Set to `null` if not applicable (but
document in evidence file why it was omitted).

### hazards (required, string)

ALWAYS required. List every breaking change, deprecation, and migration with
deployment-specific impact assessment. If there are genuinely no hazards, write
"None identified" with a brief explanation.

### sources (required, non-empty array)

Each source you consulted. Fields:

- `label` (string): Human-readable description (e.g., "Sonarr v4.0.17 release")
- `url` (string): Full URL starting with `http`

### verdict (required, string)

1-2 sentence rationale for the label, plus post-merge follow-up actions if any.

## Rules

- Every factual claim must have a full markdown link `[text](url)` — never bare
  `#123` or unlinked references in any text field.
- `ci_status` is NOT part of this schema — it is injected by the evaluation
  script from live CI checks.
- Set optional sections to `null` (not empty string) when not applicable.
  Document in the evidence file why each was omitted.

## Validation

After writing eval-data.json, run the validation subcommand:

```bash
python3 $SCRIPT_DIR/renovate_eval.py validate $ARTIFACT_DIR/eval-data.json
```

If it reports errors, fix them before finishing.
