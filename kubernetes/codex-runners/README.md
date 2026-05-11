# Codex Runners

This app provides generic Codex runner infrastructure. The base
`kubernetes/codex-runners` app owns the `codex-runners` namespace, the shared
`codex-home` ReadWriteOncePod NFS PVC, the runner scale set, NetworkPolicy, and
the runner service account.

## Auth Bootstrap

The `bootstrap` overlay creates only the temporary `codex-auth-bootstrap` pod.
Apply it only after the base app has created the namespace, `codex-home` PVC,
and `codex-runner` service account.

The bootstrap pod uses `node:24-bookworm` instead of the slim image because the
native Codex binary needs system CA certificates for device auth.

The bootstrap pod also runs a root init container that changes the existing
`codex-home` PVC contents to UID/GID `1001:1001`. That matches the upstream
`ghcr.io/actions/actions-runner:2.333.0` `runner` user used by ARC jobs and
keeps refreshed Codex auth writable after moving away from the previous
arbitrary UID.

Runner pods mount `codex-runner-hooks` at `/etc/arc/hooks` and set
`ACTIONS_RUNNER_HOOK_JOB_STARTED` to normalize the stock runner image before
workflow steps begin. The mounted `job-started.sh` follows ARC's generic hook
dispatcher shape by running scripts under `/etc/arc/hooks/job-started.d/`. The
current pre-job hook installs `gh` and `xz-utils`, which GitHub-hosted Ubuntu
runners include but `ghcr.io/actions/actions-runner:2.333.0` does not. The
runner container also sets `USER=runner` so actions that expect a normal
login-style runner environment can resolve the active user.

Static render check:

```bash
kubectl kustomize kubernetes/codex-runners/bootstrap
```

Apply only after explicit approval:

```bash
kubectl apply -k kubernetes/codex-runners/bootstrap
```

Exec into the pod only after separate approval:

```bash
kubectl -n codex-runners exec -it pod/codex-auth-bootstrap -- bash
```

Inside the pod:

```bash
npm install -g @openai/codex@latest
codex login --device-auth
codex login status
```

Cleanup:

```bash
kubectl delete -k kubernetes/codex-runners/bootstrap
```

`@openai/codex@latest` intentionally matches the current action default
`codex_version: latest`. If CI later pins `codex_version`, use that same version
for bootstrap refreshes.

## Persisted Auth

Both bootstrap and runner pods set `CODEX_HOME` to `/home/runner/.codex`. That
path is backed by the shared `codex-home` PVC, so Codex writes refreshed
`auth.json` and session state back to the PVC. The PVC is the source of truth
for refreshed Codex auth state.

Normal runner jobs should not copy refreshed auth back to GitHub Secrets or
1Password.

Because `codex-home` is ReadWriteOncePod, run the bootstrap pod only when no
Codex runner pod or job is active. Delete `codex-auth-bootstrap` before
dispatching Codex runner jobs; otherwise the bootstrap pod and runner pod may
contend for the PVC and one may remain Pending.

## GitHub Runner Registration

ARC consumes the Kubernetes Secret `codex-runner-github` in the `codex-runners`
namespace, key `github_token`. `externalsecret-github.yaml` creates that Secret
from the 1Password item `codex-runner-github`, field `github_token`, in the
`infra` vault through the `production` ClusterSecretStore.

The fine-grained PAT is manually created in GitHub; this repo does not mint it
with OpenTofu because the current repo/provider pattern does not support
creating the user PAT value.

Create the token with resource owner `claytono`, repository access
`All repositories`, repository permission `Administration: Read and write`, and
no expiration where GitHub policy permits. `All repositories` means current and
future repositories under the selected resource owner `claytono`. It does not
cover repositories owned by other users or organizations; if `repos.yaml` later
includes another owner or organization, make a separate token/source decision.

Record in the 1Password item notes that the token intentionally has broad repo
access and no planned expiration, plus the date it was created. Do not commit
the token value or expose it in command output.

This is intentionally broader than selected-repo access. A leaked token with
repository `Administration: Read and write` could administer runner registration
across current and future `claytono` repositories until revoked. If GitHub
policy prevents no-expiration tokens, use the longest policy-permitted
expiration, record that policy limitation in 1Password notes, and treat future
rotation as an operational follow-up rather than trying to encode the token
lifecycle in this repo.

GitHub may delete PATs unused for one year; if ARC stops authenticating after a
long idle period, check token existence before changing Kubernetes manifests.

No-expiration incident path: revoke the PAT in GitHub, replace the 1Password
`github_token` field, let External Secrets resync `codex-runner-github`, and
verify ARC auth with the Kubernetes checks below.

Do not store the PAT in GitHub Actions secrets. Store it only in 1Password as
the expected item/field so External Secrets can sync it into Kubernetes.

If the Kubernetes Secret syncs but ARC still cannot authenticate, check PAT
approval/authorization policy, token existence, expiration policy, resource
owner, repository access, and `Administration: Read and write` permission before
changing Kubernetes manifests.

Metadata-only 1Password verification that avoids printing the token value:

```bash
op item get codex-runner-github --vault infra --format json \
  | jq '{title: .title, vault: .vault.name, fields: [.fields[] | {label: .label, type: .type, purpose: .purpose}]}'
```

Kubernetes verification after the 1Password item exists and the app is applied:

```bash
kubectl -n codex-runners get externalsecret codex-runner-github
kubectl -n codex-runners get secret codex-runner-github -o jsonpath='{.data.github_token}' | wc -c
kubectl -n codex-runners get autoscalingrunnerset codex-infra
```

Use the `jsonpath | wc -c` command only to verify the key exists without
decoding or printing the token.
