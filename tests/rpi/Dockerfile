# QEMU Raspberry Pi 3B emulator for testing RPi OS images
FROM debian:trixie-slim@sha256:77ba0164de17b88dd0bf6cdc8f65569e6e5fa6cd256562998b62553134a00ef0

RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-arm \
    qemu-utils \
    e2fsprogs \
    kpartx \
    dosfstools \
    openssh-client \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /work

ENTRYPOINT ["/entrypoint.sh"]
