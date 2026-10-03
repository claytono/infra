---
paths: ["kubernetes/**/*"]
---

# Resource Requests and Limits

Workloads normally set **neither requests nor limits**. VPA sets requests from
observed usage, so hand-written values only get in its way, and limits throttle
or OOM-kill a workload exactly when it needs headroom.

## How requests are set

Every namespace enables Goldilocks, which creates a VPA for each workload in it.
`.kyverno/policies/require-goldilocks-vpa-config.yaml` enforces these namespace
settings through the `kyverno-validate` pre-commit hook, which CI's Lint job
also runs on every file:

```yaml
metadata:
  labels:
    goldilocks.fairwinds.com/enabled: "true"
  annotations:
    goldilocks.fairwinds.com/vpa-update-mode: InPlaceOrRecreate
    goldilocks.fairwinds.com/vpa-resource-policy: '{"containerPolicies":[{"containerName":"*","controlledValues":"RequestsOnly"}]}'
```

- `controlledValues: RequestsOnly`: VPA manages requests and never limits.
- `InPlaceOrRecreate`: the default. The VPA updater resizes running pods, in
  place where possible, during its 1–5 AM maintenance window
  (`kubernetes/vpa/`).
- `Initial`: for cluster-critical namespaces (kube-system, kube-flannel,
  metallb-system, traefik, external-secrets) and Plex. VPA sets requests when a
  pod is created and never touches it afterwards.

## Writing manifests

- Leave `resources` out of containers you write.
- When a Helm chart sets defaults, override them with `resources: {}` in
  `values.yaml`.
- When an upstream plain manifest sets them, remove them with a kustomize patch
  rather than editing the vendored file, which `render` overwrites:

  ```yaml
  patches:
    - target:
        kind: DaemonSet
        name: example
      patch: |-
        apiVersion: apps/v1
        kind: DaemonSet
        metadata:
          name: example
        spec:
          template:
            spec:
              containers:
              - name: example
                resources: null
  ```

  `kubernetes/0-multus/kustomization.yaml` is a working example. Upstream's
  100m/50Mi limits on multus throttled it during a node drain and stalled pod
  teardown across the node.

## When to set them anyway

Set a request or limit only for a concrete reason, and say why in a comment next
to it, for example:

- A device resource such as `nvidia.com/gpu`, which Kubernetes only accepts
  under `limits` (see `kubernetes/plexmediaserver/deploy.yaml`).
- A limit containing a known leak or runaway process until it is fixed.

No policy enforces leaving resources out: existing manifests that predate this
rule still set them, so one would fail today. Remove them when you touch that
workload rather than as a sweep.
