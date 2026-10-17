---
paths: ["kubernetes/**/*"]
---

# LoadBalancer Addresses

MetalLB gives LoadBalancer Services addresses on the Default VLAN and announces
them with L2 (ARP and NDP). Every address is assigned deliberately; MetalLB
never picks one on its own.

## One pool per address

`kubernetes/metallb/config.yaml` defines an `IPAddressPool` for each address,
named for what uses it. A pool holds one IPv4 address and, for dual-stack
Services, the matching IPv6 address, and sets `autoAssign: false`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: traefik
  namespace: metallb-system
spec:
  addresses:
    - 172.19.74.34/32
    - <prefix>::74:34/128
  autoAssign: false
```

The IPv6 address mirrors the IPv4 one as `<prefix>::74:<last octet>`, where
`<prefix>` is `infrastructure_ipv6_prefix`; see `docs/ipv6.md`. A single
`L2Advertisement` with no `ipAddressPools` advertises every pool from every node
except the control plane.

## Services select a pool

A Service names its pool with an annotation and never names an address. Do not
use `spec.loadBalancerIP` or `metallb.io/loadBalancerIPs`; keeping addresses out
of Services is what makes the MetalLB configuration the one place to change
them.

```yaml
metadata:
  annotations:
    metallb.io/address-pool: traefik
spec:
  type: LoadBalancer
  ipFamilyPolicy: RequireDualStack
```

- Set `ipFamilyPolicy: RequireDualStack` for Services that LAN clients reach
  over IPv6. A Service without it is IPv4-only and gets just the pool's IPv4
  address.
- Give the Service an `external-dns.kubernetes.io/hostname` annotation when it
  needs a DNS name; see `.agents/rules/integrations/cloudflare.md`.

## Sharing an address

Services that listen on different ports can share an address by selecting the
same pool and carrying the same `metallb.io/allow-shared-ip` key. The `shared`
pool (`172.19.74.21`) works this way with the key `plexmediaserver`.

## Adding or moving an address

Add a pool for the new address to `kubernetes/metallb/config.yaml`, then point
the Service at it. Choose an address in `172.19.74.0/24` that nothing else uses:
static hosts are listed in `opentofu/locals.tf`, and pods with their own LAN
address have records under "Static service IPs" in
`opentofu/modules/dns/oneill.tf`.

MetalLB rejects pools that overlap, so an address belongs to exactly one pool.
Moving an address to a different pool means deleting the old pool first, and the
Services using it lose the address until the new pool exists.

## Not MetalLB

- Pods with their own macvlan address on the LAN, `172.19.74.22` (qBittorrent)
  and `172.19.74.29` (bambuddy). No pool contains these; see
  [lan-attachments.md](./lan-attachments.md).
- Services with `loadBalancerClass: tailscale` are exposed by the Tailscale
  operator, not MetalLB.
