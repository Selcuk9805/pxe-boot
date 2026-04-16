#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  PXE Boot Sunucusu — İlk Kurulum Scripti
#  Çalıştırma: ./scripts/setup.sh
#
#  Bu script:
#    1. Bağımlılıkları kontrol eder
#    2. Dizin yapısını oluşturur
#    3. iPXE binary'lerini indirir (ipxe.efi + undionly.kpxe)
#    4. wimboot'u indirir (WinPE için)
#    5. .env dosyasını oluşturur
#    6. Docker image'larını hazırlar
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Renkler ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; }
info()  { echo -e "${CYAN}[→]${NC} $*"; }
step()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ── Evet/Hayır Sorusu ───────────────────────────────────────
ask_yes_no() {
    local prompt="$1"
    local default_no="${2:-1}"

    # Etkileşimsiz oturumlarda varsayılan: Hayır
    if ! [ -t 0 ]; then
        return 1
    fi

    local answer
    if [ "$default_no" -eq 1 ]; then
        read -rp "$prompt [E/h] " answer
        [[ "$answer" =~ ^[HhNn]$ ]] && return 1
        return 0
    else
        read -rp "$prompt [e/H] " answer
        [[ "$answer" =~ ^[EeYy]$ ]] && return 0
        return 1
    fi
}

# ── Banner ───────────────────────────────────────────────────
print_banner() {
echo -e "${BLUE}"
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║     PXE Boot Sunucusu — Kurulum           ║"
echo "  ║     Docker + iPXE + dnsmasq + NFS         ║"
echo "  ╚═══════════════════════════════════════════╝"
echo -e "${NC}"
}

# ── Bağımlılık Kontrolü ──────────────────────────────────────
check_deps() {
    step "Bağımlılıklar kontrol ediliyor..."
    local missing=0

    for cmd in docker curl wget; do
        if command -v "$cmd" &>/dev/null; then
            log "$cmd bulundu: $(command -v "$cmd")"
        else
            error "$cmd bulunamadı — lütfen yükleyin."
            missing=1
        fi
    done

    if docker compose version &>/dev/null 2>&1; then
        log "docker compose (plugin) bulundu."
    elif docker-compose version &>/dev/null 2>&1; then
        log "docker-compose (standalone) bulundu."
    else
        error "docker compose bulunamadı. Docker Compose yükleyin."
        missing=1
    fi

    [ "$missing" -eq 1 ] && { error "Eksik bağımlılıklar var. Çıkılıyor."; exit 1; }
    log "Tüm bağımlılıklar mevcut."
}

