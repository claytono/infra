---
paths: ["kubernetes/hass/**/*", "esphome/**/*"]
---

# Home Assistant

## Entity Discovery & Troubleshooting

Use the **mcp-cli** skill to query Home Assistant. The `hass` server is
configured in `.mcp_servers.json`.

### Common Tasks

**Find entities:**

```bash
mcp-cli hass/search_entities_tool '{"query":"temperature"}'
mcp-cli hass/list_entities '{"domain":"light"}'
```

**Get entity state:**

```bash
mcp-cli hass/get_entity '{"entity_id":"sensor.office_temperature"}'
mcp-cli hass/get_entity '{"entity_id":"light.kitchen", "detailed":true}'
```

**Check history:**

```bash
mcp-cli hass/get_history '{"entity_id":"climate.office", "hours":24}'
```

**Debug issues:**

```bash
mcp-cli hass/get_error_log '{}'
mcp-cli hass/list_automations '{}'
```

**System overview:**

```bash
mcp-cli hass/system_overview '{}'
```

### Available Tools

| Tool                   | Purpose                      |
| ---------------------- | ---------------------------- |
| `get_entity`           | Get state of specific entity |
| `search_entities_tool` | Search entities by query     |
| `list_entities`        | List entities by domain      |
| `domain_summary_tool`  | Summary of domain's entities |
| `system_overview`      | Full HA system overview      |
| `list_automations`     | List all automations         |
| `get_history`          | Entity state history         |
| `get_error_log`        | HA error log                 |
| `call_service_tool`    | Call any HA service          |

## Prometheus Metrics (Alternative)

Script: `kubernetes/hass/get-prom-metrics`

Cache output to avoid repeated API calls:

```bash
./kubernetes/hass/get-prom-metrics > /tmp/hass-metrics.txt
grep -i "keyword" /tmp/hass-metrics.txt
```

Use for numeric metrics; use mcp-cli for entity state and troubleshooting.
