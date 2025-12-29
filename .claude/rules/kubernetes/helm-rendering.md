---
paths: ["kubernetes/**/render", "kubernetes/**/Chart.yaml"]
---

# Helm Chart Rendering

## Render Script Pattern

Each application directory contains a `render` script that generates static YAML manifests from Helm charts.

### Standard Pattern

```bash
#!/bin/bash
source "$BASEDIR/../scripts/chart-version"
rm -rf helm tmp && mkdir tmp helm
helm_template release-name chart-name --values values.yaml \
  --namespace namespace --output-dir tmp
mv tmp/*/* helm && rmdir tmp/*
```

### Key Points

- **Source chart-version helper**: Located at `kubernetes/scripts/chart-version` (relative to repository root), provides `helm_template` function with correct repository/version handling
- **Clean output**: Remove existing `helm/` and `tmp/` directories before rendering
- **Use helm_template function**: Ensures charts are rendered with correct repository and version from `Chart.yaml`
- **Post-processing**: Some render scripts may remove deprecated resources or perform other transformations

### Critical Rule

**Never run `helm install` or `helm upgrade` directly** - all deployments use pre-rendered manifests that are deployed via kustomize and managed by ArgoCD.
