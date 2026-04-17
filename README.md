# PXE Boot Sunucusu

Docker tabanlı PXE ortamı (DHCP Proxy + TFTP + HTTP + NFS).

## Desteklenen Modlar

| # | Mod | Açıklama |
|---|-----|----------|
| 1 | Debian 12 Kurulum | Netinstall (kernel/initrd HTTP) |
| 2 | Debian 13 Live XFCE | Geçici oturum (squashfs HTTP fetch) |
| 3 | Debian 12 Persistent | NFS root (kalıcı, MAC bazlı profil desteği) |
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
- Debian 13 Live XFCE ISO indirilsin ve çıkarılsın mı?
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
    - gerekli artifact ve host NFS modül kontrolü

---

## İçerik Hazırlama

### Debian Install (zorunlu)

```bash
make extract-install
```

### Debian Live (opsiyonel)

```bash
make extract-live ISO=isos/debian-live-13.4.0-amd64-xfce.iso
```

### Debian Persistent (opsiyonel)

```bash
sudo make setup-persistent

# XFCE profili ile (grafik masaüstü)
sudo PERSISTENT_PROFILE=xfce bash scripts/setup-persistent.sh

# MAC'e özel persistent profil oluştur
make persistent-add-client MAC=00:11:22:33:44:55

# MAC'e özel persistent profili sil
make persistent-del-client MAC=00:11:22:33:44:55

# /dev/full vb. hatalı regular dosyaları temizle
make persistent-fix-dev
```

Not:
- Varsayılan durumda tüm istemciler `/nfs/persistent/base` kullanır.
- Persistent açılırken MAC'e özel dosya yoksa sistem artık otomatik profile oluşturmayı dener.
- `make persistent-add-client` sonrası ilgili MAC için
    `/nfs/persistent/clients/<mac>` yolu kullanılır.
- Bir cihazı sıfırlamak için `persistent-del-client` yeterlidir.
- Otomatik kayıt kapatmak için `docker-compose.yml` içinde `AUTO_ENROLL_PERSISTENT=0` yapabilirsiniz.

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
| pxe-enroll | Persistent auto-enroll API | internal (8080) |

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

Eğer `pxe-nfs` logunda `kernel module nfs is missing` görürseniz:

```bash
sudo modprobe nfs
sudo modprobe nfsd
make doctor
docker compose restart pxe-nfs
```

### Persistent auto-enroll 5xx

Eğer boot ekranında `/api/persistent/enroll.ipxe` için 5xx görüyorsanız:

```bash
make logs-enroll
docker compose restart pxe-enroll pxe-http
```

Not: Sistem bu durumda da shared persistent profile fallback yapar.

### Persistent root disk'i şişiyor (/dev/full büyüyor)

Belirti: istemci boot ederken "alan kalmadı" hatası ve hostta
`nfs/persistent/clients/<mac>/dev/full` dosyasının çok büyümesi.

Çözüm:

```bash
make persistent-fix-dev
```

Bu komut hatalı regular `/dev/*` dosyalarını temizler ve temel device node
iskeletini tekrar kurar.

Detaylı ağ notları: [NETWORK_SETUP_NOTES.md](NETWORK_SETUP_NOTES.md)
