#!/bin/bash
set -euo pipefail

# Defaults (can be overridden via env)
QEMU_IMG=${QEMU_IMG:-/images/openbsd.img}
QEMU_IMG_SIZE=${QEMU_IMG_SIZE:-8G}    # Size used when creating a new qcow2 image (e.g. 10G, 512M)
QEMU_ISO=${QEMU_ISO:-/images/openbsd-install.iso}
BOOT_MODE=${BOOT_MODE:-disk}         # "install" -> boot ISO, "disk" -> boot disk image
QEMU_MEM=${QEMU_MEM:-1024}
NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_DISPLAY=${VNC_DISPLAY:-1}        # QEMU display number -> VNC port = 5900 + display
VNC_PORT=$((5900 + VNC_DISPLAY))
EXTRA_QEMU_ARGS=${EXTRA_QEMU_ARGS:-} # Extra qemu args you may want to pass

# log to stderr so helper functions can emit only machine-parsable stdout (path)
log() { echo "entrypoint: $*" >&2; }

# Helper: download a URL into /images and print the local path to STDOUT only
download_to_images() {
  local url="$1"
  local dest_dir="/images"
  mkdir -p "$dest_dir"
  local fname
  fname=$(basename "$url")
  # If URL ends in query string or contains characters, normalize filename
  # strip query params if any
  fname="${fname%%\?*}"
  local dest="$dest_dir/$fname"

  if [ -f "$dest" ]; then
    log "File already exists at $dest — skipping download."
  else
    log "Downloading $url -> $dest"
    # Use wget and send its output to stderr so this function's stdout remains only the path
    # --tries=3 for a few retries, --timeout=30 for network timeout
    wget --tries=3 --timeout=30 -O "$dest" "$url" 1>&2 || { log "ERROR: download failed: $url" >&2; return 1; }
  fi

  # Print only the destination path to stdout (so callers can capture it reliably)
  printf '%s\n' "$dest"
}

# Ensure images dir exists (volume may provide it)
mkdir -p "$(dirname "$QEMU_IMG")"
mkdir -p /images

# If QEMU_ISO is a URL, download it into /images and update the var to the downloaded local path.
if [[ "${QEMU_ISO}" =~ ^https?:// ]]; then
  downloaded_iso=$(download_to_images "$QEMU_ISO") || { log "Failed to download ISO $QEMU_ISO"; exit 1; }
  # downloaded_iso is a clean local path (printed by download_to_images)
  QEMU_ISO="$downloaded_iso"
  log "Using downloaded ISO: $QEMU_ISO"
fi

# If QEMU_IMG is a URL, download it into /images and update the var to the downloaded local path.
if [[ "${QEMU_IMG}" =~ ^https?:// ]]; then
  downloaded_img=$(download_to_images "$QEMU_IMG") || { log "Failed to download disk image $QEMU_IMG"; exit 1; }
  QEMU_IMG="$downloaded_img"
  log "Using downloaded disk image: $QEMU_IMG"
fi

# Create disk image if missing (only for disk image path that's not a downloaded file)
if [ ! -f "$QEMU_IMG" ]; then
  log "No disk at $QEMU_IMG — creating a ${QEMU_IMG_SIZE} qcow2 placeholder."
  qemu-img create -f qcow2 "$QEMU_IMG" "$QEMU_IMG_SIZE"
fi

# Prepare boot args
if [ "$BOOT_MODE" = "install" ]; then
  if [ ! -f "$QEMU_ISO" ]; then
    log "ERROR: BOOT_MODE=install but ISO not found at $QEMU_ISO"
    log "Place your OpenBSD installer ISO at $QEMU_ISO or change QEMU_ISO env var (or set QEMU_ISO to a URL)."
    exit 1
  fi
  # Pass the downloaded (or local) ISO path to QEMU via -cdrom
  BOOT_ARGS=(-cdrom "$QEMU_ISO" -boot d)
  log "Starting in install mode: booting ISO $QEMU_ISO"
else
  BOOT_ARGS=(-boot c)
  log "Starting in diskboot mode: booting disk $QEMU_IMG"
fi

# KVM enablement if available
KVM_OPTS=()
if [ -e /dev/kvm ]; then
  KVM_OPTS+=(-enable-kvm)
  log "KVM device found: enabling KVM for QEMU."
else
  log "No /dev/kvm found: QEMU will run in software emulation (slow)."
fi

# Networking: user-mode with guest SSH forwarded to host:2222 by default
NETDEV_ARGS=(-netdev user,id=net0,hostfwd=tcp::2222-:22 -device e1000,netdev=net0)

# Build QEMU command safely as an array
QEMU_CMD=(qemu-system-x86_64 -m "$QEMU_MEM" -drive file="$QEMU_IMG",if=virtio,format=qcow2 -vnc 0.0.0.0:"$VNC_DISPLAY")
QEMU_CMD+=("${NETDEV_ARGS[@]}")
QEMU_CMD+=("${KVM_OPTS[@]}")
QEMU_CMD+=("${BOOT_ARGS[@]}")
# Append extra args if provided (split on whitespace)
if [ -n "$EXTRA_QEMU_ARGS" ]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS_ARRAY=($EXTRA_QEMU_ARGS)
  QEMU_CMD+=("${EXTRA_ARGS_ARRAY[@]}")
fi

# Start QEMU in background
"${QEMU_CMD[@]}" &
QEMU_PID=$!
log "QEMU started (pid=$QEMU_PID). Command: ${QEMU_CMD[*]}"

# Ensure QEMU is killed when the container exits
trap 'log "Stopping QEMU (pid=$QEMU_PID)"; kill -TERM "$QEMU_PID" 2>/dev/null || true; wait "$QEMU_PID" 2>/dev/null || true' EXIT

# Wait briefly for QEMU to bind the VNC port (simple sleep; adjust if needed)
sleep 1

# Start websockify/noVNC using distro websockify executable
log "Starting websockify/noVNC on port $NOVNC_PORT -> localhost:$VNC_PORT"
exec websockify --web /opt/novnc "$NOVNC_PORT" "localhost:$VNC_PORT"
# websockify takes over foreground; when it exits container ends and trap will stop QEMU.
