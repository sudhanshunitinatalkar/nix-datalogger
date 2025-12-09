#!/bin/bash
# This script is designed to set up a Raspberry Pi for production datalogger use.
# It MUST be run with root privileges (e.g., "sudo ./raspberry_pi_setup.sh")
#
set -euo pipefail

# --- [Step 0/10] Root User Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "!!! This script must be run as root (with sudo). Exiting. !!!"
  exit 1
fi

echo "--- [Step 1/10] Starting Full System Update & Upgrade ---"
apt update
apt upgrade -y
echo "--- System update complete. ---"
echo ""

echo "--- [Step 2/10] Installing additional required packages (pymodbus + git) ---"
apt install -y python3-pymodbus git
echo "--- python3-pymodbus and git installed. ---"
echo ""

echo "--- [Step 3/10] Applying Raspberry Pi EEPROM Firmware Updates ---"
if command -v rpi-eeprom-update >/dev/null 2>&1; then
  echo "Found rpi-eeprom-update. Applying any pending firmware updates..."
  rpi-eeprom-update -a
else
  echo "rpi-eeprom-update tool not found. Skipping (normal for older Pi models)."
fi
echo "--- EEPROM update check complete. ---"
echo ""

echo "--- [Step 4/10] Enabling Automatic Security Updates ---"
apt install unattended-upgrades -y
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades
echo "--- Automatic updates enabled. ---"
echo ""

echo "--- [Step 5/10] Enabling User Services on Boot (Linger) ---"
if [ -z "${SUDO_USER:-}" ]; then
    echo "!!! Could not find \$SUDO_USER. Skipping linger step. !!!"
elif [ "$SUDO_USER" = "root" ]; then
    echo "!!! Script was run by root directly. Skipping linger step. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Automatically enabling linger for user '$SUDO_USER'... ---"
    loginctl enable-linger "$SUDO_USER"
    echo "--- User services (linger) enabled for '$SUDO_USER'. ---"
else
    echo "!!! User '$SUDO_USER' does not seem to exist. Skipping linger step. !!!"
fi
echo ""

echo "--- [Step 6/10] Enabling Hardware Datalogger Interfaces ---"
if command -v raspi-config >/dev/null 2>&1; then
  echo "Enabling I2C..."
  raspi-config nonint do_i2c 0
  echo "Enabling SPI..."
  raspi-config nonint do_spi 0
  echo "Enabling Serial Hardware (disabling serial console)..."
  raspi-config nonint do_serial_hw 0
  echo "--- Hardware interfaces enabled. ---"
else
  echo "--- raspi-config not found. Skipping hardware interface setup. ---"
fi
echo ""

echo "--- [Step 6.5/10] Adding user to dialout group (serial port access) ---"
if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "!!! Cannot determine the original user. Skipping dialout group addition. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Ensuring user '$SUDO_USER' is in the dialout group... ---"
    usermod -a -G dialout "$SUDO_USER"
    echo "--- User '$SUDO_USER' permission set. (Effective after reboot/logout) ---"
else
    echo "!!! User '$SUDO_USER' does not exist. Skipping dialout group step. !!!"
fi
echo ""

echo "--- [Step 7/10] Configuring /boot/firmware/config.txt ---"
CONFIG_FILE="/boot/firmware/config.txt"
SETTINGS=(
    "dtparam=watchdog=on"
    "enable_uart=1"
    "dtoverlay=disable-bt"
)
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up config.txt to config.txt.bak..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    sed -i -e '$a\' "$CONFIG_FILE"
    for setting in "${SETTINGS[@]}"; do
        if ! grep -qF "$setting" "$CONFIG_FILE"; then
            echo "Adding '$setting' to $CONFIG_FILE..."
            echo "$setting" >> "$CONFIG_FILE"
        else
            echo "--- '$setting' already exists. Skipping. ---"
        fi
    done
    echo "--- Hardware configuration updated. ---"
else
    echo "--- $CONFIG_FILE not found. Skipping config.txt setup. ---"
fi
echo ""

echo "--- [Step 8/10] Creating Datalogger Data Directory ---"
DATALOGGER_DIR="/var/lib/datalogger"
if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "!!! Cannot determine correct user. Skipping data directory creation. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Creating directory '$DATALOGGER_DIR' for user '$SUDO_USER'... ---"
    mkdir -p "$DATALOGGER_DIR"
    chown "$SUDO_USER":"$SUDO_USER" "$DATALOGGER_DIR"
    echo "--- Datalogger data directory created and permissions set. ---"
else
    echo "!!! User '$SUDO_USER' does not exist. Skipping. !!!"
fi
echo ""

echo "--- [Step 9/10] Setup Complete ---"
echo "All steps finished successfully!"
echo ""

echo "--- [Step 10/10] Rebooting in 10 seconds (Ctrl+C to cancel) ---"
sleep 10
reboot