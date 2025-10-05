.PHONY: help install uninstall start stop restart status logs health check-deps
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "KB Sentinel - Available commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install the systemd service
	@./contrib/install-service.sh

uninstall: ## Uninstall the systemd service
	@./contrib/uninstall-service.sh

start: ## Start the service
	@systemctl --user start kb-sentinel.service
	@echo "✅ Service started"

stop: ## Stop the service
	@systemctl --user stop kb-sentinel.service
	@echo "🛑 Service stopped"

restart: ## Restart the service
	@systemctl --user restart kb-sentinel.service
	@echo "🔄 Service restarted"

status: ## Show service status
	@systemctl --user status kb-sentinel.service --no-pager

logs: ## Show service logs (follow mode)
	@echo "📋 Following logs (Ctrl+C to exit)..."
	@journalctl --user -u kb-sentinel.service -f

health: ## Run health check
	@./contrib/health-check.sh

check-deps: ## Check if dependencies are installed
	@echo "🔍 Checking dependencies..."
	@.venv/bin/python -c "import evdev, paho.mqtt.client; print('✅ All dependencies installed')" || echo "❌ Missing dependencies - run 'uv sync'"

setup: ## Initial setup (sync dependencies and copy env file)
	@echo "🚀 Setting up KB Sentinel..."
	@uv sync
	@if [ ! -f .env ]; then cp .env.example .env && echo "📝 Created .env file - please edit with your MQTT credentials"; fi
	@echo "✅ Setup complete"