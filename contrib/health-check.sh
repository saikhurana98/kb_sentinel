#!/bin/bash

# KB Sentinel Health Check Script
# This script checks if the KB Sentinel service is running properly

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

print_header() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}    KB Sentinel Health Check${NC}"
    echo -e "${BLUE}===========================================${NC}"
    echo
}

# Main health check function
check_service_status() {
    print_info "Checking service status..."
    
    if systemctl --user is-active --quiet kb-sentinel.service; then
        print_success "Service is running"
        
        # Check how long it's been running
        uptime=$(systemctl --user show kb-sentinel.service --property=ActiveEnterTimestamp --value)
        if [[ -n "$uptime" && "$uptime" != "n/a" ]]; then
            echo "  Started: $uptime"
        fi
        
        # Show recent status
        echo
        systemctl --user status kb-sentinel.service --no-pager --lines=5
        
    else
        print_error "Service is not running"
        
        # Check if it's enabled
        if systemctl --user is-enabled --quiet kb-sentinel.service; then
            print_info "Service is enabled but not running"
        else
            print_warning "Service is not enabled"
        fi
        
        return 1
    fi
}

check_recent_logs() {
    print_info "Checking recent logs for errors..."
    
    # Get logs from the last 10 minutes
    recent_logs=$(journalctl --user -u kb-sentinel.service --since="10 minutes ago" --no-pager 2>/dev/null || echo "")
    
    if [[ -n "$recent_logs" ]]; then
        # Check for common error patterns
        if echo "$recent_logs" | grep -qi "error\|failed\|exception\|traceback"; then
            print_warning "Found potential errors in recent logs"
            echo "Recent error-related entries:"
            echo "$recent_logs" | grep -i "error\|failed\|exception" | tail -3
        else
            print_success "No obvious errors in recent logs"
        fi
    else
        print_info "No recent log entries found"
    fi
}

check_dependencies() {
    print_info "Checking dependencies..."
    
    # Check if Python virtual environment exists
    venv_path="$PWD/.venv"
    if [[ -d "$venv_path" ]]; then
        print_success "Virtual environment found at $venv_path"
        
        # Check if required packages are installed
        if "$venv_path/bin/python" -c "import evdev, paho.mqtt.client" 2>/dev/null; then
            print_success "Required Python packages are installed"
        else
            print_error "Required Python packages are missing"
            echo "  Try: uv sync"
        fi
    else
        print_error "Virtual environment not found at $venv_path"
        echo "  Try: uv sync"
    fi
    
    # Check if .env file exists
    if [[ -f ".env" ]]; then
        print_success "Environment file (.env) found"
    else
        print_warning "Environment file (.env) not found"
        echo "  Copy .env.example to .env and configure your MQTT credentials"
    fi
}

check_permissions() {
    print_info "Checking permissions..."
    
    # Check if user is in input group
    if groups | grep -q "\binput\b"; then
        print_success "User is in 'input' group"
    else
        print_warning "User is not in 'input' group"
        echo "  Add yourself to the input group: sudo usermod -a -G input \$USER"
        echo "  Then log out and back in"
    fi
    
    # Check if input devices are accessible
    if [[ -r "/dev/input" ]]; then
        device_count=$(ls /dev/input/event* 2>/dev/null | wc -l || echo "0")
        print_info "Found $device_count input devices"
    else
        print_error "Cannot access /dev/input directory"
    fi
}

show_useful_commands() {
    echo
    print_info "Useful commands:"
    echo "  Start service:    systemctl --user start kb-sentinel.service"
    echo "  Stop service:     systemctl --user stop kb-sentinel.service"
    echo "  Restart service:  systemctl --user restart kb-sentinel.service"
    echo "  View logs:        journalctl --user -u kb-sentinel.service -f"
    echo "  Service status:   systemctl --user status kb-sentinel.service"
    echo "  Run health check: ./contrib/health-check.sh"
}

# Main execution
main() {
    print_header
    
    local exit_code=0
    
    check_service_status || exit_code=1
    echo
    
    check_recent_logs
    echo
    
    check_dependencies
    echo
    
    check_permissions
    
    show_useful_commands
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        print_success "Health check completed - KB Sentinel appears to be healthy!"
    else
        print_warning "Health check completed - Some issues found"
    fi
    
    return $exit_code
}

# Run main function
main "$@"