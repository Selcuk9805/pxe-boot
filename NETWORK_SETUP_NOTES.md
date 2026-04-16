# PXE Boot Sunucusu — Ağ Kurulum Notları
> **Router / DHCP sunucunuzda yapılması gerekenler**

---

## Özet: Genellikle HİÇBİR Değişiklik Gerekmez

Bu sistem **DHCP Proxy** modunda çalışır. dnsmasq, mevcut DHCP sunucunuzla (router) birlikte sessizce çalışır:

- Mevcut DHCP sunucusu → IP adresi dağıtmaya devam eder ✓
- dnsmasq (proxy) → Sadece PXE boot bilgisi ekler ✓
- Çakışma yok, IP havuzu değişmez ✓

**Test adımı:** Docker servislerini başlatın ve bir test makinesini network boot edin. Eğer çalışırsa, router'da değişiklik gerekmez.

---

## Güvenlik Duvarı Kuralları (PXE Sunucu Makinesinde)

Eğer sunucu makinenizde `ufw` veya `iptables` varsa, bu portları açın:

```bash
# dnsmasq (DHCP proxy + TFTP)
sudo ufw allow 67/udp    # DHCP
sudo ufw allow 68/udp    # DHCP client
sudo ufw allow 69/udp    # TFTP

# Nginx (HTTP — kernel, initrd, squashfs, WIM)
sudo ufw allow 80/tcp

# NFS (Persistent boot için)
sudo ufw allow 2049/tcp  # NFS
sudo ufw allow 2049/udp
sudo ufw allow 111/tcp   # portmapper
sudo ufw allow 111/udp
```

---

## Seçenek A: Router'da PXE Seçenekleri Ayarlama (İsteğe Bağlı)

DHCP proxy modu çalışmıyorsa veya güvenlik gereksinimleriniz varsa, router'ınıza şu DHCP seçeneklerini ekleyin:

| DHCP Option | Değer | Açıklama |
|-------------|-------|----------|
| Option 66 (Next Server) | `10.30.1.20` | TFTP sunucu IP'si |
| Option 67 (Boot File) | `undionly.kpxe` | Default (BIOS+UEFI için) |

> **Not:** Tek bir DHCP seçeneğiyle hem BIOS hem UEFI'yi desteklemek zordur.  
> Bu yüzden DHCP proxy modu önerilir — otomatik mimari tespiti yapar.

---

## ISC DHCP Server (isc-dhcp-server) Yapılandırması

Eğer ağınızda ISC DHCP Server varsa ve DHCP proxy modunu kullanmak istemiyorsanız:

```
# /etc/dhcp/dhcpd.conf

subnet 10.30.1.0 netmask 255.255.255.0 {
  range 10.30.1.100 10.30.1.200;
  option routers 10.30.1.1;
  option domain-name-servers 8.8.8.8, 8.8.4.4;

  # PXE Boot
  next-server 10.30.1.20;

  # UEFI/BIOS ayrımı (class-based)
  class "pxeclients" {
    match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";

    if option pxe-system-type = 00:07 {
      # UEFI x86-64
      filename "ipxe.efi";
    } else {
      # Legacy BIOS
      filename "undionly.kpxe";
    }
  }
}
```

---

## MikroTik RouterOS

MikroTik'te DHCP server üzerinden PXE seçenekleri:

```
# DHCP Server Network seçenekleri
/ip dhcp-server network set [find] next-server=10.30.1.20

# Option 67 (Boot File) — BIOS için
/ip dhcp-server option add code=67 name=pxe-bootfile value="'undionly.kpxe'"
/ip dhcp-server option sets add name=pxe-options options=pxe-bootfile
/ip dhcp-server set [find] option-set=pxe-options
```

> **MikroTik'te BIOS/UEFI ayrımı** yapmak için script gerekir.  
> En kolay yol: `undionly.kpxe` varsayılan olarak bırakmak.  
> UEFI istemciler `ipxe.efi` olmadan yine de boot etmeyi deneyebilir.

