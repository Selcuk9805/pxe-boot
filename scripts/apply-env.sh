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

# Mevcut IP ve Subnet değerlerini boot.ipxe ve dnsmasq.conf içinden arıyoruz
CURRENT_IP=$(grep -m1 -oP 'set server-url\s+http://\K[0-9]+(\.[0-9]+){3}' "$PROJECT_DIR/http/boot.ipxe" 2>/dev/null || true)
CURRENT_SUBNET=$(grep -m1 -oP '^dhcp-range=\K[0-9]+(\.[0-9]+){3}(?=,proxy$)' "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf" 2>/dev/null || true)

# Eğer bulunamazsa fallback olarak hardcoded değerleri kullanalım
if [ -z "$CURRENT_IP" ]; then
    CURRENT_IP="10.30.1.20"
fi
if [ -z "$CURRENT_SUBNET" ]; then
    CURRENT_SUBNET="10.30.1.0"
fi

# 1. IP Güncelleme
if [ "$CURRENT_IP" != "$PXE_SERVER_IP" ]; then
    echo -e "${YELLOW}[!] IP adresi güncelleniyor: $CURRENT_IP -> $PXE_SERVER_IP${NC}"
    # find ile .ipxe, .ipxe.0, .conf, .md ve Makefile dosyalarını bul ve değiştir
    find "$PROJECT_DIR" -type f \( -name "*.ipxe" -o -name "*.ipxe.0" -o -name "dnsmasq.conf" -o -name "*.md" -o -name "Makefile" \) -exec sed -i "s/$CURRENT_IP/$PXE_SERVER_IP/g" {} +
else
    echo -e "${GREEN}[✓] IP adresi zaten güncel: $PXE_SERVER_IP${NC}"
fi

# 2. Subnet Güncelleme
if [ "$CURRENT_SUBNET" != "$NETWORK_SUBNET" ]; then
    echo -e "${YELLOW}[!] Subnet adresi güncelleniyor: $CURRENT_SUBNET -> $NETWORK_SUBNET${NC}"
    # Sadece dnsmasq.conf ve NETWORK_SETUP_NOTES.md içinde subnet geçer
    if [ -f "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf" ]; then
        sed -i "s/$CURRENT_SUBNET/$NETWORK_SUBNET/g" "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    fi
    if [ -f "$PROJECT_DIR/NETWORK_SETUP_NOTES.md" ]; then
        sed -i "s/$CURRENT_SUBNET/$NETWORK_SUBNET/g" "$PROJECT_DIR/NETWORK_SETUP_NOTES.md"
    fi
else
    echo -e "${GREEN}[✓] Subnet adresi zaten güncel: $NETWORK_SUBNET${NC}"
fi

echo -e "${GREEN}[✓] İşlem tamamlandı.${NC}\n"
