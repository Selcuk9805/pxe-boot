#!/usr/bin/env python3
import os
import re
import shutil
import stat
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

BASE_DIR = Path("/nfs/persistent/base")
CLIENTS_DIR = Path("/nfs/persistent/clients")
HTTP_CLIENTS_DIR = Path("/http/boot/debian-persistent/clients")
DEFAULT_SCRIPT = "/boot/debian-persistent/debian-persistent.ipxe"

MAC_RE = re.compile(r"^([0-9a-f]{2}:){5}[0-9a-f]{2}$")


def load_dotenv(path: Path) -> None:
    if not path.exists() or not path.is_file():
        return

    try:
        content = path.read_text(encoding="utf-8")
    except Exception:
        return

    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key, value)


def bool_env(name: str, default: bool) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on", "e", "evet"}


def normalize_mac(raw: str) -> str:
    mac = raw.strip().lower().replace("-", ":")
    if not MAC_RE.match(mac):
        raise ValueError("invalid-mac")
    return mac


def server_host(headers) -> str:
    configured = os.getenv("PXE_SERVER_IP", "").strip()
    if configured:
        return configured

    forwarded_host = headers.get("X-Forwarded-Host", "").strip()
    if forwarded_host:
        return forwarded_host.split(":", 1)[0]

    host = headers.get("Host", "10.30.1.20").strip()
    return host.split(":", 1)[0]


def client_ipxe_content(host: str, mac: str) -> str:
    return f"""#!ipxe
set server-url  http://{host}
set nfs-server  {host}
set nfs-root    /nfs/persistent/clients/{mac}

kernel \\
  ${{server-url}}/boot/debian-persistent/vmlinuz \\
  root=/dev/nfs \\
  boot=nfs \\
  netboot=nfs \\
  nfsroot=${{nfs-server}}:${{nfs-root}} \\
  ip=dhcp \\
  systemd.unit=multi-user.target \\
  rw \\
  console=tty0 \\
  quiet

initrd \\
  ${{server-url}}/boot/debian-persistent/initrd.img

boot
"""


def chain_script(host: str, mac: str, note: str = "") -> str:
    note_line = f"echo {note}\n" if note else ""
    return (
        "#!ipxe\n"
        f"{note_line}"
        f"chain --autofree http://{host}/boot/debian-persistent/clients/{mac}.ipxe || "
        f"chain --autofree http://{host}{DEFAULT_SCRIPT}\n"
    )


def fallback_script(host: str, message: str) -> str:
    return (
        "#!ipxe\n"
        f"echo {message}\n"
        f"chain --autofree http://{host}{DEFAULT_SCRIPT}\n"
    )


def ensure_profile(host: str, mac: str) -> None:
    if not BASE_DIR.is_dir() or not (BASE_DIR / "etc/debian_version").exists():
        raise RuntimeError("base-not-ready")

    CLIENTS_DIR.mkdir(parents=True, exist_ok=True)
    HTTP_CLIENTS_DIR.mkdir(parents=True, exist_ok=True)

    client_dir = CLIENTS_DIR / mac
    if not client_dir.exists():
        shutil.copytree(BASE_DIR, client_dir, dirs_exist_ok=False)

    sanitize_runtime_tree(client_dir)

    client_ipxe = HTTP_CLIENTS_DIR / f"{mac}.ipxe"
    client_ipxe.write_text(client_ipxe_content(host, mac), encoding="utf-8")


def _safe_chmod(path: Path, mode: int) -> None:
    try:
        path.chmod(mode)
    except Exception:
        pass


def sanitize_runtime_tree(root: Path) -> None:
    (root / "dev").mkdir(parents=True, exist_ok=True)
    (root / "proc").mkdir(parents=True, exist_ok=True)
    (root / "sys").mkdir(parents=True, exist_ok=True)
    (root / "run").mkdir(parents=True, exist_ok=True)
    (root / "tmp").mkdir(parents=True, exist_ok=True)
    (root / "var" / "tmp").mkdir(parents=True, exist_ok=True)

    _safe_chmod(root / "dev", 0o755)
    _safe_chmod(root / "proc", 0o755)
    _safe_chmod(root / "sys", 0o755)
    _safe_chmod(root / "run", 0o755)
    _safe_chmod(root / "tmp", 0o1777)
    _safe_chmod(root / "var" / "tmp", 0o1777)

    # Kalıcı profile pseudo-fs runtime kalıntıları taşınmasın
    for volatile in (root / "proc", root / "sys", root / "run"):
        for child in volatile.iterdir():
            try:
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            except Exception:
                pass

    # /dev altında yanlışlıkla oluşan düzenli dosyalar disk şişirebilir
    for devname in ("full", "null", "zero", "random", "urandom", "tty", "console"):
        devpath = root / "dev" / devname
        try:
            st = os.lstat(devpath)
            if stat.S_ISREG(st.st_mode):
                devpath.unlink(missing_ok=True)
        except FileNotFoundError:
            continue
        except Exception:
            pass


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != "/enroll.ipxe":
            self.send_error(404)
            return

        host = server_host(self.headers)

        if not bool_env("AUTO_ENROLL_PERSISTENT", True):
            self.respond_ipxe(fallback_script(host, "Persistent auto-enroll kapali, shared profile kullaniliyor."))
            return

        query = parse_qs(parsed.query)
        raw_mac = (query.get("mac") or [""])[0]

        try:
            mac = normalize_mac(raw_mac)
        except ValueError:
            self.respond_ipxe(fallback_script(host, "Gecersiz MAC, shared profile kullaniliyor."))
            return

        try:
            ensure_profile(host, mac)
            self.respond_ipxe(chain_script(host, mac, f"Persistent profil hazir: {mac}"))
        except RuntimeError:
            self.respond_ipxe(fallback_script(host, "Base persistent hazir degil, shared profile kullaniliyor."))
        except Exception:
            self.respond_ipxe(fallback_script(host, "Auto-enroll hatasi, shared profile kullaniliyor."))

    def log_message(self, fmt, *args):
        return

    def respond_ipxe(self, body: str):
        payload = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-cache, no-store")
        self.end_headers()
        self.wfile.write(payload)


def main() -> None:
    load_dotenv(Path("/app/.env"))
    addr = ("0.0.0.0", int(os.getenv("PORT", "8080")))
    ThreadingHTTPServer(addr, Handler).serve_forever()


if __name__ == "__main__":
    main()
