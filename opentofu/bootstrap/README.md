# OpenTofu state-bucket bootstrap

This directory contains the one-time setup used to create the S3 bucket that
stores state for the main `opentofu/` root. It also configured versioning,
encryption, public-access blocking, and lifecycle cleanup for that bucket.

The bootstrap state was not retained. OpenTofu state files are ignored by Git,
and this root does not use a remote backend. As a result, a plan from a normal
checkout will show all bootstrap resources as new. That output does not mean a
dependency-only change will create those resources, and it is not useful for
deciding whether such a change is safe.

For a provider or lockfile-only update, initialize without upgrading providers,
validate the configuration, and rely on the repository's normal CI and safety
checks. Do not reject the update because a state-free plan shows the existing
bootstrap resources as new.

Changes to the managed resource definitions require manual handling. Without
reconstructing or importing the existing resources into state, a plan cannot
show how those changes would affect the live bucket. Do not run `tofu apply`
against the existing bucket from a state-free checkout.
