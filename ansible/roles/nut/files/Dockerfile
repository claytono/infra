# syntax=docker/dockerfile:1@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d

FROM caddy:2.10.0-builder@sha256:acf9b51367f2cdd94a5621b1d5f37a3d095b5f6e2157c83b48d2b1f127576366 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.4.0

FROM caddy:2.10.0@sha256:e23538fceb12f3f8cc97a174844aa99bdea7715023d6e088028850fd0601e2e2

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
