# CI/CD Integration

GitHub Actions automatically:

- Renders Helm charts when `Chart.yaml` or `values.yaml` files change
- Commits rendered manifests back to pull requests
- Validates manifests haven't diverged on main branch
- Uses Nix development environment for consistent tooling

## Checking CI Results

To check CI results for a PR, run:

```bash
scripts/gh-check-actions
```
