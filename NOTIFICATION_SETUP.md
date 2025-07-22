# SatPi Notification System Setup

## Overview

Your SatPi device will automatically send daily status reports to `johncherbini@hotmail.com` containing:
- Device location (public IP and geolocation)
- Network information (WiFi network, signal strength)
- System status (uptime, temperature, memory usage)
- Satellite capture statistics
- Service health status

## Initial Setup

After flashing and booting your SatPi device:

### 1. Configure Email Notifications

Connect to your device via SSH and run:
```bash
sudo /home/pi/satpi/email-setup.sh
```

Choose option 1 (Outlook/Hotmail) and enter credentials for the sending email account.

### 2. Optional: Dynamic DNS Setup

For remote access to your device, configure dynamic DNS:
```bash
/home/pi/satpi/dynamic-dns.sh setup
```

Edit the configuration file:
```bash
nano /home/pi/satpi/ddns-config.json
```

Example configuration for No-IP:
```json
{
    "enabled": true,
    "providers": [
        {
            "name": "noip",
            "enabled": true,
            "hostname": "your-satpi.ddns.net",
            "username": "your-noip-username",
            "password": "your-noip-password"
        }
    ]
}
```

## Email Report Contents

Daily reports include:

### Location & Network
- Public IP address and ISP
- Geographic location (city, region, country)
- WiFi network name and signal strength
- Local IP and gateway information

### System Status
- Device uptime
- CPU temperature
- Memory and disk usage
- All service status (WiFi hunter, satellite capture, etc.)

### Satellite Data
- Number of captured files
- Total data size
- Recent capture activity

### Remote Access Information
- Instructions for SSH access if public IP is available
- Port forwarding guidance

## Testing Notifications

Test the email system:
```bash
# Test email configuration
python3 /home/pi/satpi/location-reporter.py test

# Send a test email immediately
python3 /home/pi/satpi/location-reporter.py email send

# Generate and view a status report
python3 /home/pi/satpi/location-reporter.py report
```

## Service Management

The notification system runs as systemd services:

```bash
# Check location reporter status
systemctl status location-reporter.service

# Check dynamic DNS status
systemctl status dynamic-dns.timer

# View recent logs
journalctl -u location-reporter.service -f
journalctl -u dynamic-dns.service -f
```

## Troubleshooting

### Email Not Sending
1. Check email credentials: `cat /home/pi/satpi/email-credentials`
2. Test email setup: `/home/pi/satpi/email-setup.sh test`
3. Check service logs: `journalctl -u location-reporter.service`

### Dynamic DNS Not Working
1. Check configuration: `/home/pi/satpi/dynamic-dns.sh test`
2. Test manual update: `/home/pi/satpi/dynamic-dns.sh force`
3. Verify provider credentials in `/home/pi/satpi/ddns-config.json`

### No Location Reports
1. Check internet connectivity: `ping google.com`
2. Verify service is running: `systemctl status location-reporter.service`
3. Check logs: `tail -f /var/log/location-reporter.log`

## Security Notes

- Email credentials are stored in `/home/pi/satpi/email-credentials` with restricted permissions
- Consider using app passwords instead of regular passwords for email accounts
- Dynamic DNS passwords are stored in plain text - use a dedicated account
- SSH access is enabled by default - consider changing default passwords

## Report Schedule

- **Location reports**: Sent to server every hour
- **Email notifications**: Sent once per day (when IP changes or 24 hours since last email)
- **Dynamic DNS updates**: Checked every 15 minutes via systemd timer

Reports are sent even if the device moves between different networks, ensuring you always know where your SatPi device is located.