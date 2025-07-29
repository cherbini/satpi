#!/usr/bin/env python3
"""
Simple satellite data uploader that works with existing boatwizards.com setup
Uses basic file operations and creates summary reports
"""

import os
import sys
import time
import logging
from datetime import datetime
from pathlib import Path

# Configuration
LOG_FILE = os.path.expanduser("~/simple-uploader.log")
UPLOAD_QUEUE = "/tmp/upload-queue"
DATA_DIR = os.path.expanduser("~/sat-data")
REPORT_DIR = os.path.join(DATA_DIR, "reports")

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

class SimpleSatelliteUploader:
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

    def create_data_summary(self, filepath, satellite_name, capture_time, file_type):
        """Create a summary report of captured data"""
        try:
            os.makedirs(REPORT_DIR, exist_ok=True)
            
            file_stat = os.stat(filepath)
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            
            # Create summary report
            report_file = os.path.join(REPORT_DIR, f"{satellite_name}_{timestamp}_report.txt")
            
            with open(report_file, 'w') as f:
                f.write(f"SatPi Capture Report\\n")
                f.write(f"===================\\n\\n")
                f.write(f"Device ID: {self.device_id}\\n")
                f.write(f"Satellite: {satellite_name}\\n")
                f.write(f"Capture Time: {capture_time}\\n")
                f.write(f"File Type: {file_type}\\n")
                f.write(f"File Path: {filepath}\\n")
                f.write(f"File Size: {file_stat.st_size:,} bytes ({file_stat.st_size/1024/1024:.1f} MB)\\n")
                f.write(f"Modified: {datetime.fromtimestamp(file_stat.st_mtime)}\\n")
                f.write(f"Report Generated: {datetime.now()}\\n")
                
                # Add satellite-specific info
                if "GOES" in satellite_name:
                    f.write(f"\\nGOES Satellite Details:\\n")
                    f.write(f"- Frequency: 1686.6 MHz (L-band)\\n")
                    f.write(f"- Type: Geostationary weather satellite\\n")
                    f.write(f"- Hardware: 1690MHz Antenna + Sawbird+ LNA + GOES Filter\\n")
                else:
                    f.write(f"\\nWeather Satellite Details:\\n")
                    f.write(f"- Type: LEO polar orbiting satellite\\n")
                    f.write(f"- Hardware: VHF weather satellite antenna\\n")
            
            logger.info(f"📋 Created data summary: {report_file}")
            return report_file
            
        except Exception as e:
            logger.error(f"Failed to create summary: {e}")
            return None

    def process_raw_data(self, filepath, satellite_name):
        """Process raw data to create basic analysis"""
        try:
            # Simple data analysis
            file_size = os.path.getsize(filepath)
            
            # Read a small sample for basic analysis
            with open(filepath, 'rb') as f:
                sample = f.read(min(1024, file_size))
            
            # Basic signal analysis
            if sample:
                avg_value = sum(sample) / len(sample)
                max_value = max(sample)
                min_value = min(sample)
                
                analysis = {
                    "sample_size": len(sample),
                    "average_amplitude": avg_value,
                    "max_amplitude": max_value,
                    "min_amplitude": min_value,
                    "dynamic_range": max_value - min_value
                }
                
                logger.info(f"📊 Signal analysis - Avg: {avg_value:.1f}, Range: {max_value-min_value}")
                return analysis
            
        except Exception as e:
            logger.error(f"Processing failed: {e}")
            
        return None

    def cleanup_old_data(self):
        """Clean up old data files to manage disk space"""
        try:
            cutoff_time = time.time() - (48 * 60 * 60)  # 48 hours
            
            for filepath in Path(DATA_DIR).glob("*.raw"):
                if filepath.stat().st_mtime < cutoff_time:
                    if filepath.stat().st_size > 100 * 1024 * 1024:  # Only remove files > 100MB
                        filepath.unlink()
                        logger.info(f"🗑️ Cleaned up old file: {filepath}")
                        
        except Exception as e:
            logger.error(f"Cleanup error: {e}")

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
                    
                    # Create summary report
                    report_file = self.create_data_summary(filepath, satellite_name, capture_time, file_type)
                    
                    # Process raw data for analysis
                    analysis = self.process_raw_data(filepath, satellite_name)
                    
                    # For now, just log success (actual upload would happen here)
                    logger.info(f"✅ Processed {satellite_name} data successfully")
                    processed_count += 1
                    
                    # Keep large raw files for now, but remove from queue
                    if os.path.getsize(filepath) > 500 * 1024 * 1024:  # > 500MB
                        logger.info(f"📁 Keeping large raw file: {filepath}")
                    
                except Exception as e:
                    logger.error(f"Error processing queue entry '{line}': {e}")
                    remaining_lines.append(line)
            
            # Write back remaining items
            with open(UPLOAD_QUEUE, 'w') as f:
                f.writelines(line + '\\n' for line in remaining_lines)
            
            if processed_count > 0:
                logger.info(f"🎉 Processed {processed_count} files successfully")
                
        except Exception as e:
            logger.error(f"Error processing upload queue: {e}")

    def run_daemon(self):
        """Run as daemon, continuously processing capture data"""
        logger.info(f"🚀 Simple Satellite Data Processor started (Device: {self.device_id})")
        
        while True:
            try:
                self.process_upload_queue()
                self.cleanup_old_data()
                time.sleep(60)  # Check every minute
            except KeyboardInterrupt:
                logger.info("🛑 Daemon stopped by user")
                break
            except Exception as e:
                logger.error(f"💥 Daemon error: {e}")
                time.sleep(60)

def main():
    processor = SimpleSatelliteUploader()
    
    if len(sys.argv) > 1:
        command = sys.argv[1]
        
        if command == "daemon":
            processor.run_daemon()
        elif command == "process":
            processor.process_upload_queue()
        elif command == "cleanup":
            processor.cleanup_old_data()
        else:
            print("Usage: simple-satellite-uploader.py [daemon|process|cleanup]")
            sys.exit(1)
    else:
        # Default: process queue once
        processor.process_upload_queue()

if __name__ == "__main__":
    main()