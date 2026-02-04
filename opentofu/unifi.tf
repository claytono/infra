# UniFi DHCP Reservations for Kubernetes and infrastructure hosts
#
# These resources manage static DHCP reservations on the UDMP for hosts that
# need consistent IP addresses. The actual IP configuration on the hosts is
# managed via Ansible (see ansible/host_vars/*.yaml).
#
# Host definitions are in locals.tf (infrastructure_hosts) and shared with
# Route53 DNS records to ensure UniFi DHCP and DNS stay automatically in sync.
#
# ESPHome hosts are managed separately in esphome-hosts.tf (auto-generated).

resource "unifi_user" "infrastructure_hosts" {
  for_each = local.infrastructure_hosts

  mac              = each.value.mac
  name             = each.key
  note             = each.value.note
  fixed_ip         = each.value.ip
  local_dns_record = each.value.hostname
}

# --- Networks ---

resource "unifi_network" "dmz" {
  name    = "DMZ"
  purpose = "corporate"

  vlan_id      = 78
  subnet       = "172.19.78.0/24"
  dhcp_enabled = true
  dhcp_start   = "172.19.78.129"
  dhcp_stop    = "172.19.78.254"
}

# --- Switch port profiles ---

data "unifi_network" "default" {
  name = "Default"
}

resource "unifi_port_profile" "proxmox_trunk" {
  name                  = "Proxmox Trunk"
  forward               = "all"
  native_networkconf_id = data.unifi_network.default.id
}

# --- US XG 16 switch ---
# Import: tofu import unifi_device.usxg16 b4:fb:e4:56:ce:fe

resource "unifi_device" "usxg16" {
  mac  = "b4:fb:e4:56:ce:fe"
  name = "US XG 16"

  port_override {
    number          = 1
    name            = "p1"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  port_override {
    number          = 2
    name            = "p2"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  port_override {
    number          = 4
    name            = "p4"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }

  port_override {
    number          = 5
    name            = "p3"
    port_profile_id = unifi_port_profile.proxmox_trunk.id
  }
}
