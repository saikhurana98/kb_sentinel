#!/usr/bin/env python3
import asyncio
import time
import json
import subprocess
import re
import os
from pathlib import Path
from evdev import InputDevice, categorize, ecodes, list_devices
from paho.mqtt.client import Client, CallbackAPIVersion, MQTTv311

# --- CONFIGURATION ---

# Load environment variables from .env file
def load_env_file():
    env_path = Path(__file__).parent / '.env'
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    os.environ[key] = value

load_env_file()

TARGET_KEYBOARD_NAME = "4by4 Keyboard"

# MQTT broker settings
MQTT_BROKER = os.getenv("MQTT_BROKER", "")
MQTT_PORT = 1883
MQTT_USERNAME = os.getenv("MQTT_USERNAME", "")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "")
BASE_TOPIC = "keyboard/keypress"

# Home Assistant MQTT Discovery prefix
HA_DISCOVERY_PREFIX = "homeassistant"
DEVICE_ID = "4by4_keyboard"
DEVICE_NAME = "4by4 Keyboard"
MANUFACTURER = "Custom Integration"
MODEL = "MQTT Keyboard Bridge"

# --- Generate keybinds (Ctrl+Alt+A → Ctrl+Alt+O) ---
KEYS = [chr(i) for i in range(ord("A"), ord("O") + 1)]
HOTKEYS = {
    frozenset({"KEY_LEFTCTRL", "KEY_LEFTALT", f"KEY_{k}"}): f"ctrl+alt+{k.lower()}"
    for k in KEYS
}

# --- MQTT Setup ---
def create_mqtt_client():
    client = Client(
        client_id="keyboard-bridge",
        clean_session=True,
        protocol=MQTTv311,
        callback_api_version=CallbackAPIVersion.VERSION2,
    )
    # Only set credentials if they are provided
    if MQTT_USERNAME and MQTT_PASSWORD:
        client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    return client

mqtt_client = create_mqtt_client()

def connect_mqtt():
    try:
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
        mqtt_client.loop_start()
        print(f"✅ Connected to MQTT broker at {MQTT_BROKER}:{MQTT_PORT}")
    except Exception as e:
        print(f"❌ MQTT connection failed: {e}")
        time.sleep(5)
        connect_mqtt()

connect_mqtt()

# --- Home Assistant Discovery ---
def publish_discovery_configs():
    """Publish discovery configs for each key to Home Assistant."""
    device_info = {
        "identifiers": [DEVICE_ID],
        "manufacturer": MANUFACTURER,
        "model": MODEL,
        "name": DEVICE_NAME,
    }

    for combo, key_name in HOTKEYS.items():
        unique_id = f"{DEVICE_ID}_{key_name.replace('+', '_')}"
        discovery_topic = f"{HA_DISCOVERY_PREFIX}/sensor/{unique_id}/config"

        payload = {
            "name": key_name,
            "unique_id": unique_id,
            "state_topic": f"{BASE_TOPIC}/{key_name}",
            "device": device_info,
            "icon": "mdi:keyboard",
        }

        mqtt_client.publish(discovery_topic, json.dumps(payload), retain=True)
        print(f"📡 Published discovery for: {key_name}")

    # Create a single sensor for whenever any key is pressed, update the value with the value of the key that was pressed
    key_press_topic = f"{HA_DISCOVERY_PREFIX}/sensor/{DEVICE_ID}_key_press/config"
    payload = {
        "name": "Key Press",
        "unique_id": f"{DEVICE_ID}_key_press",
        "state_topic": f"{BASE_TOPIC}/key_press",
        "device": device_info,
        "icon": "mdi:keyboard",
    }
    mqtt_client.publish(key_press_topic, json.dumps(payload), retain=True)
    print("📡 Published discovery for: key_press")
    

    # Also create a “last pressed” sensor
    last_key_topic = f"{HA_DISCOVERY_PREFIX}/sensor/{DEVICE_ID}_last_pressed/config"
    payload = {
        "name": "Last Pressed Key",
        "unique_id": f"{DEVICE_ID}_last_pressed",
        "state_topic": f"{BASE_TOPIC}/last_pressed",
        "device": device_info,
        "icon": "mdi:keyboard-outline",
    }
    mqtt_client.publish(last_key_topic, json.dumps(payload), retain=True)
    print("📡 Published discovery for: last_pressed")


    battery_topic = f"{HA_DISCOVERY_PREFIX}/sensor/{DEVICE_ID}_battery/config"
    payload = {
        "name": "Keyboard Battery",
        "unique_id": f"{DEVICE_ID}_battery",
        "state_topic": f"{BASE_TOPIC}/battery",
        "device": device_info,
        "unit_of_measurement": "%",
        "icon": "mdi:battery",
    }
    mqtt_client.publish(battery_topic, json.dumps(payload), retain=True)


