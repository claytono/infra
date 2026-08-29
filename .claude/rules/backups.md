# Backup Architecture

Restic, managed through resticprofile, is the standard backup system across the
homelab. It protects Ansible-managed hosts and Kubernetes NFS storage mounted
into the Kubernetes Restic job. Velero backs up labeled Kubernetes resources and
provides CSI snapshot coverage for iSCSI PVCs. Application-native backup
mechanisms provide additional coverage where they are configured.

## Ansible-Managed Hosts

Host backup configuration is managed through Ansible:

- `ansible/group_vars/all/restic.yaml` defines the shared Restic repository,
  backup sources, exclusions, scheduling, monitoring, and common resticprofile
  configuration.
- `ansible/roles/resticprofile/` installs Restic and resticprofile, renders the
  client configuration, initializes missing repositories, and configures the
  scheduled backup service.
- `ansible/site.yaml` applies the `resticprofile` role to hosts.
- `ansible/host_vars/` and `ansible/group_vars/` contain host- and
  group-specific overrides, including alternate repositories, backup sources,
  and hosts where scheduled backups are intentionally disabled.
- `ansible/group_vars/all/restic-repo-secrets.yaml` contains generated,
  encrypted repository credentials. It is managed by
  `kubernetes/restic/render-and-sync` and must not be edited manually.
- `docs/bootstrap-secrets.md` documents the Restic-related 1Password and Hetzner
  credentials needed to bootstrap the environment.

By default, enabled hosts back up their root filesystem on a daily randomized
schedule, remain on one filesystem, and omit operating-system caches, temporary
files, and container runtime data. The role renders the effective client
configuration under the configured client's `~/.config/resticprofile/`
directory; the default client is `root`. This includes Kubernetes nodes, whose
host filesystems are backed up separately from Kubernetes persistent storage.

Default host backups are written to the `main` Restic repository through
`restic.k.oneill.net`. The Kubernetes `resticprofile-hetzner-main-copy` CronJob
copies that repository to Hetzner for off-site storage. Hosts with a different
repository or endpoint define that override in their Ansible host variables.

## Kubernetes Storage

The Kubernetes Restic deployment is documented and configured under
`kubernetes/restic/`:

- `kubernetes/restic/README.md` documents repository initialization and related
  operational details.
- `kubernetes/restic/profiles.yaml` defines backup sources, exclusions,
  retention, integrity checks, and local and off-site repositories.
- `kubernetes/restic/cronjobs/` contains the scheduled backup, copy, retention,
  and integrity-check jobs.
- `kubernetes/restic/render-and-sync` renders Kubernetes configuration and
  synchronizes the encrypted repository credentials consumed by Ansible.

The daily Kubernetes backup sends the Synology NFS data trees explicitly mounted
under `/source` in `kubernetes/restic/cronjobs/cronjob-hetzner.yaml` to the
off-site Hetzner Restic repository. An NFS PVC is protected only when its
underlying storage path is part of one of those mounts; using an NFS storage
class alone does not provide coverage. Explicit path exclusions are defined in
`kubernetes/restic/profiles.yaml`.

The daily `kubernetes/cluster-backup` job creates and verifies an etcd snapshot,
copies the control-plane configuration from `/etc/kubernetes`, and writes the
result under `/volume2/backups/cluster-backup`. That directory is included in
the Restic job through its `/source/backups` mount, which provides the off-site
copy of the control-plane recovery artifacts.

The `kubernetes/rsnapshot` CronJobs pull UDM Pro backups into
`/volume2/backups/rsnapshot`. The same `/source/backups` Restic mount includes
those snapshots in the off-site Hetzner backup.

The `kubernetes/got-your-back` full and incremental jobs store Gmail backups in
the `got-your-back-data` NFS PVC. Its underlying NFS data is included through
the Restic job's `/source/k8s-pv` mount.

The `daily-iscsi-backups` Velero schedule selects Kubernetes resources labeled
`velero.io/backup: 'true'`; those labels are currently applied to PVCs. Volumes
using the `synology-iscsi` storage class use the Synology iSCSI snapshot class,
while the volume policy skips the `nfs` storage class. NFS PVC data is protected
by Restic rather than Velero. Velero moves snapshot data through
`rclone-s3-velero.k.oneill.net` into an encrypted Hetzner WebDAV repository; the
CSI snapshot class itself has a `Delete` retention policy. Recovery therefore
depends on the encrypted off-site repository and its credentials, not on a
retained Synology snapshot. The Velero configuration is under
`kubernetes/velero/`.

## Monitoring and Credentials

Restic jobs report their status to Healthchecks and publish Prometheus metrics
where configured. Static Restic checks are defined in
`opentofu/healthchecks.tf`; the six local repository maintenance checks are
synchronized by `kubernetes/restic/render-and-sync --healthchecks`; and each
Restic-enabled Ansible-managed host creates its own check through the Restic
profile's `run-before` hook. Repository endpoints and encrypted credentials are
managed through the Ansible, Kubernetes External Secret, and OpenTofu
configuration referenced above.
