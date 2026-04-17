#!/usr/bin/env bash
set -euo pipefail

# Kullanım:
#   ./scripts/manage-persistent-client.sh list
#   sudo ./scripts/manage-persistent-client.sh add 00:11:22:33:44:55
#   sudo ./scripts/manage-persistent-client.sh del 00:11:22:33:44:55

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

NFS_BASE="$PROJECT_DIR/nfs/persistent/base"
NFS_CLIENTS="$PROJECT_DIR/nfs/persistent/clients"
HTTP_CLIENTS="$PROJECT_DIR/http/boot/debian-persistent/clients"

if [ -f "$PROJECT_DIR/.env" ]; then
    source "$PROJECT_DIR/.env"
else
    PXE_SERVER_IP="10.30.1.20"
fi

ACTION="${1:-}"
RAW_MAC="${2:-}"

if [ -z "$ACTION" ]; then
  echo "Kullanım:" >&2
  echo "  $0 list" >&2
  echo "  sudo $0 add <MAC>" >&2
  echo "  sudo $0 del <MAC>" >&2
    exit 1
fi

prepare_runtime_dirs() {
  local root="$1"

  mkdir -p "$root/dev" "$root/proc" "$root/sys" "$root/run" "$root/tmp" "$root/var/tmp"
  chmod 755 "$root/dev" "$root/proc" "$root/sys" "$root/run"
  chmod 1777 "$root/tmp" "$root/var/tmp"

  # Volatile pseudo-fs içeriklerini kalıcı profile taşımayın
  rm -rf "$root/proc"/* "$root/sys"/* "$root/run"/* || true

  # /dev altında oluşmuş düzenli dosya tuzaklarını temizle
  for devname in full null zero random urandom tty console; do
    if [ -f "$root/dev/$devname" ] && [ ! -c "$root/dev/$devname" ]; then
      rm -f "$root/dev/$devname"
    fi
  done

  # Host root ile oluşturuluyorsa temel device node'larını garanti et
  if command -v mknod >/dev/null 2>&1; then
    [ -e "$root/dev/null" ]    || mknod -m 666 "$root/dev/null" c 1 3 || true
    [ -e "$root/dev/zero" ]    || mknod -m 666 "$root/dev/zero" c 1 5 || true
    [ -e "$root/dev/full" ]    || mknod -m 666 "$root/dev/full" c 1 7 || true
    [ -e "$root/dev/random" ]  || mknod -m 666 "$root/dev/random" c 1 8 || true
    [ -e "$root/dev/urandom" ] || mknod -m 666 "$root/dev/urandom" c 1 9 || true
    [ -e "$root/dev/tty" ]     || mknod -m 666 "$root/dev/tty" c 5 0 || true
    [ -e "$root/dev/console" ] || mknod -m 600 "$root/dev/console" c 5 1 || true
  fi
}

mkdir -p "$NFS_CLIENTS" "$HTTP_CLIENTS"

case "$ACTION" in
  list)
    echo ""
    echo "Persistent istemci profilleri"
    echo "-----------------------------------------------"
    found=0
    shopt -s nullglob
    for d in "$NFS_CLIENTS"/*; do
      [ -d "$d" ] || continue
      mac="$(basename "$d")"
      if [[ ! "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
        continue
      fi
      found=1
      size="$(du -sh "$d" 2>/dev/null | awk '{print $1}')"
      updated="$(date -r "$d" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '-')"
      if [ -f "$HTTP_CLIENTS/$mac.ipxe" ]; then
        ipxe="ok"
      else
        ipxe="missing"
      fi
      echo "MAC: $mac | boyut: $size | guncel: $updated | ipxe: $ipxe"
    done
    shopt -u nullglob
    if [ "$found" -eq 0 ]; then
      echo "(profil bulunamadi)"
    fi
    echo ""
    ;;

  add)
    if [ "$(id -u)" -ne 0 ]; then
      echo "[!] Root gerekli. sudo ile çalıştırın." >&2
      exit 1
    fi

    if [ -z "$RAW_MAC" ]; then
      echo "Kullanım: sudo $0 add <MAC>" >&2
      exit 1
    fi

    MAC=$(echo "$RAW_MAC" | tr '[:upper:]' '[:lower:]' | tr '-' ':')
    if ! [[ "$MAC" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
      echo "[!] Geçersiz MAC: $RAW_MAC" >&2
      exit 1
    fi

    CLIENT_DIR="$NFS_CLIENTS/$MAC"
    CLIENT_IPXE="$HTTP_CLIENTS/$MAC.ipxe"

    if [ ! -d "$NFS_BASE" ] || [ ! -f "$NFS_BASE/etc/debian_version" ]; then
      echo "[!] Önce base persistent sistemi kurun: sudo make setup-persistent" >&2
      exit 1
    fi

    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete \
        --exclude='/dev/*' \
        --exclude='/proc/*' \
        --exclude='/sys/*' \
        --exclude='/run/*' \
        --exclude='/tmp/*' \
        --exclude='/var/tmp/*' \
        "$NFS_BASE/" "$CLIENT_DIR/"
    else
      rm -rf "$CLIENT_DIR"
      mkdir -p "$CLIENT_DIR"
      cp -a "$NFS_BASE/." "$CLIENT_DIR/"
    fi

    prepare_runtime_dirs "$CLIENT_DIR"

    cat > "$CLIENT_IPXE" <<EOF
#!ipxe
set server-url  http://${PXE_SERVER_IP}
set nfs-server  ${PXE_SERVER_IP}
set nfs-root    /nfs/persistent/clients/${MAC}

kernel \
  \\${server-url}/boot/debian-persistent/vmlinuz \
  root=/dev/nfs \
  boot=nfs \
  netboot=nfs \
  nfsroot=\\${nfs-server}:\\${nfs-root} \
  ip=dhcp \
  systemd.unit=multi-user.target \
  rw \
  console=tty0 \
  quiet

initrd \
  \\${server-url}/boot/debian-persistent/initrd.img

boot
EOF

    chmod 644 "$CLIENT_IPXE"
    chown -R root:root "$CLIENT_DIR"

    echo "[✓] MAC profili oluşturuldu: $MAC"
    echo "    NFS:  $CLIENT_DIR"
    echo "    iPXE: $CLIENT_IPXE"
    ;;

  del)
    if [ "$(id -u)" -ne 0 ]; then
      echo "[!] Root gerekli. sudo ile çalıştırın." >&2
      exit 1
    fi

    if [ -z "$RAW_MAC" ]; then
      echo "Kullanım: sudo $0 del <MAC>" >&2
      exit 1
    fi

    MAC=$(echo "$RAW_MAC" | tr '[:upper:]' '[:lower:]' | tr '-' ':')
    if ! [[ "$MAC" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
      echo "[!] Geçersiz MAC: $RAW_MAC" >&2
      exit 1
    fi

    CLIENT_DIR="$NFS_CLIENTS/$MAC"
    CLIENT_IPXE="$HTTP_CLIENTS/$MAC.ipxe"

    rm -rf "$CLIENT_DIR"
    rm -f "$CLIENT_IPXE"
    echo "[✓] MAC profili silindi: $MAC"
    ;;

  *)
    echo "[!] Geçersiz işlem: $ACTION (list|add|del)" >&2
    exit 1
    ;;
esac
