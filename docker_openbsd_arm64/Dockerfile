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
 # Install AARCH64 UEFI firmware (EDK2/QEMU_EFI) into common locations so QEMU can use pflash (UEFI)
 && mkdir -p /usr/share/qemu-efi-aarch64 /usr/share/AAVMF /usr/share/edk2-aarch64 /usr/share/qemu \
 && wget --tries=3 --timeout=30 -O /usr/share/qemu-efi-aarch64/QEMU_EFI.fd "https://gitlab.com/qemu-project/qemu/-/raw/master/pc-bios/QEMU_EFI.fd" 1>&2 || true \
 && wget --tries=3 --timeout=30 -O /usr/share/AAVMF/AAVMF_CODE.fd "https://gitlab.com/qemu-project/qemu/-/raw/master/pc-bios/AAVMF_CODE.fd" 1>&2 || true \
 && cp -n /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/edk2-aarch64/QEMU_EFI.fd 2>/dev/null || true \
 && cp -n /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/qemu/QEMU_EFI.fd 2>/dev/null || true \
 && chmod 644 /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/edk2-aarch64/QEMU_EFI.fd /usr/share/qemu/QEMU_EFI.fd 2>/dev/null || true \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Copy the ARM64-specific entrypoint (expected to exist in build context)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/images"]
EXPOSE 6080 5901 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
