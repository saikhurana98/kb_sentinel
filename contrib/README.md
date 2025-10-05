# KB Sentinel Service Installation

This directory contains systemd service files and installation scripts for running KB Sentinel as a user service.

## Files

- `kb-sentinel.service` - Systemd user service template
- `install-service.sh` - Installation script
- `uninstall-service.sh` - Uninstallation script

## Quick Installation

1. Make sure you're in the project root directory
2. Run the installation script:
   ```bash
   ./contrib/install-service.sh
   ```

## Manual Installation

If you prefer to install manually:

1. Create systemd user directory:
   ```bash
   mkdir -p ~/.config/systemd/user
   ```

2. Copy and customize the service file:
   ```bash
   cp contrib/kb-sentinel.service ~/.config/systemd/user/
   # Edit the file to replace paths with your actual project path
   ```

3. Reload systemd and enable the service:
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable kb-sentinel.service
   systemctl --user start kb-sentinel.service
   ```

## Prerequisites

### User Permissions

The user running the service needs access to input devices. Add your user to the `input` group:

```bash
sudo usermod -a -G input $USER
```

Then log out and back in for the group change to take effect.

### Start on Boot (Optional)

To start the service automatically on boot (without requiring user login), enable lingering:

```bash
sudo loginctl enable-linger $USER
```

## Service Management

### Start/Stop Service
```bash
systemctl --user start kb-sentinel.service
systemctl --user stop kb-sentinel.service
systemctl --user restart kb-sentinel.service
```

### Check Status
```bash
systemctl --user status kb-sentinel.service
```

### View Logs
```bash
# View recent logs
journalctl --user -u kb-sentinel.service

# Follow logs in real-time
journalctl --user -u kb-sentinel.service -f

# View logs from last boot
journalctl --user -u kb-sentinel.service -b
```

### Enable/Disable Service
```bash
systemctl --user enable kb-sentinel.service   # Start on login
systemctl --user disable kb-sentinel.service  # Don't start on login
```

## Uninstallation

Run the uninstall script:
```bash
./contrib/uninstall-service.sh
```

Or manually:
```bash
systemctl --user stop kb-sentinel.service
systemctl --user disable kb-sentinel.service
rm ~/.config/systemd/user/kb-sentinel.service
systemctl --user daemon-reload
```

## Troubleshooting

### Permission Denied Errors
- Ensure your user is in the `input` group
- Check that the service file paths are correct
- Verify the virtual environment exists and has the required packages

### Service Won't Start
- Check the service status: `systemctl --user status kb-sentinel.service`
- View detailed logs: `journalctl --user -u kb-sentinel.service`
- Ensure the Python virtual environment is activated and dependencies are installed

### Keyboard Not Detected
- Run `python3 -m evdev.evtest` to list available devices
- Check that your keyboard name matches `TARGET_KEYBOARD_NAME` in the configuration
- Ensure the keyboard is connected and recognized by the system

## Security Notes

The service runs with minimal privileges:
- `NoNewPrivileges=true` - Prevents privilege escalation
- `PrivateTmp=true` - Isolates /tmp directory
- `ProtectSystem=strict` - Read-only access to system directories
- `ProtectHome=true` - Restricts access to other users' home directories
- Only the project directory has read-write access