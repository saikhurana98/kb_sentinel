#!/bin/bash

# KB Sentinel Service Installation Script
# This script installs the KB Sentinel systemd service

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

# Get the current user
CURRENT_USER=$(whoami)
PROJECT_DIR=$(pwd)

print_info "Installing KB Sentinel service for user: $CURRENT_USER"
print_info "Project directory: $PROJECT_DIR"

# Check if we're in the right directory
if [[ ! -f "kb_sentinel.py" ]]; then
    print_error "kb_sentinel.py not found. Please run this script from the project directory."
    exit 1
fi

# Check if service file exists
if [[ ! -f "contrib/kb-sentinel.service" ]]; then
    print_error "Service file contrib/kb-sentinel.service not found."
    exit 1
fi

# Create systemd user directory if it doesn't exist
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

# Copy and customize the service file
SERVICE_FILE="$SYSTEMD_USER_DIR/kb-sentinel.service"
print_info "Creating service file: $SERVICE_FILE"

# Replace placeholders in the service file
sed "s|%h/Documents/Github/kb_sentinel|$PROJECT_DIR|g" contrib/kb-sentinel.service > "$SERVICE_FILE"

print_success "Service file created"

# Check if user is in input group
if ! groups "$CURRENT_USER" | grep -q "\binput\b"; then
    print_warning "User $CURRENT_USER is not in the 'input' group."
    print_warning "You may need to add yourself to the input group for keyboard access:"
    echo "    sudo usermod -a -G input $CURRENT_USER"
    echo "    # Then log out and back in"
fi

# Reload systemd user daemon
print_info "Reloading systemd user daemon"
systemctl --user daemon-reload

# Enable the service
print_info "Enabling KB Sentinel service"
systemctl --user enable kb-sentinel.service

# Ask if user wants to start the service now
read -p "Do you want to start the service now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Starting KB Sentinel service"
    systemctl --user start kb-sentinel.service
    print_success "Service started"
    
    # Show status
    echo
    print_info "Service status:"
    systemctl --user status kb-sentinel.service --no-pager
else
    print_info "Service enabled but not started. You can start it later with:"
    echo "    systemctl --user start kb-sentinel.service"
fi

echo
print_success "Installation complete!"
echo
print_info "Useful commands:"
echo "  Start service:    systemctl --user start kb-sentinel.service"
echo "  Stop service:     systemctl --user stop kb-sentinel.service"
echo "  Restart service:  systemctl --user restart kb-sentinel.service"
echo "  Check status:     systemctl --user status kb-sentinel.service"
echo "  View logs:        journalctl --user -u kb-sentinel.service -f"
echo "  Disable service:  systemctl --user disable kb-sentinel.service"
echo
print_info "To enable lingering (start service on boot without login):"
echo "    sudo loginctl enable-linger $CURRENT_USER"