# ESPHome DHCP Reservation Management

ESPHome devices use DHCP with reservations managed via OpenTofu. The
`scripts/gen-esphome-hosts` script generates terraform configuration from
ESPHome YAML configs.

## Adding a New Device

### 1. Flash the Device

Flash the ESPHome config to the device. It will connect via DHCP and get an IP.

### 2. Get the MAC Address and IP

Find the device in the UDMP DHCP lease file:

```bash
ssh root@udmp.oneill.net 'grep "<devicename>" /data/udapi-config/dnsmasq.lease'
```

The output format is: `<timestamp> <mac> <ip> <hostname> <client-id>`

Example:

```text
1768736115 a4:cf:12:de:93:ea 172.20.4.97 opengarage-left-door *
```

If the device isn't found by hostname, list recent IoT network leases:

```bash
ssh root@udmp.oneill.net 'grep "172\.20\." /data/udapi-config/dnsmasq.lease'
```

### 3. Add Substitutions to ESPHome Config

Add the `mac` and `ip` substitutions to your ESPHome device config. MAC
addresses can be provided in either upper or lowercase; they are normalized to
uppercase in the generated Terraform.

```yaml
substitutions:
  devicename: my-device
  human_devicename: My Device
  mac: "A4:CF:12:DE:93:EA"
  ip: "172.20.4.97"
```

### 4. Generate and Apply Terraform

```bash
scripts/gen-esphome-hosts --plan   # Review changes first
scripts/gen-esphome-hosts --apply  # Apply after confirming
```

Always run `--plan` first to verify changes before applying. This regenerates
`opentofu/esphome-hosts.tf` and runs a targeted `tofu plan` or `tofu apply` to
create the DHCP reservation and DNS record.

## Removing a Device

1. Delete the ESPHome YAML file (or remove `mac`/`ip` substitutions)
2. Run `scripts/gen-esphome-hosts --apply`

## Script Flags

| Flag      | Behavior                                                 |
| --------- | -------------------------------------------------------- |
| (none)    | Generate `opentofu/esphome-hosts.tf`                     |
| `--check` | Compare against existing file, exit non-zero if outdated |
| `--force` | Skip devices missing mac/ip (warning instead of error)   |
| `--plan`  | Generate, then run targeted `tofu plan`                  |
| `--apply` | Generate, then run targeted `tofu apply`                 |

## Validation

The script validates:

- MAC format: colon-separated hex (e.g., `AA:BB:CC:DD:EE:FF`)
- IP range: must be in `172.20.4.0/22` (IoT network)
- No duplicate MACs or IPs across devices

## Pre-commit Hook

A pre-commit hook runs `scripts/gen-esphome-hosts --check` to ensure the
generated terraform stays in sync with ESPHome configs. If it fails, regenerate
with `scripts/gen-esphome-hosts` and commit the updated file.
