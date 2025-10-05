#!/bin/bash

# KB Sentinel Service Uninstallation Script
# This script removes the KB Sentinel systemd service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

CURRENT_USER=$(whoami)
SERVICE_FILE="$HOME/.config/systemd/user/kb-sentinel.service"

print_info "Uninstalling KB Sentinel service for user: $CURRENT_USER"

# Check if service file exists
if [[ ! -f "$SERVICE_FILE" ]]; then
    print_warning "Service file not found: $SERVICE_FILE"
    print_info "Service may not be installed or already removed"
    exit 0
fi

# Stop the service if running
print_info "Stopping KB Sentinel service"
if systemctl --user is-active --quiet kb-sentinel.service; then
    systemctl --user stop kb-sentinel.service
    print_success "Service stopped"
else
    print_info "Service was not running"
fi

# Disable the service
print_info "Disabling KB Sentinel service"
if systemctl --user is-enabled --quiet kb-sentinel.service; then
    systemctl --user disable kb-sentinel.service
    print_success "Service disabled"
else
    print_info "Service was not enabled"
fi

# Remove the service file
print_info "Removing service file"
rm "$SERVICE_FILE"
print_success "Service file removed"

# Reload systemd user daemon
print_info "Reloading systemd user daemon"
systemctl --user daemon-reload

print_success "KB Sentinel service uninstalled successfully!"

# Check if user has lingering enabled
if loginctl show-user "$CURRENT_USER" | grep -q "Linger=yes"; then
    echo
    print_info "User lingering is still enabled. To disable it run:"
    echo "    sudo loginctl disable-linger $CURRENT_USER"
fi