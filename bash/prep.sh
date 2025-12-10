#!/bin/bash
# This script is designed to set up a Raspberry Pi for production datalogger use.
# It MUST be run with root privileges (e.g., "sudo ./raspberry_pi_setup.sh")
#
set -euo pipefail

# --- [Step 0/12] Root User Check ---
if [ "$(id -u)" -ne 0 ]; then
  echo "!!! This script must be run as root (with sudo). Exiting. !!!"
  exit 1
fi

echo "--- [Step 1/12] Starting Full System Update & Upgrade ---"
apt update
apt upgrade -y
echo "--- System update complete. ---"
echo ""

echo "--- [Step 2/12] Applying Raspberry Pi EEPROM Firmware Updates ---"
if command -v rpi-eeprom-update >/dev/null 2>&1; then
  echo "Found rpi-eeprom-update. Applying any pending firmware updates..."
  rpi-eeprom-update -a
else
  echo "rpi-eeprom-update tool not found. Skipping (this is normal for older Pi models)."
fi
echo "--- EEPROM update check complete. ---"
echo ""

echo "--- [Step 3/12] Cleaning up previous Nix install artifacts ---"
rm -f /etc/bashrc.backup-before-nix
rm -f /etc/profile.d/nix.sh.backup-before-nix
rm -f /etc/zshrc.backup-before-nix
rm -f /etc/bash.bashrc.backup-before-nix
echo "--- Old artifact cleanup complete. ---"
echo ""

echo "--- [Step 4/12] Installing Nix Package Manager (Daemon) ---"
if [ -d "/nix" ]; then
    echo "The /nix directory already exists."
    echo "--- Nix appears to be already installed. Skipping installation. ---"
else
    echo "No existing /nix directory found. Starting new installation..."
    curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon
    echo "--- Nix installation complete. ---"
fi
echo ""

echo "--- [Step 5/12] Configuring Nix for Flakes ---"
NIX_CONF_FILE="/etc/nix/nix.conf"
NIX_CONF_LINE="experimental-features = nix-command flakes"
mkdir -p /etc/nix
touch "$NIX_CONF_FILE"
if ! grep -qF "$NIX_CONF_LINE" "$NIX_CONF_FILE"; then
    echo "Adding '$NIX_CONF_LINE' to $NIX_CONF_FILE..."
    echo "$NIX_CONF_LINE" >> "$NIX_CONF_FILE"
    echo "--- Nix configuration updated. ---"
else
    echo "--- Nix configuration already set for flakes. Skipping. ---"
fi
echo ""

echo "--- [Step 6/12] Enabling Automatic Security Updates ---"
apt install unattended-upgrades -y
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -plow unattended-upgrades
echo "--- Automatic updates enabled. ---"
echo ""

echo "--- [Step 7/12] Enabling User Services on Boot (Linger) ---"
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

echo "--- [Step 8/12] Enabling Hardware Datalogger Interfaces ---"
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

echo "--- [Step 8.5/12] Adding user to dialout group (serial port access) ---"
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

echo "--- [Step 9/12] Configuring /boot/firmware/config.txt ---"
CONFIG_FILE="/boot/firmware/config.txt"
SETTINGS=(
    "dtparam=watchdog=on"
    "enable_uart=1"
    "dtoverlay=disable-bt"
)
if [ -f "$CONFIG_FILE" ]; then
    echo "Backing up config.txt to config.txt.bak..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    # Ensure file ends with newline before appending
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

echo "--- [Step 10/12] Creating Datalogger Data Directory ---"
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

# === NEW STEP: Automatic Login ===
echo "--- [Step 11/12] Configuring Automatic Console Login ---"
if [ -z "${SUDO_USER:-}" ] || [ "$SUDO_USER" = "root" ]; then
    echo "!!! Cannot determine correct user for auto-login. Skipping. !!!"
elif id -u "$SUDO_USER" >/dev/null 2>&1; then
    echo "--- Configuring systemd for automatic console login for user '$SUDO_USER'... ---"
    
    # Create the override directory for tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    
    # Create/Overwrite the autologin.conf file
    # This instructs agetty to login the specific user without prompting for password
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SUDO_USER --noclear %I \$TERM
EOF
    
    echo "--- Auto-login configuration written to systemd (getty@tty1). ---"
else
    echo "!!! User '$SUDO_USER' does not exist. Skipping auto-login setup. !!!"
fi
echo ""

echo "--- [Step 12/12] Setup Complete. Rebooting... ---"
echo "The system will reboot in 10 seconds. Press Ctrl+C to cancel."
sleep 10
reboot