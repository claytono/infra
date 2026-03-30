# Secrets Management

## Local Development: direnv + age

Service credentials are automatically available as environment variables in the
development shell. **Always check environment variables first** before querying
1Password, Kubernetes secrets, or other secret stores.

The mechanism:

1. `.secrets.tmpl` contains 1Password references (`{{ op://infra/item/field }}`)
2. `bootstrap-secrets --apply direnv` injects values and encrypts them with
   `age` into `.secrets.age`
3. `.envrc` decrypts `.secrets.age` on shell entry and exports the variables

Available credentials include service passwords, API keys, and tokens for tools
like `logcli`, `ansible`, `semaphore-deploy`, and others. Run
`env | cut -d= -f1 | grep -i <service>` to discover variable names without
printing secret values.

### Staleness

If `.secrets.tmpl` changes, direnv warns about stale secrets. Do not
automatically run the fix — offer to run it for the user:

```bash
bootstrap-secrets --apply direnv
```

### Adding new secrets

1. Add the 1Password reference to `.secrets.tmpl`
2. Run `bootstrap-secrets --apply direnv`
3. Run `direnv reload` or re-enter the directory

## Kubernetes: External Secrets Operator

Production workloads use a separate path — see `kubernetes/external-secrets/`.
The direnv secrets are for local CLI use only.
