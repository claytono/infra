# ESPHome Upgrades

## Warning Catalog

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

## ESP32-C6 Coprocessors

A device that reaches Wi-Fi through an ESP32-C6 coprocessor (`esp32_hosted`),
such as the CrowPanel, runs separate esp_hosted firmware on the C6. That
firmware has to stay close to the esp_hosted library built into each ESPHome
release. When the two drift too far apart, the SDIO link to the C6 never comes
up after a restart and the device boot-loops.

Give every such config an `esp32_hosted` update entity whose
`on_update_available` runs `update.perform`, as the CrowPanel device class does.
It installs a matching C6 firmware shortly after the device boots on a new
ESPHome release, then restarts. After every ESPHome upgrade, confirm it worked:
once the device is back up, its config dump in `esphome logs` should show
`Coprocessor Version` equal to `Host Library Version`, or the newest version the
manifest offers below it.

If the C6 is still on the old version, stop and tell the user before doing
anything else to that device. Do not retry the update, restart the device or
continue the rollout on your own; report what the logs show and decide the next
step together.
