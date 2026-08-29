---
paths: ["kubernetes/**/externalsecret.yaml"]
---

# External Secrets Integration

Applications use External Secrets Operator with:

- `ClusterSecretStore` named `production` for secret retrieval
- External secrets defined in `externalsecret.yaml` files
- Secrets referenced by name in application manifests
