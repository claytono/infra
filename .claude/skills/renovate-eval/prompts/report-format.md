# Report Format

Your report MUST follow this exact structure. Do NOT include any metadata
markers -- evaluate.sh adds those when posting.

## Report Structure

Every factual claim must have a full markdown link `[text](url)` — never bare
`#123` or unlinked references.

Sections may be omitted if genuinely not applicable, but you must document in
the evidence file WHY the section was omitted (e.g., "Security section omitted:
no CVEs found in range, searched GitHub Security Advisories"). The Hazards &
Risks section is always required — write "None identified" with a brief
justification if there are no hazards.

```markdown
# [Package] [OldVersion] -> [NewVersion]

**Risk:** [emoji] [Label] | **CI:** [Status] | **Confidence:** [Level]

## The Deep Dive

### Update Scope

What is updating and what the version deltas are. Explicitly state unchanged
components.

### Performance & Stability

Performance improvements, stability fixes, resource usage changes. Link each
item to its PR or issue.

### Features & UX

For EACH new feature, state: (1) what it does, (2) whether the user's config
uses it, (3) how to enable it with specific config keys/commands. "Feature X
added" without enablement guidance is insufficient. Link each item to its PR or
issue.

### Security

CVE IDs with CVSS scores as full markdown links, whether user is affected based
on their config.

### Key Fixes

Cross-reference bug fixes against actual config and usage patterns. Link each
item to its PR or issue.

### Newer Versions

Check whether newer versions exist beyond what this PR proposes. If they do,
evaluate their changelogs for:

- Bugs or regressions INTRODUCED in the proposed version and fixed later. These
  MUST be called out if relevant to the deployment's config — they mean the
  proposed version has known issues. This should influence the verdict toward
  Caution or Risk.
- Security fixes for vulnerabilities introduced in the proposed version. Always
  flag these regardless of config relevance.
- Bugs that pre-date the proposed version (already present in the current
  version) can be omitted unless they are serious.

## Hazards & Risks

REQUIRED even if no risks exist. List every breaking change, deprecation, and
migration with deployment-specific impact assessment. If there are genuinely no
hazards, write "None identified" with a brief explanation of why (e.g., "no
breaking changes in this release").

## Sources

Full markdown links to release notes, changelogs, CVE databases used.

---

## [emoji] Verdict: [Label]

[1-2 sentence rationale, plus post-merge follow-up actions if any]
```

## Verdict Mapping

- 🟢 **Safe** (`renovate:safe`) -- no concerns, straightforward update
- 🟡 **Caution** (`renovate:caution`) -- behavioral changes worth validating
- 🟠 **Breaking** (`renovate:breaking`) -- breaking changes, needs config rework
- 🔴 **Risk** (`renovate:risk`) -- known issues, regressions, or low confidence

Use Unicode emoji (not shortcodes like `:green_circle:`). Use these exact names
in the verdict heading: Safe, Caution, Breaking, or Risk. The label in
parentheses is what goes in eval-meta.json.

## Multi-Package PRs

Use per-package sub-sections under each topic heading. The top-level header
lists all packages. The verdict uses highest-risk-wins for the label.

## Failed Audit Banner

If the report did not pass audit after 3 rounds, this banner is prepended (by
evaluate.sh, not by you):

```markdown
> ⚠️ **This report did not pass automated quality review.** Treat with
> skepticism.
```
