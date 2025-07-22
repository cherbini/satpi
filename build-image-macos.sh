#!/bin/bash
# Build SatPi SD card image on macOS using Docker

set -e

# Configuration
RPI_OS_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2023-12-06/2023-12-05-raspios-bookworm-armhf-lite.img.xz"
BASE_IMAGE="raspios-lite-armhf.img.xz"
WORK_DIR="$(pwd)/build"
OUTPUT_IMAGE="satpi-$(date +%Y%m%d).img"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_dependencies() {
    # Check if we have Docker
    if ! command -v docker >/dev/null 2>&1; then
        log "ERROR: Docker is required but not installed"
        log "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log "ERROR: Docker is not running. Please start Docker Desktop"
        exit 1
    fi
}

download_base_image() {
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    
    if [[ ! -f "$BASE_IMAGE" ]]; then
        log "Downloading Raspberry Pi OS Lite..."
        curl -L -o "$BASE_IMAGE" "$RPI_OS_URL"
    else
        log "Base image already exists: $BASE_IMAGE"
    fi
}

build_with_docker() {
    log "Building SatPi image using Docker..."
    
    # Create a Dockerfile for the build environment
    cat > Dockerfile << 'EOF'
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    wget curl unxz-utils \
    parted kpartx \
    qemu-user-static \
    binfmt-support \
    systemd-container \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
EOF

    # Build the Docker image
    docker build -t satpi-builder .
    
    # Run the container with privileged access (needed for loop devices)
    docker run --rm --privileged \
        -v "$(pwd)":/build \
        -v "$(dirname $(pwd))":/satpi-src:ro \
        satpi-builder /bin/bash -c "
        set -e
        
        # Extract base image
        if [[ ! -f raspios-bookworm-armhf-lite.img ]]; then
            echo 'Extracting base image...'
            unxz -k $BASE_IMAGE
        fi
        
        # Copy to output image
        cp raspios-bookworm-armhf-lite.img $OUTPUT_IMAGE
        
        # Set up loop device
        LOOP_DEV=\$(losetup --find --show --partscan $OUTPUT_IMAGE)
        echo \"Using loop device: \$LOOP_DEV\"
        
        # Wait for partition devices
        sleep 2
        partprobe \$LOOP_DEV
        
        # Create mount points
        mkdir -p boot root
        
        # Mount partitions
        mount \${LOOP_DEV}p1 boot/
        mount \${LOOP_DEV}p2 root/
        
        echo 'Installing SatPi files...'
        
        # Enable SSH
        touch boot/ssh
        
        # Copy configuration files
        cp /satpi-src/config.txt boot/
        cp /satpi-src/cmdline.txt boot/
        cp /satpi-src/wpa_supplicant.conf boot/
        
        # Create SatPi directory
        mkdir -p root/home/pi/satpi
        
        # Copy SatPi scripts
        cp /satpi-src/*.sh root/home/pi/satpi/
        cp /satpi-src/*.py root/home/pi/satpi/
        cp /satpi-src/*.service root/home/pi/satpi/
        cp /satpi-src/*.timer root/home/pi/satpi/ 2>/dev/null || true
        cp /satpi-src/*.json root/home/pi/satpi/
        cp /satpi-src/*.md root/home/pi/satpi/
        
        # Set permissions
        chown -R 1000:1000 root/home/pi/satpi
        chmod +x root/home/pi/satpi/*.sh
        chmod +x root/home/pi/satpi/*.py
        
        # Create first-boot setup script
        cat > root/home/pi/first-boot-setup.sh << 'FIRST_BOOT_EOF'
#!/bin/bash
LOG_FILE=\"/var/log/first-boot-setup.log\"
log() {
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\" | tee -a \"\$LOG_FILE\"
}

log \"Starting SatPi first boot setup...\"

# Run dependency installation
cd /home/pi/satpi
sudo ./install-deps.sh

# Setup services
sudo ./setup-services.sh

# Clean up
rm -f /home/pi/first-boot-setup.sh
sudo rm -f /etc/systemd/system/first-boot-setup.service

log \"First boot setup completed. Rebooting in 10 seconds...\"
sleep 10
sudo reboot
FIRST_BOOT_EOF

        chmod +x root/home/pi/first-boot-setup.sh
        
        # Create systemd service for first boot
        cat > root/etc/systemd/system/first-boot-setup.service << 'SERVICE_EOF'
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
SERVICE_EOF

        # Enable first boot service
        chroot root/ systemctl enable first-boot-setup.service
        
        # Configure system settings
        chroot root/ /bin/bash -c 'echo \"en_US.UTF-8 UTF-8\" >> /etc/locale.gen'
        chroot root/ locale-gen
        
        # Configure automatic login
        mkdir -p root/etc/systemd/system/getty@tty1.service.d
        cat > root/etc/systemd/system/getty@tty1.service.d/autologin.conf << 'AUTOLOGIN_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
AUTOLOGIN_EOF

        # Add helpful aliases
        cat >> root/home/pi/.bashrc << 'BASHRC_EOF'

# SatPi aliases
alias satlog='tail -f /var/log/satdump.log'
alias wifilog='tail -f /var/log/wifi-hunter.log'
alias netlog='tail -f /var/log/network-monitor.log'
alias uploadlog='tail -f /var/log/data-uploader.log'
alias satstatus='systemctl status wifi-hunter satdump-capture data-uploader network-monitor'
alias satstart='sudo systemctl start wifi-hunter satdump-capture data-uploader network-monitor'
alias satstop='sudo systemctl stop wifi-hunter satdump-capture data-uploader network-monitor'

echo \"SatPi system ready!\"
echo \"Use 'satstatus' to check services\"
echo \"Use 'satlog' to view satellite capture logs\"
BASHRC_EOF

        # Expand filesystem service
        cat > root/etc/systemd/system/expand-filesystem.service << 'EXPAND_EOF'
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
EXPAND_EOF

        chroot root/ systemctl enable expand-filesystem.service
        
        echo 'Unmounting and cleaning up...'
        umount boot/ root/
        losetup -d \$LOOP_DEV
        
        echo 'Compressing final image...'
        xz -z -9 $OUTPUT_IMAGE
        
        echo 'Build completed successfully!'
    "
    
    # Clean up Docker image
    docker rmi satpi-builder
}

show_completion_message() {
    local output_file="$WORK_DIR/${OUTPUT_IMAGE}.xz"
    
    log "SatPi image build completed!"
    log "Output image: $output_file"
    log ""
    log "To flash to SD card on macOS:"
    log "1. Insert SD card"
    log "2. Find the disk: diskutil list"
    log "3. Unmount: diskutil unmountDisk /dev/diskN"
    log "4. Flash: sudo dd if=$output_file of=/dev/rdiskN bs=4m status=progress"
    log "5. Eject: diskutil eject /dev/diskN"
    log ""
    log "Replace 'N' with your actual SD card disk number!"
    log "⚠️  DOUBLE-CHECK the disk number to avoid overwriting your main drive!"
}

main() {
    log "Starting SatPi image build for macOS..."
    
    check_dependencies
    download_base_image
    build_with_docker
    show_completion_message
}

main