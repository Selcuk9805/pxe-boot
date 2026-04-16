#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Debian 12 — Net Install içerik hazırlama scripti
#
#  2 mod:
#    A) Internet'ten direkt indir (ISO gerekmez):
#       ./scripts/extract-debian-install.sh
#
#    B) Yerel ISO'dan çıkar:
#       ./scripts/extract-debian-install.sh isos/debian-12-netinst.iso
#
#  Çıktı: http/boot/debian-install/vmlinuz + initrd.gz
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/http/boot/debian-install"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    PXE_SERVER_IP="10.30.1.20"
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
info() { echo -e "${CYAN}[→]${NC} $*"; }

DEBIAN_ARCH="amd64"
DEBIAN_CODENAME="bookworm"
DEBIAN_MIRROR="https://deb.debian.org/debian"
NETBOOT_URL="${DEBIAN_MIRROR}/dists/${DEBIAN_CODENAME}/main/installer-${DEBIAN_ARCH}/current/images/netboot/debian-installer/${DEBIAN_ARCH}"

mkdir -p "$OUTPUT_DIR"

# ── Mod A: İnternetten direkt indir ──────────────────────────
download_from_internet() {
    echo -e "\n${CYAN}▶ Debian ${DEBIAN_CODENAME} netboot dosyaları indiriliyor...${NC}"
    info "Kaynak: $NETBOOT_URL"

    info "vmlinuz indiriliyor..."
    wget -q --show-progress "${NETBOOT_URL}/linux" -O "$OUTPUT_DIR/vmlinuz"

    info "initrd.gz indiriliyor..."
    wget -q --show-progress "${NETBOOT_URL}/initrd.gz" -O "$OUTPUT_DIR/initrd.gz"

    log "Debian kurulum dosyaları hazır."
    print_summary
}

# ── Mod B: ISO'dan çıkar ─────────────────────────────────────
extract_from_iso() {
    local iso_path="$1"

    if [ ! -f "$iso_path" ]; then
        echo "Hata: ISO dosyası bulunamadı: $iso_path" >&2
        exit 1
    fi

    echo -e "\n${CYAN}▶ ISO'dan Debian kurulum dosyaları çıkarılıyor...${NC}"
    info "ISO: $iso_path"

    # isoinfo veya 7z ile dosya çıkar
    if command -v isoinfo &>/dev/null; then
        info "isoinfo kullanılıyor..."
        isoinfo -i "$iso_path" -x "/install.amd/vmlinuz;1" > "$OUTPUT_DIR/vmlinuz" 2>/dev/null || \
        isoinfo -i "$iso_path" -x "/install.${DEBIAN_ARCH}/vmlinuz;1" > "$OUTPUT_DIR/vmlinuz"

        isoinfo -i "$iso_path" -x "/install.amd/initrd.gz;1" > "$OUTPUT_DIR/initrd.gz" 2>/dev/null || \
        isoinfo -i "$iso_path" -x "/install.${DEBIAN_ARCH}/initrd.gz;1" > "$OUTPUT_DIR/initrd.gz"
    elif command -v 7z &>/dev/null; then
        info "7z kullanılıyor..."
        local tmpdir
        tmpdir=$(mktemp -d)
        7z x "$iso_path" "install.amd/vmlinuz" "install.amd/initrd.gz" -o"$tmpdir" -y >/dev/null
        cp "$tmpdir/install.amd/vmlinuz" "$OUTPUT_DIR/vmlinuz"
        cp "$tmpdir/install.amd/initrd.gz" "$OUTPUT_DIR/initrd.gz"
        rm -rf "$tmpdir"
    else
        warn "isoinfo veya 7z bulunamadı. İnternetten indirmeye geçiliyor..."
        download_from_internet
        return
    fi

    log "ISO'dan dosyalar çıkarıldı."
    print_summary
}

print_summary() {
    echo ""
    log "Debian Kurulum dosyaları hazır:"
    info "  vmlinuz  → $(du -sh "$OUTPUT_DIR/vmlinuz" | cut -f1)"
    info "  initrd.gz → $(du -sh "$OUTPUT_DIR/initrd.gz" | cut -f1)"
    echo ""
    log "Boot URL'leri:"
    info "  Kernel : http://${PXE_SERVER_IP}/boot/debian-install/vmlinuz"
    info "  Initrd : http://${PXE_SERVER_IP}/boot/debian-install/initrd.gz"
}

# ── Ana Akış ─────────────────────────────────────────────────
if [ "${1:-}" != "" ]; then
    extract_from_iso "$1"
else
    download_from_internet
fi
