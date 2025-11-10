# syntax=docker/dockerfile:1@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6

# Pin Caddy to 2.9.1 until route53 plugin issue is resolved
# https://github.com/caddy-dns/route53/issues/58
FROM caddy:2.10.0-builder@sha256:fe8d0d6cdbfd382197c4d715ffd5b41210165e2f64a81ce546ae63eeef35873a AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.5.0

FROM caddy:2.10.2@sha256:9e95012adcbbd599f853cb315b986781845c238f9e52aa3652798758cca01422

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
