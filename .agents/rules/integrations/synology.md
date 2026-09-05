# Synology

`fs2` is a Synology DS2419+ with its rear serial console connected to infra1.

When troubleshooting fs2, use the serial console as an independent source of
information:

- Current transcript: `/var/log/conserver/fs2.log` on infra1
- Rotated transcripts: `/var/log/conserver/` on infra1
- Interactive console: `ssh -t infra1 sudo console fs2`
- Retention: daily rotation for 365 days

The serial console and its logs remain available independently of DSM and fs2's
network connectivity.
