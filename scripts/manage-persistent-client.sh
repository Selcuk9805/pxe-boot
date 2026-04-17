#!/usr/bin/env bash
set -euo pipefail

# Kullanım:
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

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Root gerekli. sudo ile çalıştırın." >&2
    exit 1
fi

if [ -z "$ACTION" ] || [ -z "$RAW_MAC" ]; then
    echo "Kullanım: $0 <add|del> <MAC>" >&2
    exit 1
fi

MAC=$(echo "$RAW_MAC" | tr '[:upper:]' '[:lower:]' | tr '-' ':')
if ! [[ "$MAC" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
    echo "[!] Geçersiz MAC: $RAW_MAC" >&2
    exit 1
fi

CLIENT_DIR="$NFS_CLIENTS/$MAC"
CLIENT_IPXE="$HTTP_CLIENTS/$MAC.ipxe"

mkdir -p "$NFS_CLIENTS" "$HTTP_CLIENTS"

case "$ACTION" in
  add)
    if [ ! -d "$NFS_BASE" ] || [ ! -f "$NFS_BASE/etc/debian_version" ]; then
      echo "[!] Önce base persistent sistemi kurun: sudo make setup-persistent" >&2
      exit 1
    fi

    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$NFS_BASE/" "$CLIENT_DIR/"
    else
      rm -rf "$CLIENT_DIR"
      mkdir -p "$CLIENT_DIR"
      cp -a "$NFS_BASE/." "$CLIENT_DIR/"
    fi

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
    chmod -R 755 "$CLIENT_DIR"
    chown -R root:root "$CLIENT_DIR"

    echo "[✓] MAC profili oluşturuldu: $MAC"
    echo "    NFS:  $CLIENT_DIR"
    echo "    iPXE: $CLIENT_IPXE"
    ;;

  del)
    rm -rf "$CLIENT_DIR"
    rm -f "$CLIENT_IPXE"
    echo "[✓] MAC profili silindi: $MAC"
    ;;

  *)
    echo "[!] Geçersiz işlem: $ACTION (add|del)" >&2
    exit 1
    ;;
esac
