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
# Rule indices are spaced 100 apart to allow inserting rules without renumbering.

# Allow MQTT TLS from IoT to mosquitto
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

# Allow IoT → DMZ (IoT is more trusted than DMZ)
resource "unifi_firewall_rule" "iot_allow_to_dmz" {
  name       = "Allow IoT to DMZ"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20100

  protocol         = "all"
  src_network_id   = data.unifi_network.iot.id
  src_network_type = "NETv4"
  dst_network_id   = unifi_network.dmz.id
  dst_network_type = "NETv4"

  state_new = true
}

# Block IoT → all internal networks (except explicit allows above)
resource "unifi_firewall_rule" "iot_block_to_internal" {
  name       = "Block IoT to Internal"
  action     = "drop"
  ruleset    = "LAN_IN"
  rule_index = 20200

  protocol         = "all"
  src_network_id   = data.unifi_network.iot.id
  src_network_type = "NETv4"
  dst_address      = "172.16.0.0/12"

  state_new = true

  logging = true
}

# Block DMZ → all internal networks
resource "unifi_firewall_rule" "dmz_block_to_internal" {
  name       = "Block DMZ to Internal"
  action     = "drop"
  ruleset    = "LAN_IN"
  rule_index = 20300

  protocol         = "all"
  src_network_id   = unifi_network.dmz.id
  src_network_type = "NETv4"
  dst_address      = "172.16.0.0/12"

  state_new = true

  logging = true
}
