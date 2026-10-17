# IPv6

Verizon Fios delegates a /56 to the UDM, which numbers each VLAN's /64 from it.
The prefixes are configuration variables, and everything that needs one refers
to the variable:

| VLAN    | IPv4             | IPv6                                                                                                   |
| ------- | ---------------- | ------------------------------------------------------------------------------------------------------ |
| Default | `172.19.74.0/24` | first /64: `infrastructure_ipv6_prefix` in `ansible/group_vars/all/ipv6.yaml` and `opentofu/locals.tf` |
| IoT     | `172.20.4.0/22`  | second /64: `iot_ipv6_prefix` in `opentofu/locals.tf`                                                  |
| Guest   |                  | third /64, not used in configuration                                                                   |

Hosts with static addresses use `<prefix>::74:<last IPv4 octet>`, so k1
(`172.19.74.134`) is `<prefix>::74:134`.

## Kubernetes

The cluster is dual-stack with IPv4 primary. Pod and Service addresses come from
the ULA `fd03:19:74::/48`, so they do not depend on the delegation:

- Pods: `fd03:19:74::/56`, a /64 per node
- Services: `fd03:19:74:ffff::/112`

Flannel masquerades pod IPv6 traffic leaving the cluster to the node's address.
LoadBalancer Services get addresses from the delegation through MetalLB,
mirroring their IPv4 addresses; see
`.agents/rules/kubernetes/load-balancers.md`.

A few pods have their own address on the LAN through a Multus macvlan interface.
They ignore the UDM's router advertisements, so the interface has only its
static address and the pod network stays the pod's only IPv6 default route; see
`.agents/rules/kubernetes/lan-attachments.md`.

### qBittorrent

qBittorrent cannot use a LoadBalancer address for peer traffic: its outgoing
IPv6 connections would come from the node's address, which is what trackers and
peers would learn. Instead, the `lan-qbittorrent` NetworkAttachmentDefinition in
`kubernetes/qbittorrent/nad.yaml` gives the pod a macvlan interface named `lan`
with `172.19.74.22` and `<prefix>::74:22` (`qbittorrent-lan.oneill.net`), and
qBittorrent's Network Interface preference binds it to `lan`. That preference
lives in qBittorrent's configuration volume, not in this repository.

The UDM forwards IPv4 port 51414 to `172.19.74.22`, and the
`allow_qbittorrent_v6` rule in `opentofu/firewall.tf` accepts IPv6 connections
to `<prefix>::74:22`. The web UI is reached through Traefik.

## Where the delegation is hard-coded

Verizon can change the delegation. These are the only places that contain it
literally, and each must be updated by hand when it changes:

- `ansible/group_vars/all/ipv6.yaml`: `infrastructure_ipv6_prefix`
- `opentofu/locals.tf`: `infrastructure_ipv6_prefix` and `iot_ipv6_prefix`
- `kubernetes/metallb/config.yaml`: the IPv6 address in each pool
- `kubernetes/qbittorrent/nad.yaml`: qBittorrent's macvlan address and gateway
- The UDM's Tailscale subnet routes, set by hand on the UDM with
  `tailscale set --advertise-routes=...`. The new route also needs approval in
  the Tailscale admin console, for both the UDM and infra1.

Searching the repository for the value of `infrastructure_ipv6_prefix`, ignoring
rendered output under `kubernetes/*/helm/`, finds these files.