# --- Utilities ---
def list_keybinds():
    print("\n🎹 Available Keybinds (Ctrl+Alt+A → Ctrl+Alt+O):")
    for combo, msg in HOTKEYS.items():
        combo_str = " + ".join(k.replace("KEY_", "").title() for k in combo)
        print(f"  {combo_str:<25} → {msg}")
    print()

def find_target_keyboard():
    devices = [InputDevice(path) for path in list_devices()]
    for dev in devices:
        if TARGET_KEYBOARD_NAME.lower() in dev.name.lower():
            print(f"✅ Found target keyboard: {dev.name} ({dev.path})")
            return dev
    return None

# --- Helper: make MQTT-safe topic strings ---
def mqtt_safe(s: str) -> str:
    """Convert strings like 'ctrl+alt+b' into MQTT-safe topics."""
    return s.replace("+", "_").replace("#", "_").replace("/", "_")

async def monitor_device(device):
    print(f"🎧 Listening on {device.path} ({device.name})")
    pressed_keys = set()

    async for event in device.async_read_loop():
        if event.type == ecodes.EV_KEY:
            key_event = categorize(event)
            key_name = key_event.keycode if hasattr(key_event, "keycode") else str(event.code)

            if key_event.keystate == key_event.key_down:
                pressed_keys.add(key_name)
            elif key_event.keystate == key_event.key_up:
                pressed_keys.discard(key_name)

            for combo, payload in HOTKEYS.items():
                if combo.issubset(pressed_keys):
                    safe_payload = mqtt_safe(payload)
                    print(f"📨 Pressed: {payload} → topic: {safe_payload}")
                    mqtt_client.publish(f"{BASE_TOPIC}/{safe_payload}", "pressed", retain=False)
                    mqtt_client.publish(f"{BASE_TOPIC}/last_pressed", payload, retain=False)

# --- Read battery via upower ---
def get_keyboard_battery_percentage():
    """
    Run `upower -d` and parse battery percentage for the 4by4 keyboard.
    """
    try:
        output = subprocess.check_output(["upower", "-d"], text=True)

        # Regex: match the 4by4 model block and extract its percentage
        match = re.search(r"model:\s+4by4.*?percentage:\s+(\d+)%", output, re.DOTALL)
        if match:
            return int(match.group(1))
        return None
    except Exception as e:
        print(f"Error fetching battery percentage: {e}")
        return None


async def publish_battery_status():
    """
    Periodically fetch and publish the battery percentage.
    """
    while True:
        percentage = get_keyboard_battery_percentage()
        if percentage is not None:
            print(f"Keyboard Battery Percentage: {percentage}%")
            mqtt_client.publish(f"{BASE_TOPIC}/battery", str(percentage), retain=True)
        else:
            print("Battery percentage not found.")
        await asyncio.sleep(30)


async def main():
    print(f"🔍 Searching for keyboard: '{TARGET_KEYBOARD_NAME}'")
    device = find_target_keyboard()
    if not device:
        print(f"❌ No device found matching name: '{TARGET_KEYBOARD_NAME}'")
        print("Run `python3 -m evdev.evtest` to list available devices.")
        return

    list_keybinds()
    publish_discovery_configs()
    await asyncio.gather(
            monitor_device(device),
            publish_battery_status()
    )

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except RuntimeError:
        # Already running event loop (e.g., Jupyter) → use alternative
        loop = asyncio.get_event_loop()
        loop.run_until_complete(main())
