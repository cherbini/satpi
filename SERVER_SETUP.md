# Custom Server Setup for SatPi

SatPi now supports flexible server configuration, allowing you to use your own server instead of the default `boatwizards.com/satellite` endpoint.

## Configuration Methods

### 1. Configuration File (Recommended)

Edit or create `/home/pi/satpi/server-config.json`:

```json
{
  "upload_server": {
    "base_url": "https://your-server.com/api",
    "upload_endpoint": "/upload",
    "status_endpoint": "/status", 
    "location_endpoint": "/location",
    "api_key": "your-api-key",
    "timeout": 300,
    "max_file_size_mb": 100,
    "retry_attempts": 5,
    "retry_delay_seconds": 300
  },
  "notification": {
    "email": "your-email@example.com",
    "device_name": "SatPi Device",
    "report_frequency_hours": 24
  },
  "system": {
    "data_directory": "/home/pi/sat-data",
    "log_directory": "/var/log",
    "cleanup_after_upload": true,
    "max_local_storage_gb": 10
  }
}
```

### 2. Environment Variables

Override specific settings with environment variables:

```bash
export SATPI_UPLOAD_URL="https://your-server.com/api"
export SATPI_API_KEY="your-api-key"
export SATPI_NOTIFICATION_EMAIL="your-email@example.com"
```

### 3. Interactive Configuration

Use the configuration script:

```bash
# Interactive setup
sudo /home/pi/satpi/configure-server.sh

# Direct setup
sudo /home/pi/satpi/configure-server.sh setup
```

## Server Endpoints

Your server should implement these endpoints:

### POST `/upload`
- **Purpose**: Receives satellite data files
- **Content**: Multipart form with `file` (binary data) and `metadata` (JSON)
- **Response**: `200 OK` with JSON `{"status": "success", "message": "Upload successful"}`

### GET `/status` 
- **Purpose**: Health check endpoint
- **Response**: `200 OK` indicates server is available

### POST `/location`
- **Purpose**: Receives device location and status reports
- **Content**: JSON with device information, location, system status
- **Response**: `200 OK` or `201 Created`

## Example Server Implementation

### Simple Node.js Server

```javascript
const express = require('express');
const multer = require('multer');
const app = express();

const upload = multer({ dest: 'uploads/' });

// Health check
app.get('/status', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// File upload
app.post('/upload', upload.single('file'), (req, res) => {
  const metadata = JSON.parse(req.body.metadata);
  console.log('Received file:', req.file.filename);
  console.log('Metadata:', metadata);
  res.json({ status: 'success', message: 'Upload successful' });
});

// Location reporting
app.post('/location', express.json(), (req, res) => {
  console.log('Device report:', req.body);
  res.json({ status: 'received' });
});

app.listen(3000, () => {
  console.log('SatPi server listening on port 3000');
});
```

### Python Flask Server

```python
from flask import Flask, request, jsonify
import json
import os

app = Flask(__name__)

@app.route('/status')
def status():
    return jsonify({"status": "ok", "timestamp": "2024-01-01T00:00:00Z"})

@app.route('/upload', methods=['POST'])
def upload():
    if 'file' not in request.files:
        return jsonify({"error": "No file provided"}), 400
    
    file = request.files['file']
    metadata = json.loads(request.form['metadata'])
    
    # Save file
    filename = f"satdata_{metadata['device_id']}_{metadata['capture_time']}.raw"
    file.save(os.path.join('uploads', filename))
    
    print(f"Received: {filename}")
    print(f"Metadata: {metadata}")
    
    return jsonify({"status": "success", "message": "Upload successful"})

@app.route('/location', methods=['POST'])
def location():
    data = request.json
    print(f"Device report from {data['device_id']}: {data}")
    return jsonify({"status": "received"})

if __name__ == '__main__':
    os.makedirs('uploads', exist_ok=True)
    app.run(host='0.0.0.0', port=5000)
```

## Configuration Management

### Test Configuration
```bash
/home/pi/satpi/configure-server.sh test
```

### Show Current Settings
```bash
/home/pi/satpi/configure-server.sh show
```

### Backup and Restore
```bash
# Configuration is automatically backed up before changes
/home/pi/satpi/configure-server.sh restore
```

### Apply Changes
After changing configuration, restart services:
```bash
/home/pi/satpi/configure-server.sh restart
```

## Metadata Format

Files uploaded to your server include this metadata:

```json
{
  "device_id": "satpi-abc123",
  "satellite": "NOAA-18",
  "capture_time": "2024-01-01T12:00:00Z",
  "file_size": 1048576,
  "file_hash": "sha256_hash_here",
  "upload_time": "2024-01-01T12:05:00Z",
  "location": {
    "lat": 37.7749,
    "lon": -122.4194,
    "source": "ip"
  },
  "frequency": 137.912,
  "sample_rate": 2048000,
  "device_info": {
    "type": "raspberry_pi_3", 
    "rtlsdr": true,
    "software": "satpi-v1.0"
  }
}
```

## Security Considerations

- Use HTTPS for your server endpoints
- Implement API key authentication
- Validate uploaded file sizes and types
- Consider rate limiting to prevent abuse
- Store API keys securely (not in plain text files)

## Troubleshooting

### Connection Issues
```bash
# Test server connectivity
curl https://your-server.com/api/status

# Check SatPi logs
tail -f /var/log/data-uploader.log
tail -f /var/log/location-reporter.log
```

### Configuration Issues
```bash
# Validate JSON
jq . /home/pi/satpi/server-config.json

# Test uploader with config
python3 /home/pi/satpi/data-uploader.py test
```

### Service Issues
```bash
# Check service status
systemctl status data-uploader.service
systemctl status location-reporter.service

# Restart services
sudo systemctl restart data-uploader.service location-reporter.service
```