.PHONY: setup start stop restart status logs clean help \
        logs-dhcp logs-http logs-nfs apply-env \
        extract-install extract-live setup-persistent extract-winpe

REQUIRED_TFTP_BINARIES := tftp/undionly.kpxe tftp/ipxe.efi tftp/snponly.efi

# ─── Yardım ───────────────────────────────────────────────────
help:
	@echo ""
	@echo "  PXE Boot Sunucusu — Make Komutları"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make setup              İlk kurulum (iPXE + wimboot indir)"
	@echo "  make apply-env          IP adresini senkronize et (.env dosyasına göre)"
	@echo "  make start              Tüm konteynerleri başlat"
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

apply-env:
	@bash scripts/apply-env.sh

# ─── Konteyner Yönetimi ───────────────────────────────────────
start:
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
