.PHONY: setup start stop restart status logs clean help \
        logs-dhcp logs-http logs-nfs \
        extract-install extract-live setup-persistent extract-winpe

# ─── Yardım ───────────────────────────────────────────────────
help:
	@echo ""
	@echo "  PXE Boot Sunucusu — Make Komutları"
	@echo "  ─────────────────────────────────────────────────"
	@echo "  make setup              İlk kurulum (iPXE + wimboot indir)"
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

# ─── Kurulum ──────────────────────────────────────────────────
setup:
	@bash scripts/setup.sh

# ─── Konteyner Yönetimi ───────────────────────────────────────
start:
	@docker compose up -d
	@echo ""
	@echo "  PXE sunucusu başlatıldı!"
	@echo "  TFTP : tftp://10.30.1.20"
	@echo "  HTTP : http://10.30.1.20"
	@echo "  NFS  : nfs://10.30.1.20:2049"
	@echo ""

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
