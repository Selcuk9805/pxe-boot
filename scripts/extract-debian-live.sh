#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Debian 12 Live — İçerik Hazırlama Scripti
#
#  Kullanım: ./scripts/extract-debian-live.sh <live.iso>
#
#  Örnek:
#    ./scripts/extract-debian-live.sh isos/debian-live-12-amd64-gnome.iso
#
#  Çıktı:
#    http/boot/debian-live/vmlinuz
#    http/boot/debian-live/initrd.img
#    http/boot/debian-live/live/filesystem.squashfs
#
#  NOT: filesystem.squashfs büyük olabilir (1-3 GB).
#  Nginx HTTP üzerinden istemciye stream edilir (TFTP kullanılmaz).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/http/boot/debian-live"

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
    echo "Kullanım: $0 <debian-live.iso>"
    echo ""
    echo "Örnek:"
    echo "  $0 isos/debian-live-12-amd64-gnome.iso"
    echo ""
    echo "ISO'yu şuradan indirin:"
    echo "  https://www.debian.org/CD/live/"
    exit 1
fi

ISO_PATH="$1"
# İso path proje dizinine göre çözümleme
[ ! -f "$ISO_PATH" ] && ISO_PATH="$PROJECT_DIR/$ISO_PATH"
[ ! -f "$ISO_PATH" ] && { error "ISO bulunamadı: $1"; exit 1; }

echo -e "\n${CYAN}▶ Debian Live ISO içerik çıkarma başlıyor...${NC}"
info "ISO: $ISO_PATH ($(du -sh "$ISO_PATH" | cut -f1))"

mkdir -p "$OUTPUT_DIR/live"

# ── Mount Yöntemi Seç ────────────────────────────────────────
extract_iso() {
    local iso="$1"
    local mount_point
    mount_point=$(mktemp -d)

    # Mount edilebilir mi kontrol et
    if [ "$(id -u)" -eq 0 ]; then
        # Root: direkt mount
        info "ISO mount ediliyor (root): $mount_point"
        mount -o loop,ro "$iso" "$mount_point"
        copy_files "$mount_point"
        umount "$mount_point"
    elif command -v fuseiso &>/dev/null; then
        # fuseiso kullanılabilir
        info "fuseiso ile mount ediliyor: $mount_point"
        fuseiso "$iso" "$mount_point"
        copy_files "$mount_point"
        fusermount -u "$mount_point"
    elif command -v 7z &>/dev/null; then
        # 7z ile çıkar (mount gerekmez)
        extract_with_7z "$iso"
        rmdir "$mount_point" 2>/dev/null || true
        return
    else
        error "ISO mount için 'fuseiso' veya '7z' gerekli, ya da root olarak çalıştırın."
        error "  sudo apt install fuseiso  (veya p7zip-full)"
        rmdir "$mount_point" 2>/dev/null || true
        exit 1
    fi

    rmdir "$mount_point" 2>/dev/null || true
}

# ── Mount Klasöründen Kopyala ────────────────────────────────
copy_files() {
    local src="$1"

    # Kernel bul (birkaç olası konum)
    local vmlinuz_src=""
    for path in \
        "$src/live/vmlinuz" \
        "$src/live/vmlinuz-amd64" \
        "$src/casper/vmlinuz"; do
        [ -f "$path" ] && { vmlinuz_src="$path"; break; }
    done

    # initrd bul
    local initrd_src=""
    for path in \
        "$src/live/initrd.img" \
        "$src/live/initrd" \
        "$src/live/initrd.img-amd64" \
        "$src/casper/initrd.lz"; do
        [ -f "$path" ] && { initrd_src="$path"; break; }
    done

    # squashfs bul
    local squashfs_src=""
    for path in \
        "$src/live/filesystem.squashfs" \
        "$src/casper/filesystem.squashfs"; do
        [ -f "$path" ] && { squashfs_src="$path"; break; }
    done

    # Kontrol
    [ -z "$vmlinuz_src" ]  && { error "vmlinuz bulunamadı! ISO geçerli bir Debian Live ISO mu?"; exit 1; }
    [ -z "$initrd_src" ]   && { error "initrd bulunamadı!"; exit 1; }
    [ -z "$squashfs_src" ] && { error "filesystem.squashfs bulunamadı!"; exit 1; }

    # Kopyala
    info "vmlinuz kopyalanıyor... ($vmlinuz_src)"
    cp "$vmlinuz_src" "$OUTPUT_DIR/vmlinuz"

    info "initrd.img kopyalanıyor... ($initrd_src)"
    cp "$initrd_src" "$OUTPUT_DIR/initrd.img"

    info "filesystem.squashfs kopyalanıyor (bu uzun sürer!)..."
    cp --progress "$squashfs_src" "$OUTPUT_DIR/live/filesystem.squashfs" 2>/dev/null || \
        cp "$squashfs_src" "$OUTPUT_DIR/live/filesystem.squashfs"
}

