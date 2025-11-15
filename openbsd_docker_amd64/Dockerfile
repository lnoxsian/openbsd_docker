FROM alpine:3.18

# Install qemu, downloader and a small init to handle signals, plus python/git for noVNC/websockify
RUN apk add --no-cache \
    qemu qemu-img \
    bash curl ca-certificates \
    dumb-init \
    python3 py3-pip git \
  && update-ca-certificates \
  && pip3 install --no-cache-dir websockify \
  && rm -rf /var/cache/apk/*

# Clone noVNC into the image so the web UI is available
# Use a tagged release or specific commit if you want reproducible builds.
RUN git clone --depth=1 https://github.com/novnc/noVNC.git /opt/noVNC \
  || (echo "Failed to clone noVNC" && exit 1)

# Add entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]
