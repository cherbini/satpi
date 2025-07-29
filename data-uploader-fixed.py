#!/usr/bin/env python3
"""
Enhanced data uploader for SatPi system
Uploads satellite images and data to boatwizards.com/satellite via web interface
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
import mimetypes
from urllib.parse import urljoin

# Configuration
UPLOAD_QUEUE = "/tmp/upload-queue"
LOG_FILE = "/var/log/data-uploader.log"
DATA_DIR = os.path.expanduser("~/sat-data")
IMAGES_DIR = os.path.join(DATA_DIR, "images")

# Server configuration
SERVER_CONFIG = {
    "base_url": "https://boatwizards.com/satellite/",
    "upload_methods": [
        "direct_ftp",     # Try FTP first if available  
        "web_form",       # Web form upload
        "simple_post"     # Simple HTTP POST
    ],
    "timeout": 300,
    "max_file_size_mb": 50,  # Smaller size for images
    "retry_attempts": 3,
    "retry_delay_seconds": 60
}

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
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'SatPi-Enhanced-Uploader/2.0'
        })
        self.device_id = self.get_device_id()
        self.max_file_size = SERVER_CONFIG["max_file_size_mb"] * 1024 * 1024
        
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
        
        try:
            mac = subprocess.check_output(['cat', '/sys/class/net/wlan0/address']).decode().strip()
            return f"satpi-{mac.replace(':', '')[-8:]}"
        except:
            return f"satpi-{int(time.time()) % 100000000}"

    def get_file_info(self, filepath):
        """Get comprehensive file information"""
        try:
            stat = os.stat(filepath)
            mime_type, _ = mimetypes.guess_type(filepath)
            
            return {
                "size": stat.st_size,
                "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(),
                "mime_type": mime_type or "application/octet-stream",
                "hash": self.calculate_file_hash(filepath),
                "is_image": filepath.lower().endswith(('.png', '.jpg', '.jpeg', '.gif', '.bmp'))
            }
        except Exception as e:
            logger.error(f"Error getting file info for {filepath}: {e}")
            return None

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

    def upload_via_direct_web(self, filepath, filename, satellite_name, file_type):
        """Upload file directly to web directory using various methods"""
        
        file_info = self.get_file_info(filepath)
        if not file_info:
            return False
            
        if file_info["size"] > self.max_file_size:
            logger.warning(f"File too large: {filepath} ({file_info['size']} bytes)")
            return False

        # Method 1: Try to upload to images directory if it's an image
        if file_info["is_image"]:
            upload_url = urljoin(SERVER_CONFIG["base_url"], "images/")
            success = self._try_web_upload(filepath, filename, upload_url, file_info)
            if success:
                return True

        # Method 2: Try to upload to raw data directory
        upload_url = urljoin(SERVER_CONFIG["base_url"], "raw/")
        success = self._try_web_upload(filepath, filename, upload_url, file_info)
        if success:
            return True

        # Method 3: Try root directory upload
        upload_url = SERVER_CONFIG["base_url"]
        success = self._try_web_upload(filepath, filename, upload_url, file_info)
        if success:
            return True

        return False

    def _try_web_upload(self, filepath, filename, upload_url, file_info):
        """Try uploading to a specific URL endpoint"""
        try:
            logger.info(f"Attempting upload to: {upload_url}")
            
            with open(filepath, 'rb') as f:
                files = {'file': (filename, f, file_info["mime_type"])}
                
                # Try with form data
                data = {
                    'device_id': self.device_id,
                    'timestamp': datetime.now().isoformat(),
                    'file_hash': file_info["hash"],
                    'file_size': file_info["size"]
                }
                
                response = self.session.post(
                    upload_url,
                    files=files,
                    data=data,
                    timeout=SERVER_CONFIG["timeout"]
                )
                
                if response.status_code in [200, 201, 202]:
                    logger.info(f"Upload successful to {upload_url}: {filename}")
                    return True
                else:
                    logger.debug(f"Upload failed to {upload_url}: {response.status_code} - {response.text[:200]}")
                    return False
                    
        except requests.exceptions.RequestException as e:
            logger.debug(f"Network error uploading to {upload_url}: {e}")
            return False
        except Exception as e:
            logger.debug(f"Unexpected error uploading to {upload_url}: {e}")
            return False

    def upload_via_ftp(self, filepath, filename, satellite_name, file_type):
        """Upload via FTP if available"""
        try:
            import ftplib
            
            # Try common FTP configurations
            ftp_configs = [
                {"host": "boatwizards.com", "user": "anonymous", "passwd": ""},
                {"host": "ftp.boatwizards.com", "user": "anonymous", "passwd": ""}
            ]
            
            for config in ftp_configs:
                try:
                    ftp = ftplib.FTP()
                    ftp.connect(config["host"], timeout=30)
                    ftp.login(config["user"], config["passwd"])
                    
                    # Try to change to satellite directory
                    try:
                        ftp.cwd('/satellite/images' if filename.lower().endswith(('.png', '.jpg', '.jpeg')) else '/satellite/raw')
                    except:
                        ftp.cwd('/satellite')
                    
                    # Upload file
                    with open(filepath, 'rb') as f:
                        ftp.storbinary(f'STOR {filename}', f)
                    
                    ftp.quit()
                    logger.info(f"FTP upload successful: {filename}")
                    return True
                    
                except Exception as e:
                    logger.debug(f"FTP upload failed with {config['host']}: {e}")
                    continue
                    
        except ImportError:
            logger.debug("FTP not available (ftplib not found)")
        except Exception as e:
            logger.debug(f"FTP upload error: {e}")
            
        return False

    def upload_file(self, filepath, satellite_name, capture_time, file_type):
        """Upload file using multiple methods"""
        if not os.path.exists(filepath):
            logger.error(f"File not found: {filepath}")
            return False
            
        # Generate appropriate filename
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        file_ext = os.path.splitext(filepath)[1]
        filename = f"{satellite_name}_{self.device_id}_{timestamp}{file_ext}"
        
        logger.info(f"Uploading {filepath} as {filename} (Type: {file_type})")
        
        # Try different upload methods in order
        upload_methods = [
            ("FTP", self.upload_via_ftp),
            ("Web", self.upload_via_direct_web)
        ]
        
        for method_name, method_func in upload_methods:
            try:
                logger.debug(f"Trying {method_name} upload...")
                if method_func(filepath, filename, satellite_name, file_type):
                    logger.info(f"✅ Upload successful via {method_name}: {filename}")
                    return True
                else:
                    logger.debug(f"❌ {method_name} upload failed")
            except Exception as e:
                logger.debug(f"❌ {method_name} upload error: {e}")
                
        logger.error(f"❌ All upload methods failed for: {filepath}")
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
                    if len(parts) < 3:
                        logger.warning(f"Invalid queue entry: {line}")
                        continue
                        
                    filepath, satellite_name, capture_time = parts[:3]
                    file_type = parts[3] if len(parts) > 3 else "RAW"
                    
                    if not os.path.exists(filepath):
                        logger.warning(f"File not found, skipping: {filepath}")
                        continue
                    
                    # Attempt upload with retries
                    success = False
                    for attempt in range(SERVER_CONFIG["retry_attempts"]):
                        if self.upload_file(filepath, satellite_name, capture_time, file_type):
                            success = True
                            break
                        else:
                            if attempt < SERVER_CONFIG["retry_attempts"] - 1:
                                logger.info(f"Retrying upload in {SERVER_CONFIG['retry_delay_seconds']} seconds...")
                                time.sleep(SERVER_CONFIG["retry_delay_seconds"])
                    
                    if success:
                        logger.info(f"✅ Successfully uploaded {filepath}")
                        # Delete local file after successful upload if it's not an image
                        if not filepath.lower().endswith(('.png', '.jpg', '.jpeg')):
                            try:
                                os.remove(filepath)
                                logger.info(f"🗑️ Deleted uploaded file: {filepath}")
                            except Exception as e:
                                logger.warning(f"Could not delete {filepath}: {e}")
                    else:
                        logger.error(f"❌ Failed to upload {filepath} after all attempts")
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
            response = self.session.get(SERVER_CONFIG["base_url"], timeout=10)
            
            if response.status_code == 200:
                logger.info("✅ Connection to upload server: OK")
                return True
            else:
                logger.warning(f"⚠️ Server returned: {response.status_code}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Connection test failed: {e}")
            return False

    def cleanup_old_files(self):
        """Clean up old files to save disk space"""
        try:
            # Remove raw files older than 24 hours
            cutoff_time = time.time() - (24 * 60 * 60)
            
            for directory in [DATA_DIR, IMAGES_DIR]:
                if not os.path.exists(directory):
                    continue
                    
                for filename in os.listdir(directory):
                    filepath = os.path.join(directory, filename)
                    
                    if os.path.isfile(filepath):
                        file_mtime = os.path.getmtime(filepath)
                        
                        # Remove old raw files (but keep images longer)
                        if (filename.endswith('.raw') and file_mtime < cutoff_time) or \
                           (os.path.getsize(filepath) > 1000 * 1024 * 1024):  # Remove files > 1GB
                            try:
                                os.remove(filepath)
                                logger.info(f"🗑️ Cleaned up old file: {filepath}")
                            except Exception as e:
                                logger.warning(f"Could not remove {filepath}: {e}")
                                
        except Exception as e:
            logger.error(f"Cleanup error: {e}")

    def run_daemon(self):
        """Run as daemon, continuously processing upload queue"""
        logger.info(f"🚀 SatPi Enhanced Uploader daemon started (Device ID: {self.device_id})")
        
        while True:
            try:
                self.process_upload_queue()
                self.cleanup_old_files()
                time.sleep(60)  # Check every minute
            except KeyboardInterrupt:
                logger.info("🛑 Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"💥 Daemon error: {e}")
                time.sleep(SERVER_CONFIG["retry_delay_seconds"])

def main():
    uploader = SatelliteDataUploader()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "test":
            if uploader.test_connection():
                print("✅ Connection test: PASSED")
                sys.exit(0)
            else:
                print("❌ Connection test: FAILED")
                sys.exit(1)
                
        elif command == "upload":
            if len(sys.argv) != 4:
                print("Usage: data-uploader.py upload <filepath> <satellite_name>")
                sys.exit(1)
            filepath = sys.argv[2]
            satellite_name = sys.argv[3]
            capture_time = datetime.now().isoformat()
            
            if uploader.upload_file(filepath, satellite_name, capture_time, "MANUAL"):
                print("✅ Upload successful")
                sys.exit(0)
            else:
                print("❌ Upload failed")
                sys.exit(1)
                
        elif command == "daemon":
            uploader.run_daemon()
            
        elif command == "cleanup":
            uploader.cleanup_old_files()
            
        else:
            print("Usage: data-uploader.py [test|upload <file> <satellite>|daemon|cleanup]")
            sys.exit(1)
    else:
        # Default: process queue once
        uploader.process_upload_queue()

if __name__ == "__main__":
    main()