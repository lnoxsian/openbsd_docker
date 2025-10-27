FROM debian:bookworm-slim

# Install dependencies including the distro websockify package (more reliable than pip here)
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-utils \
    python3 \
    websockify \
    git \
    wget \
    ca-certificates \
 && git clone https://github.com/novnc/noVNC /opt/novnc \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Add entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/images"]
EXPOSE 6080 5901 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
