# KB Sentinel

A Python-based keyboard monitoring service that bridges a 4by4 Keyboard to MQTT and Home Assistant for automation and monitoring purposes.

## Overview

KB Sentinel monitors keyboard input from a specific 4by4 Keyboard device and publishes keypress events to an MQTT broker. It also provides Home Assistant auto-discovery for seamless integration with your smart home setup. The service can monitor battery levels and track the last pressed key combinations.

## Features

- 🎹 **Keyboard Monitoring**: Listens for specific key combinations (Ctrl+Alt+A through Ctrl+Alt+O)
- 📡 **MQTT Integration**: Publishes keypress events to MQTT broker
- 🏠 **Home Assistant Discovery**: Automatic sensor discovery for Home Assistant
- 🔋 **Battery Monitoring**: Tracks and reports keyboard battery percentage via `upower`
- ⚡ **Async Operations**: Non-blocking event monitoring and battery reporting

## Requirements

- Python 3.13+
- Linux system with `evdev` support
- `upower` utility for battery monitoring
- Access to input devices (may require running as root or adding user to `input` group)

## Dependencies

The project uses the following Python packages:
- `evdev` - For keyboard event monitoring
- `paho-mqtt` - For MQTT communication

## Quick Start

For the fastest setup experience:

```bash
# Clone and setup
git clone https://github.com/saikhurana98/kb_sentinel.git
cd kb_sentinel

# Initial setup (install dependencies and create .env)
make setup

# Edit .env with your MQTT credentials
nano .env

# Install and start the service
make install
```

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd kb_sentinel
   ```

2. Install dependencies using uv (recommended):
   ```bash
   uv sync
   ```

   Or using pip:
   ```bash
   pip install evdev paho-mqtt
   ```

## Configuration

The application loads MQTT credentials from a `.env` file for security. Create a `.env` file in the project root:

```bash
cp .env.example .env
```

Then edit the `.env` file with your MQTT credentials:

```env
# MQTT Credentials
MQTT_USERNAME=admin
MQTT_PASSWORD=raspberry
```

### Other Configuration

Other settings are configured directly in `kb_sentinel.py` and can be modified as needed:

```python
# Target keyboard name
TARGET_KEYBOARD_NAME = "4by4 Keyboard"

# MQTT broker settings
MQTT_BROKER = "192.168.42.13"
MQTT_PORT = 1883
BASE_TOPIC = "keyboard/keypress"

# Home Assistant MQTT Discovery prefix
HA_DISCOVERY_PREFIX = "homeassistant"
DEVICE_ID = "4by4_keyboard"
DEVICE_NAME = "4by4 Keyboard"
MANUFACTURER = "Custom Integration"
MODEL = "MQTT Keyboard Bridge"
```

### Key Bindings

The service monitors the following key combinations:
- Ctrl+Alt+A through Ctrl+Alt+O (15 combinations total)

## Usage

### Running the Service

```bash
# Using Python directly
python3 kb_sentinel.py

# Or using uv
uv run kb_sentinel.py
```

### Finding Your Keyboard

If you need to identify your keyboard device name:

```bash
python3 -m evdev.evtest
```

This will list all available input devices.

### Permissions

You may need to run the script with appropriate permissions to access input devices:

```bash
# Option 1: Run as root (not recommended for production)
sudo python3 kb_sentinel.py

# Option 2: Add your user to the input group (recommended)
sudo usermod -a -G input $USER
# Then log out and back in
```

## Service Management

### Using Make (Recommended)

The project includes a Makefile for easy service management:

```bash
make help          # Show all available commands
make setup         # Initial setup (dependencies + .env)
make install       # Install systemd service
make start         # Start the service
make stop          # Stop the service  
make restart       # Restart the service
make status        # Show service status
make logs          # Follow service logs
make health        # Run health check
make uninstall     # Remove service
```

### Manual systemctl Commands

```bash
systemctl --user start kb-sentinel.service    # Start
systemctl --user stop kb-sentinel.service     # Stop
systemctl --user restart kb-sentinel.service  # Restart
systemctl --user status kb-sentinel.service   # Status
journalctl --user -u kb-sentinel.service -f   # Logs
```

## MQTT Topics

The service publishes to the following MQTT topics:

- `keyboard/keypress/{key_combination}` - Individual keypress events
- `keyboard/keypress/last_pressed` - Last pressed key combination
- `keyboard/keypress/battery` - Battery percentage (0-100)

Example topics:
- `keyboard/keypress/ctrl_alt_a`
- `keyboard/keypress/ctrl_alt_b`
- `keyboard/keypress/last_pressed`
- `keyboard/keypress/battery`

## Home Assistant Integration

The service automatically creates the following sensors in Home Assistant:

- Individual sensors for each key combination (ctrl+alt+a, ctrl+alt+b, etc.)
- Last pressed key sensor
- Battery percentage sensor

These sensors will appear automatically in Home Assistant if MQTT discovery is enabled.

## Project Structure

```
kb_sentinel/
├── .env.example     # Environment configuration template
├── .env            # Your environment configuration (create from .env.example)
├── .gitignore      # Git ignore rules
├── kb_sentinel.py  # Main application logic
├── main.py         # Simple entry point
├── pyproject.toml  # Project configuration
├── README.md       # This file
└── uv.lock        # Dependency lock file
```

## Troubleshooting

### Device Not Found
- Ensure the keyboard is connected
- Check the device name using `python3 -m evdev.evtest`
- Update `TARGET_KEYBOARD_NAME` in the configuration

### Permission Errors
- Add your user to the `input` group
- Ensure `/dev/input/` devices are accessible

### MQTT Connection Issues
- Verify MQTT broker settings
- Check network connectivity
- Ensure MQTT broker is running and accessible

### Battery Monitoring Not Working
- Ensure `upower` is installed: `sudo apt install upower`
- Check if the keyboard is detected by upower: `upower -d`

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]