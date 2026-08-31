# ESPHome Upgrade Warnings

ESPHome compile logs are the source for `esphome/warning-catalog.yaml`. The
catalog is a generated inventory of the ESPHome `WARNING` records currently
emitted by every active top-level device configuration. It is not an allowlist
and does not suppress warnings.

CI checks each compile shard against the catalog. A new, changed, or removed
warning makes the check fail so the catalog cannot silently become stale.
Compiler and toolchain diagnostics such as lowercase `warning:` messages are
outside this catalog and remain visible in the normal compile logs.

When CI reports a warning change:

1. Read the warning and determine whether the configuration should change.
2. Fix warnings that can be addressed with the proposed ESPHome version.
3. From the `esphome/` directory, regenerate the catalog:

   ```bash
   ./scripts/esphome-warnings update
   ```

   The command performs a fresh sequential compile of every active device. It
   leaves `warning-catalog.yaml` unchanged if any configuration fails.

4. Review the configuration change and generated catalog diff together. A fixed
   warning should disappear from the catalog; a new warning that remains should
   appear in it.
