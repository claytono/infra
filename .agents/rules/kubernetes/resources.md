---
paths: ["kubernetes/**/*"]
---

# Resource Requests and Limits

Workloads normally set **no CPU or memory requests or limits**. Running without
them is fine here; where VPA can manage a workload it sets requests from
observed usage, and hand-written values only get in its way. Limits throttle or
OOM-kill a workload exactly when it needs headroom.

## How requests are set

Every namespace defined in this repo is labeled
`goldilocks.fairwinds.com/enabled: "true"`, so Goldilocks creates a VPA for each
workload it can target. Workloads VPA can't target, such as custom controllers
without a `/scale` subresource like the actions-runner-controller runners,
simply run without requests.

`.kyverno/policies/require-goldilocks-vpa-config.yaml` requires every Namespace
manifest to carry that label and both VPA annotations. It checks the annotations
are present, not their values, so a namespace can opt out of VPA changes with
`vpa-update-mode: "Off"` rather than by dropping the label. The
`kyverno-validate` pre-commit hook runs it, and CI's Lint job runs that on every
file. The convention for those values:

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

- Leave out CPU and memory requests and limits; VPA manages only those two. Keep
  any other resource a workload needs (`nvidia.com/gpu`, `ephemeral-storage`,
  hugepages), since nothing else will add it back.
- When a Helm chart sets resource defaults, remove them with `resources: null`
  in `values.yaml` (Helm merges maps, so `resources: {}` leaves the chart's
  defaults in place), then check the rendered manifests under `helm/`. If the
  chart's templates still emit them, use a kustomize patch as below. Null out
  the whole `resources` map only when it holds nothing but CPU and memory;
  otherwise remove just those keys.
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
- Workloads in `vpa` and `cert-manager`. The VPA admission webhook skips those
  namespaces (it cannot depend on itself or on the certificates cert-manager
  issues for it), so VPA never applies requests there; keep their explicit
  requests.
- A limit containing a known leak or runaway process until it is fixed.

No policy enforces leaving resources out: existing manifests that predate this
rule still set them, so one would fail today. Remove them when you touch that
workload rather than as a sweep.
