# Home Assistant Metrics and Entity Discovery

Script: `kubernetes/hass/get-prom-metrics`

## Usage Pattern

Cache output to avoid repeated API calls:

```bash
./kubernetes/hass/get-prom-metrics > /tmp/hass-metrics.txt
grep -i "keyword" /tmp/hass-metrics.txt
```

Only re-fetch if data has changed (e.g., new devices added).

## Common Discovery Patterns

- Entity names: `grep 'entity="sensor\.'`
- Binary sensors: `grep 'entity="binary_sensor\.'`
- Sensor values: `grep 'hass_sensor_temperature_celsius'`
- By friendly name: `grep -i 'friendly_name=".*keyword'`
