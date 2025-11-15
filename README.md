# openbsd_docker_amd64 — OpenBSD in Docker with KVM + noVNC

A small Docker image and helper scripts that run QEMU/KVM to install and run an OpenBSD guest. The container:
- stores VM artifacts under `./images` on the Docker host (ISO and `*.qcow2` disk),
- can download an OpenBSD installer ISO automatically (when configured),
- supports two boot modes:
  - `install` — boot the installer ISO and install to the qcow2 disk,
  - `boot` — boot the qcow2 disk image,
- exposes a browser-accessible noVNC web UI and (optionally) raw VNC,
- forwards guest SSH (via QEMU user-mode networking) to the Docker host.

This README explains the entrypoint behavior, environment variables, build/run examples, the interactive helper script (`run_in_docker_helper.sh`), and troubleshooting tips.

---

## Contents
- `Dockerfile` — builds the image with QEMU, websockify and noVNC.
- `docker-compose.yml` — example compose file and environment defaults.
- `entrypoint.sh` — starts QEMU, handles ISO download, qcow2 creation, and noVNC/websockify.
- `run_in_docker_helper.sh` (helper) — interactive script to build & run the container.

---

## Prerequisites
- Docker (or Docker Compose)
- On the Docker host: KVM enabled and `/dev/kvm` present (for hardware acceleration)
  - Check: `ls /dev/kvm` and `lsmod | grep kvm`
  - If the host is a VM, nested virtualization must be enabled.
- A writable `./images` directory on the Docker host (the helper will create it if missing).

---

## Entrypoint behavior (what the container does)
- Ensures `/images` exists (host-mounted `./images` recommended).
- If `BOOT_MODE=install`:
  - If `ISO` is missing and `OPENBSD_ISO_URL` is set, the ISO is downloaded to `/images/<ISO_NAME>`.
  - QEMU is started with the ISO attached (`-cdrom`) and `-boot d`.
- If `BOOT_MODE=boot`:
  - QEMU boots directly from the qcow2 disk image (`-boot c`).
- If the disk (`/images/<DISK_NAME>`) doesn't exist, it is created automatically with `qemu-img create`.
- If `GRAPHICAL=true`, QEMU is started with a VNC server bound to `127.0.0.1:59XX`. `websockify` (noVNC) proxies that VNC to a websocket and serves the noVNC web UI.
- If `GRAPHICAL=false`, QEMU runs headless on a serial console.

---

## Environment variables (defaults shown)
- `BOOT_MODE="install"`         # "install" or "boot"
- `OPENBSD_ISO_URL=""`          # URL to download installer ISO (used when BOOT_MODE=install)
- `ISO_NAME="install.iso"`
- `DISK_NAME="disk.qcow2"`
- `DISK_SIZE="20G"`
- `MEMORY="2048"`               # MB
- `CORES="2"`
- `GRAPHICAL="true"`            # true -> VNC + noVNC; false -> serial console
- `VNC_DISPLAY="1"`             # QEMU VNC display number (1 => 5901)
- `NOVNC_PORT="6080"`           # noVNC web UI port inside container
- `HOST_VNC_PORT="6080"`        # host port mapped to NOVNC_PORT
- `HOST_VNC_RAW_PORT="5901"`    # host raw VNC TCP port (optional)
- `HOST_SSH_PORT="2222"`        # host port forwarded to guest SSH (guest port 22)

---

## Helper: run_in_docker_helper.sh
To make using this project easier, a helper script is included: `run_in_docker_helper.sh`. The helper will:
- verify Docker is installed and the Docker daemon is reachable,
- check for `/dev/kvm` on the host and prompt about running in emulation mode if missing,
- prompt for and collect common environment configuration (BOOT_MODE, OPENBSD_ISO_URL, memory, cores, disk size, ports, graphical),
- create `./images` if missing,
- build the Docker image,
- stop/remove any existing container named `openbsd-kvm`,
- run `docker run` with sensible ports, mounts and env variables.

Usage:
1. Make the script executable:
```bash
   chmod +x run_in_docker_helper.sh # just use bash run_in_docker_helper.sh
```

2. Run interactively (recommended):
```bash
  ./run_in_docker_helper.sh
```

3. Run non-interactively using defaults:
```bash
   ./run_in_docker_helper.sh --non-interactive
```

