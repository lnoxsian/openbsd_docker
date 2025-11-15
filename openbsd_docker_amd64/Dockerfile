FROM alpine:3.18

# Install qemu, downloader and a small init to handle signals
RUN apk add --no-cache \
    qemu qemu-img \
    bash curl ca-certificates \
    dumb-init \
  && update-ca-certificates

# Add entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /work
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]
