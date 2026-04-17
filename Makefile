.PHONY: setup prepare doctor start stop restart status logs clean help \
		logs-dhcp logs-http logs-nfs apply-env \
		extract-install extract-live setup-persistent extract-winpe \
		persistent-add-client persistent-del-client persistent-list-clients persistent-fix-dev logs-enroll

REQUIRED_TFTP_BINARIES := tftp/undionly.kpxe tftp/ipxe.efi tftp/snponly.efi
REQUIRED_INSTALL_ASSETS := http/boot/debian-install/vmlinuz http/boot/debian-install/initrd.gz
REQUIRED_LIVE_ASSETS := http/boot/debian-live/vmlinuz http/boot/debian-live/initrd.img http/boot/debian-live/live/filesystem.squashfs
REQUIRED_PERSISTENT_ASSETS := http/boot/debian-persistent/vmlinuz http/boot/debian-persistent/initrd.img

# ─── Yardım ───────────────────────────────────────────────────
help:
	@echo ""
	@echo "  PXE Boot Sunucusu — Make Komutları"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make setup              İlk kurulum + opsiyonel Live/Persistent XFCE sihirbazi"
	@echo "  make prepare            Debian install içerik kontrol/hazırlık"
	@echo "  make doctor             Eksik dosya ve içerik ön-kontrol"
	@echo "  make apply-env          IP adresini senkronize et (.env dosyasına göre)"
	@echo "  make start              Sadece konteynerleri başlat"
	@echo "  make stop               Tüm konteynerleri durdur"
	@echo "  make restart            Yeniden başlat"
	@echo "  make status             Konteyner durumu"
	@echo "  make logs               Tüm loglar (canlı)"
	@echo "  make logs-dhcp          dnsmasq (DHCP/TFTP) logları"
	@echo "  make logs-http          Nginx logları"
	@echo "  make logs-nfs           NFS sunucu logları"
	@echo "  make logs-enroll        Persistent auto-enroll logları"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make extract-install    Debian kurulum dosyaları hazırla"
	@echo "  make extract-live ISO=  Debian Live ISO işle"
	@echo "  make setup-persistent   Persistent NFS sistemi kur (root)"
	@echo "  make persistent-list-clients         Kayitli MAC profillerini listele"
	@echo "  make persistent-add-client MAC=..   MAC'e özel persistent profil oluştur"
	@echo "  make persistent-del-client MAC=..   MAC'e özel persistent profil sil"
	@echo "  make persistent-fix-dev  /dev/full gibi hatalı regular dosyaları temizle"
	@echo "  make extract-winpe ISO= WinPE ISO işle"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make clean              Konteynerleri sil (veri korunur)"
	@echo ""

# ─── Kurulum & Yapılandırma ──────────────────────────────────
setup:
	@bash scripts/setup.sh
	@$(MAKE) prepare

prepare:
	@missing=0; \
	for f in $(REQUIRED_TFTP_BINARIES); do \
		if [ ! -f "$$f" ]; then \
			echo "[!] Eksik TFTP binary: $$f"; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -eq 1 ]; then \
		echo "[!] iPXE binary dosyalari eksik. scripts/setup.sh calistiriliyor..."; \
		bash scripts/setup.sh; \
	fi
	@missing_install=0; \
	for f in $(REQUIRED_INSTALL_ASSETS); do \
		if [ ! -f "$$f" ]; then \
			echo "[!] Eksik Debian install dosyasi: $$f"; \
			missing_install=1; \
		fi; \
	done; \
	if [ "$$missing_install" -eq 1 ]; then \
		echo "[!] Debian netinstall dosyalari indiriliyor..."; \
		bash scripts/extract-debian-install.sh; \
	fi
	@for f in $(REQUIRED_LIVE_ASSETS); do \
		if [ ! -f "$$f" ]; then \
			echo "[!] Debian Live hazir degil. Calistir: make extract-live ISO=isos/debian-live-*.iso"; \
			break; \
		fi; \
	done
	@for f in $(REQUIRED_PERSISTENT_ASSETS); do \
		if [ ! -f "$$f" ]; then \
			echo "[!] Debian Persistent hazir degil. Calistir: sudo make setup-persistent"; \
			break; \
		fi; \
	done

