# openbsd_docker_amd64 — OpenBSD in Docker with KVM, noVNC, and firmware selection

![./.github/screen_cap_openbsd_docker_amd64.png]

A Docker image + helper scripts to run an OpenBSD VM using QEMU inside a container. Features:
- VM artifacts stored under `./images` on the host (ISO and `*.qcow2` disk).
- Two boot modes:
  - `install` — boot the installer ISO and install to the qcow2 disk.
  - `boot` — boot the qcow2 disk image.
- Two firmware modes:
  - `legacy` — classic BIOS (default).
  - `uefi` — UEFI via OVMF/EDK2 (requires OVMF firmware files inside the image or mounted from host).
- Browser-accessible noVNC UI (websockify proxy), optional raw VNC, and guest SSH forwarding (optional).
- Helper script `run_in_docker_helper.sh` to interactively build and run the container.

This README documents the new FIRMWARE option, how to use it with the helper, and the environment variables.

---

## Contents
- `openbsd_docker_amd64/` — build context with `Dockerfile`, `entrypoint.sh`, noVNC is cloned into `/opt/noVNC`.
- `docker-compose.yml` — example compose file.
- `run_in_docker_helper.sh` — interactive helper to build and run the container.
- `images/` — host-mounted directory for ISOs and disk images (created automatically by the helper if missing).

---

## Prerequisites
- Docker (or Docker Compose).
- Recommended: host with KVM enabled (`/dev/kvm`) for acceleration. If not present, QEMU runs in slow emulation mode.
- Writable `./images` directory on the Docker host (helper will create it if missing).
- If you plan to use UEFI: OVMF/EDK2 firmware files must be present in the container (or mounted from the host). See "UEFI (OVMF) support" below.

---

## New feature: firmware selection (FIRMWARE)
- New environment variable: `FIRMWARE` — controls VM firmware:
  - `legacy` (default) — BIOS-style boot (SeaBIOS / QEMU default).
  - `uefi` — attempts to enable UEFI using OVMF/EDK2 firmware files.
- Behavior:
  - If `FIRMWARE=uefi`, the entrypoint searches common container paths for OVMF/EDK2 code files (OVMF_CODE.fd or common package paths).
  - If found, the script configures QEMU with two pflash drives (readonly code + writable vars file) and enables UEFI boot.
  - If not found, the script warns and falls back to `legacy` BIOS automatically.
- Typical use cases:
  - Use legacy BIOS for normal OpenBSD installs (default & simplest).
  - Use UEFI if you need an EFI environment or are installing UEFI-only OSes / testing EFI boot.

---

## Environment variables
Defaults shown in parentheses. Important/new ones bolded.

- BOOT_MODE ("install") — "install" to boot the installer ISO, "boot" to boot the qcow2 disk.
- OPENBSD_ISO_URL ("") — URL to download installer ISO (used when BOOT_MODE=install).
- ISO_NAME ("install.iso")
- DISK_NAME ("disk.qcow2")
- DISK_SIZE ("20G")
- MEMORY ("2048") — MB
- CORES ("2")
- GRAPHICAL ("true") — "true" enables VNC + noVNC; "false" runs headless serial.
- VNC_DISPLAY ("1") — QEMU VNC display number (1 → TCP 5901)
- NOVNC_PORT ("6080") — noVNC web UI port inside container
- HOST_VNC_PORT ("6080") — host port mapped to `NOVNC_PORT`
- HOST_VNC_RAW_PORT ("5901") — host raw VNC TCP port (optional)
- HOST_SSH_PORT ("2222") — host port forwarded to guest SSH (guest port 22). Optional; helper can ask to expose SSH or not.
- **FIRMWARE ("legacy")** — "legacy" or "uefi"
  - If `uefi`, entrypoint will attempt to enable OVMF. If OVMF is missing it falls back to legacy BIOS.

---

## UEFI (OVMF/EDK2) support
To use `FIRMWARE=uefi` you must provide OVMF firmware files inside the container (or mount them from host). Two approaches:

1. Install OVMF into the image (recommended if you control the Dockerfile):
   - Add the appropriate package to the Dockerfile (package name depends on base image):
     - Alpine: package may be `edk2-ovmf`, `ovmf` or available as `ovmf` in some distros. If using Alpine, test availability or pin the package name/version.
     - Example (Alpine): `apk add --no-cache edk2-ovmf` (verify package name for the chosen Alpine version).
   - Rebuild the image.

2. Mount OVMF files from host:
   - Place the OVMF code file (e.g., `OVMF_CODE.fd`) and optionally a writable vars file into a host directory.
   - Mount the directory into the container at a path the entrypoint checks (or adjust entrypoint paths).
   - Example docker run: `-v /path/to/ovmf:/ovmf` and set `-e FIRMWARE=uefi` and bind the `OVMF_CODE.fd` into one of the known paths or update entrypoint.

Notes:
- The entrypoint attempts to find common OVMF paths (several typical locations). If none found, it prints a warning and falls back.
- The script will create a writable vars file (copied from the code file) at `/tmp/OVMF_VARS.fd` to preserve variable storage across VM runtime. For persistent vars, mount a host file.

---

## Build the image
From repo root (assuming `openbsd_docker_amd64/` folder contains Dockerfile and entrypoint.sh):
```bash
docker build -t openbsd_docker_amd64:latest ./openbsd_docker_amd64
```
Or use the included helper (recommended) which will build and run for you.