---

## pfSense / OPNsense

**Services → DHCP Server → [interface] → Additional BOOTP/DHCP Options:**

| Number | Type | Value |
|--------|------|-------|
| 66 | String | `10.30.1.20` |
| 67 | String | `undionly.kpxe` |

Veya **TFTP Server** alanına direkt `10.30.1.20` yazın.

---

## Sorun Giderme

### "DHCP proxy çalışmıyor" senaryosu

```bash
# dnsmasq loglarını kontrol edin
make logs-dhcp

# DHCP trafiğini izleyin (sunucu üzerinde)
sudo tcpdump -i any -n port 67 or port 68

# Test makinesinden PXE trafiği yakalanıyor mu?
sudo tcpdump -i any -n port 69  # TFTP
```

### "iPXE boot.ipxe yüklenemiyor" senaryosu

```bash
# Nginx erişim logları
make logs-http

# HTTP sunucusunu test edin
curl -v http://10.30.1.20/boot.ipxe
curl -v http://10.30.1.20/boot/debian-install/vmlinuz
```

### "UEFI PXE başlıyor ama firmware ekranına geri dönüyor" senaryosu

Bu belirti genellikle aşağıdaki 3 nedenden biridir:

1. **Secure Boot açık** ve kullanılan `ipxe.efi/snponly.efi` imzasız.
2. UEFI firmware, ProxyDHCP'de sadece bir kısmını işler (PXE menu vs `dhcp-boot` farkı).
3. UEFI PXE ROM, TFTP blocksize negotiation (OACK) ile uyumsuzdur.

Kontrol adımları:

```bash
# 1) DHCP/TFTP loglarında UEFI istemciyi doğrula
make logs-dhcp

# 2) TFTP istekleri gerçekten geliyor mu?
sudo tcpdump -i any -n port 69

# 3) UEFI istemci için sunulan dosya adı ne?
# Beklenen: ipxe.efi
```

Ek notlar:
- Projede UEFI için varsayılan ilk aşama dosya `ipxe.efi` olarak ayarlanmıştır.
- `tftp-no-blocksize` açık tutulur; sorunlu firmware'lerde kritik fark yaratır.
- Secure Boot aktifse, test için geçici olarak kapatıp tekrar deneyin.

### "NFS mount başarısız" senaryosu

```bash
# NFS export'ları kontrol edin
showmount -e 10.30.1.20

# NFS logları
make logs-nfs

# Test mount
sudo mount -t nfs 10.30.1.20:/nfs/persistent /mnt/test
```

### Boot döngüsü (sonsuz iPXE reboot)

Bu durum dnsmasq'ın iPXE istemciyi tespit edemediği anlamına gelir.  
`config/dnsmasq/dnsmasq.conf` dosyasında şunları doğrulayın:

```
dhcp-match=set:ipxe,175
dhcp-boot=tag:ipxe,http://10.30.1.20/boot.ipxe
```

---

## QEMU ile Test

Fiziksel makine kullanmadan test etmek için:

```bash
# BIOS boot testi
qemu-system-x86_64 \
  -m 2048 \
  -netdev user,id=net0,net=10.30.1.0/24,dhcpstart=10.30.1.50 \
  -device e1000,netdev=net0,bootindex=1 \
  -boot n

# UEFI boot testi (OVMF gerekli)
sudo apt install ovmf
qemu-system-x86_64 \
  -m 2048 \
  -bios /usr/share/OVMF/OVMF_CODE.fd \
  -netdev user,id=net0,net=10.30.1.0/24,dhcpstart=10.30.1.50 \
  -device e1000,netdev=net0,bootindex=1 \
  -boot n
```

> ⚠️ **QEMU user networking** ile DHCP proxy modu çalışmaz (broadcast yönlendirmez).  
> Gerçek test için sunucu ile aynı ağdaki fiziksel veya bridge ağlı VM kullanın.
