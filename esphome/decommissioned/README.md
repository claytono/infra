# Decommissioned ESPHome Devices

This directory contains ESPHome configuration files for devices that are no longer in active use but are kept for reference.

These configurations are excluded from CI builds (the `esphome-all` script only processes top-level YAML files).

## Devices

- **water-pump.yaml** - ESP32-S3 Lolin S3 Mini water pump controller
  - Decommissioned: 2025-11-10
  - Reason: Build issues with neopixelbus requiring Arduino framework while other ESP32 devices migrated to ESP-IDF
