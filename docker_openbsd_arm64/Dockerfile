FROM debian:bookworm-slim

# Install required packages including qemu-system-aarch64 and websockify (distro package)
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    qemu-system-aarch64 \
    qemu-utils \
    python3 \
    websockify \
    wget \
    git \
    ca-certificates \
 && git clone https://github.com/novnc/noVNC /opt/novnc \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy the ARM64-specific entrypoint (expected to exist in build context)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/images"]
EXPOSE 6080 5901 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
