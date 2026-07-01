# Codex Runners

This app provides generic Codex runner infrastructure for GitHub Actions jobs
that target the `codex` runner label.

The app owns the `codex-runners` namespace, the `codex-infra` ARC scale set, the
runner service account, the NetworkPolicy for normal runner pods, GitHub runner
registration auth, and Codex subscription auth distribution.

## Auth Architecture

Codex subscription auth is stored in the `codex-auth` ReadWriteMany NFS PVC.
That PVC is intentionally small and stores only `auth.json`.

Normal runner pods do not mount `codex-auth` in the main runner container.
Instead, an initContainer mounts `codex-auth` read-only, validates
`/auth/auth.json`, and copies it into the pod-local `emptyDir`
`/home/runner/.codex/auth.json`. The main runner container uses that local
directory as `CODEX_HOME`.

This avoids sharing a mutable `CODEX_HOME` across runner pods. Codex can refresh
or rewrite auth locally during a workflow, but that local state is discarded
when the pod exits.

## Auth Refresh

The `codex-auth-refresh` CronJob runs hourly at minute 17. It is trusted
operational automation, not an untrusted PR/eval runner.

Refresh flow:

1. Mount `codex-auth` read-write at `/auth`.
2. Mount an `emptyDir` at `/codex-home`.
3. Copy and validate `/auth/auth.json` into `/codex-home/auth.json`.
4. Install Node/npm and `@openai/codex@latest`.
5. Run a minimal `codex exec` prompt with `CODEX_HOME=/codex-home`.
6. Validate and publish `/codex-home/auth.json` back to `/auth/auth.json` with a
   same-directory temporary file and `os.replace`.
7. Ping Healthchecks success only after publish succeeds.

The refresh job never calls a `/fail` Healthchecks endpoint. If refresh stops
successfully reporting, the self-hosted Healthchecks check `codex-auth-refresh`
alerts after 48 hours without a success ping.

Do not print, decode, or upload `auth.json` contents.

## Recovery Re-Auth

If `codex-auth/auth.json` is missing, revoked, or no longer refreshable, run a
temporary re-auth pod from stdin. Do not commit this Pod manifest.

```bash
kubectl -n codex-runners apply -f - <<'EOF'
---
apiVersion: v1
kind: Pod
metadata:
  name: codex-auth-reauth
spec:
  restartPolicy: Never
  containers:
  - name: reauth
    image: ghcr.io/astral-sh/uv@sha256:05bc724e74da13ad6238b9721a0e2f0f649dd2ed86b0453e7e88e63831b38dfe
    command:
    - sleep
    - infinity
    env:
    - name: CODEX_HOME
      value: /codex-home
    - name: SOURCE_AUTH
      value: /codex-home/auth.json
    - name: AUTH_DIR
      value: /auth
    volumeMounts:
    - name: codex-home
      mountPath: /codex-home
    - name: codex-auth
      mountPath: /auth
    - name: codex-auth-tools
      mountPath: /etc/codex-auth-tools
      readOnly: true
  volumes:
  - name: codex-home
    emptyDir: {}
  - name: codex-auth
    persistentVolumeClaim:
      claimName: codex-auth
  - name: codex-auth-tools
    configMap:
      name: codex-auth-tools
      defaultMode: 0555
EOF
```

Exec into the pod only after separate approval:

```bash
kubectl -n codex-runners exec -it pod/codex-auth-reauth -- bash
```

Inside the pod:

```bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates nodejs npm
npm install -g @openai/codex@latest
codex login --device-auth
codex login status
python3 /etc/codex-auth-tools/publish-auth-json.py
```

Cleanup:

```bash
kubectl -n codex-runners delete pod codex-auth-reauth
```

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
