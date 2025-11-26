#!/bin/bash

# KB Sentinel Deployment Script
# This script handles  deployment & error checking

set -e

# Configuration
DEPLOY_PATH="/home/kb-sentinel/kb_sentinel"
SERVICE_NAME="kb-sentinel"
LOG_FILE="/tmp/kb-sentinel-deploy.log"
REPO_URL="https://github.com/saikhurana98/kb_sentinel.git"

# Arguments
COMMIT_SHA="$1"
BRANCH_NAME="$2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    exit $exit_code
}

trap cleanup_on_error ERR


# check preexisting deployment
check_preexisting_deployment() {
    log_info "Checking for pre-existing deployment at $DEPLOY_PATH..."
    # System Dependencies
    log_info "Checking and installing system dependencies..."
    sudo apt-get update
    sudo apt-get install -y python3-venv python3-pip git upower

    # User Group Permissions
    log_info "Ensuring user is in 'input' group for device access..."
    if ! groups "$USER" | grep &>/dev/null "\binput\b"; then
        sudo usermod -aG input "$USER"
        log_info "Added $USER to 'input' group. You may need to log out and back in for changes to take effect."
    else
        log_info "$USER is already in 'input' group."
    fi
}


# Deploy new version
deploy_new_version() {
    log_info "Deploying new version (commit: $COMMIT_SHA)..."
    
    cd "$(dirname "$DEPLOY_PATH")"
    
    if [ -d "$DEPLOY_PATH/.git" ]; then
        # Update existing repository
        cd "$DEPLOY_PATH"
        log_info "Updating existing repository..."
        
        # Preserve .env contents even if it's (mistakenly) tracked
        if [ -f .env ]; then
            cp .env /tmp/kb-sentinel.env.backup
            if git ls-files --error-unmatch .env >/dev/null 2>&1; then
                log_warning ".env appears to be tracked by git; consider adding it to .gitignore for safer preservation."
            fi
            log_info "Backed up existing .env file"
        fi
        
        # Fetch latest changes
        git fetch origin
        
        # Reset to the specific commit
        git reset --hard "$COMMIT_SHA"
        
        # Clean any untracked files
        git clean -fd --exclude=.env
        
        # Restore .env after reset/clean
        if [ -f /tmp/kb-sentinel.env.backup ]; then
            mv /tmp/kb-sentinel.env.backup .env
            log_info "Restored preserved .env file"
        fi
    else
        # Fresh clone
        log_info "Cloning repository..."
        # Backup .env if directory exists from previous deployment
        if [ -d "$DEPLOY_PATH" ] && [ -f "$DEPLOY_PATH/.env" ]; then
            cp "$DEPLOY_PATH/.env" /tmp/kb-sentinel.env.backup
            log_info "Preserved existing .env before fresh clone"
        fi
        rm -rf "$DEPLOY_PATH"
        git clone "$REPO_URL" "$DEPLOY_PATH"
        cd "$DEPLOY_PATH"
        git checkout "$COMMIT_SHA"
        # Restore .env if it was backed up
        if [ -f /tmp/kb-sentinel.env.backup ]; then
            mv /tmp/kb-sentinel.env.backup "$DEPLOY_PATH/.env"
            log_info "Restored preserved .env after fresh clone"
        fi
    fi
    
    log_success "Repository updated to commit $COMMIT_SHA"
}

# Install dependencies and setup
setup_environment() {
    log_info "Setting up environment..."
    
    cd "$DEPLOY_PATH"
    
    # Check if uv is available
    if command -v uv >/dev/null 2>&1; then
        log_info "Installing dependencies with uv..."
        uv sync
    else
        log_warning "uv not found, using pip..."
        python3 -m venv .venv
        source .venv/bin/activate
        pip install evdev paho-mqtt
    fi
    
    # Ensure scripts are executable
    chmod +x contrib/*.sh 2>/dev/null || log_warning "Could not make scripts executable"
    
    log_success "Environment setup complete"
}

# Test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    cd "$DEPLOY_PATH"
    
    # Test Python syntax
    if ! .venv/bin/python -m py_compile kb_sentinel.py; then
        log_error "Python syntax error in kb_sentinel.py"
        return 1
    fi
    
    # Test imports
    if ! .venv/bin/python -c "import kb_sentinel" 2>>"$LOG_FILE"; then
        log_error "Failed to import kb_sentinel module"
        return 1
    fi
    
    # Test configuration loading
    if ! .venv/bin/python -c "
import sys
sys.path.append('.')
from kb_sentinel import load_env_file
load_env_file()
print('Configuration loaded successfully')
" 2>>"$LOG_FILE"; then
        log_error "Failed to load configuration"
        return 1
    fi
    
    log_success "Deployment tests passed"
}

# Start the service and verify it's working
start_and_verify_service() {
    log_info "Starting service..."
    
    cd "$DEPLOY_PATH"
    
    # Install/update systemd service
    if [ -f "contrib/install-service.sh" ]; then
        log_info "Installing/updating systemd service..."
        bash contrib/install-service.sh --non-interactive 2>>"$LOG_FILE" || log_warning "Service installation had warnings"
    fi
    
    # Start the service
    systemctl --user start "$SERVICE_NAME.service"
    
    # Wait a moment for startup
    sleep 5
    
    # Check if service is running
    if systemctl --user is-active --quiet "$SERVICE_NAME.service"; then
        log_success "Service started successfully"
        
        # Run health check if available
        if [ -f "contrib/health-check.sh" ]; then
            log_info "Running health check..."
            if bash contrib/health-check.sh 2>>"$LOG_FILE"; then
                log_success "Health check passed"
            else
                log_error "Health check failed"
                return 1
            fi
        fi
    else
        log_error "Service failed to start"
        # Get service status for debugging
        systemctl --user status "$SERVICE_NAME.service" --no-pager 2>>"$LOG_FILE" || true
        return 1
    fi
}




# Main deployment process
main() {
    log_info "Starting deployment process..."
    log_info "Commit SHA: $COMMIT_SHA"
    log_info "Branch: $BRANCH_NAME"
    log_info "Timestamp: $(date)"
    
    # Clear previous log
    > "$LOG_FILE"
    
    check_preexisting_deployment
    deploy_new_version
    setup_environment
    test_deployment
    start_and_verify_service
    
    log_success "Deployment completed successfully!"
    
    # Output summary
    echo "
========================================
        DEPLOYMENT SUMMARY
========================================
Status: SUCCESS
Commit: $COMMIT_SHA
Branch: $BRANCH_NAME
Log: $LOG_FILE
Time: $(date)
========================================
"
}

# Handle non-interactive mode for automation
if [ "$3" = "--non-interactive" ]; then
    export DEBIAN_FRONTEND=noninteractive
fi

# Run main function
main "$@"