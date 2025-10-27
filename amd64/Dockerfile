FROM debian:bookworm-slim

# Install build deps so pip can build wheels (if needed), then install websockify via pip
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    qemu-utils \
    python3 \
    python3-pip \
    build-essential \
    python3-dev \
    libssl-dev \
    git \
    wget \
    ca-certificates \
 && python3 -m pip install --upgrade pip setuptools wheel \
 && python3 -m pip install --no-cache-dir websockify \
 && git clone https://github.com/novnc/noVNC /opt/novnc \
 && apt-get remove -y build-essential python3-dev libssl-dev \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Add entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/images"]
EXPOSE 6080 5901 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
