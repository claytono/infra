# Firewall rules for the UniFi Security Gateway
#
# Existing rules were manually created and imported into state.
# New rules are created via OpenTofu.

data "unifi_network" "iot" {
  name = "IOT"
}

# --- WAN_LOCAL rules ---

resource "unifi_firewall_rule" "allow_icmp" {
  name       = "Allow ICMP"
  action     = "accept"
  ruleset    = "WAN_LOCAL"
  rule_index = 20000
  protocol   = "icmp"
}

# --- WANv6_LOCAL rules ---

resource "unifi_firewall_rule" "allow_icmpv6_wan" {
  name        = "Allow ICMPv6 to Router"
  action      = "accept"
  ruleset     = "WANv6_LOCAL"
  rule_index  = 25001
  protocol_v6 = "icmpv6"
}

# --- LANv6_LOCAL rules ---

resource "unifi_firewall_rule" "allow_icmpv6_lan" {
  name        = "Allow ICMPv6 from LAN"
  action      = "accept"
  ruleset     = "LANv6_LOCAL"
  rule_index  = 25001
  protocol_v6 = "icmpv6"
}

# --- LAN_IN rules ---

# Allow MQTT TLS from IoT to mosquitto (before logging rule)
resource "unifi_firewall_rule" "iot_allow_mqtt_tls" {
  name       = "Allow IoT MQTT TLS"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20000

  protocol         = "tcp"
  src_network_id   = data.unifi_network.iot.id
  src_network_type = "NETv4"
  dst_address      = "172.19.74.21"
  dst_port         = "8883"

  state_new = true
}

# Log IoT → Default LAN traffic (existing rule, codified as-is)
resource "unifi_firewall_rule" "iot_log_to_default_lan" {
  name       = "Log IoT to Other VLANs"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20001

  protocol         = "all"
  src_network_id   = data.unifi_network.iot.id
  src_network_type = "NETv4"
  dst_address      = "172.19.74.0/24"

  state_new = true

  logging = true
}