4. The script will show a summary of settings and ask to proceed (unless `--non-interactive`).

Notes:
- The helper passes environment variables to the container; you can also use a `.env` file or docker-compose for persistent settings.

---

## Build the image (manual)
- Using Docker CLI:
```bash
  docker build -t openbsd_docker_amd64:latest .
```

- Using Docker Compose:
```bash
  docker compose build
```

---

## Run examples (manual)
Create images directory (if not present):
```bash
  mkdir -p ./images
  chmod 0777 ./images   # optional if you encounter permission issues
```

1) Install mode — boot the OpenBSD installer and create/overwrite disk image
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
    -e GRAPHICAL="true" \
    -e VNC_DISPLAY="1" \
    -e NOVNC_PORT="6080" \
    -e HOST_SSH_PORT="2222" \
    -e DISK_SIZE="20G" \
    -e MEMORY="2048" \
    -e CORES="2" \
    openbsd_docker_amd64:latest
```

2) Boot mode — boot the qcow2 disk image (use after you installed OpenBSD)
```bash
  docker run --rm -it \
    --name openbsd-kvm \
    --device /dev/kvm:/dev/kvm \
    --security-opt seccomp=unconfined \
    -v "$(pwd)/images":/images \
    -p 6080:6080 \
    -p 5901:5901 \
    -p 2222:2222 \
    -e BOOT_MODE="boot" \
    -e GRAPHICAL="true" \
    -e VNC_DISPLAY="1" \
    -e NOVNC_PORT="6080" \
    -e HOST_SSH_PORT="2222" \
    -e DISK_SIZE="20G" \
    -e MEMORY="2048" \
    -e CORES="2" \
    openbsd_docker_amd64:latest
```

---

## How to interact with the VM
- noVNC (browser):
  - Open: `http://<docker-host>:<HOST_VNC_PORT>/vnc.html`
  - Default example: `http://localhost:6080/vnc.html`
- Raw VNC (optional):
  - If you mapped `5901:5901` you may connect with a desktop VNC client to `localhost:5901`.
- SSH (after OpenBSD sshd is installed & running inside the guest):
  - ssh -p 2222 user@localhost

---

## Typical install workflow
1. Run container with `BOOT_MODE=install` and `OPENBSD_ISO_URL` set (or drop the ISO into `./images/install.iso`).
2. Use noVNC to run the installer and install OpenBSD to the disk `disk.qcow2`.
3. When install completes, shut down the VM from inside the guest.
4. Restart the container with `BOOT_MODE=boot` to boot the installed system from `disk.qcow2`.

---

## Troubleshooting
- noVNC inaccessible:
  - Ensure `websockify` is running (container logs): `docker logs openbsd-kvm`
  - Ensure Docker port mapping is correct and the host firewall allows the port.
  - From the host: `curl -I http://localhost:6080/vnc.html` should return a 200.
  - Inside container: check `ss -lntp` or `ps aux | grep websockify` and confirm `websockify` bound to the mapped listen address.
- QEMU cannot open `/dev/kvm`:
  - Ensure host has `/dev/kvm` and you passed `--device /dev/kvm:/dev/kvm`.
  - If container can’t access `/dev/kvm` due to permissions, run with appropriate user or adjust host device permissions.
- If you want to avoid loosening seccomp, supply a custom seccomp profile that allows the required KVM ioctls.
- Disk/image persistence:
  - VM artifacts are kept in `./images` on the host. Do not delete `disk.qcow2` if you want to preserve the installed system.

---

## Security notes
- The raw VNC connection is usually unauthenticated and unencrypted — exposing it to untrusted networks is not recommended.
- noVNC over plain HTTP is unencrypted; proxy behind HTTPS if exposing to untrusted networks.
- The compose example uses `seccomp:unconfined` to allow KVM ioctls; you may prefer a custom seccomp profile instead.

---

## Logs & debugging
- Container logs: `docker logs -f openbsd-kvm`
- Compose logs: `docker compose logs -f openbsd-kvm`
- Inside the container (if you need a shell): `docker exec -it openbsd-kvm /bin/sh`

---

## Image tags
- The examples use `openbsd_docker_amd64:latest` as the build tag. If you previously built with a different name (e.g. `openbsd-kvm:latest`) use that tag consistently.

---

