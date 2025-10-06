# Self-Hosted GitHub Runner Setup

This guide explains how to set up a self-hosted GitHub runner for local network deployment of KB Sentinel.

## Why Self-Hosted Runner?

Since your KB Sentinel deployment is on a local PC within your network, a self-hosted runner provides:

- **Direct Network Access**: No need for external SSH access to your local PC
- **Faster Deployment**: Local network speeds
- **Better Security**: No need to expose SSH to the internet
- **Lower Latency**: Direct connection to target host

## Architecture

```
[GitHub] → [Self-Hosted Runner Host] → [KB Sentinel Target PC]
             (same local network)      (192.168.x.x)
```

## Setup Steps

### 1. Choose Runner Host

The runner should be on a separate machine from your KB Sentinel target PC:
- **Option A**: Raspberry Pi or small dedicated device
- **Option B**: Another PC/server on your network
- **Option C**: Docker container on your router/NAS

**Requirements:**
- Linux-based system (Ubuntu/Debian recommended)
- Network access to your KB Sentinel target PC
- Internet access for GitHub communication
- 2GB+ RAM, 10GB+ disk space

### 2. Install GitHub Runner

On your chosen runner host:

```bash
# Create runner user
sudo useradd -m -s /bin/bash github-runner
sudo usermod -a -G docker github-runner  # If using Docker

# Switch to runner user
sudo su - github-runner

# Create runner directory
mkdir actions-runner && cd actions-runner

# Download latest runner (check GitHub for latest version)
curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz

# Extract
tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz

# Configure runner
./config.sh --url https://github.com/saikhurana98/kb_sentinel --token YOUR_REGISTRATION_TOKEN
```

**To get your registration token:**
1. Go to your repository on GitHub
2. Settings → Actions → Runners
3. Click "New self-hosted runner"
4. Copy the token from the configuration command

### 3. Configure SSH Access

The runner needs SSH access to your KB Sentinel target PC:

```bash
# Generate SSH key on runner
ssh-keygen -t ed25519 -f ~/.ssh/kb_sentinel_deploy -N ""

# Copy public key to target PC
ssh-copy-id -i ~/.ssh/kb_sentinel_deploy.pub kb-sentinel@YOUR_TARGET_PC_IP

# Test connection
ssh -i ~/.ssh/kb_sentinel_deploy kb-sentinel@YOUR_TARGET_PC_IP "echo 'Connection successful'"
```

### 4. Configure SSH Config

Create `~/.ssh/config` on the runner:

```
Host kb-sentinel-target
    HostName YOUR_TARGET_PC_IP
    User kb-sentinel
    IdentityFile ~/.ssh/kb_sentinel_deploy
    StrictHostKeyChecking no
```

### 5. Set GitHub Secrets

In your repository, set these secrets (Settings → Secrets → Actions):

- `DEPLOY_HOST`: IP address of your KB Sentinel PC (e.g., `192.168.1.100`)
- `DEPLOY_USER`: Username on target PC (e.g., `kb-sentinel`)

**Note:** With self-hosted runner, you don't need `DEPLOY_SSH_KEY` secret since SSH is configured locally.

### 6. Install Runner as Service

```bash
# Exit from github-runner user back to sudo user
exit

# Install runner as systemd service
sudo ./svc.sh install github-runner
sudo ./svc.sh start

# Check status
sudo ./svc.sh status

# Enable auto-start
sudo systemctl enable actions.runner.saikhurana98-kb_sentinel.github-runner.service
```

### 7. Test Runner

1. Push a commit to your main branch
2. Check GitHub Actions tab to see if the workflow runs on your self-hosted runner
3. You should see the runner name in the workflow logs

## Network Configuration

### Firewall Rules

On the runner host, ensure these ports are open:

```bash
# Outbound HTTPS for GitHub (443)
sudo ufw allow out 443

# SSH to target PC (22)
sudo ufw allow out 22
```

### Router Configuration

No special router configuration needed since all communication is:
- Outbound HTTPS to GitHub (allowed by default)
- Local network SSH (internal traffic)

## Security Considerations

### Runner Security

- Runner only needs outbound internet access
- No inbound ports need to be opened
- SSH keys are stored locally on runner
- Target PC doesn't need internet access

### SSH Security

- Use key-based authentication only
- Disable password authentication on target PC
- Consider using SSH certificates for rotation

### Network Isolation

- Consider running runner in isolated network segment
- Use firewall rules to limit runner's network access
- Monitor runner logs for unusual activity

## Troubleshooting

### Runner Not Appearing

```bash
# Check runner service status
sudo systemctl status actions.runner.saikhurana98-kb_sentinel.github-runner.service

# Check runner logs
sudo journalctl -u actions.runner.saikhurana98-kb_sentinel.github-runner.service -f
```

### SSH Connection Issues

```bash
# Test SSH connection from runner
ssh -i ~/.ssh/kb_sentinel_deploy kb-sentinel@YOUR_TARGET_PC_IP

# Check SSH logs on target
sudo journalctl -u ssh -f
```

### Deployment Failures

```bash
# Check deployment logs on target PC
tail -f /tmp/kb-sentinel-deploy.log

# Check service status on target
systemctl --user status kb-sentinel.service
```

## Maintenance

### Update Runner

```bash
# Stop runner
sudo ./svc.sh stop

# Update runner (download new version and replace)
# ... (follow GitHub's update instructions)

# Start runner
sudo ./svc.sh start
```

### Monitor Resources

```bash
# Check disk space on runner
df -h

# Check memory usage
free -h

# Monitor runner performance
htop
```

### Backup Runner Configuration

```bash
# Backup runner configuration
sudo cp -r /home/github-runner/actions-runner /backup/runner-config-$(date +%Y%m%d)
```

## Docker Alternative

If you prefer Docker, you can run the runner in a container:

```yaml
# docker-compose.yml
version: '3.8'
services:
  github-runner:
    image: myoung34/github-runner:latest
    environment:
      REPO_URL: https://github.com/saikhurana98/kb_sentinel
      RUNNER_TOKEN: YOUR_TOKEN
      RUNNER_WORKDIR: /tmp/runner/work
      RUNNER_GROUP: default
      RUNNER_SCOPE: repo
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./runner-data:/tmp/runner
      - ~/.ssh:/home/runner/.ssh:ro
    restart: unless-stopped
```

This provides easier updates and isolation while maintaining the same functionality.