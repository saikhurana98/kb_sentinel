#!/bin/bash

# KB Sentinel Deployment Script
# This script handles backup, deployment, error checking, and rollback

set -e

# Configuration
DEPLOY_PATH="/home/kb-sentinel/kb_sentinel"
BACKUP_PATH="/home/kb-sentinel/backups"
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
    
    if [ -n "$BACKUP_TIMESTAMP" ] && [ -d "$BACKUP_PATH/kb_sentinel_$BACKUP_TIMESTAMP" ]; then
        log_warning "Attempting to rollback to previous version..."
        rollback_deployment
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Create backup of current deployment
create_backup() {
    log_info "Creating backup of current deployment..."
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_PATH"
    
    # Generate timestamp for backup
    BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="$BACKUP_PATH/kb_sentinel_$BACKUP_TIMESTAMP"
    
    if [ -d "$DEPLOY_PATH" ]; then
        # Stop service before backup
        log_info "Stopping service for backup..."
        systemctl --user stop "$SERVICE_NAME.service" || log_warning "Service was not running"
        
        # Create backup
        cp -r "$DEPLOY_PATH" "$BACKUP_DIR"
        log_success "Backup created at $BACKUP_DIR"
        
        # Store current commit info
        if [ -d "$DEPLOY_PATH/.git" ]; then
            cd "$DEPLOY_PATH"
            git rev-parse HEAD > "$BACKUP_DIR/.previous_commit" 2>/dev/null || echo "unknown" > "$BACKUP_DIR/.previous_commit"
        fi
    else
        log_info "No existing deployment found, skipping backup"
        mkdir -p "$DEPLOY_PATH"
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
        
        # Fetch latest changes
        git fetch origin
        
        # Reset to the specific commit
        git reset --hard "$COMMIT_SHA"
        
        # Clean any untracked files
        git clean -fd
    else
        # Fresh clone
        log_info "Cloning repository..."
        rm -rf "$DEPLOY_PATH"
        git clone "$REPO_URL" "$DEPLOY_PATH"
        cd "$DEPLOY_PATH"
        git checkout "$COMMIT_SHA"
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

# Rollback to previous version
rollback_deployment() {
    if [ -z "$BACKUP_TIMESTAMP" ]; then
        log_error "No backup timestamp available for rollback"
        return 1
    fi
    
    local backup_dir="$BACKUP_PATH/kb_sentinel_$BACKUP_TIMESTAMP"
    
    if [ ! -d "$backup_dir" ]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    log_warning "Rolling back to previous version..."
    
    # Stop current service
    systemctl --user stop "$SERVICE_NAME.service" || log_warning "Service was not running"
    
    # Remove current deployment
    rm -rf "$DEPLOY_PATH"
    
    # Restore from backup
    cp -r "$backup_dir" "$DEPLOY_PATH"
    
    # Start service
    cd "$DEPLOY_PATH"
    systemctl --user start "$SERVICE_NAME.service"
    
    if systemctl --user is-active --quiet "$SERVICE_NAME.service"; then
        log_success "Rollback completed successfully"
    else
        log_error "Rollback failed - service did not start"
        return 1
    fi
}

# Clean old backups (keep last 5)
cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    if [ -d "$BACKUP_PATH" ]; then
        # Keep last 5 backups
        ls -t "$BACKUP_PATH"/kb_sentinel_* 2>/dev/null | tail -n +6 | while read -r old_backup; do
            if [ -d "$old_backup" ]; then
                log_info "Removing old backup: $(basename "$old_backup")"
                rm -rf "$old_backup"
            fi
        done
    fi
    
    log_success "Backup cleanup completed"
}

# Main deployment process
main() {
    log_info "Starting deployment process..."
    log_info "Commit SHA: $COMMIT_SHA"
    log_info "Branch: $BRANCH_NAME"
    log_info "Timestamp: $(date)"
    
    # Clear previous log
    > "$LOG_FILE"
    
    create_backup
    deploy_new_version
    setup_environment
    test_deployment
    start_and_verify_service
    cleanup_old_backups
    
    log_success "Deployment completed successfully!"
    
    # Output summary
    echo "
========================================
        DEPLOYMENT SUMMARY
========================================
Status: SUCCESS
Commit: $COMMIT_SHA
Branch: $BRANCH_NAME
Backup: $BACKUP_TIMESTAMP
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