#!/usr/bin/env python3
"""
Data uploader for SatPi system
Uploads captured satellite data to boatwizards.com/satellite
"""

import os
import sys
import json
import time
import requests
import hashlib
import logging
from pathlib import Path
from datetime import datetime
import subprocess

# Default configuration - can be overridden by config file or environment
DEFAULT_CONFIG = {
    "upload_server": {
        "base_url": "https://boatwizards.com/satellite",
        "upload_endpoint": "/upload",
        "status_endpoint": "/status",
        "api_key": "satpi-client",
        "timeout": 300,
        "max_file_size_mb": 100,
        "retry_attempts": 5,
        "retry_delay_seconds": 300
    },
    "notification": {
        "email": "johncherbini@hotmail.com"
    },
    "system": {
        "data_directory": "/home/pi/sat-data",
        "cleanup_after_upload": True
    }
}

CONFIG_FILE = "/home/pi/satpi/server-config.json"
UPLOAD_QUEUE = "/tmp/upload-queue"
LOG_FILE = "/var/log/data-uploader.log"

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

class SatelliteDataUploader:
    def __init__(self):
        self.config = self.load_config()
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'SatPi-Uploader/1.0',
            'X-API-Key': self.config["upload_server"]["api_key"]
        })
        self.device_id = self.get_device_id()
        
        # Set up URLs from config
        self.upload_url = self.config["upload_server"]["base_url"] + self.config["upload_server"]["upload_endpoint"]
        self.status_url = self.config["upload_server"]["base_url"] + self.config["upload_server"]["status_endpoint"]
        self.max_file_size = self.config["upload_server"]["max_file_size_mb"] * 1024 * 1024
        self.timeout = self.config["upload_server"]["timeout"]
        self.retry_delay = self.config["upload_server"]["retry_delay_seconds"]
        self.max_retries = self.config["upload_server"]["retry_attempts"]
        self.data_dir = self.config["system"]["data_directory"]
        
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
            # Parse full URL or just base
            if '/upload' in env_base_url:
                config["upload_server"]["base_url"] = env_base_url.replace('/upload', '')
            else:
                config["upload_server"]["base_url"] = env_base_url
            logger.info(f"Using upload URL from environment: {env_base_url}")
        
        env_api_key = os.environ.get('SATPI_API_KEY')
        if env_api_key:
            config["upload_server"]["api_key"] = env_api_key
            logger.info("Using API key from environment")
        
        env_email = os.environ.get('SATPI_NOTIFICATION_EMAIL')
        if env_email:
            config["notification"]["email"] = env_email
            logger.info(f"Using notification email from environment: {env_email}")
        
        return config
        
    def get_device_id(self):
        """Generate unique device ID based on Raspberry Pi serial"""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Serial'):
                        serial = line.split(':')[1].strip()
                        return f"satpi-{serial[-8:]}"
        except:
            pass
        
        # Fallback to MAC address
        try:
            mac = subprocess.check_output(['cat', '/sys/class/net/wlan0/address']).decode().strip()
            return f"satpi-{mac.replace(':', '')[-8:]}"
        except:
            return f"satpi-{int(time.time()) % 100000000}"

    def get_location_data(self):
        """Get GPS location if available, otherwise estimate from IP"""
        location = {"lat": None, "lon": None, "source": "unknown"}
        
        # Try to get GPS data (if GPS module is connected)
        try:
            # This would be GPS module specific
            pass
        except:
            pass
            
        # Fallback to IP geolocation
        if location["lat"] is None:
            try:
                response = self.session.get("http://ip-api.com/json/", timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if data.get("status") == "success":
                        location.update({
                            "lat": data.get("lat"),
                            "lon": data.get("lon"),
                            "source": "ip"
                        })
            except Exception as e:
                logger.warning(f"IP geolocation failed: {e}")
        
        return location

    def calculate_file_hash(self, filepath):
        """Calculate SHA-256 hash of file"""
        sha256_hash = hashlib.sha256()
        try:
            with open(filepath, "rb") as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    sha256_hash.update(chunk)
            return sha256_hash.hexdigest()
        except Exception as e:
            logger.error(f"Error calculating hash for {filepath}: {e}")
            return None

    def prepare_metadata(self, filepath, satellite_name, capture_time):
        """Prepare metadata for upload"""
        try:
            stat = os.stat(filepath)
            location = self.get_location_data()
            
            metadata = {
                "device_id": self.device_id,
                "satellite": satellite_name,
                "capture_time": capture_time,
                "file_size": stat.st_size,
                "file_hash": self.calculate_file_hash(filepath),
                "upload_time": datetime.utcnow().isoformat() + "Z",
                "location": location,
                "frequency": self.get_satellite_frequency(satellite_name),
                "sample_rate": 2048000,  # Default sample rate
                "device_info": {
                    "type": "raspberry_pi_3",
                    "rtlsdr": True,
                    "software": "satpi-v1.0"
                }
            }
            return metadata
        except Exception as e:
            logger.error(f"Error preparing metadata: {e}")
            return None

    def get_satellite_frequency(self, satellite_name):
        """Get frequency for satellite"""
        frequencies = {
            "NOAA-15": 137.620,
            "NOAA-18": 137.912,
            "NOAA-19": 137.100,
            "METEOR-M2": 137.100,
            "ISS": 145.800
        }
        return frequencies.get(satellite_name, 137.500)

    def upload_file(self, filepath, metadata):
        """Upload file to server"""
        try:
            # Check file size
            if metadata["file_size"] > self.max_file_size:
                logger.warning(f"File too large: {filepath} ({metadata['file_size']} bytes)")
                return False

            files = {
                'file': ('data.raw', open(filepath, 'rb'), 'application/octet-stream'),
                'metadata': ('metadata.json', json.dumps(metadata), 'application/json')
            }
            
            logger.info(f"Uploading {filepath} ({metadata['file_size']} bytes) to {self.upload_url}")
            
            response = self.session.post(
                self.upload_url,
                files=files,
                timeout=self.timeout
            )
            
            files['file'][1].close()  # Close file handle
            
            if response.status_code == 200:
                result = response.json()
                logger.info(f"Upload successful: {result.get('message', 'OK')}")
                return True
            else:
                logger.error(f"Upload failed: {response.status_code} - {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            logger.error(f"Network error during upload: {e}")
            return False
        except Exception as e:
            logger.error(f"Unexpected error during upload: {e}")
            return False

    def process_upload_queue(self):
        """Process files in upload queue"""
        if not os.path.exists(UPLOAD_QUEUE):
            logger.debug("No upload queue found")
            return

        try:
            with open(UPLOAD_QUEUE, 'r') as f:
                lines = f.readlines()

            remaining_lines = []
            
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                    
                try:
                    parts = line.split('|')
                    if len(parts) != 3:
                        logger.warning(f"Invalid queue entry: {line}")
                        continue
                        
                    filepath, satellite_name, capture_time = parts
                    
                    if not os.path.exists(filepath):
                        logger.warning(f"File not found, skipping: {filepath}")
                        continue
                    
                    metadata = self.prepare_metadata(filepath, satellite_name, capture_time)
                    if not metadata:
                        logger.error(f"Failed to prepare metadata for {filepath}")
                        remaining_lines.append(line)
                        continue
                    
                    if self.upload_file(filepath, metadata):
                        logger.info(f"Successfully uploaded {filepath}")
                        # Delete local file after successful upload if configured
                        if self.config["system"].get("cleanup_after_upload", True):
                            try:
                                os.remove(filepath)
                                logger.info(f"Deleted local file: {filepath}")
                            except Exception as e:
                                logger.warning(f"Could not delete {filepath}: {e}")
                    else:
                        logger.error(f"Failed to upload {filepath}")
                        remaining_lines.append(line)
                        
                except Exception as e:
                    logger.error(f"Error processing queue entry '{line}': {e}")
                    remaining_lines.append(line)
            
            # Write back remaining items
            with open(UPLOAD_QUEUE, 'w') as f:
                f.writelines(line + '\n' for line in remaining_lines)
                
        except Exception as e:
            logger.error(f"Error processing upload queue: {e}")

    def test_connection(self):
        """Test connection to upload server"""
        try:
            # Test endpoint
            response = self.session.get(self.status_url, timeout=10)
            
            if response.status_code == 200:
                logger.info("Connection to upload server: OK")
                return True
            else:
                logger.warning(f"Server returned: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"Connection test failed: {e}")
            return False

    def run_daemon(self):
        """Run as daemon, continuously processing upload queue"""
        logger.info(f"SatPi Data Uploader daemon started (Device ID: {self.device_id})")
        
        while True:
            try:
                self.process_upload_queue()
                time.sleep(60)  # Check every minute
            except KeyboardInterrupt:
                logger.info("Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"Daemon error: {e}")
                time.sleep(self.retry_delay)

def main():
    uploader = SatelliteDataUploader()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "test":
            if uploader.test_connection():
                print("Connection test: PASSED")
                sys.exit(0)
            else:
                print("Connection test: FAILED")
                sys.exit(1)
                
        elif command == "upload":
            if len(sys.argv) != 4:
                print("Usage: data-uploader.py upload <filepath> <satellite_name>")
                sys.exit(1)
            filepath = sys.argv[2]
            satellite_name = sys.argv[3]
            capture_time = datetime.now().isoformat()
            
            metadata = uploader.prepare_metadata(filepath, satellite_name, capture_time)
            if metadata and uploader.upload_file(filepath, metadata):
                print("Upload successful")
                sys.exit(0)
            else:
                print("Upload failed")
                sys.exit(1)
                
        elif command == "daemon":
            uploader.run_daemon()
        else:
            print("Usage: data-uploader.py [test|upload <file> <satellite>|daemon]")
            sys.exit(1)
    else:
        # Default: process queue once
        uploader.process_upload_queue()

if __name__ == "__main__":
    main()