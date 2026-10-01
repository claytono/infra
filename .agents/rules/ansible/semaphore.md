# Semaphore Deployment

## Automatic Deployment

Merges to `main` that touch `ansible/**` automatically trigger deployment via
GitHub Actions
([ansible-production-deploy.yaml](/.github/workflows/ansible-production-deploy.yaml)).

The workflow:

1. Detects which hosts are affected by the changes
2. Deploys only to affected hosts via Semaphore

This means Ansible changes are deployed immediately after PR merge - no manual
action required.

## Kubernetes Version Changes

Merging a Kubernetes patch update (`ansible/group_vars/kubernetes.yaml`) makes
the merge deploy upgrade the cluster: control plane first, then workers one at a
time. A failed or retried job is safe to re-run; it resumes at the node that did
not finish. A minor upgrade refuses to run from a merge and is run by hand
first. See `docs/kubernetes-upgrade-playbook.md`.

## Manual Deployment via GitHub Actions

You can trigger deployment manually via GitHub Actions:

- Go to Actions → "Ansible Production Deployment" → Run workflow
- Optionally specify hosts and tags

## When to Use Semaphore CLI

Semaphore deploys from the **git repository**, not local changes. This makes it
unsuitable for interactive development.

Use Semaphore when:

- Deploying committed, pushed changes
- Running from CI/CD pipelines

Use CLI directly when:

- Developing or testing local changes (most of the time)
- Iterating on fixes
- Debugging with verbose output

## Running via Semaphore

```bash
# Deploy to specific hosts
semaphore-deploy --hosts "hostname" --project Infra --template ansible-deploy

# Deploy to all hosts
semaphore-deploy --hosts all --project Infra --template ansible-deploy

# With specific tags
semaphore-deploy --hosts all --project Infra --template ansible-deploy --tags common
```

## Capturing Output

```bash
semaphore-deploy --hosts all --project Infra --template ansible-deploy 2>&1 | tee output.log
```
