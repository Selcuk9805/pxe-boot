FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends dnsmasq && \
    rm -rf /var/lib/apt/lists/*

# dnsmasq'ın log buffer'ını devre dışı bırak (container logları için)
EXPOSE 53/udp 67/udp 68/udp 69/udp

CMD ["dnsmasq", "--no-daemon", "--log-facility=-", "--log-queries=extra"]
