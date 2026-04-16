#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Debian 12 Persistent — NFS Kök Sistemi Kurulum Scripti
#
#  Bu script şunları yapar:
#    1. debootstrap ile minimal Debian sistemi kurar
#       → nfs/persistent/base/
#    2. Chroot içinde linux kernel kurar
#    3. NFS root için gerekli /etc dosyalarını ayarlar
#    4. Kernel + initrd'yi HTTP sunucusuna kopyalar
#       → http/boot/debian-persistent/
#
#  GEREKSİNİMLER:
#    sudo apt install debootstrap
#    (veya Docker üzerinden çalışır — root gerekir)
#
#  Çalıştırma (root gerekli):
#    sudo ./scripts/setup-persistent.sh
#
#  Süre: 10-25 dakika (internet hızına bağlı)
#  Boyut: ~500MB - 1.5GB
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
NFS_BASE="$PROJECT_DIR/nfs/persistent/base"
BOOT_OUTPUT="$PROJECT_DIR/http/boot/debian-persistent"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    PXE_SERVER_IP="10.30.1.20"
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
info()  { echo -e "${CYAN}[→]${NC} $*"; }
step()  { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ── Root Kontrolü ────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    error "Bu script root yetkisi gerektirir."
    error "  sudo $0"
    exit 1
fi

# ── debootstrap Kontrolü ─────────────────────────────────────
if ! command -v debootstrap &>/dev/null; then
    error "debootstrap bulunamadı."
    error "  sudo apt install debootstrap"
    exit 1
fi

echo -e "\n${BOLD}${CYAN}PXE Persistent Debian — NFS Kök Kurulumu${NC}"
echo "NFS hedef : $NFS_BASE"
echo "HTTP hedef: $BOOT_OUTPUT"
echo ""
warn "Bu işlem 10-25 dakika sürebilir ve ~500MB-1.5GB alan kaplar."
echo ""
read -rp "Devam etmek istiyor musunuz? [E/h] " confirm
[[ "$confirm" =~ ^[Hh] ]] && { echo "İptal edildi."; exit 0; }

# ── Debootstrap ──────────────────────────────────────────────
step "Debian Bookworm debootstrap başlatılıyor..."
mkdir -p "$NFS_BASE"
mkdir -p "$BOOT_OUTPUT"

if [ -f "$NFS_BASE/etc/debian_version" ]; then
    warn "NFS base sistemi zaten mevcut. Atlanıyor."
    warn "Yeniden kurmak için: sudo rm -rf $NFS_BASE && $0"
else
    info "debootstrap çalıştırılıyor (minimal Debian)..."
    debootstrap \
        --arch=amd64 \
        --include=linux-image-amd64,nfs-common,systemd-sysv,udev,net-tools,iproute2,openssh-server \
        bookworm \
        "$NFS_BASE" \
        https://deb.debian.org/debian

    log "debootstrap tamamlandı."
fi

# ── Temel Yapılandırma ───────────────────────────────────────
step "Sistem yapılandırması..."

# /etc/fstab (NFS root için özel — yerel mount yok)
cat > "$NFS_BASE/etc/fstab" <<EOF
# NFS root sistemi için fstab
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /tmp tmpfs defaults,size=256m 0 0
EOF

# /etc/hostname
echo "pxe-persistent" > "$NFS_BASE/etc/hostname"

# /etc/hosts
cat > "$NFS_BASE/etc/hosts" <<EOF
127.0.0.1   localhost
127.0.1.1   pxe-persistent
::1         localhost ip6-localhost ip6-loopback
EOF

# /etc/network/interfaces
cat > "$NFS_BASE/etc/network/interfaces" <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Root şifresi ayarla
info "Root şifresi ayarlanıyor (varsayılan: pxeboot)..."
echo "root:pxeboot" | chroot "$NFS_BASE" chpasswd
warn "ÜNEMLİ: root şifresi 'pxeboot' olarak ayarlandı. Değiştirin!"

# ── SSH Yapılandırması ───────────────────────────────────────
# PermitRootLogin (lab ortamı için)
sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' "$NFS_BASE/etc/ssh/sshd_config" 2>/dev/null || true

# ── Kernel + initrd Kopyalama ────────────────────────────────
step "Kernel ve initrd HTTP sunucusuna kopyalanıyor..."

# En yeni kernel bul
VMLINUZ=$(find "$NFS_BASE/boot/" -name "vmlinuz-*" | sort | tail -1)
INITRD=$(find "$NFS_BASE/boot/" -name "initrd.img-*" | sort | tail -1)

if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ]; then
    error "Kernel veya initrd bulunamadı: $NFS_BASE/boot/"
    error "debootstrap'ta linux-image-amd64 kurulu olmalı."
    exit 1
fi

info "Kernel: $VMLINUZ → $BOOT_OUTPUT/vmlinuz"
cp "$VMLINUZ" "$BOOT_OUTPUT/vmlinuz"

info "Initrd: $INITRD → $BOOT_OUTPUT/initrd.img"
cp "$INITRD" "$BOOT_OUTPUT/initrd.img"

log "Kernel ve initrd kopyalandı."

# ── NFS İzinleri ─────────────────────────────────────────────
step "NFS dizin izinleri ayarlanıyor..."
chmod -R 755 "$NFS_BASE"
chown -R root:root "$NFS_BASE"

# ── Özet ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Persistent Debian Kurulumu Tamamlandı!  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""
log "NFS kök boyutu : $(du -sh "$NFS_BASE" | cut -f1)"
log "vmlinuz        : $(du -sh "$BOOT_OUTPUT/vmlinuz" | cut -f1)"
log "initrd.img     : $(du -sh "$BOOT_OUTPUT/initrd.img" | cut -f1)"
echo ""
info "Sonraki adımlar:"
echo "  1. docker compose up -d pxe-nfs"
echo "  2. NFS export kontrol: showmount -e $PXE_SERVER_IP"
echo "  3. PXE menüsünden 'Debian Persistent' seçin"
echo ""
warn "Root şifresi: pxeboot — değiştirmeyi unutmayın!"
warn "  chroot $NFS_BASE passwd root"
