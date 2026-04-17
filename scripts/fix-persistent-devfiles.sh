#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PERSISTENT_ROOT="$PROJECT_DIR/nfs/persistent"

if [ "$(id -u)" -ne 0 ]; then
  echo "[!] Root gerekli. sudo ile çalıştırın." >&2
  exit 1
fi

if [ ! -d "$PERSISTENT_ROOT" ]; then
  echo "[!] Dizin bulunamadı: $PERSISTENT_ROOT" >&2
  exit 1
fi

clean_one() {
  local root="$1"
  [ -d "$root" ] || return 0

  mkdir -p "$root/dev" "$root/proc" "$root/sys" "$root/run" "$root/tmp" "$root/var/tmp"
  chmod 755 "$root/dev" "$root/proc" "$root/sys" "$root/run"
  chmod 1777 "$root/tmp" "$root/var/tmp"

  rm -rf "$root/proc"/* "$root/sys"/* "$root/run"/* || true

  for devname in full null zero random urandom tty console; do
    if [ -f "$root/dev/$devname" ] && [ ! -c "$root/dev/$devname" ]; then
      echo "[fix] regular file siliniyor: $root/dev/$devname"
      rm -f "$root/dev/$devname"
    fi
  done

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

clean_one "$PERSISTENT_ROOT/base"

if [ -d "$PERSISTENT_ROOT/clients" ]; then
  for c in "$PERSISTENT_ROOT/clients"/*; do
    [ -d "$c" ] || continue
    clean_one "$c"
  done
fi

echo "[✓] Persistent /dev temizliği tamamlandı."