doctor:
	@echo "[i] TFTP binary kontrolu"
	@for f in $(REQUIRED_TFTP_BINARIES); do \
		if [ -f "$$f" ]; then echo "[OK] $$f"; else echo "[MISSING] $$f"; fi; \
	done
	@echo "[i] Debian Install kontrolu"
	@for f in $(REQUIRED_INSTALL_ASSETS); do \
		if [ -f "$$f" ]; then echo "[OK] $$f"; else echo "[MISSING] $$f"; fi; \
	done
	@echo "[i] Opsiyonel içerikler"
	@for f in $(REQUIRED_LIVE_ASSETS) $(REQUIRED_PERSISTENT_ASSETS); do \
		if [ -f "$$f" ]; then echo "[OK] $$f"; else echo "[MISSING] $$f"; fi; \
	done
	@echo "[i] Host NFS kernel modulleri"
	@if command -v lsmod >/dev/null 2>&1; then \
		if lsmod | grep -q '^nfs\b'; then echo "[OK] nfs modulu yuklu"; else echo "[MISSING] nfs modulu"; fi; \
		if lsmod | grep -q '^nfsd\b'; then echo "[OK] nfsd modulu yuklu"; else echo "[MISSING] nfsd modulu"; fi; \
		if ! lsmod | grep -q '^nfs\b' || ! lsmod | grep -q '^nfsd\b'; then \
			echo "[HINT] sudo modprobe nfs && sudo modprobe nfsd"; \
		fi; \
	else \
		echo "[WARN] lsmod komutu bulunamadi, modul kontrolu atlandi"; \
	fi

apply-env:
	@bash scripts/apply-env.sh

# ─── Konteyner Yönetimi ───────────────────────────────────────
start:
	@docker compose up -d
	@PXE_IP=$$(grep '^PXE_SERVER_IP=' .env 2>/dev/null | cut -d= -f2); \
	if [ -z "$$PXE_IP" ]; then PXE_IP="10.30.1.20"; fi; \
	echo ""; \
	echo "  PXE sunucusu başlatıldı!"; \
	echo "  TFTP : tftp://$$PXE_IP"; \
	echo "  HTTP : http://$$PXE_IP"; \
	echo "  NFS  : nfs://$$PXE_IP:2049"; \
	echo ""

stop:
	@docker compose down

restart:
	@docker compose restart

status:
	@docker compose ps

# ─── Log İzleme ──────────────────────────────────────────────
logs:
	@docker compose logs -f

logs-dhcp:
	@docker compose logs -f pxe-dhcp

logs-http:
	@docker compose logs -f pxe-http

logs-nfs:
	@docker compose logs -f pxe-nfs

logs-enroll:
	@docker compose logs -f pxe-enroll

# ─── İçerik Hazırlama ────────────────────────────────────────
extract-install:
	@bash scripts/extract-debian-install.sh

extract-live:
	@if [ -z "$(ISO)" ]; then \
		echo "Kullanım: make extract-live ISO=isos/debian-live-*.iso"; \
		exit 1; \
	fi
	@bash scripts/extract-debian-live.sh "$(ISO)"

setup-persistent:
	@sudo bash scripts/setup-persistent.sh

persistent-list-clients:
	@bash scripts/manage-persistent-client.sh list

persistent-add-client:
	@if [ -z "$(MAC)" ]; then \
		echo "Kullanım: make persistent-add-client MAC=00:11:22:33:44:55"; \
		exit 1; \
	fi
	@sudo bash scripts/manage-persistent-client.sh add "$(MAC)"

persistent-del-client:
	@if [ -z "$(MAC)" ]; then \
		echo "Kullanım: make persistent-del-client MAC=00:11:22:33:44:55"; \
		exit 1; \
	fi
	@sudo bash scripts/manage-persistent-client.sh del "$(MAC)"

persistent-fix-dev:
	@sudo bash scripts/fix-persistent-devfiles.sh

extract-winpe:
	@if [ -z "$(ISO)" ]; then \
		echo "Kullanım: make extract-winpe ISO=isos/winpe.iso"; \
		exit 1; \
	fi
	@bash scripts/extract-winpe.sh "$(ISO)"

# ─── Temizlik ─────────────────────────────────────────────────
clean:
	@docker compose down --remove-orphans
	@echo "Konteynerler temizlendi. Veri dizinleri korundu."
