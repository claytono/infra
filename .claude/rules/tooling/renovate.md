# Renovate Configuration

## Testing Changes

When modifying `.renovaterc`, always test with the local dry-run script before committing:

```bash
scripts/renovate-dryrun full
```

Modes:
- `full` - Full dry-run including branch/PR simulation (default)
- `extract` - Only extract dependencies
- `lookup` - Extract and lookup new versions

The script automatically checks for critical errors and exits non-zero if found. Log file: `.tmp/renovate/dryrun.log`

## Key Constraints

Renovate uses **RE2 regex engine** which does NOT support:
- Lookbehind assertions (`(?<=...)`)
- Lookahead assertions (`(?=...)`)
- Backreferences

## autoReplaceStringTemplate Newlines

To include newlines in `autoReplaceStringTemplate`, use `\\n` in JSON (double-escaped):

```json
"autoReplaceStringTemplate": "# comment\\n{{{prefix}}}{{{depName}}}"
```

The template engine interprets `\n` as a newline escape, so JSON's `\n` (single escape) becomes empty. Double-escape to pass literal `\n` to the template engine.

## Docker Image Annotations

Use comment annotations for Docker images in Ansible:

```yaml
# renovate: datasource=docker
variable_name: "image:tag@sha256:digest"
```

The generic regex manager in `.renovaterc` handles these automatically.
