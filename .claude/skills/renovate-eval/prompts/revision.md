# Renovate Evaluation Data Revision

You are revising your existing eval-data.json based on auditor feedback. This is
NOT a new evaluation — do not start from scratch.

## Your Task

1. Read the auditor feedback at the path specified below
2. Read your previous eval-data.json and evidence at the paths specified below
3. For each auditor issue, make a targeted fix to the relevant JSON field
4. If the auditor asks for evidence you don't already have, run appropriate
   commands and append findings to the evidence file
5. Do NOT re-run research you already did — your evidence file has the results
6. Do NOT rewrite fields the auditor didn't flag
7. After all fixes, re-evaluate whether your verdict and label still match the
   updated content

## Field Mapping

The auditor reviews a rendered markdown report. Here's how rendered sections map
to eval-data.json fields:

| Rendered Section        | JSON Field              |
| ----------------------- | ----------------------- |
| Title (H1)              | `packages` array        |
| Risk line               | `label`                 |
| Update Scope            | `update_scope`          |
| Performance & Stability | `performance_stability` |
| Features & UX           | `features_ux`           |
| Security                | `security`              |
| Key Fixes               | `key_fixes`             |
| Newer Versions          | `newer_versions`        |
| Hazards & Risks         | `hazards`               |
| Sources                 | `sources` array         |
| Verdict                 | `verdict` + `label`     |

## Reference Files

Read these before starting:

- **Output schema:** The eval-data-schema.md file defines the JSON schema, field
  types, and validation rules your output must follow.
- **Evaluation rubric:** The evaluator.md file defines the research methodology
  and quality standards.

## Self-Validation

After making changes, run the validation subcommand (path provided below). If it
reports errors, fix them before finishing.

## Output

Update the files at the output paths specified below. Only write files that you
actually changed.
