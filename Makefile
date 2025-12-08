.PHONY: help setup validate start stop restart logs status pull update backup clean

# Default target
help:
	@echo "Alarm System - Makefile Commands"
	@echo "================================="
	@echo ""
	@echo "Setup & Configuration:"
	@echo "  make setup      - Initial setup (copy .env.example to .env)"
	@echo "  make validate   - Validate configuration"
	@echo ""
	@echo "Service Management:"
	@echo "  make start      - Start all services"
	@echo "  make start-ssl  - Start with Caddy SSL/TLS reverse proxy"
	@echo "  make stop       - Stop all services"
	@echo "  make restart    - Restart all services"
	@echo "  make status     - Show service status"
	@echo ""
	@echo "Maintenance:"
	@echo "  make logs       - Show logs (all services)"
	@echo "  make logs-mail  - Show alarm-mail logs"
	@echo "  make logs-monitor - Show alarm-monitor logs"
	@echo "  make logs-messenger - Show alarm-messenger logs"
	@echo "  make pull       - Pull latest images"
	@echo "  make update     - Pull and restart services"
	@echo "  make backup     - Backup persistent data"
	@echo "  make clean      - Remove stopped containers and unused images"
	@echo ""
	@echo "For more information, see:"
	@echo "  - README.md for full documentation"
	@echo "  - QUICKSTART.md for quick setup guide"
	@echo "  - ARCHITECTURE.md for technical details"

setup:
	@if [ ! -f .env ]; then \
		echo "Creating .env from .env.example..."; \
		cp .env.example .env; \
		echo ""; \
		echo "✓ .env file created"; \
		echo ""; \
		echo "Please edit .env and configure:"; \
		echo "  - IMAP credentials"; \
		echo "  - API keys (generate with: openssl rand -hex 32)"; \
		echo "  - Server URL"; \
		echo ""; \
		echo "Then run: make validate"; \
	else \
		echo ".env already exists. Skipping."; \
	fi

validate:
	@./validate-config.sh

start:
	@echo "Starting Alarm System..."
	docker-compose up -d
	@echo ""
	@echo "Services started. Check status with: make status"
	@echo "View logs with: make logs"

start-ssl:
	@echo "Starting Alarm System with SSL/TLS (Caddy)..."
	docker-compose --profile with-caddy up -d
	@echo ""
	@echo "Services started with Caddy reverse proxy."
	@echo "Check status with: make status"

stop:
	@echo "Stopping Alarm System..."
	docker-compose --profile with-caddy down
	@echo "Services stopped."

restart:
	@echo "Restarting Alarm System..."
	docker-compose restart
	@echo "Services restarted."

status:
	@docker-compose ps

logs:
	docker-compose logs -f

logs-mail:
	docker-compose logs -f alarm-mail

logs-monitor:
	docker-compose logs -f alarm-monitor

logs-messenger:
	docker-compose logs -f alarm-messenger

pull:
	@echo "Pulling latest images..."
	docker-compose pull

update: pull
	@echo "Updating services..."
	docker-compose up -d
	@echo ""
	@echo "Services updated and restarted."
	@echo "Cleaning up old images..."
	@docker image prune -f
	@echo "Update complete."

backup:
	@echo "Creating backup..."
	@mkdir -p backup
	@echo "Backing up alarm-monitor data..."
	@docker run --rm \
		-v alarm-system_alarm-monitor-data:/data \
		-v $(PWD)/backup:/backup \
		alpine tar czf /backup/monitor-$$(date +%Y%m%d-%H%M%S).tar.gz /data
	@echo "Backing up alarm-messenger data..."
	@docker run --rm \
		-v alarm-system_alarm-messenger-data:/data \
		-v $(PWD)/backup:/backup \
		alpine tar czf /backup/messenger-$$(date +%Y%m%d-%H%M%S).tar.gz /data
	@echo "Backing up .env file..."
	@cp .env backup/.env-$$(date +%Y%m%d-%H%M%S).backup
	@echo ""
	@echo "Backup complete. Files saved in ./backup/"
	@ls -lh backup/

clean:
	@echo "Cleaning up Docker resources..."
	docker-compose down --remove-orphans
	@docker image prune -f
	@echo "Cleanup complete."

# Generate API keys
generate-keys:
	@echo "Generating API keys..."
	@echo ""
	@echo "ALARM_MONITOR_API_KEY=$$(openssl rand -hex 32)"
	@echo "ALARM_MESSENGER_API_SECRET_KEY=$$(openssl rand -hex 32)"
	@echo "ALARM_MESSENGER_JWT_SECRET=$$(openssl rand -hex 32)"
	@echo ""
	@echo "Copy these values to your .env file"
