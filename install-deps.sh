#!/bin/bash
# Install dependencies for SatPi system

set -e

LOG_FILE="/var/log/satpi-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting SatPi dependency installation..."

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    cmake \
    pkg-config \
    libfftw3-dev \
    libvorbis-dev \
    libogg-dev \
    libpng-dev \
    libjpeg-dev \
    librtlsdr-dev \
    rtl-sdr \
    sox \
    bc \
    jq \
    wireless-tools \
    wpasupplicant \
    dhcpcd5 \
    hostapd \
    dnsmasq \
    iptables \
    python3 \
    python3-pip \
    python3-numpy \
    python3-scipy \
    python3-requests

# Install RTL-SDR tools
log "Installing RTL-SDR tools..."
apt-get install -y rtl-sdr librtlsdr0 librtlsdr-dev

# Blacklist DVB-T drivers to prevent conflicts
log "Configuring RTL-SDR..."
echo 'blacklist dvb_usb_rtl28xxu' >> /etc/modprobe.d/blacklist-rtl.conf
echo 'blacklist dvb_usb_rtl2832u' >> /etc/modprobe.d/blacklist-rtl.conf
echo 'blacklist rtl_2832' >> /etc/modprobe.d/blacklist-rtl.conf
echo 'blacklist rtl_2830' >> /etc/modprobe.d/blacklist-rtl.conf

# Install SatDump if available
log "Attempting to install SatDump..."
if ! command -v satdump >/dev/null 2>&1; then
    # Try to install from source
    cd /tmp
    git clone --recursive https://github.com/SatDump/SatDump.git || {
        log "WARNING: Could not clone SatDump repository"
    }
    
    if [[ -d SatDump ]]; then
        cd SatDump
        mkdir -p build
        cd build
        cmake -DCMAKE_BUILD_TYPE=Release .. || {
            log "WARNING: SatDump cmake configuration failed"
        }
        make -j$(nproc) || {
            log "WARNING: SatDump compilation failed"
        }
        make install || {
            log "WARNING: SatDump installation failed"
        }
    fi
fi

# Install predict for satellite tracking
log "Installing predict..."
cd /tmp
wget http://http.debian.net/debian/pool/main/p/predict/predict_2.2.3-4_armhf.deb || {
    log "WARNING: Could not download predict package"
}
if [[ -f predict_2.2.3-4_armhf.deb ]]; then
    dpkg -i predict_2.2.3-4_armhf.deb || {
        apt-get install -f -y
    }
fi

# Configure RTL-SDR permissions
log "Configuring RTL-SDR permissions..."
usermod -a -G plugdev pi
echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666", SYMLINK+="rtl_sdr"' > /etc/udev/rules.d/99-rtlsdr.rules

# Install Python packages for data processing
log "Installing Python packages..."
pip3 install --upgrade pip
pip3 install \
    numpy \
    scipy \
    matplotlib \
    pillow \
    requests \
    schedule \
    pytz \
    smtplib \
    email

# Create directories
log "Creating directories..."
mkdir -p /home/pi/sat-data
mkdir -p /var/log
chown pi:pi /home/pi/sat-data

# Set up log rotation
log "Configuring log rotation..."
cat > /etc/logrotate.d/satpi << EOF
/var/log/satpi*.log /var/log/satdump.log /var/log/wifi-hunter.log /var/log/network-monitor.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

log "SatPi dependency installation completed successfully!"
log "Please reboot the system to complete the setup."