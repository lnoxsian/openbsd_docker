#!/usr/bin/env bash
set -euo pipefail

# Default values (can be overridden via env)
OPENBSD_ISO_URL="${OPENBSD_ISO_URL:-}"
ISO_NAME="${ISO_NAME:-install.iso}"
DISK_NAME="${DISK_NAME:-disk.qcow2}"
DISK_SIZE="${DISK_SIZE:-20G}"
MEMORY="${MEMORY:-2048}"   # in MB
CORES="${CORES:-2}"
HOST_SSH_PORT="${HOST_SSH_PORT:-2222}"
GRAPHICAL="${GRAPHICAL:-false}"

IMAGES_DIR="/images"
ISO_PATH="${IMAGES_DIR}/${ISO_NAME}"
DISK_PATH="${IMAGES_DIR}/${DISK_NAME}"

mkdir -p "${IMAGES_DIR}"
chown "${UID:-0}:${GID:-0}" "${IMAGES_DIR}" || true

# Ensure /dev/kvm is present and accessible
if [ ! -e /dev/kvm ]; then
  echo "ERROR: /dev/kvm not found inside container. Ensure the container was started with --device /dev/kvm and the host has KVM enabled."
  echo "Continuing without KVM will be very slow (emulation mode), do you want to continue? (y/N)"
  read -r REPLY || true
  if [[ "${REPLY:-N}" != "y" && "${REPLY:-Y}" != "Y" ]]; then
    exit 1
  fi
  USE_KVM="false"
else
  USE_KVM="true"
fi

# Download ISO if URL provided and ISO not already present
if [ -n "${OPENBSD_ISO_URL}" ] && [ ! -f "${ISO_PATH}" ]; then
  echo "Downloading OpenBSD ISO from ${OPENBSD_ISO_URL} to ${ISO_PATH} ..."
  curl -L --fail -o "${ISO_PATH}" "${OPENBSD_ISO_URL}"
  echo "Download complete."
fi

if [ ! -f "${ISO_PATH}" ]; then
  echo "Warning: ISO not found at ${ISO_PATH}. If you want to install, place the OpenBSD install ISO at ${ISO_PATH} or set OPENBSD_ISO_URL to download it."
fi

# Create disk image if missing
if [ ! -f "${DISK_PATH}" ]; then
  echo "Creating qcow2 disk ${DISK_PATH} (${DISK_SIZE}) ..."
  qemu-img create -f qcow2 "${DISK_PATH}" "${DISK_SIZE}"
fi

# Build QEMU command
QEMU_BIN="qemu-system-x86_64"
QEMU_ARGS=()

if [ "${USE_KVM}" = "true" ]; then
  QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
else
  # No kvm available: use slower emulation but still attempt to start
  echo "KVM not available: running in full emulation mode (slow)."
fi

QEMU_ARGS+=("-m" "${MEMORY}" "-smp" "${CORES}")

# Drive and CD
QEMU_ARGS+=("-drive" "file=${DISK_PATH},if=virtio,cache=writeback,format=qcow2")

if [ -f "${ISO_PATH}" ]; then
  QEMU_ARGS+=("-cdrom" "${ISO_PATH}" "-boot" "d")
fi

# Networking: user-mode with hostfwd (host -> container -> guest)
# This will make guest's port 22 reachable on the container at HOST_SSH_PORT,
# and the compose file exposes that same port to the Docker host.
QEMU_ARGS+=("-netdev" "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:22")
QEMU_ARGS+=("-device" "virtio-net-pci,netdev=net0")

# Graphics vs serial
if [ "${GRAPHICAL}" = "true" ]; then
  # Try a simple VGA display (may require X forwarding / host support)
  QEMU_ARGS+=("-vga" "std")
  echo "Starting QEMU in graphical mode. Ensure you can forward or access display from the container host."
else
  # Headless, use serial console
  QEMU_ARGS+=("-nographic" "-serial" "mon:stdio")
  echo "Starting QEMU in headless mode (nographic + serial)."
fi

echo "QEMU command:"
echo "${QEMU_BIN} ${QEMU_ARGS[*]}"

# Exec QEMU (replace shell)
exec "${QEMU_BIN}" "${QEMU_ARGS[@]}"
