---
paths: ["kubernetes/hass/**/*", "esphome/**/*"]
---

# Home Assistant

## REST API

Query and change Home Assistant through its REST API at
`https://hass.k.oneill.net/api/`. `$HASS_BEARER_TOKEN` is available in the
environment (loaded from 1Password via `.secrets.tmpl` / `.envrc`).

```bash
H="Authorization: Bearer $HASS_BEARER_TOKEN"
U=https://hass.k.oneill.net/api
```

**Find entities:**

```bash
curl -s -H "$H" $U/states | jq -r '.[].entity_id | select(test("temperature"))'
curl -s -H "$H" $U/states | jq -r '.[].entity_id | select(startswith("light."))'
```

**Get entity state and attributes:**

```bash
curl -s -H "$H" $U/states/climate.office_thermostat
```

**Check history** (state changes between two times; without `end_time` both
calls return only the first day after `start`; `date -d` is GNU date from the
dev shell):

```bash
start=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
end=$(date -u +%Y-%m-%dT%H:%M:%SZ)
curl -s -H "$H" \
  "$U/history/period/$start?end_time=$end&filter_entity_id=climate.office_thermostat&minimal_response&no_attributes"
curl -s -H "$H" "$U/logbook/$start?end_time=$end&entity=climate.office_thermostat"
```

**Debug issues:**

```bash
curl -s -H "$H" $U/error_log | tail -100
curl -s -H "$H" $U/states | jq -r '.[] | select(.entity_id | startswith("automation.")) | "\(.entity_id) \(.state) \(.attributes.last_triggered)"'
```

**Evaluate a template** (read-only; useful for counts and lookups across
entities):

```bash
curl -s -H "$H" -H "Content-Type: application/json" \
  -d '{"template":"{{ states.light | selectattr(\"state\", \"eq\", \"on\") | list | count }}"}' \
  $U/template
```

**Create or update a UI automation, then reload automations:**

```bash
curl -s -X POST \
  -H "$H" \
  -H "Content-Type: application/json" \
  -d '{ ... }' \
  "$U/config/automation/config/<automation_id>"

curl -s -X POST -H "$H" $U/services/automation/reload
```

`$U/services` lists every service; call one with
`curl -s -X POST -H "$H" -H "Content-Type: application/json" -d '{...}' "$U/services/<domain>/<service>"`.
A service that returns data, such as `weather.get_forecasts`, answers HTTP 400
unless the URL ends in `?return_response`.

## Prometheus Metrics (Alternative)

Script: `kubernetes/hass/get-prom-metrics`

Cache output to avoid repeated API calls:

```bash
./kubernetes/hass/get-prom-metrics > /tmp/hass-metrics.txt
grep -i "keyword" /tmp/hass-metrics.txt
```

Use for numeric metrics; use the REST API for entity state and troubleshooting.