---

## Run examples

1) Install mode with BIOS (default):
```bash
docker run --rm -it \
  --name openbsd-kvm \
  --device /dev/kvm:/dev/kvm \
  --security-opt seccomp=unconfined \
  -v "$(pwd)/images":/images \
  -p 6080:6080 \
  -p 5901:5901 \
  -p 2222:2222 \
  -e BOOT_MODE="install" \
  -e OPENBSD_ISO_URL="https://cdn.openbsd.org/pub/OpenBSD/7.4/amd64/install74.iso" \
  -e FIRMWARE="legacy" \
  -e GRAPHICAL="true" \
  openbsd_docker_amd64:latest
```

2) Boot installed system with UEFI (if OVMF present in container or mounted):
```bash
docker run --rm -it \
  --name openbsd-kvm \
  --device /dev/kvm:/dev/kvm \
  --security-opt seccomp=unconfined \
  -v "$(pwd)/images":/images \
  -v /host/ovmf:/opt/ovmf:ro \            # optional: mount OVMF files from host
  -p 6080:6080 \
  -p 5901:5901 \
  -p 2222:2222 \
  -e BOOT_MODE="boot" \
  -e FIRMWARE="uefi" \
  -e GRAPHICAL="true" \
  openbsd_docker_amd64:latest
```

If UEFI files are not present, the entrypoint will warn and boot using legacy BIOS.

---

## Docker Compose
A sample `docker-compose.yml` includes:
```yaml
environment:
  FIRMWARE: "legacy"   # or "uefi"
  BOOT_MODE: "install"
  OPENBSD_ISO_URL: ""
  ISO_NAME: "install.iso"
  DISK_NAME: "disk.qcow2"
  DISK_SIZE: "20G"
  MEMORY: "2048"
  CORES: "2"
  GRAPHICAL: "true"
  VNC_DISPLAY: "1"
  NOVNC_PORT: "6080"
  HOST_VNC_PORT: "6080"
  HOST_VNC_RAW_PORT: "5901"
  HOST_SSH_PORT: "2222"
```
Set `FIRMWARE` to `uefi` to request UEFI boot (requires OVMF in image or mounted).

---

## Helper: run_in_docker_helper.sh
The helper script prompts for common settings (BOOT_MODE, OPENBSD_ISO_URL, MEMORY, CORES, GRAPHICAL, VNC ports, whether to expose SSH) and now prompts for `FIRMWARE` (default `legacy`). It:
- verifies Docker
- checks `/dev/kvm` and prompts whether to continue if missing
- builds the image from `./openbsd_docker_amd64`
- runs the container with selected env vars and port mappings

Usage:
1. Make the script executable:
   chmod +x run_in_docker_helper.sh

2. Run interactively:
   ./run_in_docker_helper.sh

3. Non-interactive with defaults:
   ./run_in_docker_helper.sh --non-interactive

When you choose `FIRMWARE=uefi` the helper will pass that into the container; the entrypoint will enable UEFI if OVMF files are available.

---

## Typical install workflow
1. Run container with `BOOT_MODE=install` and `OPENBSD_ISO_URL` set (or place ISO in `./images/install.iso`).
2. Use noVNC (`http://<host>:6080/vnc.html`) to run the OpenBSD installer and install to `disk.qcow2`.
3. Shutdown the VM inside the guest after install.
4. Re-run container with `BOOT_MODE=boot` to boot the installed system. Set `FIRMWARE=uefi` if the install was performed under UEFI (and OVMF present).

---

## Troubleshooting
- noVNC inaccessible:
  - Check container logs: `docker logs -f openbsd-kvm`
  - From host: `curl -I http://localhost:6080/vnc.html` should return 200.
  - Inside container: check `ps aux | grep websockify` and `ss -lntp`.
- UEFI not activated:
  - Ensure OVMF/EDK2 firmware files exist in the container or are mounted. If not, entrypoint falls back to legacy BIOS.
  - To add OVMF into the image, install the appropriate package (example for Debian-based images: `apt-get install -y ovmf` — package names differ by distro).
- QEMU cannot open `/dev/kvm`:
  - Ensure host has `/dev/kvm` and the container is run with `--device /dev/kvm:/dev/kvm`.
  - Adjust host device permissions or run with appropriate privileges.
- SSH not reachable:
  - If you chose not to expose SSH in `run_in_docker_helper.sh`, there will be no host port mapping for SSH. Re-run helper and enable SSH exposure or `docker run -p 2222:2222`.

---

## Security notes
- Raw VNC is typically unauthenticated/encrypted — avoid exposing it to untrusted networks.
- noVNC over HTTP is unencrypted; proxy behind HTTPS when exposing remotely.
- Using `seccomp:unconfined` loosens container constraints to allow KVM ioctls; prefer creating a tailored seccomp profile for production.

---

## Next steps / tips
- If you want persistent UEFI variable storage across restarts, mount a host file for the OVMF vars file (the entrypoint creates `/tmp/OVMF_VARS.fd` by default; mount your persistent file and adjust permissions).
- If you'd like, add `edk2-ovmf` / `ovmf` to the Dockerfile and pin a package name for the base image you use so `FIRMWARE=uefi` works out-of-the-box.

---
