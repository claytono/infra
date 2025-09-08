# syntax=docker/dockerfile:1@sha256:38387523653efa0039f8e1c89bb74a30504e76ee9f565e25c9a09841f9427b05

# Pin Caddy to 2.9.1 until route53 plugin issue is resolved
# https://github.com/caddy-dns/route53/issues/58
FROM caddy:2.9.1-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.5.0

FROM caddy:2.9.1

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
