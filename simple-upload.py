#!/usr/bin/env python3
"""
Simple uploader that works without custom server endpoints
Uses basic HTTP file upload to existing web directory
"""

import os
import sys
import requests
import json
from datetime import datetime

def upload_via_basic_http(filepath, satellite_name, device_id):
    """Upload file using basic HTTP to existing web structure"""
    
    # Generate filename based on satellite and timestamp
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    filename = f"{satellite_name}_{device_id}_{timestamp}.raw"
    
    # Target URL for raw files directory
    upload_url = "https://boatwizards.com/satellite/raw/"
    
    try:
        with open(filepath, 'rb') as f:
            files = {'file': (filename, f, 'application/octet-stream')}
            
            # Try basic HTTP POST
            response = requests.post(upload_url, files=files, timeout=30)
            
            if response.status_code == 200:
                print(f"✅ Upload successful: {filename}")
                return True
            else:
                print(f"❌ Upload failed: {response.status_code}")
                print(f"Response: {response.text[:200]}")
                return False
                
    except Exception as e:
        print(f"❌ Upload error: {e}")
        return False

def main():
    if len(sys.argv) != 4:
        print("Usage: simple-upload.py <filepath> <satellite_name> <device_id>")
        sys.exit(1)
    
    filepath = sys.argv[1]
    satellite_name = sys.argv[2] 
    device_id = sys.argv[3]
    
    if not os.path.exists(filepath):
        print(f"❌ File not found: {filepath}")
        sys.exit(1)
    
    print(f"📡 Uploading {satellite_name} data from {device_id}")
    print(f"📁 File: {filepath}")
    
    if upload_via_basic_http(filepath, satellite_name, device_id):
        print("🎉 Upload complete!")
        sys.exit(0)
    else:
        print("💥 Upload failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()