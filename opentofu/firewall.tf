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

# Allow basement clock → K8s ingress for weather backgrounds
resource "unifi_firewall_rule" "iot_allow_basement_clock_ingress" {
  name       = "Allow Basement Clock to K8s Ingress"
  action     = "accept"
  ruleset    = "LAN_IN"
  rule_index = 20050

  protocol    = "tcp"
  src_address = "172.20.6.10"
  dst_address = "172.19.74.34"
  dst_port    = "443"

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

# --- LANv6_IN rules ---
# The LAN_IN rules above apply only to IPv4. IoT and Default both have
# delegated IPv6 prefixes, and LANv6_IN accepts everything unless these rules
# say otherwise. The rules match prefixes because the provider rejects any
# network type except ADDRv4 and NETv4. The controller requires IPv6 rule
# indices in the 25000 range.

# Allow MQTT TLS from IoT to mosquitto's IPv6 load balancer address
resource "unifi_firewall_rule" "iot_allow_mqtt_tls_v6" {
  name       = "Allow IoT MQTT TLS (IPv6)"
  action     = "accept"
  ruleset    = "LANv6_IN"
  rule_index = 25100

  # The controller rejects a port unless the IPv4 protocol is also set.
  protocol         = "tcp"
  protocol_v6      = "tcp"
  src_address_ipv6 = "${local.iot_ipv6_prefix}::/64"
  dst_address_ipv6 = "${local.infrastructure_ipv6_prefix}::74:21"
  dst_port         = "8883"

  state_new = true
}

# Block IoT → Default. basement-clock has no IPv6 address, so its IPv4 allow
# has no IPv6 counterpart; if it gains one, it would try Traefik's AAAA
# record and be dropped here.
resource "unifi_firewall_rule" "iot_block_to_internal_v6" {
  name       = "Block IoT to Internal (IPv6)"
  action     = "drop"
  ruleset    = "LANv6_IN"
  rule_index = 25200

  protocol_v6      = "all"
  src_address_ipv6 = "${local.iot_ipv6_prefix}::/64"
  dst_address_ipv6 = "${local.infrastructure_ipv6_prefix}::/64"

  state_new = true

  logging = true
}

# --- WANv6_IN rules ---
# WANv6_IN drops new connections from the internet unless a rule here accepts
# them. IPv4 needs a port forward instead; qBittorrent's was created by hand on
# the UDM.

# Allow BitTorrent peers to reach qBittorrent's macvlan address
resource "unifi_firewall_rule" "allow_qbittorrent_v6" {
  name       = "Allow qBittorrent (IPv6)"
  action     = "accept"
  ruleset    = "WANv6_IN"
  rule_index = 25100

  # The controller rejects a port unless the IPv4 protocol is also set.
  protocol         = "tcp_udp"
  protocol_v6      = "tcp_udp"
  dst_address_ipv6 = "${local.infrastructure_ipv6_prefix}::74:22"
  dst_port         = "51414"

  state_new = true
}
