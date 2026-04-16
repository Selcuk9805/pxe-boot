#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  .env Değerlerini Dosyalara Uygulama Scripti
#  Mevcut hardcoded IP ve subnet'i dinamik olarak günceller
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo -e "${RED}[✗] Hata: .env dosyası bulunamadı.${NC}"
    exit 1
fi

source "$PROJECT_DIR/.env"

if [ -z "${PXE_SERVER_IP:-}" ] || [ -z "${NETWORK_SUBNET:-}" ]; then
    echo -e "${RED}[✗] Hata: .env içerisinde PXE_SERVER_IP veya NETWORK_SUBNET tanımlı değil.${NC}"
    exit 1
fi

echo -e "\n${CYAN}▶ Ortam değişkenleri uygulanıyor (IP: $PXE_SERVER_IP, Subnet: $NETWORK_SUBNET)...${NC}"

# Regex ifadeleriyle genel tarama yap (Eski IP'nin ne olduğundan bağımsız olarak, yerini PXE_SERVER_IP alacak)
IP_REGEX="[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"

echo -e "${YELLOW}[!] IP adresleri güncelleniyor: -> $PXE_SERVER_IP${NC}"
# 1. dnsmasq.conf
if [ -f "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf" ]; then
    sed -i -E "s|http://$IP_REGEX|http://$PXE_SERVER_IP|g" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    sed -i -E "s|^dhcp-range=$IP_REGEX,proxy|dhcp-range=$NETWORK_SUBNET,proxy|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    sed -i -E "s|^(dhcp-boot=.*,,)$IP_REGEX$|\1$PXE_SERVER_IP|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"

    # LISTEN_INTERFACE ayarı (opsiyonel)
    if [ -n "${LISTEN_INTERFACE:-}" ]; then
        sed -i -E "s|^#\s*interface=.*|interface=$LISTEN_INTERFACE|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
        sed -i -E "s|^#\s*bind-interfaces|bind-interfaces|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    else
        sed -i -E "s|^interface=.*|# interface=eth0|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
        sed -i -E "s|^bind-interfaces|# bind-interfaces|" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    fi
fi

# 2. http altındaki tüm .ipxe scriptleri
while IFS= read -r ipxe_file; do
    sed -i -E "s|http://$IP_REGEX|http://$PXE_SERVER_IP|g" "$ipxe_file"
    sed -i -E "s|^(set nfs-server[[:space:]]+)$IP_REGEX|\1$PXE_SERVER_IP|g" "$ipxe_file"
done < <(find "$PROJECT_DIR/http" -type f -name "*.ipxe")

# 3. TFTP Yönlendirme betikleri (autoexec.ipxe vb.)
for tftp_file in "$PROJECT_DIR/tftp/"*.ipxe*; do
    if [ -f "$tftp_file" ]; then
         sed -i -E "s|chain http://$IP_REGEX|chain http://$PXE_SERVER_IP|g" "$tftp_file"
    fi
done

echo -e "${GREEN}[✓] İşlem tamamlandı.${NC}\n"
