#!/usr/bin/env bash
# run_in_docker.sh
# Interactive helper to build the OpenBSD-in-Docker image and run a container in either
# "install" mode (boot installer ISO) or "boot" mode (boot from qcow2 disk).
#
# This version adds checks to ensure Docker is installed and the Docker daemon is
# reachable. It also checks for /dev/kvm on the host and prompts about continuing
# in emulation mode if KVM is not available (honors --non-interactive).
#
# It now asks whether you want to expose the guest SSH port to the Docker host.
# If you answer "no", the script will not publish the SSH port on the host (the
# container will still configure QEMU hostfwd inside the container, but the host
# will not have a mapped port).
#
# Usage:
#   ./run_in_docker.sh
#   ./run_in_docker.sh --non-interactive    # will use defaults (no prompts)
#
set -euo pipefail

DEFAULT_IMAGE_TAG="openbsd_docker_amd64:latest"
DEFAULT_BOOT_MODE="install"   # install or boot
DEFAULT_GRAPHICAL="true"
DEFAULT_VNC_DISPLAY="1"
DEFAULT_NOVNC_PORT="6080"
DEFAULT_HOST_VNC_PORT="6080"
DEFAULT_HOST_VNC_RAW_PORT="5901"
DEFAULT_HOST_SSH_PORT="2222"
DEFAULT_MEMORY="2048"
DEFAULT_CORES="2"
DEFAULT_DISK_SIZE="20G"
DEFAULT_OPENBSD_ISO_URL="https://cdn.openbsd.org/pub/OpenBSD/7.4/amd64/install74.iso"

NONINTERACTIVE=0
for arg in "$@"; do
  case "$arg" in
    --non-interactive|-n) NONINTERACTIVE=1 ;;
    --help|-h)
      cat <<EOF
Usage: $0 [--non-interactive|-n]

Interactive script that:
 - builds the docker image (Dockerfile in current directory)
 - runs a docker container with sensible defaults and env vars for BOOT_MODE, etc.

Options:
  --non-interactive, -n   Use defaults and do not prompt.
  --help, -h              Show this help.

EOF
      exit 0
      ;;
  esac
done

prompt() {
  local var_name="$1"
  local default="$2"
  local prompt_text="$3"
  local result
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    result="$default"
  else
    # shellcheck disable=SC2162
    read -r -p "$prompt_text [$default]: " result
    result="${result:-$default}"
  fi
  eval "$var_name=\"\$result\""
}

# Check for docker availability and daemon responsiveness
check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    cat <<MSG
ERROR: 'docker' command not found. Please install Docker before proceeding.
 - Ubuntu / Debian: sudo apt install docker.io
 - CentOS/RHEL: sudo yum install docker
 - macOS: install Docker Desktop
See https://docs.docker.com/get-docker/
MSG
    exit 1
  fi

  # Check docker daemon access
  if ! docker info >/dev/null 2>&1; then
    cat <<MSG

ERROR: Docker appears to be installed but the daemon is not reachable, or your user
does not have permission to talk to Docker.

Common fixes:
 - Ensure the Docker service is running:
     sudo systemctl start docker
 - If you need elevated privileges to run docker, either run this script with sudo
   or add your user to the docker group:
     sudo usermod -aG docker "$USER"
   Then log out/in for group changes to take effect.

You can test with:
  sudo docker info

MSG
    exit 1
  fi
}

# Check for KVM device on the host. If missing, either warn or prompt to continue.
check_kvm() {
  if [ -e /dev/kvm ]; then
    echo "KVM device found: /dev/kvm"
    return 0
  fi

  echo "Warning: /dev/kvm was not found on this host. KVM acceleration will not be available."
  if [ "$NONINTERACTIVE" -eq 1 ]; then
    echo "Continuing in non-interactive mode: will run QEMU in emulation mode (slow)."
    return 0
  fi

  # Prompt user whether to continue in emulation mode
  while true; do
    read -r -p "Continue and run QEMU in emulation mode (much slower)? (y/N): " yn
    yn="${yn:-N}"
    case "$yn" in
      [Yy]* ) echo "Continuing in emulation mode."; return 0 ;;
      [Nn]* ) echo "Aborting. Enable KVM on host or run on a host with /dev/kvm present."; exit 1 ;;
      * ) echo "Please answer y or n." ;;
    esac
  done
}

echo "== openbsd Docker build & run helper =="
echo

# Run the checks now
check_docker
check_kvm