# ── Dizin Yapısı ─────────────────────────────────────────────
create_dirs() {
    step "Dizin yapısı oluşturuluyor..."

    local dirs=(
        "$PROJECT_DIR/tftp"
        "$PROJECT_DIR/http/boot/debian-install"
        "$PROJECT_DIR/http/boot/debian-live/live"
        "$PROJECT_DIR/http/boot/debian-persistent"
        "$PROJECT_DIR/http/boot/winpe"
        "$PROJECT_DIR/isos"
        "$PROJECT_DIR/nfs/debian-live"
        "$PROJECT_DIR/nfs/persistent/base"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
        info "$dir"
    done

    # .gitkeep dosyaları (boş dizinleri git'te saklamak için)
    touch "$PROJECT_DIR/isos/.gitkeep"
    touch "$PROJECT_DIR/nfs/debian-live/.gitkeep"
    touch "$PROJECT_DIR/nfs/persistent/.gitkeep"
    touch "$PROJECT_DIR/tftp/.gitkeep"

    log "Dizinler oluşturuldu."
}

# ── iPXE Binary İndirme ──────────────────────────────────────
# boot.ipxe.org erişilemez olduğundan, iPXE binary'lerini
# Debian/Kali ipxe paketinden çekiyoruz. Bu yöntem standart
# chainloading destekli binary'leri güvenilir biçimde sağlar.
download_ipxe() {
    step "iPXE binary'leri hazırlanıyor..."

    local tftp_dir="$PROJECT_DIR/tftp"

    if [ -f "$tftp_dir/ipxe.efi" ] && [ -f "$tftp_dir/undionly.kpxe" ]; then
        warn "iPXE binary'leri zaten mevcut — atlanıyor."
        return
    fi

    info "Debian ipxe paketi indiriliyor (apt-get download)..."
    local tmpdir
    tmpdir=$(mktemp -d)

    # Paketi kur (sadece indir)
    (cd "$tmpdir" && apt-get download ipxe 2>/dev/null) || \
    (cd "$tmpdir" && \
        # Kali mirror fallback
        wget -q --show-progress \
        "http://ftp.debian.org/debian/pool/main/i/ipxe/ipxe_1.21.1+git20230124.ccf29ac-1_all.deb" \
        -O ipxe.deb 2>/dev/null) || true

    local deb_file
    deb_file=$(find "$tmpdir" -name "ipxe*.deb" | head -1)

    if [ -z "$deb_file" ]; then
        error "iPXE paketi indirilemedi."
        error "Manuel adım: sudo apt install ipxe"
        error "  cp /usr/lib/ipxe/ipxe.efi $tftp_dir/"
        error "  cp /usr/lib/ipxe/undionly.kpxe $tftp_dir/"
        rm -rf "$tmpdir"
        return 1
    fi

    info "Paket extract ediliyor: $deb_file"
    dpkg-deb -x "$deb_file" "$tmpdir/extracted"

    # Binary'leri kopyala
    if [ ! -f "$tftp_dir/ipxe.efi" ]; then
        cp "$tmpdir/extracted/usr/lib/ipxe/ipxe.efi" "$tftp_dir/ipxe.efi"
        log "ipxe.efi hazır ($(du -sh "$tftp_dir/ipxe.efi" | cut -f1)) — UEFI"
    fi

    if [ ! -f "$tftp_dir/undionly.kpxe" ]; then
        cp "$tmpdir/extracted/usr/lib/ipxe/undionly.kpxe" "$tftp_dir/undionly.kpxe"
        log "undionly.kpxe hazır ($(du -sh "$tftp_dir/undionly.kpxe" | cut -f1)) — Legacy BIOS"
    fi

    # Bonus: snponly.efi (bazı UEFI sistemler için)
    [ -f "$tmpdir/extracted/usr/lib/ipxe/snponly.efi" ] && \
        cp "$tmpdir/extracted/usr/lib/ipxe/snponly.efi" "$tftp_dir/snponly.efi" && \
        log "snponly.efi hazır — alternatif UEFI"

    rm -rf "$tmpdir"
    log "iPXE binary'leri hazır."
}

# ── wimboot İndirme (WinPE) ──────────────────────────────────
download_wimboot() {
    step "wimboot indiriliyor (WinPE desteği)..."

    local wimboot_path="$PROJECT_DIR/http/wimboot"

    if [ ! -f "$wimboot_path" ]; then
        info "GitHub'dan son wimboot sürümü alınıyor..."

        # GitHub API ile son release URL'ini al
        local api_url="https://api.github.com/repos/ipxe/wimboot/releases/latest"
        local wimboot_url

        wimboot_url=$(curl -sf "$api_url" \
            | grep "browser_download_url" \
            | grep -v "\.sha256" \
            | grep -v "signed" \
            | grep -v "\.img" \
            | head -1 \
            | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

        if [ -n "$wimboot_url" ]; then
            info "İndiriliyor: $wimboot_url"
            wget -q --show-progress "$wimboot_url" -O "$wimboot_path"
            chmod +x "$wimboot_path"
            log "wimboot indirildi ($(du -sh "$wimboot_path" | cut -f1))."
        else
            warn "wimboot indirilemedi (internet erişimi yok veya API hatası)."
            warn "WinPE özelliği çalışmayacak. Manuel olarak indirin:"
            warn "  https://github.com/ipxe/wimboot/releases"
            warn "  → http/wimboot olarak kaydedin."
        fi
    else
        warn "wimboot zaten mevcut — atlanıyor."
    fi
}

# ── .env Dosyası ─────────────────────────────────────────────
create_env() {
    step ".env dosyası kontrol ediliyor..."

    if [ ! -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        log ".env dosyası oluşturuldu."
        warn "ÖNEMLİ: $PROJECT_DIR/.env dosyasını kontrol edin!"
        warn "  PXE_SERVER_IP ve NETWORK_SUBNET değerlerini doğrulayın."
    else
        warn ".env zaten mevcut — değiştirilmedi."
    fi
}

# ── İzinler ──────────────────────────────────────────────────
set_permissions() {
    step "İzinler ayarlanıyor..."
    chmod +x "$PROJECT_DIR/scripts/"*.sh
    chmod 644 "$PROJECT_DIR/config/dnsmasq/dnsmasq.conf"
    chmod 644 "$PROJECT_DIR/config/nginx/nginx.conf"
    chmod 644 "$PROJECT_DIR/config/nfs/exports"
    chmod -R 755 "$PROJECT_DIR/nfs/"
    log "İzinler ayarlandı."
}

# ── IP/Subnet Güncellemesi ───────────────────────────────────
apply_env() {
    step "Ortam değişkenleri (.env) projedeki IP'lere uygulanıyor..."
    bash "$PROJECT_DIR/scripts/apply-env.sh"
}

# ── Docker Image'ları ─────────────────────────────────────────
prepare_docker() {
    step "Docker image'ları hazırlanıyor..."
    cd "$PROJECT_DIR"

    info "nginx:alpine ve erichough/nfs-server pull ediliyor..."
    docker compose pull pxe-http pxe-nfs 2>/dev/null || \
        docker-compose pull pxe-http pxe-nfs 2>/dev/null || \
        warn "Pull hatası — internet bağlantısını kontrol edin."

    info "pxe-dhcp (dnsmasq) image build ediliyor..."
    docker compose build pxe-dhcp 2>/dev/null || \
        docker-compose build pxe-dhcp 2>/dev/null || true

    log "Docker image'ları hazır."
}

# ── Debian Live XFCE Hazırlığı (Opsiyonel) ──────────────────
prepare_live_xfce() {
    step "Debian 13 Live XFCE otomatik hazırlık"

    local live_iso_dir="$PROJECT_DIR/isos"
    local live_iso_path="$live_iso_dir/debian-live-13.4.0-amd64-xfce.iso"
    local live_url_base="https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid"

    mkdir -p "$live_iso_dir"

    # Eğer kullanıcı farklı isimle ISO koyduysa onu kullan
    local existing_iso
    existing_iso=$(find "$live_iso_dir" -maxdepth 1 -type f -name 'debian-live*amd64*xfce*.iso' | sort -V | tail -1 || true)
    if [ -n "$existing_iso" ]; then
        live_iso_path="$existing_iso"
    fi

    if [ ! -f "$live_iso_path" ]; then
        info "Debian 13 Live XFCE ISO bulunamadı, indiriliyor..."

        local index_html iso_name live_url
        index_html=$(curl -fsSL "$live_url_base/" 2>/dev/null || true)
        iso_name=$(echo "$index_html" \
            | grep -oE 'debian-live-13(\.[0-9]+)*-amd64-xfce\.iso' \
            | sort -V | tail -1 || true)

        if [ -z "$iso_name" ]; then
            warn "Sürüm bazlı dosya adı bulunamadı, alternatif adlar denenecek..."
        fi

        local downloaded=0
        local candidates=()
        [ -n "$iso_name" ] && candidates+=("$iso_name")
        candidates+=("debian-live-13.4.0-amd64-xfce.iso" "debian-live-13-amd64-xfce.iso" "debian-live-amd64-xfce.iso")

        for candidate in "${candidates[@]}"; do
            live_url="$live_url_base/$candidate"
            info "Deneniyor: $live_url"
            if wget -q --show-progress "$live_url" -O "$live_iso_path"; then
                downloaded=1
                break
            fi
        done

        if [ "$downloaded" -ne 1 ]; then
            warn "Debian 13 Live XFCE ISO otomatik indirilemedi."
            warn "Manuel indirin ve tekrar deneyin:"
            warn "  https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/"
            warn "  -> $live_iso_dir/ altina bir *.iso kopyalayin"
            return 1
        fi

        log "ISO indirildi: $live_iso_path ($(du -sh "$live_iso_path" | cut -f1))"
    else
        warn "ISO mevcut, indirme atlandı: $live_iso_path"
    fi

    info "Live dosyaları çıkarılıyor..."
    bash "$PROJECT_DIR/scripts/extract-debian-live.sh" "$live_iso_path"
    log "Debian Live XFCE hazır."
}

# ── Debian Persistent XFCE Hazırlığı (Opsiyonel) ────────────
prepare_persistent_xfce() {
    step "Debian 12 Persistent XFCE otomatik hazırlık"

    info "Bu adım root gerektirir; sudo istenebilir."
    if ! sudo PERSISTENT_PROFILE=xfce NONINTERACTIVE=1 \
        bash "$PROJECT_DIR/scripts/setup-persistent.sh"; then
        return 1
    fi

    log "Debian Persistent XFCE hazır."
}

# ── Opsiyonel İçerik Soruları ───────────────────────────────
optional_content_wizard() {
    step "Opsiyonel içerik sihirbazı"

    if ask_yes_no "Debian 13 Live XFCE dosyalari indirilsin ve hazirlansin mi?" 1; then
        prepare_live_xfce || warn "Debian 13 Live XFCE hazırlığı başarısız, setup devam ediyor."
    else
        info "Debian 13 Live XFCE atlandı."
    fi

    if ask_yes_no "Debian 12 Persistent XFCE (NFS root) kurulsun mu?" 1; then
        prepare_persistent_xfce || warn "Debian Persistent XFCE hazırlığı başarısız, setup devam ediyor."
    else
        info "Debian Persistent XFCE atlandı."
    fi
}

# ── Son Mesaj ────────────────────────────────────────────────
print_next_steps() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Kurulum Tamamlandı! ✓                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Sonraki Adımlar:${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} ISO'ları isos/ dizinine kopyalayın"
    echo ""
    echo -e "  ${CYAN}2.${NC} İçerikleri çıkarın:"
    echo "       ./scripts/extract-debian-install.sh"
    echo "       ./scripts/extract-debian-live.sh  isos/debian-live-*.iso"
    echo "       ./scripts/setup-persistent.sh     (uzun sürer!)"
    echo ""
    echo -e "  ${CYAN}3.${NC} Sunucuyu başlatın:"
    echo "       make start"
    echo "       (veya: docker compose up -d)"
    echo ""
    echo -e "  ${CYAN}4.${NC} Logları izleyin:"
    echo "       make logs"
    echo ""
    echo -e "  ${YELLOW}NETWORK_SETUP_NOTES.md${NC} dosyasını okuyun!"
    echo ""
}

# ── Ana Akış ─────────────────────────────────────────────────
main() {
    print_banner
    check_deps
    create_dirs
    create_env
    download_ipxe
    download_wimboot
    set_permissions
    apply_env
    prepare_docker
    optional_content_wizard
    print_next_steps
}

main "$@"
