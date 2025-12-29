# Pre-commit Hooks

The repository uses extensive pre-commit validation including:

- YAML formatting (yamlfix) and validation (yamllint)
- Kubernetes manifest validation (kubeconform)
- Shell script validation (shellcheck, shfmt)
- Ansible linting
- Terraform/OpenTofu validation

## Excluded Directories

The following directories are excluded from most hooks:

- Rendered Helm templates: `kubernetes/*/helm/`
- Third-party Ansible code

## Usage

Do not run pre-commit or linting tools manually - they run automatically on commit.
