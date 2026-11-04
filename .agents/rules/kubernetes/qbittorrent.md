---
paths: ["kubernetes/qbittorrent/**", "kubernetes/qbit-manage/**"]
---

# qBittorrent and qbit_manage

qbit_manage normally refuses to run against a qBittorrent version its release
has not been tested with. That check is bypassed: `skip_qb_version_check: true`
in `config.yml` on the `qbit-manage-config` PVC. The setting is not in Git.
Setting `QBT_SKIP_QB_VERSION_CHECK` in the Deployment would have no effect,
because qbit_manage ignores command environment variables while `config.yml` has
a `commands:` block.

With the check bypassed, a qBittorrent update can reach a version that the
pinned qbit_manage has not been tested with. Before merging one, renovate-eval
establishes whether it has (`.renovate-eval.md`, qBittorrent Updates). If the
target version is in the support matrix of the pinned qbit_manage, nothing else
is needed. If it isn't, prefer upgrading qbit_manage to a release that supports
it. If no such release exists and the evaluation finds nothing incompatible,
roll out qBittorrent and confirm that qbit_manage works with it as described
below.

## Verifying qbit_manage after a qBittorrent rollout

Only needed when the new qBittorrent version is outside the pinned qbit_manage's
support matrix. Once the new qBittorrent pod is ready, start a run with every
command enabled in the `commands:` block of `config.yml` (currently `recheck`,
`rem_unregistered` and `tag_tracker_error`; check the file first):

```bash
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl exec deploy/qbit-manage -- curl -sS -X POST http://localhost:8181/api/run-command -H 'Content-Type: application/json' -d '{"commands": ["recheck", "rem_unregistered", "tag_tracker_error"], "skip_qb_version_check": true}'
```

A run started this way takes its commands from the request, not from
`config.yml`, so the request has to set `skip_qb_version_check` itself. The call
returns when the run finishes. If it returns `"status": "queued"`, a scheduled
run was already going, and qbit_manage runs the request after it.

Then, in the same shell, read the whole run (about 120 lines):

```bash
kubectl logs deploy/qbit-manage --since-time="$started_at"
```

The run worked if the log shows the new qBittorrent version,
`Qbt Connection Successful`, and a `Finished WebAPI Run` summary whose
`Executed Commands` line lists every command you sent. A command left off that
line was skipped. Also read the rest of the run for anything unexpected; the
version-check bypass warning is expected. If anything is missing or looks wrong,
investigate before calling the rollout finished.
