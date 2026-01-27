# UniFi Integration

Query and manage the UniFi controller via `mcp-cli` using `go-unifi-mcp`.

## Configuration

Running in **eager mode** - all 242 tools are registered directly as MCP tools.

## Usage

```bash
# List all servers
mcp-cli

# Show unifi server tools
mcp-cli unifi

# Show tool schema
mcp-cli unifi/list_firewall_rule

# Call tool
mcp-cli unifi/list_device '{}'

# Get firewall rule details
mcp-cli unifi/get_firewall_rule '{"id": "rule-id-here"}'
```

## Available Tool Categories

Tools follow the pattern `{operation}_{resource}` where operation is one of:
list, get, create, update, delete.

- **Devices**: list_device, get_device, create_device, update_device,
  delete_device
- **Firewall Rules**: list_firewall_rule, get_firewall_rule,
  create_firewall_rule, update_firewall_rule, delete_firewall_rule
- **Firewall Groups**: list_firewall_group, get_firewall_group,
  create_firewall_group, update_firewall_group, delete_firewall_group
- **Firewall Zones**: list_firewall_zone, get_firewall_zone,
  create_firewall_zone, update_firewall_zone, delete_firewall_zone
- **Firewall Zone Policies**: list_firewall_zone_policy,
  get_firewall_zone_policy, create_firewall_zone_policy,
  update_firewall_zone_policy, delete_firewall_zone_policy
- **Networks**: list_network, get_network, create_network, update_network,
  delete_network
- **Port Forwarding**: list_port_forward, get_port_forward, create_port_forward,
  update_port_forward, delete_port_forward
- **Users**: list_user, get_user, create_user, update_user, delete_user
- **WLANs**: list_wlan, get_wlan, create_wlan, update_wlan, delete_wlan
- **Settings**: `get_setting_*`, `update_setting_*` (46+ setting types)
- **DNS Records**: list_dns_record, get_dns_record, create_dns_record,
  update_dns_record, delete_dns_record
- **DHCP Options**: list_dhcp_option, get_dhcp_option, create_dhcp_option,
  update_dhcp_option, delete_dhcp_option

## Firewall IPv6 Support

Full IPv6 support via filipowm/go-unifi:

- IPv6 rulesets: WANv6_IN, WANv6_OUT, WANv6_LOCAL, LANv6_IN, etc.
- Fields: src_address_ipv6, dst_address_ipv6, protocol_v6, icmpv6_typename
- Zone-based policies with ip_version (ipv4/ipv6/both)
