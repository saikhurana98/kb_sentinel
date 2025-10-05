#!/bin/bash

# Quick fix for the existing service
print_info() {
    echo -e "\033[0;34mℹ\033[0m $1"
}

print_success() {
    echo -e "\033[0;32m✅\033[0m $1"
}

PROJECT_DIR=$(pwd)
SERVICE_FILE="$HOME/.config/systemd/user/kb-sentinel.service"

print_info "Fixing existing service configuration..."

# Stop the service
systemctl --user stop kb-sentinel.service 2>/dev/null || true

# Update the service file
sed "s|%h/Documents/Github/kb_sentinel|$PROJECT_DIR|g" contrib/kb-sentinel.service > "$SERVICE_FILE"

# Reload and restart
systemctl --user daemon-reload
systemctl --user start kb-sentinel.service

print_success "Service updated and restarted"

# Show status
systemctl --user status kb-sentinel.service --no-pager