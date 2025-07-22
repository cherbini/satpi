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

- NOAA-15 (137.620 MHz)
- NOAA-18 (137.912 MHz)  
- NOAA-19 (137.100 MHz)
- METEOR-M2 (137.100 MHz)
- ISS (145.800 MHz)

## Hardware Requirements

- Raspberry Pi 3 (ARMhf)
- RTL-SDR USB dongle
- Appropriate antenna for satellite reception
- SD card (16GB minimum recommended)

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

### Upload Settings
Modify `data-uploader.py` to change:
- Upload URL
- API credentials
- File size limits
- Retry settings

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

# Capture specific satellite
./satdump-capture.sh capture NOAA-18 600

# Test upload connection
python3 data-uploader.py test

# Manual upload
python3 data-uploader.py upload /path/to/file.raw NOAA-18
```

## Services

All components run as systemd services:
- `wifi-hunter.service` - WiFi connection management
- `network-monitor.service` - Network quality monitoring
- `satdump-capture.service` - Satellite data capture
- `data-uploader.service` - Data upload daemon

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