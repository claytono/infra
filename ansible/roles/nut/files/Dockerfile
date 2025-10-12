# syntax=docker/dockerfile:1@sha256:b6afd42430b15f2d2a4c5a02b919e98a525b785b1aaff16747d2f623364e39b6

# Pin Caddy to 2.9.1 until route53 plugin issue is resolved
# https://github.com/caddy-dns/route53/issues/58
FROM caddy:2.9.1-builder@sha256:1609bfce85bd4452a875e4d459f25e602c484b5a36e9c015511b5bdbd3539784 AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.5.0

FROM caddy:2.9.1@sha256:748016f285ed8c43a9ce6e3aed6d92d3009d90ca41157950880f40beaf3ff62b

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
