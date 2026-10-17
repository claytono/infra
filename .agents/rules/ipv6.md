# IPv6

The network is dual-stack. [docs/ipv6.md](../../docs/ipv6.md) describes how IPv6
is addressed and used: the Fios delegation and the variables that hold it,
static host addresses, the Kubernetes pod and Service ranges, and pods attached
to the LAN.

- Refer to the delegation through its variables (`infrastructure_ipv6_prefix`
  and `iot_ipv6_prefix` in Ansible and OpenTofu). Do not write the prefix in
  documentation or comments; write `<prefix>` and name the variable.
- When a file must contain the prefix literally, such as a Kubernetes manifest,
  add it to "Where the delegation is hard-coded" in `docs/ipv6.md`.
