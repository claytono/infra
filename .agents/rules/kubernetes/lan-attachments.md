---
paths: ["kubernetes/**/*"]
---

# LAN Attachments

A pod that must have its own address on the Default VLAN gets a Multus macvlan
interface from a NetworkAttachmentDefinition. Use one only when the application
itself has to be on the LAN; everything else uses a LoadBalancer Service (see
[load-balancers.md](./load-balancers.md)). The existing ones are examples:

- `kubernetes/1-nad/network-attachment-definition.yaml`: `lan-172-19-74`, shared
  by pods that pick their IPv4 address in their Multus annotation. bambuddy's
  virtual printer uses it.
- `kubernetes/qbittorrent/nad.yaml`: `lan-qbittorrent`, dedicated to
  qBittorrent, with fixed IPv4 and IPv6 addresses, a fixed MAC, and source-based
  routing.

## Ignore router advertisements

Every chain starts with `passthru` and a `tuning` step that turns off router
advertisements in the pod's network namespace:

```json
"plugins": [
  { "type": "passthru" },
  {
    "type": "tuning",
    "sysctl": { "net.ipv6.conf.default.accept_ra": "0" }
  },
  { "type": "macvlan", ... }
]
```

Otherwise the UDM's router advertisements give the interface a SLAAC address and
a second IPv6 default route alongside the pod network's. Setting `accept_ra` on
the interface after macvlan runs leaves a window for an advertisement to arrive;
when the interface has an IPv6 gateway, one always does, because macvlan brings
the link up and waits for DAD before returning. The kernel copies the
namespace's `default` settings into an interface when it is created, so setting
the default first closes the window. `passthru` is there only because `tuning`
cannot be first in a chain.

## Addresses

- Choose an address that nothing else uses (see
  [load-balancers.md](./load-balancers.md)) and give it a record under "Static
  service IPs" in `opentofu/modules/dns/oneill.tf`. Those records are the list
  of macvlan addresses. Derive an IPv6 record from
  `var.infrastructure_ipv6_prefix`.
- Use `strategy: Recreate`, so two pods never hold the same address during a
  rollout.
- A dedicated NetworkAttachmentDefinition can fix the MAC address with macvlan's
  `mac` option, which keeps the UDM's neighbor entry and client record stable
  across restarts.

## Sending from the LAN address

The pod network stays the pod's default route, so traffic from the LAN address
reaches only the LAN subnet. When the application must reach the internet from
its LAN address, as qBittorrent does, add `sbr` last in the chain and give each
static address a `gateway` in IPAM's `addresses`, not a default route in
`routes`. `sbr` uses the gateway to build a routing table used only for traffic
from that address; a default route in `routes` would conflict with the pod
network's. The application then has to bind to the interface.

## Limitations

- The node running the pod cannot reach its macvlan addresses; macvlan isolates
  them from the parent interface.
- NetworkPolicies do not apply to the macvlan interface, so anything the pod
  listens on for all addresses is reachable from the LAN.
