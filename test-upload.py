#!/usr/bin/env python3
"""
Test upload system to verify boatwizards.com endpoints
"""

import requests
import json
import tempfile
import os
from datetime import datetime

# Test configuration
TEST_CONFIG = {
    "base_url": "https://boatwizards.com/satellite",
    "upload_endpoint": "/upload",
    "status_endpoint": "/status",
    "api_key": "satpi-client"
}

def test_endpoints():
    """Test all endpoints to see what's available"""
    session = requests.Session()
    session.headers.update({
        'User-Agent': 'SatPi-Uploader-Test/1.0',
        'X-API-Key': TEST_CONFIG["api_key"]
    })
    
    # Test base URL
    print("Testing base URL...")
    try:
        response = session.get(TEST_CONFIG["base_url"])
        print(f"Base URL: {response.status_code} - OK" if response.status_code == 200 else f"Base URL: {response.status_code} - Error")
    except Exception as e:
        print(f"Base URL: Error - {e}")
    
    # Test status endpoint
    print("Testing status endpoint...")
    status_url = TEST_CONFIG["base_url"] + TEST_CONFIG["status_endpoint"]
    try:
        response = session.get(status_url)
        print(f"Status endpoint: {response.status_code} - {'OK' if response.status_code == 200 else 'Not found'}")
        if response.status_code == 200:
            print(f"Status response: {response.text[:200]}...")
    except Exception as e:
        print(f"Status endpoint: Error - {e}")
    
    # Test upload endpoint
    print("Testing upload endpoint...")
    upload_url = TEST_CONFIG["base_url"] + TEST_CONFIG["upload_endpoint"]
    try:
        response = session.get(upload_url)
        print(f"Upload endpoint (GET): {response.status_code} - {'OK' if response.status_code == 200 else 'Not found/Method not allowed'}")
    except Exception as e:
        print(f"Upload endpoint: Error - {e}")
    
    # Test alternative endpoints that might exist
    print("\nTesting alternative endpoints...")
    alternatives = ['/api/upload', '/api/status', '/raw/', '/images/', '/logs/']
    for alt in alternatives:
        try:
            response = session.get(TEST_CONFIG["base_url"] + alt)
            print(f"{alt}: {response.status_code} - {'OK' if response.status_code == 200 else 'Not found'}")
        except Exception as e:
            print(f"{alt}: Error - {e}")

def test_file_upload():
    """Test actual file upload with small test file"""
    print("\nTesting file upload...")
    
    # Create a small test file
    with tempfile.NamedTemporaryFile(mode='wb', delete=False, suffix='.raw') as test_file:
        test_data = b'TEST_SATELLITE_DATA_' * 100  # Small test file
        test_file.write(test_data)
        test_file_path = test_file.name
    
    try:
        session = requests.Session()
        session.headers.update({
            'User-Agent': 'SatPi-Uploader-Test/1.0',
            'X-API-Key': TEST_CONFIG["api_key"]
        })
        
        # Prepare test metadata
        metadata = {
            "device_id": "test-device",
            "satellite": "NOAA-18",
            "satellite_type": "VHF",
            "capture_time": datetime.now().isoformat(),
            "file_size": len(test_data),
            "file_hash": "test-hash",
            "upload_time": datetime.utcnow().isoformat() + "Z",
            "location": {"lat": 37.7749, "lon": -122.4194, "source": "test"},
            "frequency": 137.912,
            "sample_rate": 2048000,
        }
        
        files = {
            'file': ('test_data.raw', open(test_file_path, 'rb'), 'application/octet-stream'),
            'metadata': ('metadata.json', json.dumps(metadata), 'application/json')
        }
        
        upload_url = TEST_CONFIG["base_url"] + TEST_CONFIG["upload_endpoint"]
        response = session.post(upload_url, files=files, timeout=30)
        
        files['file'][1].close()
        
        print(f"Upload test: {response.status_code}")
        print(f"Upload response: {response.text[:200]}...")
        
        if response.status_code == 200:
            print("✓ Upload successful!")
        else:
            print("✗ Upload failed")
            
    except Exception as e:
        print(f"Upload test error: {e}")
    finally:
        # Clean up test file
        os.unlink(test_file_path)

if __name__ == "__main__":
    print("SatPi Upload System Test")
    print("=" * 40)
    test_endpoints()
    test_file_upload()