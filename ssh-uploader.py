#!/usr/bin/env python3
"""
SSH-based uploader for SatPi system
Uses SCP to upload files directly to boatwizards.com
"""

import os
import sys
import time
import logging
import subprocess
from datetime import datetime
from pathlib import Path

# Configuration
LOG_FILE = os.path.expanduser("~/ssh-uploader.log")
UPLOAD_QUEUE = "/tmp/upload-queue"
DATA_DIR = os.path.expanduser("~/sat-data")
REPORT_DIR = os.path.join(DATA_DIR, "reports")

# Server configuration
SERVER_HOST = "root@boatwizards.com"
SERVER_PATHS = {
    'raw': '/var/www/boatwizards.com/html/satellite/raw/',
    'images': '/var/www/boatwizards.com/html/satellite/images/', 
    'reports': '/var/www/boatwizards.com/html/satellite/reports/'
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

class SSHSatelliteUploader:
    def __init__(self):
        self.device_id = self.get_device_id()
        
    def get_device_id(self):
        """Generate unique device ID"""
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if line.startswith('Serial'):
                        serial = line.split(':')[1].strip()
                        return f"pi-{serial[-6:]}"
        except:
            pass
        return f"pi-{int(time.time()) % 1000000}"

    def get_upload_path(self, filepath):
        """Determine server upload path based on file type"""
        file_ext = os.path.splitext(filepath)[1].lower()
        
        if file_ext in ['.jpg', '.jpeg', '.png', '.gif']:
            return SERVER_PATHS['images']
        elif file_ext in ['.txt', '.json', '.log']:
            return SERVER_PATHS['reports']
        else:
            return SERVER_PATHS['raw']

    def upload_file_ssh(self, filepath, satellite_name, capture_time, file_type):
        """Upload file using SCP"""
        try:
            if not os.path.exists(filepath):
                logger.error(f"File not found: {filepath}")
                return False
                
            # Get file info
            file_size = os.path.getsize(filepath)
            if file_size > 1000 * 1024 * 1024:  # 1GB limit
                logger.warning(f"File too large: {filepath} ({file_size} bytes)")
                return False
                
            # Determine upload path
            upload_path = self.get_upload_path(filepath)
            
            # Generate server filename
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            file_ext = os.path.splitext(filepath)[1]
            base_name = os.path.splitext(os.path.basename(filepath))[0]
            server_filename = f"{base_name}_{self.device_id}_{timestamp}{file_ext}"
            
            # Upload using SCP
            server_path = f"{SERVER_HOST}:{upload_path}{server_filename}"
            
            logger.info(f"📤 Uploading {os.path.basename(filepath)} to {upload_path}")
            
            result = subprocess.run([
                'scp', '-o', 'StrictHostKeyChecking=no',
                '-o', 'ConnectTimeout=60',
                '-o', 'ServerAliveInterval=30',
                '-o', 'ServerAliveCountMax=10',
                filepath, server_path
            ], capture_output=True, text=True, timeout=1800)
            
            if result.returncode == 0:
                logger.info(f"✅ Upload successful: {server_filename} ({file_size} bytes)")
                
                # Create latest symlink for images
                if 'images' in upload_path:
                    symlink_cmd = f"cd {upload_path} && ln -sf {server_filename} latest_{satellite_name}{file_ext}"
                    subprocess.run(['ssh', SERVER_HOST, symlink_cmd], 
                                 capture_output=True, timeout=30)
                
                return True
            else:
                logger.error(f"❌ SCP upload failed: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error(f"❌ Upload timeout for {filepath}")
            return False
        except Exception as e:
            logger.error(f"❌ Upload error: {e}")
            return False

    def test_connection(self):
        """Test SSH connection to server"""
        try:
            result = subprocess.run([
                'ssh', '-o', 'StrictHostKeyChecking=no',
                '-o', 'ConnectTimeout=10',
                SERVER_HOST, 'echo "SSH connection test successful"'
            ], capture_output=True, text=True, timeout=15)
            
            if result.returncode == 0:
                logger.info("✅ SSH connection test: PASSED")
                return True
            else:
                logger.error(f"❌ SSH connection test failed: {result.stderr}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Connection test error: {e}")
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
            processed_count = 0
            
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
                    
                    logger.info(f"📡 Processing {satellite_name} data: {os.path.basename(filepath)}")
                    
                    # Attempt upload with retry
                    success = False
                    for attempt in range(2):  # 2 attempts
                        if self.upload_file_ssh(filepath, satellite_name, capture_time, file_type):
                            success = True
                            break
                        else:
                            if attempt < 1:
                                logger.info("Retrying upload in 30 seconds...")
                                time.sleep(30)
                    
                    if success:
                        processed_count += 1
                        # Delete large raw files after successful upload
                        if filepath.endswith('.raw') and os.path.getsize(filepath) > 100 * 1024 * 1024:
                            try:
                                os.remove(filepath)
                                logger.info(f"🗑️ Deleted large raw file: {filepath}")
                            except Exception as e:
                                logger.warning(f"Could not delete {filepath}: {e}")
                    else:
                        logger.error(f"❌ Failed to upload {filepath}")
                        remaining_lines.append(line)
                        
                except Exception as e:
                    logger.error(f"Error processing queue entry '{line}': {e}")
                    remaining_lines.append(line)
            
            # Write back remaining items
            with open(UPLOAD_QUEUE, 'w') as f:
                f.writelines(line + '\\n' for line in remaining_lines)
            
            if processed_count > 0:
                logger.info(f"🎉 Successfully processed {processed_count} files")
                
        except Exception as e:
            logger.error(f"Error processing upload queue: {e}")

    def run_daemon(self):
        """Run as daemon, continuously processing upload queue"""
        logger.info(f"🚀 SSH Satellite Uploader daemon started (Device: {self.device_id})")
        
        while True:
            try:
                self.process_upload_queue()
                time.sleep(60)  # Check every minute
            except KeyboardInterrupt:
                logger.info("🛑 Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"💥 Daemon error: {e}")
                time.sleep(60)

def main():
    uploader = SSHSatelliteUploader()
    
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
                print("Usage: ssh-uploader.py upload <filepath> <satellite_name>")
                sys.exit(1)
            filepath = sys.argv[2]
            satellite_name = sys.argv[3]
            capture_time = datetime.now().isoformat()
            
            if uploader.upload_file_ssh(filepath, satellite_name, capture_time, "MANUAL"):
                print("✅ Upload successful")
                sys.exit(0)
            else:
                print("❌ Upload failed")
                sys.exit(1)
                
        elif command == "daemon":
            uploader.run_daemon()
            
        else:
            print("Usage: ssh-uploader.py [test|upload <file> <satellite>|daemon]")
            sys.exit(1)
    else:
        # Default: process queue once
        uploader.process_upload_queue()

if __name__ == "__main__":
    main()