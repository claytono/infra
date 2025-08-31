# syntax=docker/dockerfile:1@sha256:38387523653efa0039f8e1c89bb74a30504e76ee9f565e25c9a09841f9427b05

FROM caddy:2.10.2-builder@sha256:b33f07bbf5f8a431f224b3df0f0e709f4c7cb484515df2cdf71218e6e6021205 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.4.0

FROM caddy:2.10.2@sha256:4163a5c7b7631707956db4057720ec75de429992d5e3aa518d54872c01644dbe

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
