#!/usr/bin/env bash
set -euo pipefail

# Entrypoint for openbsd-kvm container
# Supports two boot modes controlled by BOOT_MODE:
#  - install : boot the installer ISO (requires ISO present or OPENBSD_ISO_URL set)
#  - boot    : boot the qcow2 disk image
#
# Set BOOT_MODE via docker-compose.yml or docker run -e BOOT_MODE=install|boot
# Default: install (keeps prior behavior); change if you prefer boot as default.

OPENBSD_ISO_URL="${OPENBSD_ISO_URL:-}"
ISO_NAME="${ISO_NAME:-install.iso}"
DISK_NAME="${DISK_NAME:-disk.qcow2}"
DISK_SIZE="${DISK_SIZE:-20G}"
MEMORY="${MEMORY:-2048}"   # in MB
CORES="${CORES:-2}"
HOST_SSH_PORT="${HOST_SSH_PORT:-2222}"
GRAPHICAL="${GRAPHICAL:-false}"
BOOT_MODE="${BOOT_MODE:-install}"   # "install" or "boot"

# VNC / noVNC
VNC_DISPLAY="${VNC_DISPLAY:-1}"     # QEMU display number (1 => 5901)
NOVNC_PORT="${NOVNC_PORT:-6080}"    # Port to serve noVNC web UI inside container
# Compute TCP VNC port from display
VNC_PORT=$((5900 + VNC_DISPLAY))

IMAGES_DIR="/images"
ISO_PATH="${IMAGES_DIR}/${ISO_NAME}"
DISK_PATH="${IMAGES_DIR}/${DISK_NAME}"
NOVNC_WEB_DIR="/opt/noVNC"

mkdir -p "${IMAGES_DIR}"
chmod 0777 "${IMAGES_DIR}" || true

# Verify required binaries
if ! command -v qemu-img >/dev/null 2>&1; then
  echo "ERROR: qemu-img not found in the container. Ensure the image includes qemu/qemu-img."
  exit 1
fi
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: qemu-system-x86_64 not found in the container."
  exit 1
fi

# Ensure ISO present if needed (download if OPENBSD_ISO_URL provided)
if [ "${BOOT_MODE}" = "install" ]; then
  if [ ! -f "${ISO_PATH}" ]; then
    if [ -n "${OPENBSD_ISO_URL}" ]; then
      echo "ISO not found at ${ISO_PATH}. Downloading from ${OPENBSD_ISO_URL} ..."
      tmp_iso="${ISO_PATH}.part"
      curl -L --fail --retry 5 --retry-delay 3 -o "${tmp_iso}" "${OPENBSD_ISO_URL}"
      mv "${tmp_iso}" "${ISO_PATH}"
      echo "Downloaded ISO to ${ISO_PATH}."
    else
      echo "ERROR: BOOT_MODE=install but ISO not found at ${ISO_PATH} and OPENBSD_ISO_URL is not set."
      echo "Set OPENBSD_ISO_URL or place the ISO at ${ISO_PATH}."
      exit 1
    fi
  fi
fi

# Create disk image if missing (both modes may need a disk)
if [ ! -f "${DISK_PATH}" ]; then
  echo "Creating qcow2 disk ${DISK_PATH} (${DISK_SIZE}) ..."
  qemu-img create -f qcow2 "${DISK_PATH}" "${DISK_SIZE}"
fi

# Check KVM availability
USE_KVM="false"
if [ -e /dev/kvm ]; then
  if [ -r /dev/kvm ] || [ -w /dev/kvm ]; then
    USE_KVM="true"
  else
    echo "Warning: /dev/kvm exists but is not accessible (permissions). KVM disabled."
  fi
else
  echo "Note: /dev/kvm not present inside container; QEMU will run in emulation mode (slow)."
fi

QEMU_BIN="qemu-system-x86_64"
QEMU_ARGS=()

# KVM / CPU
if [ "${USE_KVM}" = "true" ]; then
  QEMU_ARGS+=("-enable-kvm" "-cpu" "host")
  echo "KVM available: enabling -enable-kvm."
else
  echo "KVM not available: running without -enable-kvm (emulation)."
fi

# Memory & CPUs
QEMU_ARGS+=("-m" "${MEMORY}" "-smp" "${CORES}")

# Disk as virtio
QEMU_ARGS+=("-drive" "file=${DISK_PATH},if=virtio,cache=writeback,format=qcow2")

# Mode-specific boot configuration
case "${BOOT_MODE}" in
  install)
    echo "BOOT_MODE=install: attaching ISO ${ISO_PATH} as CD-ROM and setting boot to CD."
    if [ -f "${ISO_PATH}" ]; then
      QEMU_ARGS+=("-cdrom" "${ISO_PATH}" "-boot" "d")
    else
      echo "ERROR: expected ISO at ${ISO_PATH} but missing (should have been downloaded earlier)."
      exit 1
    fi
    ;;
  boot)
    echo "BOOT_MODE=boot: booting from disk image."
    # Ensure we boot from disk first
    QEMU_ARGS+=("-boot" "c")
    ;;
  *)
    echo "ERROR: unknown BOOT_MODE='${BOOT_MODE}'. Use 'install' or 'boot'."
    exit 1
    ;;
esac

# Networking: user-mode with hostfwd for SSH (host -> guest via container port)
QEMU_ARGS+=("-netdev" "user,id=net0,hostfwd=tcp::${HOST_SSH_PORT}-:22")
QEMU_ARGS+=("-device" "virtio-net-pci,netdev=net0")

# Graphics / VNC / noVNC
if [ "${GRAPHICAL}" = "true" ]; then
  # Bind QEMU's VNC to localhost only; websockify will proxy it to the browser.
  QEMU_ARGS+=("-vnc" "127.0.0.1:${VNC_DISPLAY}")
  echo "Starting QEMU with VNC on 127.0.0.1:${VNC_PORT} (display ${VNC_DISPLAY})."

  # Start websockify (noVNC) to proxy /opt/noVNC to NOVNC_PORT and forward to the VNC port
  if [ -d "${NOVNC_WEB_DIR}" ]; then
    if command -v websockify >/dev/null 2>&1; then
      echo "Starting websockify serving ${NOVNC_WEB_DIR} on port ${NOVNC_PORT}, proxying to 127.0.0.1:${VNC_PORT}"
      # Bind to 0.0.0.0 so Docker port mapping is reachable from the host
      websockify --web "${NOVNC_WEB_DIR}" --bind=0.0.0.0 "${NOVNC_PORT}" 127.0.0.1:${VNC_PORT} --heartbeat=30 &
      WEBSOCKIFY_PID=$!
      echo "websockify pid=${WEBSOCKIFY_PID}"
    else
      echo "WARNING: websockify not found. noVNC will not be available."
    fi
  else
    echo "WARNING: noVNC web directory ${NOVNC_WEB_DIR} not found. noVNC will not be available."
  fi

  # Do not add -nographic so VNC works
else
  # Headless serial mode
  QEMU_ARGS+=("-nographic" "-serial" "mon:stdio")
  echo "Starting QEMU in headless mode (serial console)."
fi

echo "Final QEMU command:"
echo "${QEMU_BIN} ${QEMU_ARGS[*]}"

# Execute QEMU (replace shell)
exec "${QEMU_BIN}" "${QEMU_ARGS[@]}"
