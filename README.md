# PXE Boot Sunucusu

Docker tabanlı, tam donanımlı ağ önyükleme (network boot) sunucusu.

**Desteklenen önyükleme modları:**
| # | Mod | Açıklama |
|---|-----|----------|
| 1 | Debian 12 Kurulum | Ağ üzerinden tam Debian kurulumu |
| 2 | Debian 12 Live | Geçici oturum, RAM'de çalışır |
| 3 | Debian 12 Persistent | NFS kök sistemi, kalıcı değişiklikler |
| 4 | WinPE | Windows Preinstallation Environment |

---

## Hızlı Başlangıç

### 1. Kurulum

```bash
cd /home/damar/Masaüstü/pxe

# .env oluştur
cp .env.example .env
# .env'i düzenleyip PXE_SERVER_IP kontrol edin (varsayılan: 10.30.1.20)

# Kurulum scriptini çalıştır (iPXE + wimboot indirir)
make setup
```

### 2. Debian Kurulum için Dosya Hazırlama

```bash
# İnternetten otomatik indir (ISO gerekmez)
make extract-install
```

### 3. Debian Live için ISO İşleme

```bash
# ISO'yu isos/ dizinine kopyalayın, sonra:
make extract-live ISO=isos/debian-live-12-amd64-gnome.iso
```

### 4. Sunucuyu Başlat

```bash
make start

# Logları izle
make logs-dhcp   # DHCP/TFTP trafiği
make logs-http   # HTTP dosya erişimleri
```

---

## Servisler

| Konteyner | Görev | Port |
|-----------|-------|------|
| `pxe-dhcp` | DHCP Proxy + TFTP (dnsmasq) | 67/udp, 69/udp |
| `pxe-http` | HTTP dosya sunucu (nginx) | 80/tcp |
| `pxe-nfs` | NFS sunucusu (Persistent boot) | 2049/tcp |

> `pxe-dhcp` `network_mode: host` ile çalışır. DHCP broadcast'leri için zorunludur.

---

## Dizin Yapısı

```
pxe/
├── docker-compose.yml
├── .env                     ← Yapılandırın!
├── Makefile
├── NETWORK_SETUP_NOTES.md   ← Router notları
│
├── config/
│   ├── dnsmasq/dnsmasq.conf ← DHCP proxy + TFTP ayarları
│   ├── nginx/nginx.conf     ← HTTP sunucu ayarları
│   └── nfs/exports          ← NFS export tanımları
│
├── tftp/                    ← iPXE binary'leri (setup.sh indirir)
│   ├── ipxe.efi             (UEFI)
│   └── undionly.kpxe        (Legacy BIOS)
│
├── http/                    ← Nginx kök dizini
│   ├── boot.ipxe            ← Ana boot menüsü
│   ├── wimboot              (setup.sh indirir)
│   └── boot/
│       ├── debian-install/  ← vmlinuz + initrd.gz (extract-debian-install.sh)
│       ├── debian-live/     ← vmlinuz + initrd.img + live/filesystem.squashfs
│       ├── debian-persistent/ ← kernel + initrd (setup-persistent.sh)
│       └── winpe/           ← boot.wim + BCD + boot.sdi
│
├── nfs/
│   ├── debian-live/         ← (opsiyonel NFS live root)
│   └── persistent/base/     ← Debian NFS kök (setup-persistent.sh kurar)
│
├── isos/                    ← Ham ISO'ları buraya koyun
└── scripts/
    ├── setup.sh
    ├── extract-debian-install.sh
    ├── extract-debian-live.sh
    ├── setup-persistent.sh  (sudo gerekli)
    └── extract-winpe.sh
```

---

## Boot Senaryoları

### Debian 12 Kurulum (Net Install)
- Kernel + initrd yerel HTTP sunucusundan
- Debian paketleri kurulum sırasında internet'ten indirilir
- Hazırlık: `make extract-install`

### Debian 12 Live (Geçici)
- squashfs HTTP `fetch=` ile RAM'e yüklenir
- Kapanınca tüm değişiklikler kaybolur
- Hazırlık: `make extract-live ISO=<path>`

### Debian 12 Persistent (NFS Kök)
- Tam Debian sistemi NFS üzerinde çalışır
- Değişiklikler NFS sunucusunda kalıcı olarak saklanır
- Hazırlık: `sudo make setup-persistent` (debootstrap çalıştırır, ~15 dk)

### WinPE
- wimboot + WIM dosyası HTTP üzerinden yüklenir
- Windows ADK ile oluşturulmuş ISO gerekir
- Hazırlık: `make extract-winpe ISO=isos/winpe.iso`

---

## Boot Akışı

```
[İstemci NIC]
    │
    │ DHCP broadcast
    ▼
[dnsmasq PROXY] ──── TFTP ────► ipxe.efi (UEFI)
                                 undionly.kpxe (BIOS)
                                      │
                                      │ iPXE başlar
                                      ▼
                           [iPXE DHCP] ──── HTTP ────► boot.ipxe (menü)
                                                           │
                           ┌───────────────────────────────┤
                           │               │               │
                    debian-install   debian-live     debian-persist
                    vmlinuz+initrd   squashfs HTTP   NFS root boot
                           │               │               │
                           └───────── [Nginx HTTP] ────────┘
                                               │
                                          [NFS Server]
                                        (Persistent için)
```

---

## Ağ Notları

> ⚠️ **DHCP proxy modu** için genellikle router'da değişiklik gerekmez.
> Detaylar için: **[NETWORK_SETUP_NOTES.md](NETWORK_SETUP_NOTES.md)**

Güvenlik duvarı portları (sunucu makinesinde açılmalı):
- **67, 68/udp** — DHCP
- **69/udp** — TFTP  
- **80/tcp** — HTTP (kernel, squashfs, WIM)
- **2049/tcp, 111/tcp+udp** — NFS (Persistent boot için)

---

## Sık Kullanılan Komutlar

```bash
make start              # Başlat
make stop               # Durdur
make status             # Durum
make logs               # Tüm loglar
make logs-dhcp          # DHCP/TFTP logları (boot trafik izleme)
make logs-http          # HTTP erişim logları
```

---

## Sorun Giderme

**Boot döngüsü (iPXE kendini tekrar yükliyor):**
→ `dnsmasq.conf` içinde `dhcp-match=set:ipxe,175` ve `dhcp-boot=tag:ipxe,...` satırlarını kontrol edin.

**squashfs yüklenmiyor:**
→ `make logs-http` ile HTTP erişim logunu kontrol edin.  
→ `curl http://10.30.1.20/boot/debian-live/live/filesystem.squashfs` ile test edin.

**NFS mount başarısız:**
→ `showmount -e 10.30.1.20` komutuyla export'ları kontrol edin.  
→ `make logs-nfs` ile NFS loglarına bakın.

Daha fazlası için: **[NETWORK_SETUP_NOTES.md](NETWORK_SETUP_NOTES.md)**
