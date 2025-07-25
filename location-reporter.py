#!/usr/bin/env python3
"""
SatPi Location Reporter and Notification System
Reports device location, IP, and status to remote server and via email
"""

import os
import sys
import json
import time
import requests
import smtplib
import logging
import socket
import subprocess
from datetime import datetime, timedelta
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path

# Default configuration
CONFIG_FILE = "/home/pi/satpi/server-config.json"
STATUS_FILE = "/tmp/satpi-status.json"
LAST_REPORT_FILE = "/tmp/last-location-report"
LOG_FILE = "/var/log/location-reporter.log"

DEFAULT_CONFIG = {
    "upload_server": {
        "base_url": "https://boatwizards.com/satellite",
        "location_endpoint": "/location"
    },
    "notification": {
        "email": "johncherbini@hotmail.com"
    }
}

# Email credentials (will be set via environment or config)
EMAIL_USER = os.environ.get('SATPI_EMAIL_USER', 'satpi.notifications@outlook.com')
EMAIL_PASS = os.environ.get('SATPI_EMAIL_PASS', '')

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class LocationReporter:
    def __init__(self):
        self.config = self.load_config()
        self.device_id = self.get_device_id()
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'SatPi-LocationReporter/1.0',
            'Content-Type': 'application/json'
        })
        
        # Set up URLs from config
        self.report_url = self.config["upload_server"]["base_url"] + self.config["upload_server"]["location_endpoint"]
        self.notification_email = self.config["notification"]["email"]

    def load_config(self):
        """Load configuration from file or environment, with defaults"""
        config = DEFAULT_CONFIG.copy()
        
        # Try to load from config file
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    file_config = json.load(f)
                
                # Deep merge configuration
                for section, settings in file_config.items():
                    if section in config:
                        config[section].update(settings)
                    else:
                        config[section] = settings
                logger.info(f"Loaded configuration from {CONFIG_FILE}")
        except Exception as e:
            logger.warning(f"Could not load config file {CONFIG_FILE}: {e}")
        
        # Override with environment variables if set
        env_base_url = os.environ.get('SATPI_UPLOAD_URL')
        if env_base_url:
            config["upload_server"]["base_url"] = env_base_url
            logger.info(f"Using upload URL from environment: {env_base_url}")
        
        env_email = os.environ.get('SATPI_NOTIFICATION_EMAIL')
        if env_email:
            config["notification"]["email"] = env_email
            logger.info(f"Using notification email from environment: {env_email}")
        
        return config

    def get_device_id(self):
        """Generate unique device ID"""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Serial'):
                        serial = line.split(':')[1].strip()
                        return f"satpi-{serial[-8:]}"
        except:
            pass
        
        try:
            mac = subprocess.check_output(['cat', '/sys/class/net/wlan0/address']).decode().strip()
            return f"satpi-{mac.replace(':', '')[-8:]}"
        except:
            return f"satpi-{int(time.time()) % 100000000}"

    def get_public_ip_info(self):
        """Get public IP and geolocation information"""
        ip_services = [
            "http://ip-api.com/json/",
            "https://ipapi.co/json/",
            "https://api.ipify.org?format=json"
        ]
        
        for service in ip_services:
            try:
                response = self.session.get(service, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    
                    # Normalize data from different services
                    ip_info = {
                        "ip": data.get("query") or data.get("ip"),
                        "city": data.get("city"),
                        "region": data.get("regionName") or data.get("region"),
                        "country": data.get("country"),
                        "lat": data.get("lat"),
                        "lon": data.get("lon"),
                        "isp": data.get("isp"),
                        "org": data.get("org"),
                        "timezone": data.get("timezone"),
                        "service_used": service
                    }
                    
                    if ip_info["ip"]:
                        logger.info(f"Got IP info from {service}: {ip_info['ip']}")
                        return ip_info
                        
            except Exception as e:
                logger.warning(f"Failed to get IP info from {service}: {e}")
                continue
        
        return {"ip": None, "error": "All IP services failed"}

    def get_local_network_info(self):
        """Get local network information"""
        try:
            # Get WiFi SSID
            ssid_result = subprocess.run(['iwgetid', '-r'], 
                                       capture_output=True, text=True, timeout=5)
            ssid = ssid_result.stdout.strip() if ssid_result.returncode == 0 else "Unknown"
            
            # Get signal strength
            signal_result = subprocess.run(['iwconfig', 'wlan0'], 
                                         capture_output=True, text=True, timeout=5)
            signal_strength = "Unknown"
            if signal_result.returncode == 0:
                for line in signal_result.stdout.split('\n'):
                    if 'Signal level' in line:
                        signal_strength = line.split('Signal level=')[1].split()[0]
                        break
            
            # Get local IP
            local_ip = subprocess.check_output(['hostname', '-I']).decode().strip().split()[0]
            
            # Get gateway
            gateway_result = subprocess.run(['ip', 'route', 'show', 'default'], 
                                          capture_output=True, text=True)
            gateway = "Unknown"
            if gateway_result.returncode == 0:
                parts = gateway_result.stdout.split()
                if len(parts) > 2:
                    gateway = parts[2]
            
            return {
                "ssid": ssid,
                "signal_strength": signal_strength,
                "local_ip": local_ip,
                "gateway": gateway
            }
            
        except Exception as e:
            logger.error(f"Error getting local network info: {e}")
            return {"error": str(e)}

    def get_system_status(self):
        """Get system status information"""
        try:
            # System uptime
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
                uptime_str = str(timedelta(seconds=int(uptime_seconds)))
            
            # Memory usage
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
                mem_total = int([line for line in meminfo.split('\n') if 'MemTotal' in line][0].split()[1])
                mem_free = int([line for line in meminfo.split('\n') if 'MemAvailable' in line][0].split()[1])
                mem_used_percent = int((1 - mem_free / mem_total) * 100)
            
            # Disk usage
            disk_result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
            disk_usage = "Unknown"
            if disk_result.returncode == 0:
                lines = disk_result.stdout.strip().split('\n')
                if len(lines) > 1:
                    disk_usage = lines[1].split()[4]  # Usage percentage
            
            # CPU temperature
            try:
                with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                    temp_millidegrees = int(f.read().strip())
                    cpu_temp = f"{temp_millidegrees / 1000:.1f}°C"
            except:
                cpu_temp = "Unknown"
            
            # Service status
            services = ['wifi-hunter', 'satdump-capture', 'data-uploader', 'network-monitor']
            service_status = {}
            
            for service in services:
                try:
                    result = subprocess.run(['systemctl', 'is-active', f'{service}.service'], 
                                          capture_output=True, text=True)
                    service_status[service] = result.stdout.strip()
                except:
                    service_status[service] = "unknown"
            
            # Data capture stats
            data_dir = Path("/home/pi/sat-data")
            total_files = 0
            total_size = 0
            if data_dir.exists():
                for file_path in data_dir.rglob("*"):
                    if file_path.is_file():
                        total_files += 1
                        total_size += file_path.stat().st_size
            
            return {
                "uptime": uptime_str,
                "memory_used_percent": mem_used_percent,
                "disk_usage": disk_usage,
                "cpu_temperature": cpu_temp,
                "services": service_status,
                "data_files": total_files,
                "data_size_mb": round(total_size / (1024 * 1024), 2)
            }
            
        except Exception as e:
            logger.error(f"Error getting system status: {e}")
            return {"error": str(e)}

    def generate_status_report(self):
        """Generate comprehensive status report"""
        timestamp = datetime.utcnow().isoformat() + "Z"
        
        report = {
            "device_id": self.device_id,
            "timestamp": timestamp,
            "public_ip": self.get_public_ip_info(),
            "local_network": self.get_local_network_info(),
            "system_status": self.get_system_status()
        }
        
        # Save status to file
        with open(STATUS_FILE, 'w') as f:
            json.dump(report, f, indent=2)
        
        return report

    def send_status_to_server(self, report):
        """Send status report to remote server"""
        try:
            response = self.session.post(self.report_url, json=report, timeout=30)
            if response.status_code in [200, 201]:
                logger.info("Status report sent to server successfully")
                return True
            else:
                logger.error(f"Server returned {response.status_code}: {response.text}")
                return False
        except Exception as e:
            logger.error(f"Failed to send status to server: {e}")
            return False

    def format_email_report(self, report):
        """Format status report for email"""
        public_ip = report["public_ip"]
        local_net = report["local_network"]
        system = report["system_status"]
        
        subject = f"SatPi Daily Report - {self.device_id} - SYSTEM READY"
        
        # Get service health for status indicator
        services = system.get('services', {})
        all_services_ok = all(status == 'active' for status in services.values())
        status_indicator = "🟢 OPERATIONAL" if all_services_ok else "🟡 PARTIAL" if any(status == 'active' for status in services.values()) else "🔴 DOWN"
        
        body = f"""
═══════════════════════════════════════════════════
           SatPi SATELLITE CAPTURE SYSTEM
              Device Status & Usage Guide
═══════════════════════════════════════════════════

DEVICE STATUS: {status_indicator}
Device ID: {self.device_id}
Report Time: {report['timestamp']}

📍 CURRENT LOCATION & NETWORK:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Public IP: {public_ip.get('ip', 'Unknown')}
Location: {public_ip.get('city', 'Unknown')}, {public_ip.get('region', 'Unknown')}, {public_ip.get('country', 'Unknown')}
ISP: {public_ip.get('isp', 'Unknown')}
GPS Coordinates: {public_ip.get('lat', 'N/A')}, {public_ip.get('lon', 'N/A')}

Connected WiFi: {local_net.get('ssid', 'Unknown')}
Signal Strength: {local_net.get('signal_strength', 'Unknown')}
Local IP: {local_net.get('local_ip', 'Unknown')}
Router Gateway: {local_net.get('gateway', 'Unknown')}

🖥️ SYSTEM HEALTH:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Uptime: {system.get('uptime', 'Unknown')}
Memory Usage: {system.get('memory_used_percent', 'Unknown')}%
Disk Usage: {system.get('disk_usage', 'Unknown')}
CPU Temperature: {system.get('cpu_temperature', 'Unknown')}

📡 SATELLITE CAPTURE STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Files Captured: {system.get('data_files', 0)}
Data Storage: {system.get('data_size_mb', 0)} MB
Upload Server: {self.config["upload_server"]["base_url"]}

⚙️ SERVICE STATUS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WiFi Hunter: {services.get('wifi-hunter', 'unknown').upper()}
Satellite Capture: {services.get('satdump-capture', 'unknown').upper()}
Data Uploader: {services.get('data-uploader', 'unknown').upper()}
Network Monitor: {services.get('network-monitor', 'unknown').upper()}

🔧 HOW TO ACCESS YOUR SATPI DEVICE:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
If you can access your router/network:
  ssh pi@{local_net.get('local_ip', 'N/A')}

If device has public IP (requires port forwarding):
  ssh pi@{public_ip.get('ip', 'N/A')}
  (Configure router to forward port 22 to device)

Default SSH password: raspberry (CHANGE THIS!)

📊 MONITORING COMMANDS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Once connected via SSH, use these commands:

Service Status:
  satstatus          # Check all service status
  satstart           # Start all services
  satstop            # Stop all services

View Logs:
  satlog             # Satellite capture logs
  wifilog            # WiFi connection logs
  netlog             # Network monitor logs
  uploadlog          # Data upload logs

Manual Operations:
  # Test satellite capture (10 seconds)
  /home/pi/satpi/satdump-capture.sh test
  
  # Capture specific satellite (600 seconds)
  /home/pi/satpi/satdump-capture.sh capture NOAA-18 600
  
  # Test upload connection
  python3 /home/pi/satpi/data-uploader.py test
  
  # Test email notifications
  python3 /home/pi/satpi/location-reporter.py email send

⚙️ CONFIGURATION:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Change Upload Server:
  sudo /home/pi/satpi/configure-server.sh

Setup Email Notifications:
  sudo /home/pi/satpi/email-setup.sh

Configure Dynamic DNS:
  /home/pi/satpi/dynamic-dns.sh setup

Add WiFi Networks:
  sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
  sudo systemctl restart wpa_supplicant

🛠️ TROUBLESHOOTING:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
No Satellite Data:
  • Check RTL-SDR USB connection
  • Verify antenna is connected and positioned correctly
  • Check logs: tail -f /var/log/satdump.log

No WiFi Connection:
  • Check available networks: sudo iwlist scan
  • Restart WiFi: sudo systemctl restart wifi-hunter
  • Check logs: tail -f /var/log/wifi-hunter.log

Upload Issues:
  • Test connection: python3 /home/pi/satpi/data-uploader.py test
  • Check server config: /home/pi/satpi/configure-server.sh show
  • Check logs: tail -f /var/log/data-uploader.log

📡 SUPPORTED SATELLITES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• NOAA-15 (137.620 MHz) - Weather satellite
• NOAA-18 (137.912 MHz) - Weather satellite  
• NOAA-19 (137.100 MHz) - Weather satellite
• METEOR-M2 (137.100 MHz) - Russian weather satellite
• ISS (145.800 MHz) - International Space Station

📋 SYSTEM FILES:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Configuration: /home/pi/satpi/server-config.json
Data Directory: /home/pi/sat-data/
Log Directory: /var/log/
Documentation: /home/pi/satpi/README.md

🔒 SECURITY REMINDERS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
• Change default SSH password: passwd
• Consider SSH key authentication
• Update system regularly: sudo apt update && sudo apt upgrade
• Monitor this email for unexpected location changes

═══════════════════════════════════════════════════
This automated report confirms your SatPi device is 
online and operational. Next report in 24 hours.

Questions? Check the documentation at:
https://github.com/cherbini/satpi
═══════════════════════════════════════════════════
"""
        return subject, body

    def send_email_notification(self, subject, body):
        """Send email notification"""
        if not EMAIL_PASS:
            logger.warning("No email password configured, skipping email notification")
            return False
        
        try:
            msg = MIMEMultipart()
            msg['From'] = EMAIL_USER
            msg['To'] = self.notification_email
            msg['Subject'] = subject
            
            msg.attach(MIMEText(body, 'plain'))
            
            server = smtplib.SMTP(SMTP_SERVER, SMTP_PORT)
            server.starttls()
            server.login(EMAIL_USER, EMAIL_PASS)
            server.send_message(msg)
            server.quit()
            
            logger.info(f"Email notification sent to {self.notification_email}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email: {e}")
            return False

    def should_send_daily_report(self):
        """Check if daily report should be sent"""
        try:
            if not os.path.exists(LAST_REPORT_FILE):
                return True
                
            with open(LAST_REPORT_FILE, 'r') as f:
                last_report_time = datetime.fromisoformat(f.read().strip())
            
            # Send report if more than 23 hours have passed
            return (datetime.utcnow() - last_report_time).total_seconds() > 23 * 3600
            
        except Exception as e:
            logger.error(f"Error checking last report time: {e}")
            return True

    def should_send_online_notification(self):
        """Check if we should send an 'online' notification (IP change or first time online)"""
        online_file = "/tmp/last-online-report"
        current_ip = self.get_public_ip_info().get('ip')
        
        if not current_ip:
            return False
            
        try:
            if not os.path.exists(online_file):
                # First time online
                with open(online_file, 'w') as f:
                    f.write(f"{current_ip}|{datetime.utcnow().isoformat()}")
                return True
                
            with open(online_file, 'r') as f:
                last_ip, last_time_str = f.read().strip().split('|')
                last_time = datetime.fromisoformat(last_time_str)
            
            # Send if IP changed or been more than 6 hours since last online notification
            if (current_ip != last_ip or 
                (datetime.utcnow() - last_time).total_seconds() > 6 * 3600):
                
                with open(online_file, 'w') as f:
                    f.write(f"{current_ip}|{datetime.utcnow().isoformat()}")
                return True
                
        except Exception as e:
            logger.error(f"Error checking online status: {e}")
            return True
            
        return False

    def mark_report_sent(self):
        """Mark that daily report was sent"""
        try:
            with open(LAST_REPORT_FILE, 'w') as f:
                f.write(datetime.utcnow().isoformat())
        except Exception as e:
            logger.error(f"Error marking report sent: {e}")

    def run_report_cycle(self, force_email=False):
        """Run complete reporting cycle"""
        logger.info("Starting location report cycle")
        
        # Generate status report
        report = self.generate_status_report()
        
        # Send to server
        self.send_status_to_server(report)
        
        # Check if we should send email notifications
        send_daily = force_email or self.should_send_daily_report()
        send_online = self.should_send_online_notification()
        
        if send_daily or send_online:
            subject, body = self.format_email_report(report)
            
            # Modify subject for different notification types
            if send_online and not send_daily:
                subject = subject.replace("Daily Report", "ONLINE NOTIFICATION")
                body = f"""🔔 DEVICE ONLINE ALERT 🔔

Your SatPi device is now available on the internet!

{body}

※ This notification was sent because your device came online 
or changed IP addresses. Daily reports will continue as scheduled.
"""
            
            if self.send_email_notification(subject, body):
                if send_daily:
                    self.mark_report_sent()
                logger.info("Email notification sent successfully")
        else:
            logger.info("No email notifications due at this time")
        
        logger.info("Location report cycle completed")

    def run_daemon(self):
        """Run as daemon, sending reports periodically"""
        logger.info(f"Location Reporter daemon started (Device ID: {self.device_id})")
        
        while True:
            try:
                self.run_report_cycle()
                # Check every hour, but only send email once per day
                time.sleep(3600)
            except KeyboardInterrupt:
                logger.info("Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"Daemon error: {e}")
                time.sleep(300)  # Wait 5 minutes on error

def main():
    reporter = LocationReporter()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "report":
            reporter.run_report_cycle(force_email=True)
        elif command == "test":
            report = reporter.generate_status_report()
            print(json.dumps(report, indent=2))
        elif command == "email":
            report = reporter.generate_status_report()
            subject, body = reporter.format_email_report(report)
            print(f"Subject: {subject}")
            print(f"Body:\n{body}")
            if len(sys.argv) > 2 and sys.argv[2] == "send":
                reporter.send_email_notification(subject, body)
        elif command == "daemon":
            reporter.run_daemon()
        else:
            print("Usage: location-reporter.py [report|test|email [send]|daemon]")
            sys.exit(1)
    else:
        # Default: run single report cycle
        reporter.run_report_cycle()

if __name__ == "__main__":
    main()