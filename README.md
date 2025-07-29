# SatPi - Satellite Data Capture System

A robust, network-enabled satellite data capture system for Raspberry Pi 3 (ARMhf) designed to automatically connect to public WiFi networks and upload captured satellite data to boatwizards.com/satellite.

## Features

- **Aggressive WiFi Networking**: Automatically scans and connects to available public WiFi networks
- **Satellite Data Capture**: Uses RTL-SDR to capture data from weather satellites (NOAA, METEOR-M2, ISS)
- **Automatic Upload**: Uploads captured data to boatwizards.com/satellite when internet is available
- **Location Reporting**: Daily email notifications with device location and status to johncherbini@hotmail.com
- **Dynamic DNS**: Optional dynamic DNS updates for remote access
- **Comprehensive Monitoring**: Monitors network quality, system health, and capture statistics
- **Zero-Configuration**: Boots and runs automatically from SD card

## Supported Satellites

### VHF Weather Satellites
- NOAA-15 (137.620 MHz)
- NOAA-18 (137.912 MHz)  
- NOAA-19 (137.100 MHz)
- METEOR-M2 (137.100 MHz)
- ISS (145.800 MHz)

### GOES Geostationary Satellites (L-band)
- **GOES-18 West (1686.6 MHz)** - Primary target for West Coast operations
- GOES-16 East (1694.1 MHz) - East Coast coverage
- GOES-17 West (1686.0 MHz) - Backup West Coast satellite

## Hardware Requirements

### Basic Setup
- Raspberry Pi 3 (ARMhf)
- RTL-SDR USB dongle
- SD card (16GB minimum recommended)

### Antenna Options

#### VHF Weather Satellites (137-145 MHz)
- Simple dipole or V-dipole antenna
- QFH (Quadrifilar Helix) antenna for circular polarization

#### GOES L-band Setup (1690 MHz) - **Recommended for West Coast**
- **1690 MHz directional antenna** (parabolic or patch)
- **Sawbird+ GOES LNA** (30dB gain, 1dB noise figure)  
- **GOES bandpass filter** (1680-1700 MHz)
- Proper coaxial cable (low loss at L-band)

**Signal Chain:** Antenna → GOES Filter → Sawbird+ LNA → RTL-SDR

## GOES Antenna Aiming

For optimal GOES satellite reception, use the included antenna aiming tool:

```bash
# Run the interactive GOES aiming tool
./goes-aiming-tool.sh
```

### GOES-18 West Coast Pointing
- **Azimuth:** ~200° (SSW)
- **Elevation:** ~50° above horizon  
- **Satellite Position:** 137.2°W longitude
- **Coverage:** Western US, Pacific Ocean

### Signal Quality Guidelines
- **Excellent:** > -60dB signal strength
- **Good:** > -70dB signal strength
- **Usable:** > -80dB signal strength
- **Poor:** < -90dB (check antenna pointing)

The aiming tool provides:
- Real-time signal strength monitoring
- Visual signal bars and color coding
- GOES band scanning (1680-1700 MHz)
- LNA saturation testing
- Optimal RTL-SDR gain recommendations

## Quick Start

### Building the Image

1. Run the build script on a Linux system:
```bash
sudo ./build-image.sh
```

2. Flash the resulting image to an SD card:
```bash
dd if=build/satpi-YYYYMMDD.img.xz of=/dev/sdX bs=4M status=progress
```

### Manual Installation

If you prefer to set up an existing Raspberry Pi OS installation:

1. Copy all files to your Raspberry Pi
2. Run the dependency installer:
```bash
sudo ./install-deps.sh
```
3. Set up the services:
```bash
sudo ./setup-services.sh
```
4. Reboot the system

## System Components

### WiFi Hunter (`wifi-hunter.sh`)
- Continuously scans for available WiFi networks
- Attempts connections to open networks and common public WiFi
- Handles captive portal detection and bypass
- Prioritizes networks by signal strength

