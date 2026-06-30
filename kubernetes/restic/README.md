# Restic Repository Template

## Build template repo v1

The template repository is created once at
`/volume2/backups/restic/repos/template/v1` by copying chunker parameters from
the existing `main` repo. Do not schedule this Job. Delete it after checking the
logs.

Before running the Job:

1. Run `kubernetes/restic/render-and-sync --secrets`. This command requires the
   expected 1Password fields to already exist and fails closed if they do not.
   For first-time bootstrap only, run
   `kubernetes/restic/render-and-sync --secrets --create-missing`.
2. Apply the shared ExternalSecret resources:

   ```sh
   kubectl apply -k kubernetes/restic/shared
   kubectl -n restic get secret resticprofile -o jsonpath='{.data.RESTIC_TEMPLATE_PASSWORD}' >/dev/null
   ```

3. Replace `<RESTICPROFILE_IMAGE_FROM_KUSTOMIZATION>` below with the currently
   pinned `creativeprojects/resticprofile` image from
   `kubernetes/restic/kustomization.yaml` or from
   `kubectl kustomize kubernetes/restic`.

Apply the one-off Job:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: restic-template-v1-build
  namespace: restic
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: build
          image: <RESTICPROFILE_IMAGE_FROM_KUSTOMIZATION>
          command:
            - sh
            - -ceu
            - |
              template=/repos/template/v1
              if [ -e "$template/config" ]; then
                echo "template config already exists: $template/config" >&2
                exit 1
              fi
              if [ -d "$template" ] && [ "$(find "$template" -mindepth 1 -print -quit)" ]; then
                echo "template directory exists and is not empty: $template" >&2
                exit 1
              fi

              mkdir -p "$template"
              RESTIC_PASSWORD_FILE=/secrets/template-passphrase \
                restic -r "$template" init \
                --copy-chunker-params \
                --from-repo /repos/main \
                --from-password-file /secrets/main-passphrase

              restic -r /repos/main \
                --password-file /secrets/main-passphrase \
                cat config > /tmp/main-config.json
              restic -r "$template" \
                --password-file /secrets/template-passphrase \
                cat config > /tmp/template-config.json

              main_poly="$(sed -n 's/.*"chunker_polynomial"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/main-config.json)"
              template_poly="$(sed -n 's/.*"chunker_polynomial"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/template-config.json)"

              echo "main chunker_polynomial=$main_poly"
              echo "template chunker_polynomial=$template_poly"
              if [ -z "$main_poly" ] || [ -z "$template_poly" ] || [ "$main_poly" != "$template_poly" ]; then
                echo "chunker_polynomial mismatch" >&2
                exit 1
              fi
          volumeMounts:
            - name: repos
              mountPath: /repos
            - name: restic-secrets
              mountPath: /secrets
              readOnly: true
      volumes:
        - name: repos
          nfs:
            server: fs2.oneill.net
            path: /volume2/backups/restic/repos
        - name: restic-secrets
          secret:
            secretName: resticprofile
            defaultMode: 0400
            items:
              - key: RESTIC_PASSWORD
                path: main-passphrase
              - key: RESTIC_TEMPLATE_PASSWORD
                path: template-passphrase
```

Cleanup:

```sh
kubectl -n restic logs job/restic-template-v1-build
kubectl -n restic delete job restic-template-v1-build
```

When verifying the template through the read-only rest-server with commands such
as `restic cat config`, pass `--no-lock`; otherwise restic will try to create a
lock in the read-only template repository. Do not add `--no-lock` to normal
backup repositories.

## Future repository initialization

Any future Kubernetes resticprofile job that may create a repository must copy
chunker parameters from the template repo. For public ingress consumers, add:

```yaml
init:
  copy-chunker-params: true
  from-repository: rest:https://restic-template.k.oneill.net/v1
  from-password-file: /restic-template/password
```

Mount the template password from the existing `resticprofile` Secret:

```yaml
volumeMounts:
  - name: restic-template-password
    mountPath: /restic-template
    readOnly: true
volumes:
  - name: restic-template-password
    secret:
      secretName: resticprofile
      defaultMode: 0400
      items:
        - key: RESTIC_TEMPLATE_PASSWORD
          path: password
```

Use `rest:https://restic-template.cow-banjo.ts.net/v1` for jobs or hosts that
must reach the template repo over Tailscale.
