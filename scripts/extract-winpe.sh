#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  WinPE — İçerik Hazırlama Scripti
#
#  Kullanım: ./scripts/extract-winpe.sh <winpe.iso>
#
#  Gereksinimler:
#    - Windows ADK ile oluşturulmuş WinPE ISO
#      (ADK: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
#    - ISO içinde /sources/boot.wim veya /boot/boot.wim
#    - BCD ve boot.sdi dosyaları
#
#  Çıktı dizini: http/boot/winpe/
#    - boot.wim   (WinPE çekirdeği)
#    - BCD        (Boot Configuration Data)
#    - boot.sdi   (Boot sektor imajı)
#
#  wimboot (http/wimboot) setup.sh tarafından indirilir.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/http/boot/winpe"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    PXE_SERVER_IP="10.30.1.20"
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
info()  { echo -e "${CYAN}[→]${NC} $*"; }

# ── Argüman Kontrolü ─────────────────────────────────────────
if [ "${1:-}" == "" ]; then
    echo ""
    echo "Kullanım: $0 <winpe.iso>"
    echo ""
    echo "WinPE ISO oluşturma (Windows'ta):"
    echo "  1. Windows ADK + WinPE Add-on kurun"
    echo "     https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install"
    echo "  2. Copype komutu:"
    echo "     copype amd64 C:\\WinPE_amd64"
    echo "  3. ISO oluştur:"
    echo "     MakeWinPEMedia /ISO C:\\WinPE_amd64 C:\\WinPE.iso"
    echo "  4. ISO'yu bu sunucuya kopyalayın:"
    echo "     isos/winpe.iso"
    echo ""
    exit 1
fi

ISO_PATH="$1"
[ ! -f "$ISO_PATH" ] && ISO_PATH="$PROJECT_DIR/$ISO_PATH"
[ ! -f "$ISO_PATH" ] && { error "ISO bulunamadı: $1"; exit 1; }

echo -e "\n${CYAN}▶ WinPE ISO içerik çıkarma başlıyor...${NC}"
info "ISO: $ISO_PATH ($(du -sh "$ISO_PATH" | cut -f1))"

mkdir -p "$OUTPUT_DIR"

# ── Çıkarma Aracı Seç ────────────────────────────────────────
if ! command -v 7z &>/dev/null; then
    error "7z (p7zip-full) gerekli:"
    error "  sudo apt install p7zip-full"
    exit 1
fi

# ── Dosyaları Çıkar ──────────────────────────────────────────
info "7z ile WinPE dosyaları çıkarılıyor..."

local_tmp=$(mktemp -d)
trap 'rm -rf "$local_tmp"' EXIT

7z x "$ISO_PATH" -o"$local_tmp" -y >/dev/null

# boot.wim bul ve kopyala
BOOT_WIM=""
for path in \
    "$local_tmp/sources/boot.wim" \
    "$local_tmp/boot/boot.wim"; do
    [ -f "$path" ] && { BOOT_WIM="$path"; break; }
done

[ -z "$BOOT_WIM" ] && { error "boot.wim bulunamadı. Geçerli bir WinPE ISO mu?"; exit 1; }

info "boot.wim kopyalanıyor..."
cp "$BOOT_WIM" "$OUTPUT_DIR/boot.wim"

# BCD kopyala
BCD_FILE=""
for path in \
    "$local_tmp/boot/BCD" \
    "$local_tmp/EFI/Microsoft/Boot/BCD"; do
    [ -f "$path" ] && { BCD_FILE="$path"; break; }
done

if [ -n "$BCD_FILE" ]; then
    info "BCD kopyalanıyor..."
    cp "$BCD_FILE" "$OUTPUT_DIR/BCD"
else
    warn "BCD bulunamadı — wimboot BCD oluşturmayı destekler, sorun olmayabilir."
fi

# boot.sdi kopyala
SDI_FILE="$local_tmp/boot/boot.sdi"
if [ -f "$SDI_FILE" ]; then
    info "boot.sdi kopyalanıyor..."
    cp "$SDI_FILE" "$OUTPUT_DIR/boot.sdi"
else
    warn "boot.sdi bulunamadı."
fi

# ── wimboot Kontrolü ─────────────────────────────────────────
WIMBOOT_PATH="$PROJECT_DIR/http/wimboot"
if [ ! -f "$WIMBOOT_PATH" ]; then
    warn "wimboot bulunamadı: $WIMBOOT_PATH"
    warn "setup.sh çalıştırın: ./scripts/setup.sh"
else
    log "wimboot mevcut: $(du -sh "$WIMBOOT_PATH" | cut -f1)"
fi

# ── Özet ─────────────────────────────────────────────────────
echo ""
log "WinPE dosyaları hazır:"
[ -f "$OUTPUT_DIR/boot.wim" ]  && info "  boot.wim  → $(du -sh "$OUTPUT_DIR/boot.wim" | cut -f1)"
[ -f "$OUTPUT_DIR/BCD" ]       && info "  BCD       → $(du -sh "$OUTPUT_DIR/BCD" | cut -f1)"
[ -f "$OUTPUT_DIR/boot.sdi" ]  && info "  boot.sdi  → $(du -sh "$OUTPUT_DIR/boot.sdi" | cut -f1)"
echo ""
log "Boot URL'leri:"
info "  wimboot  : http://${PXE_SERVER_IP}/wimboot"
info "  boot.sdi : http://${PXE_SERVER_IP}/boot/winpe/boot.sdi"
info "  BCD      : http://${PXE_SERVER_IP}/boot/winpe/BCD"
info "  boot.wim : http://${PXE_SERVER_IP}/boot/winpe/boot.wim"
echo ""
log "WinPE hazır. PXE menüsünden 'WinPE' seçeneğini kullanın."
