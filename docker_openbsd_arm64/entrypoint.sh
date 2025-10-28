#!/bin/bash
set -euo pipefail

# Simple ARM64-specific entrypoint: no UID/chown logic, downloads allowed, forces aarch64 QEMU
QEMU_IMG=${QEMU_IMG:-/images/openbsd.img}
QEMU_IMG_SIZE=${QEMU_IMG_SIZE:-8G}
QEMU_ISO=${QEMU_ISO:-/images/openbsd-install.iso}
BOOT_MODE=${BOOT_MODE:-disk}
QEMU_MEM=${QEMU_MEM:-1024}
NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_DISPLAY=${VNC_DISPLAY:-1}
VNC_PORT=$((5900 + VNC_DISPLAY))
EXTRA_QEMU_ARGS=${EXTRA_QEMU_ARGS:-}

log() { echo "entrypoint-arm64: $*" >&2; }

download_to_dir() {
  local url="$1"; local dest_dir="$2"
  mkdir -p "$dest_dir"
  local fname
  fname=$(basename "$url")
  fname="${fname%%\?*}"
  if [ -z "$fname" ] || [ "$fname" = "/" ]; then
    fname="downloaded-file-$(date +%s)"
  fi
  local dest="$dest_dir/$fname"
  if [ -f "$dest" ]; then
    log "File exists, skipping: $dest"
  else
    log "Downloading $url -> $dest"
    wget --tries=3 --timeout=30 -O "$dest" "$url" 1>&2 || { log "ERROR: download failed: $url"; return 1; }
  fi
  sync
  local abs
  abs=$(readlink -f "$dest" 2>/dev/null || printf '%s\n' "$dest")
  if [ ! -s "$abs" ]; then
    log "ERROR: downloaded file is missing or empty: $abs"
    return 2
  fi
  printf '%s\n' "$abs"
}

mkdir -p /images
IMAGES_DIR="/images"
if [ ! -w "$IMAGES_DIR" ]; then
  log "$IMAGES_DIR not writable, using /tmp/images"
  IMAGES_DIR="/tmp/images"
  mkdir -p "$IMAGES_DIR"
fi

if [[ "${QEMU_ISO}" =~ ^https?:// ]]; then
  log "Downloading ISO to ${IMAGES_DIR}"
  QEMU_ISO=$(download_to_dir "$QEMU_ISO" "$IMAGES_DIR") || { log "Failed to download ISO"; exit 1; }
  log "ISO downloaded to $QEMU_ISO"
fi

if [[ "${QEMU_IMG}" =~ ^https?:// ]]; then
  log "Downloading disk image to ${IMAGES_DIR}"
  QEMU_IMG=$(download_to_dir "$QEMU_IMG" "$IMAGES_DIR") || { log "Failed to download IMG"; exit 1; }
  log "IMG downloaded to $QEMU_IMG"
fi

if [ ! -f "$QEMU_IMG" ]; then
  log "Creating disk image $QEMU_IMG (${QEMU_IMG_SIZE})"
  qemu-img create -f qcow2 "$QEMU_IMG" "$QEMU_IMG_SIZE"
fi

if [ "$BOOT_MODE" = "install" ]; then
  if [ ! -f "$QEMU_ISO" ]; then
    log "ERROR: BOOT_MODE=install but ISO not found at $QEMU_ISO"
    exit 1
  fi
  BOOT_ARGS=(-cdrom "$QEMU_ISO" -boot d)
else
  BOOT_ARGS=(-boot c)
fi

QEMU_BIN="qemu-system-aarch64"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  log "ERROR: qemu-system-aarch64 not found in container."
  exit 1
fi

QEMU_CMD=("$QEMU_BIN" -machine virt,accel=kvm -cpu host -m "$QEMU_MEM" -drive "file=${QEMU_IMG},if=virtio,format=qcow2" -vnc "0.0.0.0:${VNC_DISPLAY}" -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0 "${BOOT_ARGS[@]}")
if [ -n "$EXTRA_QEMU_ARGS" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS_ARRAY=($EXTRA_QEMU_ARGS)
  QEMU_CMD+=("${EXTRA_ARGS_ARRAY[@]}")
fi

log "Starting QEMU (aarch64): ${QEMU_CMD[*]}"
"${QEMU_CMD[@]}" &
QEMU_PID=$!
trap 'log "Stopping QEMU (pid=$QEMU_PID)"; kill -TERM "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true' EXIT

sleep 1

if ! command -v websockify >/dev/null 2>&1; then
  log "ERROR: websockify missing."
  exit 1
fi

log "Starting websockify on port $NOVNC_PORT -> localhost:$VNC_PORT"
exec websockify --web /opt/novnc "$NOVNC_PORT" "localhost:$VNC_PORT"
