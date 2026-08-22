# Renovate Eval Context

## Role of This File

This file provides repository context, discovery hints, available tools, and
action-menu behavior. It does not redefine the shared `renovate:safe`,
`renovate:caution`, `renovate:breaking`, or `renovate:risk` label semantics.

## Repo Layout

- Kubernetes apps: `kubernetes/<app>/` with Helm values at `values.yaml` and
  `Chart.yaml`. Rendered Helm templates at `kubernetes/<app>/helm/`.
- Ansible roles: `ansible/roles/<role>/defaults/main.yaml` (some legacy roles
  use `main.yml`)
- Ansible inventory: `ansible/inventory/`
- OpenTofu: `opentofu/*.tf`
- Pre-commit hooks: `.pre-commit-config.yaml`

## Normal Validation and Deployment Actions

These commands describe this repository's normal validation and deployment
workflows. Needing one of these normal workflows is not, by itself, evidence for
`renovate:caution`; the label still depends on the shared rubric.

- Kubernetes deploys via ArgoCD on PR merge -- no manual deploy needed
- Ansible deploys via Semaphore on merge to main
- For pre-merge testing: `kubectl apply -k kubernetes/<app>/` for Kubernetes,
  `ansible-playbook` for Ansible (run from `ansible/` directory)

## Pre-commit Hook Security Review

For every Renovate update to `.pre-commit-config.yaml`, check out or fetch the
upstream hook repository and inspect the exact diff between the old and new
revisions before recommending a merge. Do not rely only on the Renovate PR diff,
release notes, or changelog.

Review executable hook entrypoints and any changed dependencies, build files,
generated artifacts, or release workflows that can affect installed code. Look
specifically for new access to the network, filesystem, environment variables,
credentials, subprocesses, or downloaded executables, as well as obfuscated or
unexpected binary content and changes in maintainer or release provenance.

Record the inspected revisions and security-relevant findings in the evaluation.
If the exact upstream diff cannot be inspected, record that limitation as an
unresolved hazard and do not recommend merging the update.

## MinusPod Stable Digest Updates

`kubernetes/minuspod/deploy.yaml` tracks
`ttlequals0/minuspod:stable@sha256:<digest>`. MinusPod defines `stable` as its
promoted stable channel, while the committed digest keeps the deployed image
immutable.

For every MinusPod digest update:

- Resolve both the current and proposed digests to their numeric MinusPod image
  tags. Report and evaluate the numeric version change, not merely a Docker
  digest change.
- Confirm that the proposed digest equals the current Docker Hub `stable` digest
  and that its numeric tag is the newest non-prerelease GitHub Release. If
  either check fails, treat the proposal as stale and do not recommend merging
  it.
- Treat numeric Docker tags that are absent from GitHub Releases or still marked
  as prereleases as unpublished or unpromoted build artifacts, not as stable
  release candidates.
- Compare the resolved numeric versions. If the proposed stable version is lower
  than the current deployed version, treat it as a downgrade and do not
  recommend merging it. Leave the PR open for Renovate to refresh when the
  stable channel advances to the same or a newer version.
- Evaluate the complete release and configuration delta between the resolved
  current and proposed versions. Do not recommend switching to a different
  release that is not represented by the proposed digest.
- Do not describe the deployment as using an unpinned or mutable image. The
  floating tag selects the release channel for Renovate, while Kubernetes uses
  the committed immutable digest.

## Available Tools

- `skopeo` -- container image inspection (list tags, inspect manifests)
- `kubectl` and `helm` -- Kubernetes inspection (local mode only)

## Config Discovery

- Helm values: `kubernetes/[app]/values.yaml`, `Chart.yaml`
- K8s raw manifests: `kubernetes/[app]/*.yaml`
- Kustomize overlays: `kubernetes/[app]/kustomization.yaml`
- Rendered Helm templates: `kubernetes/[app]/helm/` (read-only reference)
- Ansible defaults: `ansible/roles/[role]/defaults/main.yaml` (or `main.yml`)
- Ansible inventory: `ansible/inventory/`
- Look for: enabled features, sidecar containers (Redis is common), integrations
  (ingress, Prometheus monitoring, Authentik SSO/OIDC), persistence, env vars,
  resource limits, External Secrets pulling from 1Password

**IMPORTANT: Kustomize image overrides.** Many apps use kustomize to pin the
container image independently of the Helm chart default. Check
`kubernetes/[app]/kustomization.yaml` for `images:` entries. When a kustomize
image override exists and the PR does NOT change it, the deployed app version is
NOT changing — only the chart scaffolding (templates, labels, defaults) is
updating. In this case, focus your report on chart-level changes. Do not
describe app-level features, fixes, or CVEs for versions the user already has or
versions that won't be deployed by this PR.

## Notes

- 14-day minimumReleaseAge on Renovate
- Sidecar containers are common (Redis, proxies, exporters)
- Authentik provides SSO for most services
- External Secrets Operator pulls secrets from 1Password
- Persistent storage via NFS and Synology iSCSI storage classes

## Actions Menu

The following actions MUST be included in the actions menu presented to the user
after evaluation. These are in addition to the default actions provided by the
skill (Merge, Review later, Close).

- **Deploy for testing** — Show for kubernetes, ansible, and terraform/opentofu
  updates. Read `.claude/rules/` for deployment instructions specific to each
  update type. For Kubernetes: `kubectl apply -k kubernetes/<app>/`. For
  Ansible: run `ansible-playbook` from the `ansible/` directory. For OpenTofu:
  run `tofu plan` then `tofu apply` from the `opentofu/` directory.
