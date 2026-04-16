.PHONY: setup prepare doctor start stop restart status logs clean help \
		logs-dhcp logs-http logs-nfs apply-env \
		extract-install extract-live setup-persistent extract-winpe

REQUIRED_TFTP_BINARIES := tftp/undionly.kpxe tftp/ipxe.efi tftp/snponly.efi
REQUIRED_INSTALL_ASSETS := http/boot/debian-install/vmlinuz http/boot/debian-install/initrd.gz
REQUIRED_LIVE_ASSETS := http/boot/debian-live/vmlinuz http/boot/debian-live/initrd.img http/boot/debian-live/live/filesystem.squashfs
REQUIRED_PERSISTENT_ASSETS := http/boot/debian-persistent/vmlinuz http/boot/debian-persistent/initrd.img

# ─── Yardım ───────────────────────────────────────────────────
help:
	@echo ""
	@echo "  PXE Boot Sunucusu — Make Komutları"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make setup              İlk kurulum + temel içerik hazırlığı"
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
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make extract-install    Debian kurulum dosyaları hazırla"
	@echo "  make extract-live ISO=  Debian Live ISO işle"
	@echo "  make setup-persistent   Persistent NFS sistemi kur (root)"
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
	@echo "[i] dnsmasq config test"
	@dnsmasq --test --conf-file=config/dnsmasq/dnsmasq.conf || true

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
