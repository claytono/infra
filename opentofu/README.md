# OpenTofu

This repository has three separate OpenTofu roots. Read the instructions for the
affected root before running OpenTofu commands.

## Main infrastructure

The configuration in this directory manages the homelab's regular
infrastructure. Run OpenTofu from `opentofu/`. Its state is stored in the S3
bucket configured in `main.tf`.

Do not use `tofu init -upgrade`; dependency versions are controlled by the lock
file. See
[the repository OpenTofu instructions](../.agents/rules/opentofu/usage.md) for
the standard workflow.

## Slack applications

The configuration in [`slack/`](slack/) is a separate OpenTofu root. Use
`scripts/tofu-slack` from the repository root instead of running OpenTofu in
that directory directly. See [`slack/README.md`](slack/README.md) for details.

## State-bucket bootstrap

The configuration in [`bootstrap/`](bootstrap/) is a one-time setup root that
created the S3 bucket used by the main infrastructure root. It does not share
the main root's state or normal planning workflow. See
[`bootstrap/README.md`](bootstrap/README.md) before validating or changing it.
