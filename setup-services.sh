#!/bin/bash
# Setup systemd services for SatPi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="/etc/systemd/system"
SATPI_DIR="/home/pi/satpi"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Setting up SatPi services..."

# Create SatPi directory
mkdir -p "$SATPI_DIR"

# Copy scripts to target directory
log "Copying scripts..."
cp "$SCRIPT_DIR"/*.sh "$SATPI_DIR/"
cp "$SCRIPT_DIR"/*.py "$SATPI_DIR/"
chmod +x "$SATPI_DIR"/*.sh
chmod +x "$SATPI_DIR"/*.py

# Set ownership
chown -R pi:pi "$SATPI_DIR"

# Install service files
log "Installing service files..."
cp "$SCRIPT_DIR"/*.service "$SERVICES_DIR/"
cp "$SCRIPT_DIR"/*.timer "$SERVICES_DIR/"

# Enable services
log "Enabling services..."
systemctl daemon-reload

systemctl enable wifi-hunter.service
systemctl enable network-monitor.service
systemctl enable satdump-capture.service
systemctl enable data-uploader.service
systemctl enable location-reporter.service
systemctl enable dynamic-dns.service
systemctl enable dynamic-dns.timer

# Configure boot files
log "Configuring boot files..."
cp "$SCRIPT_DIR/config.txt" /boot/
cp "$SCRIPT_DIR/cmdline.txt" /boot/
cp "$SCRIPT_DIR/wpa_supplicant.conf" /etc/wpa_supplicant/

# Set permissions
chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf

# Enable required services
systemctl enable ssh
systemctl enable wpa_supplicant
systemctl enable dhcpcd

log "Starting services..."
systemctl start wifi-hunter.service
systemctl start network-monitor.service
systemctl start data-uploader.service
systemctl start location-reporter.service
systemctl start dynamic-dns.timer

# Wait for network before starting satellite capture
sleep 30
systemctl start satdump-capture.service

log "SatPi services setup completed!"
log "Services status:"
systemctl --no-pager status wifi-hunter.service
systemctl --no-pager status network-monitor.service
systemctl --no-pager status data-uploader.service
systemctl --no-pager status satdump-capture.service
systemctl --no-pager status location-reporter.service
systemctl --no-pager status dynamic-dns.timer