#!/usr/bin/env bash
set -euo pipefail

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
# Ensure the container user can write (avoid failing on some host setups)
chmod 0777 "${IMAGES_DIR}" || true

# Check qemu-img availability
if ! command -v qemu-img >/dev/null 2>&1; then
  echo "ERROR: qemu-img not found in the container. Ensure the image includes qemu/qemu-img."
  exit 1
fi

# Download ISO if missing and URL provided; fail if ISO missing and no URL
if [ ! -f "${ISO_PATH}" ]; then
  if [ -n "${OPENBSD_ISO_URL}" ]; then
    echo "ISO not found at ${ISO_PATH}. Downloading from ${OPENBSD_ISO_URL} ..."
    tmp_iso="${ISO_PATH}.part"
    # Use curl with retries and fail on http error
    curl -L --fail --retry 5 --retry-delay 3 -o "${tmp_iso}" "${OPENBSD_ISO_URL}"
    mv "${tmp_iso}" "${ISO_PATH}"
    echo "Downloaded ISO to ${ISO_PATH}."
  else
    echo "ERROR: ISO not found at ${ISO_PATH} and OPENBSD_ISO_URL is not set."
    echo "Set OPENBSD_ISO_URL in docker-compose.yml or place the ISO at ${ISO_PATH}."
    exit 1
  fi
fi

# Create disk image if missing
if [ ! -f "${DISK_PATH}" ]; then
  echo "Creating qcow2 disk ${DISK_PATH} (${DISK_SIZE}) ..."
  qemu-img create -f qcow2 "${DISK_PATH}" "${DISK_SIZE}"
fi

# Determine KVM availability
USE_KVM="false"
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] || [ -w /dev/kvm ]; then
    USE_KVM="true"
  else
    echo "Warning: /dev/kvm exists but is not accessible (permissions)."
    USE_KVM="false"
  fi
else
  echo "Note: /dev/kvm not present inside container; QEMU will run in emulation mode (slow)."
fi

QEMU_BIN="qemu-system-x86_64"
# Build QEMU args
QEMU_ARGS=()

if [ "${USE_KVM}" = "true" ]; then
  QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
  echo "KVM available: enabling -ENABLE-KVM."
else
  echo "KVM not available: starting in emulation mode (no -enable-kvm)."
fi

QEMU_ARGS+=("-m" "${MEMORY}" "-smp" "${CORES}")

# Drive (use virtio)
QEMU_ARGS+=("-drive" "file=${DISK_PATH},if=virtio,cache=writeback,format=qcow2")

# Attach ISO as CDROM and boot from it when present
if [ -f "${ISO_PATH}" ]; then
  QEMU_ARGS+=("-cdrom" "${ISO_PATH}" "-boot" "d")
fi

# Networking: user-mode with hostfwd for SSH
QEMU_ARGS+=("-netdev" "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:22")
QEMU_ARGS+=("-device" "virtio-net-pci,netdev=net0")

# Graphics
if [ "${GRAPHICAL}" = "true" ]; then
  QEMU_ARGS+=("-vga" "std")
  echo "Starting QEMU in graphical mode (vga std)."
else
  QEMU_ARGS+=("-nographic" "-serial" "mon:stdio")
  echo "Starting QEMU in headless mode (serial console)."
fi

echo "Launching: ${QEMU_BIN} ${QEMU_ARGS[*]}"
exec "${QEMU_BIN}" "${QEMU_ARGS[@]}"
