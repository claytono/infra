# Semaphore Deployment (Optional)

## When to Use Semaphore

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
