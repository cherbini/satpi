#!/bin/bash
# Build SatPi SD card image from Raspberry Pi OS Lite

set -e

# Configuration
RPI_OS_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2023-12-06/2023-12-05-raspios-bookworm-armhf-lite.img.xz"
BASE_IMAGE="raspios-lite-armhf.img.xz"
WORK_DIR="$(pwd)/build"
MOUNT_BOOT="$WORK_DIR/boot"
MOUNT_ROOT="$WORK_DIR/root"
OUTPUT_IMAGE="satpi-$(date +%Y%m%d).img"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

cleanup() {
    log "Cleaning up..."
    sudo umount "$MOUNT_BOOT" 2>/dev/null || true
    sudo umount "$MOUNT_ROOT" 2>/dev/null || true
    sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
}

trap cleanup EXIT

log "Starting SatPi image build process..."

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log "ERROR: Do not run this script as root"
    exit 1
fi

# Check dependencies
for cmd in curl wget unxz losetup mount chroot; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "ERROR: Missing required command: $cmd"
        exit 1
    fi
done

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download base image if not exists
if [[ ! -f "$BASE_IMAGE" ]]; then
    log "Downloading Raspberry Pi OS Lite..."
    wget -O "$BASE_IMAGE" "$RPI_OS_URL"
fi

# Extract image
log "Extracting base image..."
unxz -k "$BASE_IMAGE"
BASE_IMG="${BASE_IMAGE%.xz}"

# Copy to output image
log "Creating SatPi image..."
cp "$BASE_IMG" "$OUTPUT_IMAGE"

# Set up loop device
LOOP_DEV=$(sudo losetup --find --show --partscan "$OUTPUT_IMAGE")
log "Using loop device: $LOOP_DEV"

# Wait for partition devices
sleep 2

# Create mount points
mkdir -p "$MOUNT_BOOT" "$MOUNT_ROOT"

# Mount partitions
log "Mounting partitions..."
sudo mount "${LOOP_DEV}p1" "$MOUNT_BOOT"
sudo mount "${LOOP_DEV}p2" "$MOUNT_ROOT"

# Enable SSH
log "Enabling SSH..."
sudo touch "$MOUNT_BOOT/ssh"

# Copy configuration files
log "Installing SatPi configuration..."
sudo cp ../config.txt "$MOUNT_BOOT/"
sudo cp ../cmdline.txt "$MOUNT_BOOT/"
sudo cp ../wpa_supplicant.conf "$MOUNT_BOOT/"

# Create SatPi directory in root filesystem
sudo mkdir -p "$MOUNT_ROOT/home/pi/satpi"

# Copy SatPi scripts
log "Installing SatPi scripts..."
sudo cp ../*.sh "$MOUNT_ROOT/home/pi/satpi/"
sudo cp ../*.py "$MOUNT_ROOT/home/pi/satpi/"
sudo cp ../*.service "$MOUNT_ROOT/home/pi/satpi/"

# Set permissions
sudo chown -R 1000:1000 "$MOUNT_ROOT/home/pi/satpi"
sudo chmod +x "$MOUNT_ROOT/home/pi/satpi"/*.sh
sudo chmod +x "$MOUNT_ROOT/home/pi/satpi"/*.py

# Create installation script for first boot
log "Creating first-boot setup script..."
sudo tee "$MOUNT_ROOT/home/pi/first-boot-setup.sh" > /dev/null << 'EOF'
#!/bin/bash
# First boot setup for SatPi

LOG_FILE="/var/log/first-boot-setup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting SatPi first boot setup..."

# Run dependency installation
cd /home/pi/satpi
sudo ./install-deps.sh

# Setup services
sudo ./setup-services.sh

# Clean up
rm -f /home/pi/first-boot-setup.sh
sudo rm -f /etc/systemd/system/first-boot-setup.service

log "First boot setup completed. Rebooting in 10 seconds..."
sleep 10
sudo reboot
EOF

sudo chmod +x "$MOUNT_ROOT/home/pi/first-boot-setup.sh"

# Create systemd service for first boot
sudo tee "$MOUNT_ROOT/etc/systemd/system/first-boot-setup.service" > /dev/null << 'EOF'
[Unit]
Description=SatPi First Boot Setup
After=multi-user.target
Before=wifi-hunter.service

[Service]
Type=oneshot
ExecStart=/home/pi/first-boot-setup.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable first boot service
sudo chroot "$MOUNT_ROOT" systemctl enable first-boot-setup.service

# Install basic packages that we know we'll need
log "Pre-installing essential packages..."
sudo chroot "$MOUNT_ROOT" apt-get update
sudo chroot "$MOUNT_ROOT" apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    rtl-sdr \
    wireless-tools \
    wpasupplicant

# Configure locale and timezone
log "Configuring system settings..."
sudo chroot "$MOUNT_ROOT" /bin/bash -c 'echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen'
sudo chroot "$MOUNT_ROOT" locale-gen
sudo chroot "$MOUNT_ROOT" timedatectl set-timezone UTC

# Configure automatic login for pi user
sudo mkdir -p "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d"
sudo tee "$MOUNT_ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" > /dev/null << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I $TERM
EOF

# Add helpful aliases and environment
sudo tee -a "$MOUNT_ROOT/home/pi/.bashrc" > /dev/null << 'EOF'

# SatPi aliases
alias satlog='tail -f /var/log/satdump.log'
alias wifilog='tail -f /var/log/wifi-hunter.log'
alias netlog='tail -f /var/log/network-monitor.log'
alias uploadlog='tail -f /var/log/data-uploader.log'
alias satstatus='systemctl status wifi-hunter satdump-capture data-uploader network-monitor'
alias satstart='sudo systemctl start wifi-hunter satdump-capture data-uploader network-monitor'
alias satstop='sudo systemctl stop wifi-hunter satdump-capture data-uploader network-monitor'

echo "SatPi system ready!"
echo "Use 'satstatus' to check services"
echo "Use 'satlog' to view satellite capture logs"
EOF

# Expand filesystem on first boot
sudo tee "$MOUNT_ROOT/etc/systemd/system/expand-filesystem.service" > /dev/null << 'EOF'
[Unit]
Description=Expand filesystem
After=systemd-remount-fs.service
Before=first-boot-setup.service

[Service]
Type=oneshot
ExecStart=/usr/bin/raspi-config --expand-rootfs
ExecStartPost=/bin/systemctl disable expand-filesystem.service
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo chroot "$MOUNT_ROOT" systemctl enable expand-filesystem.service

log "Unmounting partitions..."
sudo umount "$MOUNT_BOOT"
sudo umount "$MOUNT_ROOT"
sudo losetup -d "$LOOP_DEV"

# Compress final image
log "Compressing final image..."
xz -z -9 "$OUTPUT_IMAGE"

log "SatPi image build completed!"
log "Output image: $WORK_DIR/${OUTPUT_IMAGE}.xz"
log ""
log "To flash to SD card:"
log "  dd if=${OUTPUT_IMAGE}.xz of=/dev/sdX bs=4M status=progress"
log ""
log "Or use Raspberry Pi Imager with the compressed image file."