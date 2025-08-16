# syntax=docker/dockerfile:1@sha256:9857836c9ee4268391bb5b09f9f157f3c91bb15821bb77969642813b0d00518d

FROM caddy:2.10.0-builder@sha256:fe8d0d6cdbfd382197c4d715ffd5b41210165e2f64a81ce546ae63eeef35873a AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/route53@v1.4.0

FROM caddy:2.10.0@sha256:e23538fceb12f3f8cc97a174844aa99bdea7715023d6e088028850fd0601e2e2

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
