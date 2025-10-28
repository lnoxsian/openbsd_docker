FROM debian:bookworm-slim

# Install required packages including qemu-system-aarch64, websockify and wget
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
 \
 # Ensure a place for QEMU ROMs and attempt to install the efi-virtio ROM used by some virtio devices
 && mkdir -p /usr/share/qemu /usr/share/qemu/pc-bios \
 && wget -O /usr/share/qemu/efi-virtio.rom "https://gitlab.com/qemu-project/qemu/-/raw/master/pc-bios/efi-virtio.rom" \
 && cp /usr/share/qemu/efi-virtio.rom /usr/share/qemu/pc-bios/efi-virtio.rom \
 && chmod 644 /usr/share/qemu/efi-virtio.rom /usr/share/qemu/pc-bios/efi-virtio.rom \
 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy the ARM64-specific entrypoint (expected to exist in build context)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/images"]
EXPOSE 6080 5901 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
