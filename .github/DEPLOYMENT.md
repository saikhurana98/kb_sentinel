# CI/CD Pipeline Documentation

This document describes the comprehensive CI/CD pipeline for KB Sentinel deployment, backup management, and rollback procedures.

## Overview

The CI/CD pipeline provides:
- ✅ Automated testing and deployment
- 💾 Automatic backup creation before deployments
- 🔄 Automatic rollback on deployment failures
- 📊 Health monitoring and reporting
- 🛠️ Manual rollback capabilities
- 📋 Backup management and reporting

## Workflows

### 1. Main Deployment Pipeline (`deploy.yml`)

**Triggers:**
- Push to `main` branch
- Pull requests to `main` branch
- Manual workflow dispatch

**Jobs:**

#### Test Job
- Sets up Python environment with uv
- Validates syntax of Python files
- Checks imports and basic functionality
- Validates systemd service files and shell scripts

#### Deploy Job (main branch only)
- Creates SSH connection to target host
- Executes deployment script on remote server
- Captures deployment logs
- Reports failures via GitHub issues
- Uploads deployment artifacts

#### Health Check Job
- Runs post-deployment validation
- Executes health check script on target
- Verifies service is running correctly

### 2. Manual Rollback Pipeline (`rollback.yml`)

**Triggers:**
- Manual workflow dispatch with parameters

**Parameters:**
- `backup_timestamp`: The backup to rollback to (format: YYYYMMDD_HHMMSS)
- `confirm_rollback`: Must type "CONFIRM" to proceed

**Process:**
- Validates inputs and confirmation
- Creates backup of current state before rollback
- Restores specified backup
- Starts service and validates functionality
- Reports status via GitHub issues

### 3. Backup Management (`list-backups.yml`)

**Triggers:**
- Manual workflow dispatch
- Weekly schedule (Monday 9 AM UTC)

**Functions:**
- Lists all available backups with details
- Shows current deployment status
- Provides backup statistics
- Creates weekly backup report issues

## Deployment Script (`deploy.sh`)

The deployment script handles the complete deployment process on the target host:

### Key Features

1. **Backup Creation**
   - Creates timestamped backup of current deployment
   - Preserves git commit information
   - Stops service safely before backup

2. **Deployment Process**
   - Clones/updates repository to specific commit
   - Installs dependencies using uv or pip
   - Makes scripts executable

3. **Testing & Validation**
   - Python syntax checking
   - Import validation
   - Configuration loading tests

4. **Service Management**
   - Installs/updates systemd service
   - Starts service with health checks
   - Validates service is running correctly

5. **Error Handling**
   - Automatic rollback on any failure
   - Comprehensive logging
   - Clean error reporting

6. **Backup Cleanup**
   - Keeps last 5 backups automatically
   - Removes old backups to save space

## Required Secrets

Configure these secrets in your GitHub repository:

- `DEPLOY_SSH_KEY`: Private SSH key for deployment host access
- `DEPLOY_HOST`: Target host IP address or hostname
- `DEPLOY_USER`: Username for SSH connection

## Host Requirements

### Target Host Setup

1. **User Account**
   ```bash
   # Create dedicated user
   sudo useradd -m -s /bin/bash kb-sentinel
   sudo usermod -a -G input kb-sentinel
   ```

2. **SSH Access**
   ```bash
   # Add GitHub Actions public key to authorized_keys
   sudo -u kb-sentinel mkdir -p /home/kb-sentinel/.ssh
   sudo -u kb-sentinel touch /home/kb-sentinel/.ssh/authorized_keys
   # Add your deployment public key to authorized_keys
   ```

3. **Directory Structure**
   ```bash
   sudo -u kb-sentinel mkdir -p /home/kb-sentinel/kb_sentinel
   sudo -u kb-sentinel mkdir -p /home/kb-sentinel/backups
   ```

4. **Dependencies**
   ```bash
   # Install required tools
   sudo apt update
   sudo apt install git python3 python3-venv python3-pip uv
   ```

5. **Systemd User Service**
   ```bash
   # Enable lingering for user services
   sudo loginctl enable-linger kb-sentinel
   ```

## Usage Examples

### 1. Normal Deployment
```bash
# Push to main branch triggers automatic deployment
git push origin main
```

### 2. Manual Rollback
1. Go to Actions → Manual Rollback
2. Enter backup timestamp (e.g., `20241006_143022`)
3. Type `CONFIRM` in confirmation field
4. Run workflow

### 3. Check Backup Status
1. Go to Actions → List Backups
2. Run workflow manually
3. Check artifacts for backup report

### 4. View Deployment Logs
- Check workflow run artifacts
- SSH to host and check `/tmp/kb-sentinel-deploy.log`
- Use `journalctl --user -u kb-sentinel.service -f`

## Monitoring and Alerts

### Automatic Notifications

- **Deployment Failures**: Creates GitHub issue with error details
- **Rollback Status**: Creates GitHub issue with rollback results
- **Weekly Reports**: Automated backup status reports

### Health Checks

- Post-deployment service validation
- Health check script execution
- Service status monitoring

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   - Verify `DEPLOY_SSH_KEY` secret is correct
   - Check `DEPLOY_HOST` and `DEPLOY_USER` secrets
   - Ensure SSH key is added to target host

2. **Service Won't Start**
   - Check service logs: `journalctl --user -u kb-sentinel.service`
   - Verify user is in `input` group
   - Check file permissions and paths

3. **Backup Not Found**
   - Use List Backups workflow to see available backups
   - Verify backup timestamp format (YYYYMMDD_HHMMSS)

4. **Permission Errors**
   - Ensure user has proper group membership
   - Check systemd user service configuration
   - Verify directory permissions

### Manual Recovery

If automated rollback fails:

```bash
# SSH to host
ssh kb-sentinel@your-host

# List available backups
ls -la /home/kb-sentinel/backups/

# Manual rollback
sudo systemctl --user stop kb-sentinel.service
cd /home/kb-sentinel
rm -rf kb_sentinel
cp -r backups/kb_sentinel_TIMESTAMP kb_sentinel
cd kb_sentinel
sudo systemctl --user start kb-sentinel.service
```

## Security Considerations

- SSH keys are managed via GitHub Secrets
- Deployment runs as non-root user
- Service runs with minimal privileges
- Backups are stored locally on target host
- No sensitive data in logs or artifacts

## Maintenance

### Regular Tasks

1. **Monitor backup disk usage**
   - Backups are automatically cleaned (keep last 5)
   - Monitor `/home/kb-sentinel/backups` disk usage

2. **Review deployment logs**
   - Check weekly backup reports
   - Monitor deployment success rates

3. **Update dependencies**
   - Python packages via uv sync
   - System packages on target host

4. **Security updates**
   - Rotate SSH keys periodically
   - Update target host system packages