# ── 7z ile Çıkarma ────────────────────────────────────────────
extract_with_7z() {
    local iso="$1"
    local tmpdir
    tmpdir=$(mktemp -d)

    info "7z ile dosyalar çıkarılıyor..."

    # Kernel
    7z e "$iso" "live/vmlinuz" -o"$tmpdir" -y >/dev/null 2>&1 || \
    7z e "$iso" "live/vmlinuz-amd64" -o"$tmpdir" -y >/dev/null 2>&1 || true
    [ -f "$tmpdir/vmlinuz" ] && cp "$tmpdir/vmlinuz" "$OUTPUT_DIR/vmlinuz"
    [ -f "$tmpdir/vmlinuz-amd64" ] && cp "$tmpdir/vmlinuz-amd64" "$OUTPUT_DIR/vmlinuz"

    # initrd
    7z e "$iso" "live/initrd.img" -o"$tmpdir" -y >/dev/null 2>&1 || \
    7z e "$iso" "live/initrd" -o"$tmpdir" -y >/dev/null 2>&1 || true
    [ -f "$tmpdir/initrd.img" ] && cp "$tmpdir/initrd.img" "$OUTPUT_DIR/initrd.img"
    [ -f "$tmpdir/initrd" ] && cp "$tmpdir/initrd" "$OUTPUT_DIR/initrd.img"

    # squashfs (büyük dosya)
    info "filesystem.squashfs çıkarılıyor (büyük dosya)..."
    7z e "$iso" "live/filesystem.squashfs" -o"$tmpdir/live" -y >/dev/null 2>&1 || true
    [ -f "$tmpdir/live/filesystem.squashfs" ] && \
        mv "$tmpdir/live/filesystem.squashfs" "$OUTPUT_DIR/live/filesystem.squashfs"

    rm -rf "$tmpdir"
}

# ── Çalıştır ─────────────────────────────────────────────────
extract_iso "$ISO_PATH"

# ── Sonuç ────────────────────────────────────────────────────
echo ""
if [ -f "$OUTPUT_DIR/vmlinuz" ] && \
   [ -f "$OUTPUT_DIR/initrd.img" ] && \
   [ -f "$OUTPUT_DIR/live/filesystem.squashfs" ]; then
    log "Debian Live dosyaları hazır:"
    info "  vmlinuz            → $(du -sh "$OUTPUT_DIR/vmlinuz" | cut -f1)"
    info "  initrd.img         → $(du -sh "$OUTPUT_DIR/initrd.img" | cut -f1)"
    info "  filesystem.squashfs → $(du -sh "$OUTPUT_DIR/live/filesystem.squashfs" | cut -f1)"
    echo ""
    log "Boot URL'leri:"
    info "  Kernel  : http://${PXE_SERVER_IP}/boot/debian-live/vmlinuz"
    info "  Initrd  : http://${PXE_SERVER_IP}/boot/debian-live/initrd.img"
    info "  Squashfs: http://${PXE_SERVER_IP}/boot/debian-live/live/filesystem.squashfs"
else
    error "Bazı dosyalar eksik! ISO geçerli bir Debian Live ISO mu?"
    ls -la "$OUTPUT_DIR/" "$OUTPUT_DIR/live/" 2>/dev/null || true
    exit 1
fi