### Satellite Capture (`satdump-capture.sh`)
- Automatically captures satellite data using RTL-SDR
- Supports multiple satellite frequencies
- Processes raw data when SatDump is available
- Queues captured data for upload

### Data Uploader (`data-uploader.py`)
- Uploads captured data to boatwizards.com/satellite
- Includes metadata (location, timestamp, satellite info)
- Handles retry logic and network failures
- Removes local files after successful upload

### Network Monitor (`network-monitor.sh`)
- Monitors connection quality and bandwidth
- Triggers WiFi hunter when connection degrades
- Logs network statistics

## Configuration

### WiFi Networks
Edit `wpa_supplicant.conf` to add specific networks:
```
network={
    ssid="YourNetwork"
    psk="password"
    priority=5
}
```

### Custom Server Setup
Configure your own server instead of boatwizards.com:

```bash
# Interactive configuration
sudo /home/pi/satpi/configure-server.sh

# Edit configuration file directly
nano /home/pi/satpi/server-config.json
```

See [SERVER_SETUP.md](SERVER_SETUP.md) for detailed instructions.

### Environment Variables
Override settings with environment variables:
```bash
export SATPI_UPLOAD_URL="https://your-server.com/api"
export SATPI_API_KEY="your-api-key" 
export SATPI_NOTIFICATION_EMAIL="your-email@example.com"
```

## Monitoring

### Service Status
```bash
satstatus  # Check all service status
```

### Log Files
```bash
satlog      # Satellite capture logs
wifilog     # WiFi hunter logs
netlog      # Network monitor logs
uploadlog   # Data upload logs
```

### Manual Operations
```bash
# Test RTL-SDR
./satdump-capture.sh test

# List all supported satellites
./satdump-capture.sh list

# Capture VHF weather satellite
./satdump-capture.sh capture NOAA-18 600

# Capture GOES satellite (10 minutes)
./satdump-capture.sh capture GOES-18 600

# GOES-specific operations
./satdump-capture.sh goes test                    # Test GOES signal
./satdump-capture.sh goes continuous GOES-18 3600 # 1-hour continuous capture

# Test upload connection
python3 data-uploader.py test

# GOES antenna aiming tool
./goes-aiming-tool.sh
```

## Services

All components run as systemd services:
- `wifi-hunter.service` - WiFi connection management
- `network-monitor.service` - Network quality monitoring
- `satdump-capture.service` - Satellite data capture
- `data-uploader.service` - Data upload daemon
- `startup-notification.service` - Sends email when device boots online

## Troubleshooting

### No RTL-SDR Device
- Check USB connection
- Verify device with `lsusb`
- Check for driver conflicts in dmesg

### WiFi Connection Issues
- Check signal strength: `iwlist scan`
- Review WiFi logs: `wifilog`
- Manually test: `sudo wpa_supplicant -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf`

### Upload Failures
- Test connection: `python3 data-uploader.py test`
- Check logs: `uploadlog`
- Verify network connectivity: `ping boatwizards.com`

### Service Issues
```bash
# Restart all services
satstop && sleep 5 && satstart

# Check individual service
systemctl status wifi-hunter.service
```

## File Structure

```
/home/pi/satpi/
├── wifi-hunter.sh           # WiFi connection script
├── network-monitor.sh       # Network monitoring
├── satdump-capture.sh       # Satellite capture
├── data-uploader.py         # Upload client
├── install-deps.sh          # Dependency installer
└── setup-services.sh        # Service setup

/boot/
├── config.txt               # Pi configuration
├── cmdline.txt              # Boot parameters
└── wpa_supplicant.conf      # WiFi configuration

/etc/systemd/system/
├── wifi-hunter.service
├── network-monitor.service
├── satdump-capture.service
└── data-uploader.service
```

## License

This project is designed for defensive satellite monitoring and research purposes only.