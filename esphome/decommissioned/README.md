# Decommissioned ESPHome Devices

This directory contains ESPHome configuration files for devices that are no
longer in active use but are kept for reference.

These configurations are excluded from CI builds (the `esphome-all` script only
processes top-level YAML files).

## Devices

- **bedjet.yaml** - ESP32 BedJet climate controller
  - Decommissioned: 2026-08-16
  - Reason: BedJet integration is no longer in use
- **water-pump.yaml** - ESP32-S3 Lolin S3 Mini water pump controller
  - Decommissioned: 2025-11-10
  - Reason: Build issues with neopixelbus requiring Arduino framework while
    other ESP32 devices migrated to ESP-IDF
