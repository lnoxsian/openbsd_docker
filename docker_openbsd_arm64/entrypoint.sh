#!/bin/bash
set -euo pipefail

# ARM64-specific entrypoint: boot installer in UEFI (pflash) mode when possible.
# Does NOT change ownership of downloaded/created files.
QEMU_IMG=${QEMU_IMG:-/images/openbsd.img}
QEMU_IMG_SIZE=${QEMU_IMG_SIZE:-8G}
QEMU_ISO=${QEMU_ISO:-/images/install78.iso}
BOOT_MODE=${BOOT_MODE:-install}    # default to install (you can set disk)
QEMU_MEM=${QEMU_MEM:-2048}
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
    log "File exists, skipping download: $dest"
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

# Ensure images dir exists (volume may provide it)
mkdir -p "$(dirname "$QEMU_IMG")"
mkdir -p /images
IMAGES_DIR="/images"
if [ ! -w "$IMAGES_DIR" ]; then
  log "Warning: $IMAGES_DIR not writable, falling back to /tmp/images"
  IMAGES_DIR="/tmp/images"
  mkdir -p "$IMAGES_DIR"
fi

# Download ISO or IMG if URLs were given (update variable to local path)
if [[ "${QEMU_ISO}" =~ ^https?:// ]]; then
  log "QEMU_ISO is a URL, downloading to ${IMAGES_DIR}"
  QEMU_ISO=$(download_to_dir "$QEMU_ISO" "$IMAGES_DIR") || { log "Failed to download ISO"; exit 1; }
  log "QEMU_ISO -> ${QEMU_ISO}"
fi

if [[ "${QEMU_IMG}" =~ ^https?:// ]]; then
  log "QEMU_IMG is a URL, downloading to ${IMAGES_DIR}"
  QEMU_IMG=$(download_to_dir "$QEMU_IMG" "$IMAGES_DIR") || { log "Failed to download IMG"; exit 1; }
  log "QEMU_IMG -> ${QEMU_IMG}"
fi

# Create disk if missing
if [ ! -f "$QEMU_IMG" ]; then
  log "Creating qcow2 disk: $QEMU_IMG (${QEMU_IMG_SIZE})"
  qemu-img create -f qcow2 "$QEMU_IMG" "$QEMU_IMG_SIZE"
fi

# Look for common aarch64 UEFI firmware (EDK2/OVMF) locations
FW_CANDIDATES=(
  "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
  "/usr/share/AAVMF/AAVMF_CODE.fd"
  "/usr/share/edk2/aarch64/QEMU_EFI.fd"
  "/usr/share/edk2-aarch64/QEMU_EFI.fd"
  "/usr/share/qemu/edk2-aarch64-code.fd"
  "/usr/share/OVMF/OVMF_CODE.fd"
)

UEFI_CODE=""
for f in "${FW_CANDIDATES[@]}"; do
  if [ -f "$f" ]; then
    UEFI_CODE="$f"
    break
  fi
done

UEFI_ARGS=()
if [ -n "$UEFI_CODE" ]; then
  log "Found UEFI firmware: $UEFI_CODE"
  # writable vars store (one per disk/VM). Keep it in images so it can persist.
  VARS_FILE="${IMAGES_DIR}/uefi-vars-$(basename "$UEFI_CODE").fd"
  if [ ! -f "$VARS_FILE" ]; then
    log "Creating UEFI vars file: $VARS_FILE"
    # create small writable pflash (64K)
    dd if=/dev/zero of="$VARS_FILE" bs=64k count=1 >/dev/null 2>&1 || \
      { log "ERROR: failed to create vars file $VARS_FILE"; exit 1; }
    chmod 666 "$VARS_FILE" 2>/dev/null || true
  fi
  # Add pflash code (readonly) and vars (writable). QEMU expects these as pflash drives.
  UEFI_ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=${UEFI_CODE}")
  UEFI_ARGS+=(-drive "if=pflash,format=raw,file=${VARS_FILE}")
else
  log "UEFI firmware not found in container. To boot in UEFI mode install EDK2/UEFI firmware into the image (e.g. install edk2-aarch64 or place a QEMU_EFI.fd) or rebuild the Dockerfile to include it."
  log "Falling back to non-UEFI boot (this will use the default firmware)."
fi

# Prepare boot args: for installer use -cdrom, for disk boot use default
if [ "$BOOT_MODE" = "install" ]; then
  if [ ! -f "$QEMU_ISO" ]; then
    log "ERROR: BOOT_MODE=install but ISO not found at $QEMU_ISO"
    exit 1
  fi
  BOOT_ARGS=(-cdrom "$QEMU_ISO" -boot d)
  log "Will boot installer ISO: $QEMU_ISO"
else
  BOOT_ARGS=(-boot c)
  log "Will boot disk: $QEMU_IMG"
fi

# Build the QEMU command (aarch64 virt machine)
QEMU_BIN="qemu-system-aarch64"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  log "ERROR: $QEMU_BIN not found in container. Please install qemu-system-aarch64 in the Docker image."
  exit 1
fi

QEMU_CMD=("$QEMU_BIN" -machine virt,accel=kvm -cpu host -m "$QEMU_MEM")
# Append UEFI pflash args if present (code readonly + vars)
if [ "${#UEFI_ARGS[@]}" -gt 0 ]; then
  QEMU_CMD+=("${UEFI_ARGS[@]}")
fi

# Primary disk (qcow2) and VNC
QEMU_CMD+=(-drive "file=${QEMU_IMG},if=virtio,format=qcow2")
QEMU_CMD+=(-vnc "0.0.0.0:${VNC_DISPLAY}")

# Network: use virtio-net-device (no ROM required) and user-mode with ssh forward
QEMU_CMD+=(-netdev user,id=net0,hostfwd=tcp::2222-:22)
QEMU_CMD+=(-device virtio-net-device,netdev=net0)

# Boot args (iso/disk)
QEMU_CMD+=("${BOOT_ARGS[@]}")

# Extra args (if any)
if [ -n "$EXTRA_QEMU_ARGS" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS_ARRAY=($EXTRA_QEMU_ARGS)
  QEMU_CMD+=("${EXTRA_ARGS_ARRAY[@]}")
fi

log "Starting QEMU (aarch64). Command: ${QEMU_CMD[*]}"
"${QEMU_CMD[@]}" &
QEMU_PID=$!
log "QEMU started (pid=${QEMU_PID})"

trap 'log "Stopping QEMU (pid=${QEMU_PID})"; kill -TERM "${QEMU_PID}" 2>/dev/null || true; wait "${QEMU_PID}" 2>/dev/null || true' EXIT

# Brief pause for QEMU to bring up VNC
sleep 1

if ! command -v websockify >/dev/null 2>&1; then
  log "ERROR: websockify not found. Install websockify in the image."
  exit 1
fi

log "Starting websockify/noVNC on port ${NOVNC_PORT} -> localhost:${VNC_PORT}"
exec websockify --web /opt/novnc "${NOVNC_PORT}" "localhost:${VNC_PORT}"