# Gather values interactively (or use defaults)
prompt IMAGE_TAG "$DEFAULT_IMAGE_TAG" "Image tag to build"
prompt BOOT_MODE "$DEFAULT_BOOT_MODE" "BOOT_MODE (install|boot)"
# If install or user wants, ask for ISO URL
if [ "$BOOT_MODE" = "install" ]; then
  prompt OPENBSD_ISO_URL "$DEFAULT_OPENBSD_ISO_URL" "OpenBSD installer ISO URL (leave blank to place ISO in ./images manually)"
else
  # still allow user to set ISO url even in boot mode (harmless)
  prompt OPENBSD_ISO_URL "" "OpenBSD installer ISO URL (optional, only used with BOOT_MODE=install)"
fi
prompt ISO_NAME "install.iso" "ISO filename in ./images"
prompt DISK_NAME "disk.qcow2" "Disk image filename in ./images"
prompt DISK_SIZE "$DEFAULT_DISK_SIZE" "Disk size for new qcow2 (e.g. 20G)"
prompt MEMORY "$DEFAULT_MEMORY" "Memory (MB) for VM"
prompt CORES "$DEFAULT_CORES" "CPU cores for VM"
prompt GRAPHICAL "$DEFAULT_GRAPHICAL" "GRAPHICAL (true|false) - use VNC/noVNC or serial"
prompt VNC_DISPLAY "$DEFAULT_VNC_DISPLAY" "VNC display number (1 => 5901)"
prompt NOVNC_PORT "$DEFAULT_NOVNC_PORT" "noVNC web UI port inside container"
prompt HOST_VNC_PORT "$DEFAULT_HOST_VNC_PORT" "Host port mapped to noVNC web UI"

# expose the vnc locally dont need if using novnc
prompt expose_raw_vnc "no" "Expose raw VNC TCP port to host? (yes|no)"
if [ "${expose_raw_vnc,,}" = "yes" ] || [ "${expose_raw_vnc,,}" = "y" ]; then
  prompt HOST_VNC_RAW_PORT "$DEFAULT_HOST_VNC_RAW_PORT" "Host raw VNC TCP port"
else
  HOST_VNC_RAW_PORT=""
fi


# expose the ssh locally dont need if using novnc
prompt expose_ssh "no" "Expose guest SSH port to Docker host? (yes|no)"
if [ "${expose_ssh,,}" = "yes" ] || [ "${expose_ssh,,}" = "y" ]; then
  prompt HOST_SSH_PORT "$DEFAULT_HOST_SSH_PORT" "Host port forwarded to guest SSH (guest:22)"
else
  HOST_SSH_PORT=""
fi

prompt DETACHED "no" "Run container detached? (yes|no)"

# Compute derived values
VNC_PORT=$((5900 + VNC_DISPLAY))

# Create ./images directory if missing
IMAGES_DIR="$(pwd)/images"
if [ ! -d "$IMAGES_DIR" ]; then
  echo "Creating images directory at $IMAGES_DIR"
  mkdir -p "$IMAGES_DIR"
  chmod 0777 "$IMAGES_DIR" || true
fi

echo
echo "Summary of settings:"
cat <<EOF
 Image tag:         $IMAGE_TAG
 BOOT_MODE:         $BOOT_MODE
 OPENBSD_ISO_URL:   ${OPENBSD_ISO_URL:-<not set>}
 ISO path:          $IMAGES_DIR/$ISO_NAME
 Disk path:         $IMAGES_DIR/$DISK_NAME
 Disk size:         $DISK_SIZE
 Memory:            $MEMORY MB
 CPU cores:         $CORES
 GRAPHICAL:         $GRAPHICAL
 VNC display:       $VNC_DISPLAY (TCP port $VNC_PORT)
 noVNC port (ctr):  $NOVNC_PORT
 noVNC port (host): $HOST_VNC_PORT
 Raw VNC host port: ${HOST_VNC_RAW_PORT:-<not exposed>}
 SSH host port:     ${HOST_SSH_PORT:-<not exposed>}
 Run detached:      $DETACHED
EOF

if [ "$NONINTERACTIVE" -eq 0 ]; then
  read -r -p "Proceed to build and run the container? (Y/n) " proceed
  proceed="${proceed:-Y}"
  if [[ ! "$proceed" =~ ^[Yy] ]]; then
    echo "Aborted by user."
    exit 0
  fi
fi

# Build the image
echo
echo "Building Docker image: $IMAGE_TAG"
docker build -t "$IMAGE_TAG" .

