# PXE Boot Sunucusu

Docker tabanlı PXE ortamı (DHCP Proxy + TFTP + HTTP + NFS).

## Desteklenen Modlar

| # | Mod | Açıklama |
|---|-----|----------|
| 1 | Debian 12 Kurulum | Netinstall (kernel/initrd HTTP) |
| 2 | Debian 12 Live | Geçici oturum (squashfs HTTP fetch) |
| 3 | Debian 12 Persistent | NFS root (kalıcı) |
| 4 | WinPE | wimboot + WIM |

---

## Hızlı Başlangıç

```bash
cd /home/damar/Masaüstü/pxe
cp .env.example .env
# .env içinde PXE_SERVER_IP ve NETWORK_SUBNET değerlerini düzenleyin.

make setup     # Altyapı + iPXE/wimboot + temel içerik hazırlığı
make doctor    # Eksik dosya/konfig kontrolü
make start     # Sadece konteynerleri başlatır
```

`make setup` sırasında 2 soru gelir:
- Debian 12 Live XFCE ISO indirilsin ve çıkarılsın mı?
- Debian 12 Persistent XFCE (NFS root) kurulsun mu?

Kullanıcı `E` derse kurulum otomatik ilerler.

Log takibi:

```bash
make logs-dhcp
make logs-http
```

---

## Komut Akışı (Önerilen)

- `make setup`:
    - script kurulumunu yapar
    - `make prepare` çağırır
    - opsiyonel olarak Live XFCE ve Persistent XFCE kurulumunu sorar
- `make prepare`:
    - eksikse Debian install dosyalarını hazırlar (`vmlinuz`, `initrd.gz`)
    - Live/Persistent/WinPE için eksik içerikleri bilgilendirir
- `make start`:
    - sadece servisleri başlatır (otomatik indirme yapmaz)
- `make doctor`:
    - gerekli artifact ve dnsmasq config kontrolü

---

## İçerik Hazırlama

### Debian Install (zorunlu)

```bash
make extract-install
```

### Debian Live (opsiyonel)

```bash
make extract-live ISO=isos/debian-live-12-amd64-xfce.iso
```

### Debian Persistent (opsiyonel)

```bash
sudo make setup-persistent

# XFCE profili ile (grafik masaüstü)
sudo PERSISTENT_PROFILE=xfce bash scripts/setup-persistent.sh
```

### WinPE (opsiyonel)

```bash
make extract-winpe ISO=isos/winpe.iso
```

---

## Servisler

| Servis | Görev | Port |
|--------|-------|------|
| pxe-dhcp | dnsmasq (DHCP Proxy + TFTP) | 67/udp, 69/udp |
| pxe-http | nginx (boot dosyaları) | 80/tcp |
| pxe-nfs | NFS (persistent) | 2049/tcp, 111/tcp+udp |

> `pxe-dhcp` host network kullanır. DHCP broadcast için gereklidir.

---

## UEFI/Legacy Notu

- Legacy: `undionly.kpxe`
- UEFI: `snponly.efi` (Hyper-V dahil daha stabil)
- iPXE menü: `http://<PXE_SERVER_IP>/boot.ipxe`

---

## Sorun Giderme

### Menüde `Not Found` (Debian seçenekleri)

Eksik içerik vardır. Aşağıdakileri çalıştırın:

```bash
make prepare
make doctor
```

### UEFI mavi iPXE ekranı sonrası düşüş

```bash
make logs-dhcp
make logs-http
sudo tcpdump -i any -nn 'port 67 or port 68 or port 69 or port 4011'
```

### NFS mount sorunu

```bash
showmount -e <PXE_SERVER_IP>
make logs-nfs
```

Detaylı ağ notları: [NETWORK_SETUP_NOTES.md](NETWORK_SETUP_NOTES.md)
