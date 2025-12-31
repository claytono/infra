# QEMU Raspberry Pi 3B emulator for testing RPi OS images
FROM debian:trixie-slim@sha256:4bcb9db66237237d03b55b969271728dd3d955eaaa254b9db8a3db94550b1885

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