# Stop & remove existing container if present
if docker ps -a --format '{{.Names}}' | grep -q "^openbsd-kvm$"; then
  echo "Found existing container named openbsd-kvm - removing it."
  docker rm -f openbsd-kvm >/dev/null 2>&1 || true
fi

# Prepare docker run args
RUN_ARGS=()
RUN_ARGS+=(--rm)
if [ "${DETACHED,,}" = "yes" ] || [ "${DETACHED,,}" = "y" ]; then
  RUN_ARGS+=(-d)
fi
RUN_ARGS+=(--name openbsd-kvm)
# KVM device (if available on host) - mount only if exists
if [ -e /dev/kvm ]; then
  RUN_ARGS+=(--device /dev/kvm:/dev/kvm)
else
  echo "Note: running without --device /dev/kvm (no KVM available)."
fi
# allow KVM ioctls through seccomp by default (compose used seccomp:unconfined)
RUN_ARGS+=(--security-opt seccomp=unconfined)
# mount images directory
RUN_ARGS+=(-v "$IMAGES_DIR":/images)

# Port mappings
# Map noVNC web UI
RUN_ARGS+=(-p "${HOST_VNC_PORT}:${NOVNC_PORT}")
# Optionally map raw VNC TCP port to container VNC port
if [ -n "$HOST_VNC_RAW_PORT" ]; then
  # container VNC port is VNC_PORT
  RUN_ARGS+=(-p "${HOST_VNC_RAW_PORT}:${VNC_PORT}")
fi
# Map SSH forward port (host -> container -> guest:22) only if user asked to expose it
if [ -n "$HOST_SSH_PORT" ]; then
  RUN_ARGS+=(-p "${HOST_SSH_PORT}:${HOST_SSH_PORT}")
fi

# Environment variables to pass in
ENV_ARGS=(
  -e "BOOT_MODE=${BOOT_MODE}"
  -e "OPENBSD_ISO_URL=${OPENBSD_ISO_URL}"
  -e "ISO_NAME=${ISO_NAME}"
  -e "DISK_NAME=${DISK_NAME}"
  -e "DISK_SIZE=${DISK_SIZE}"
  -e "MEMORY=${MEMORY}"
  -e "CORES=${CORES}"
  -e "GRAPHICAL=${GRAPHICAL}"
  -e "VNC_DISPLAY=${VNC_DISPLAY}"
  -e "NOVNC_PORT=${NOVNC_PORT}"
)
# Only pass HOST_SSH_PORT env if user chose to expose it (helps avoid confusion)
if [ -n "$HOST_SSH_PORT" ]; then
  ENV_ARGS+=(-e "HOST_SSH_PORT=${HOST_SSH_PORT}")
fi

# Build final docker run command (array-safe)
DOCKER_CMD=(docker run "${RUN_ARGS[@]}" "${ENV_ARGS[@]}" "$IMAGE_TAG")

echo
echo "Running container:"
printf '%q ' "${DOCKER_CMD[@]}"
echo
echo

# Execute
"${DOCKER_CMD[@]}"

# Print access hints (only when running attached; in detached mode the container might be in background)
echo
echo "Container started."
if [ "${DETACHED,,}" = "yes" ] || [ "${DETACHED,,}" = "y" ]; then
  echo "Use: docker logs -f openbsd-kvm"
else
  echo "QEMU output is attached to this terminal (unless you used detached mode)."
fi

# Guidance for accessing the VM
echo
echo "Access information:"
if [ "${GRAPHICAL,,}" = "true" ]; then
  echo " - noVNC web UI: http://<docker-host>:${HOST_VNC_PORT}/vnc.html"
  if [ -n "$HOST_VNC_RAW_PORT" ]; then
    echo " - Raw VNC (if exposed): vnc://<docker-host>:${HOST_VNC_RAW_PORT}"
  else
    echo " - Raw VNC not exposed by default. Use noVNC unless you exposed raw VNC port."
  fi
else
  echo " - Running headless. QEMU serial console is attached to the container's logs/stdout."
fi

if [ -n "$HOST_SSH_PORT" ]; then
  echo " - SSH (after guest sshd running): ssh -p ${HOST_SSH_PORT} user@<docker-host>"
else
  echo " - SSH port not exposed on the Docker host. You can still access guest ssh via the container if you exec into it or expose the port later."
fi

echo
echo "Images and disk are stored on host at: $IMAGES_DIR"
