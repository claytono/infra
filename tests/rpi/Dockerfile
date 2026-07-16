# QEMU Raspberry Pi 3B emulator for testing RPi OS images
FROM debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd

RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-arm \
    qemu-utils \
    e2fsprogs \
    kpartx \
    dosfstools \
    fdisk \
    openssh-client \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /work

ENTRYPOINT ["/entrypoint.sh"]
