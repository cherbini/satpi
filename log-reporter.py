#!/usr/bin/env python3
"""
Log reporter for SatPi system
Collects and sends system logs to boatwizards.com for web viewing
"""

import os
import sys
import json
import time
import requests
import subprocess
import logging
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
DEFAULT_CONFIG = {
    "log_server": {
        "base_url": "https://boatwizards.com/satellite", 
        "log_endpoint": "/api-logs.php",
        "api_key": "satpi-logs",
        "timeout": 60
    },
    "collection": {
        "max_lines": 1000,
        "services": [
            "satdump-capture.service",
            "data-uploader.service"
        ],
        "log_files": [
            "/var/log/satdump.log",
            "/var/log/data-uploader.log"
        ],
        "include_system": True
    }
}

CONFIG_FILE = os.path.expanduser("~/satpi/server-config.json")
LOG_FILE = os.path.expanduser("~/satpi/log-reporter.log")

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

class LogReporter:
    def __init__(self):
        self.config = self.load_config()
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'SatPi-LogReporter/1.0',
            'X-API-Key': self.config["log_server"]["api_key"],
            'Content-Type': 'application/json'
        })
        self.device_id = self.get_device_id()
        self.log_url = self.config["log_server"]["base_url"] + self.config["log_server"]["log_endpoint"]
        
    def load_config(self):
        """Load configuration from file with defaults"""
        config = DEFAULT_CONFIG.copy()
        
        try:
            if os.path.exists(CONFIG_FILE):
                with open(CONFIG_FILE, 'r') as f:
                    file_config = json.load(f)
                
                # Merge configuration
                for section, settings in file_config.items():
                    if section in config:
                        config[section].update(settings)
                    else:
                        config[section] = settings
                logger.info(f"Loaded configuration from {CONFIG_FILE}")
        except Exception as e:
            logger.warning(f"Could not load config file {CONFIG_FILE}: {e}")
        
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

    def get_systemd_logs(self, service_name, lines=100):
        """Get logs from systemd journal for a service"""
        try:
            cmd = [
                'journalctl',
                '-u', service_name,
                '--no-pager',
                '--output=json',
                '-n', str(lines)
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                # Parse JSON lines
                log_entries = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        try:
                            entry = json.loads(line)
                            log_entries.append({
                                'timestamp': entry.get('__REALTIME_TIMESTAMP', ''),
                                'message': entry.get('MESSAGE', ''),
                                'priority': entry.get('PRIORITY', '6'),
                                'unit': entry.get('_SYSTEMD_UNIT', service_name)
                            })
                        except json.JSONDecodeError:
                            continue
                return log_entries
            else:
                logger.warning(f"Failed to get logs for {service_name}: {result.stderr}")
                return []
        except Exception as e:
            logger.error(f"Error getting systemd logs for {service_name}: {e}")
            return []

    def get_file_logs(self, log_file, lines=100):
        """Get logs from a file"""
        try:
            if not os.path.exists(log_file):
                return []
                
            cmd = ['tail', '-n', str(lines), log_file]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                log_entries = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        log_entries.append({
                            'timestamp': datetime.now().isoformat(),
                            'message': line,
                            'source': log_file,
                            'priority': '6'
                        })
                return log_entries
            else:
                logger.warning(f"Failed to read {log_file}: {result.stderr}")
                return []
        except Exception as e:
            logger.error(f"Error reading log file {log_file}: {e}")
            return []

    def get_system_status(self):
        """Get system status information"""
        try:
            status = {}
            
            # System uptime
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = float(f.read().split()[0])
                status['uptime'] = str(timedelta(seconds=int(uptime_seconds)))
            
            # Memory usage
            with open('/proc/meminfo', 'r') as f:
                meminfo = {}
                for line in f:
                    key, value = line.split(':')
                    meminfo[key.strip()] = value.strip()
                
                total_mem = int(meminfo['MemTotal'].split()[0])
                free_mem = int(meminfo['MemFree'].split()[0])
                status['memory_usage_percent'] = int((total_mem - free_mem) / total_mem * 100)
            
            # Disk usage
            result = subprocess.run(['df', '-h', '/'], capture_output=True, text=True)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                if len(lines) > 1:
                    parts = lines[1].split()
                    status['disk_usage'] = parts[4]  # Usage percentage
            
            # CPU temperature (Pi specific)
            try:
                with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                    temp = int(f.read().strip()) / 1000
                    status['cpu_temp_c'] = round(temp, 1)
            except:
                pass
            
            # Service status
            services_status = {}
            for service in self.config["collection"]["services"]:
                try:
                    result = subprocess.run(['systemctl', 'is-active', service], 
                                          capture_output=True, text=True)
                    services_status[service] = result.stdout.strip()
                except:
                    services_status[service] = "unknown"
            
            status['services'] = services_status
            
            return status
        except Exception as e:
            logger.error(f"Error getting system status: {e}")
            return {}

    def collect_logs(self):
        """Collect all logs and system information"""
        try:
            log_data = {
                'device_id': self.device_id,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'system_status': self.get_system_status(),
                'logs': {}
            }
            
            max_lines = self.config["collection"]["max_lines"]
            
            # Collect systemd service logs
            for service in self.config["collection"]["services"]:
                logger.info(f"Collecting logs for service: {service}")
                logs = self.get_systemd_logs(service, max_lines)
                log_data['logs'][service] = logs
            
            # Collect file logs
            for log_file in self.config["collection"]["log_files"]:
                logger.info(f"Collecting logs from file: {log_file}")
                logs = self.get_file_logs(log_file, max_lines)
                if logs:
                    log_data['logs'][os.path.basename(log_file)] = logs
            
            return log_data
        except Exception as e:
            logger.error(f"Error collecting logs: {e}")
            return None

    def send_logs(self, log_data):
        """Send logs to server"""
        try:
            logger.info(f"Sending logs to {self.log_url}")
            
            response = self.session.post(
                self.log_url,
                json=log_data,
                timeout=self.config["log_server"]["timeout"]
            )
            
            if response.status_code == 200:
                logger.info("Logs sent successfully")
                return True
            else:
                logger.error(f"Failed to send logs: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Network error sending logs: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error sending logs: {e}")
            return False

    def run_once(self):
        """Collect and send logs once"""
        logger.info("Starting log collection...")
        
        log_data = self.collect_logs()
        if not log_data:
            logger.error("Failed to collect logs")
            return False
        
        return self.send_logs(log_data)

    def run_daemon(self, interval=300):  # 5 minutes default
        """Run as daemon, continuously collecting and sending logs"""
        logger.info(f"Log reporter daemon started (Device ID: {self.device_id})")
        logger.info(f"Reporting interval: {interval} seconds")
        
        while True:
            try:
                self.run_once()
                time.sleep(interval)
            except KeyboardInterrupt:
                logger.info("Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"Daemon error: {e}")
                time.sleep(60)  # Wait a minute before retrying

def main():
    reporter = LogReporter()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "once":
            if reporter.run_once():
                print("Log collection successful")
                sys.exit(0)
            else:
                print("Log collection failed")
                sys.exit(1)
                
        elif command == "daemon":
            interval = int(sys.argv[2]) if len(sys.argv) > 2 else 300
            reporter.run_daemon(interval)
            
        else:
            print("Usage: log-reporter.py [once|daemon [interval_seconds]]")
            sys.exit(1)
    else:
        # Default: run once
        reporter.run_once()

if __name__ == "__main__":
    main()