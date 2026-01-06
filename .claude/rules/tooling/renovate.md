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

## Multiline Matching Strategy

For patterns spanning multiple lines (like comment annotations), use `matchStringsStrategy: "recursive"` instead of trying to include newlines in `autoReplaceStringTemplate`. Renovate only replaces the last match in recursive mode, so you can:

1. First pattern: Match the full block (comment + value line)
2. Second pattern: Extract only the parts to be replaced

This avoids newline escaping issues entirely.

## Docker Image Annotations

Use comment annotations for Docker images in Ansible:

```yaml
# renovate: datasource=docker
variable_name: "image:tag@sha256:digest"
```

The generic regex manager in `.renovaterc` uses `matchStringsStrategy: "recursive"` to handle these - the comment identifies the block, and only the image reference is replaced.
