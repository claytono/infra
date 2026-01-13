# Container Registry Operations

Always use `skopeo` for interacting with remote container registries. Never use
`docker pull` or `docker inspect` for lookups.

## Common Operations

**Get multi-arch manifest digest (preferred):**

```bash
skopeo inspect --raw docker://image:tag | skopeo manifest-digest /dev/stdin
```

**Get platform-specific digest (only if no multi-arch manifest):**

```bash
skopeo inspect --override-arch amd64 --override-os linux docker://image:tag --format '{{.Digest}}'
```

**List available tags:**

```bash
skopeo list-tags docker://image
```

**Get full image metadata:**

```bash
skopeo inspect --override-arch amd64 --override-os linux docker://image:tag
```

## Digest Selection

Always use the multi-arch manifest digest when available. This allows Kubernetes
to pull the correct architecture automatically. Only fall back to
platform-specific digests for images that don't publish multi-arch manifests.

## Why skopeo

- Does not require pulling the image (faster, no disk usage)
- Works without Docker daemon
