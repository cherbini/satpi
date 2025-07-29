#!/bin/bash
# SatPi Dual WiFi Configuration Script
# Configures both built-in WiFi and external USB WiFi adapter

set -e

echo "🔧 SatPi Dual WiFi Configuration"
echo "================================"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   echo "Please run: sudo $0"
   exit 1
fi

# Identify WiFi interfaces
echo "📡 Detecting WiFi interfaces..."
WIFI_INTERFACES=($(ip link show | grep -oE 'wlan[0-9]+' | sort))

if [[ ${#WIFI_INTERFACES[@]} -eq 0 ]]; then
    echo "❌ No WiFi interfaces detected"
    exit 1
fi

echo "✅ Found ${#WIFI_INTERFACES[@]} WiFi interface(s):"
for iface in "${WIFI_INTERFACES[@]}"; do
    echo "  • $iface"
    
    # Check if interface has a driver
    if [[ -d "/sys/class/net/$iface/device/driver" ]]; then
        DRIVER=$(basename $(readlink "/sys/class/net/$iface/device/driver"))
        echo "    Driver: $DRIVER"
    fi
    
    # Check if it's USB
    if [[ -d "/sys/class/net/$iface/device" ]]; then
        USB_PATH=$(readlink "/sys/class/net/$iface/device" | grep -o "usb[0-9]" || echo "")
        if [[ -n "$USB_PATH" ]]; then
            echo "    Type: USB WiFi Adapter"
        else
            echo "    Type: Built-in WiFi"
        fi
    fi
done

echo ""

# Identify primary and secondary interfaces
PRIMARY_IFACE="${WIFI_INTERFACES[0]}"
SECONDARY_IFACE=""

if [[ ${#WIFI_INTERFACES[@]} -gt 1 ]]; then
    SECONDARY_IFACE="${WIFI_INTERFACES[1]}"
    echo "🎯 Configuration:"
    echo "  Primary WiFi: $PRIMARY_IFACE (main connection)"
    echo "  Secondary WiFi: $SECONDARY_IFACE (backup/scanning)"
else
    echo "🎯 Configuration:"
    echo "  Single WiFi: $PRIMARY_IFACE"
fi
echo ""

# Update wpa_supplicant configuration
echo "📝 Updating wpa_supplicant configuration..."

# Backup existing config
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup

# Create enhanced wpa_supplicant.conf
cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US
ap_scan=1
fast_reauth=1

# High priority networks (known good networks)
network={
    ssid="kkmi-public"
    key_mgmt=NONE
    priority=15
    scan_ssid=1
}

network={
    ssid="Wilhelmina"
    psk="INFORMATI0n!"
    priority=12
    scan_ssid=1
}

network={
    ssid="YourHomeNetwork"
    psk="your_password"
    priority=10
    scan_ssid=1
}

# Common open networks
network={
    ssid="xfinitywifi"
    key_mgmt=NONE
    priority=5
}

network={
    ssid="CableWiFi"
    key_mgmt=NONE
    priority=5
}

network={
    ssid="attwifi"
    key_mgmt=NONE
    priority=5
}

network={
    ssid="Spectrum WiFi"
    key_mgmt=NONE
    priority=5
}

# Captive portal networks
network={
    ssid="Starbucks WiFi"
    key_mgmt=NONE
    priority=3
}

network={
    ssid="McDonald's Free WiFi"
    key_mgmt=NONE
    priority=3
}

# Fallback for any open network
network={
    key_mgmt=NONE
    priority=1
    scan_ssid=1
}
EOF

echo "✅ wpa_supplicant.conf updated"

# Create enhanced WiFi hunter script
echo "🔍 Creating enhanced WiFi hunter script..."

cat > /home/johnc/satpi/wifi-hunter-dual.sh << 'EOF'
#!/bin/bash
# Enhanced WiFi hunter with dual interface support
# Supports both built-in WiFi and USB WiFi adapters

LOG_FILE="/var/log/wifi-hunter.log"
SCAN_INTERVAL=15
CONNECTION_TIMEOUT=30
MAX_RETRY_COUNT=3

# Detect available WiFi interfaces
WIFI_INTERFACES=($(ip link show | grep -oE 'wlan[0-9]+' | sort))
# Use wlan1 (USB TP-Link) as primary for external connectivity, wlan0 is for AP mode
PRIMARY_IFACE="wlan1"
SECONDARY_IFACE="wlan0"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_internet() {
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
    return $?
}

get_interface_status() {
    local iface="$1"
    if [[ -d "/sys/class/net/$iface" ]]; then
        local status=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "down")
        echo "$status"
    else
        echo "missing"
    fi
}

setup_interface() {
    local iface="$1"
    log "Setting up interface: $iface"
    
    # Bring interface up
    ip link set "$iface" up 2>/dev/null || {
        log "WARNING: Could not bring up $iface"
        return 1
    }
    
    # Kill any existing wpa_supplicant on this interface
    pkill -f "wpa_supplicant.*$iface" 2>/dev/null
    sleep 2
    
    return 0
}

scan_networks() {
    local iface="$1"
    
    # Use the specified interface for scanning
    iwlist "$iface" scan 2>/dev/null | grep -E "ESSID:|Quality=" | \
    awk 'BEGIN{ORS=""} /Quality/{quality=$0; getline; print quality " " $0 "\n"}' | \
    grep -v 'ESSID:""' | \
    sort -k2 -nr | \
    head -20
}

attempt_connection() {
    local iface="$1"
    local ssid="$2"
    local security="$3"
    
    log "Attempting connection on $iface to: $ssid"
    
    # Setup interface
    if ! setup_interface "$iface"; then
        return 1
    fi
    
    # Start wpa_supplicant on this interface
    wpa_supplicant -B -i "$iface" -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211 || {
        log "Failed to start wpa_supplicant on $iface"
        return 1
    }
    
    sleep 5
    
    # Get IP via DHCP
    dhclient "$iface" -timeout 20 || {
        log "DHCP failed on $iface"
        return 1
    }
    
    sleep 5
    
    # Check connection
    if check_internet; then
        log "Successfully connected via $iface to: $ssid"
        return 0
    else
        log "Connection failed or no internet via $iface: $ssid"
        return 1
    fi
}

main_loop() {
    log "Enhanced WiFi hunter started"
    log "Available interfaces: ${WIFI_INTERFACES[*]}"
    log "Primary: $PRIMARY_IFACE, Secondary: $SECONDARY_IFACE"
    
    while true; do
        if check_internet; then
            log "Internet connection available"
            sleep 60
            continue
        fi
        
        log "No internet connection. Scanning for networks..."
        
        # Try primary interface first
        if [[ -n "$PRIMARY_IFACE" ]] && [[ $(get_interface_status "$PRIMARY_IFACE") != "missing" ]]; then
            log "Scanning with primary interface: $PRIMARY_IFACE"
            
            networks=$(scan_networks "$PRIMARY_IFACE")
            
            if [[ -n "$networks" ]]; then
                while IFS= read -r network; do
                    if [[ -z "$network" ]]; then continue; fi
                    
                    ssid=$(echo "$network" | grep -o 'ESSID:"[^"]*"' | cut -d'"' -f2)
                    if [[ -z "$ssid" ]]; then continue; fi
                    
                    quality=$(echo "$network" | grep -o 'Quality=[0-9]*/[0-9]*' | cut -d'=' -f2)
                    
                    # Skip weak signals
                    if [[ -n "$quality" ]]; then
                        strength=$(echo "scale=0; $(echo $quality | cut -d'/' -f1) * 100 / $(echo $quality | cut -d'/' -f2)" | bc -l 2>/dev/null || echo 0)
                        if [[ $strength -lt 30 ]]; then
                            log "Skipping weak signal: $ssid ($strength%)"
                            continue
                        fi
                    fi
                    
                    # Determine security
                    security="open"
                    if echo "$network" | grep -q "Encryption key:on"; then
                        security="encrypted"
                    fi
                    
                    # Try connection
                    if attempt_connection "$PRIMARY_IFACE" "$ssid" "$security"; then
                        if check_internet; then
                            log "Connected successfully via $PRIMARY_IFACE to: $ssid"
                            break 2
                        fi
                    fi
                    
                    sleep 5
                done <<< "$networks"
            fi
        fi
        
        # Skip secondary interface (wlan0) as it's in AP mode
        log "Secondary interface ($SECONDARY_IFACE) is in AP mode - skipping"
        
        sleep "$SCAN_INTERVAL"
    done
}

# Initialize interfaces
for iface in "${WIFI_INTERFACES[@]}"; do
    setup_interface "$iface"
done

# Start main loop
main_loop
EOF

chmod +x /home/johnc/satpi/wifi-hunter-dual.sh
chown johnc:johnc /home/johnc/satpi/wifi-hunter-dual.sh

echo "✅ Enhanced WiFi hunter created"

# Create systemd service for dual WiFi
echo "🔧 Creating systemd service..."

cat > /etc/systemd/system/wifi-hunter-dual.service << EOF
[Unit]
Description=SatPi Dual WiFi Hunter Service
After=multi-user.target
Wants=network.target

[Service]
Type=simple
ExecStart=/home/johnc/satpi/wifi-hunter-dual.sh
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

# Environment
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Systemd service created"

# Configure Access Point on wlan0 (built-in WiFi)
echo "📡 Configuring Access Point on wlan0..."

# Install required packages
echo "📦 Installing required packages..."
apt update
apt install -y bc wireless-tools wpasupplicant dhcpcd5 iw hostapd dnsmasq lighttpd

# Configure hostapd for AP mode
cat > /etc/hostapd/hostapd.conf << EOF
interface=wlan0
driver=nl80211
ssid=SatPi-Config
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=satpi123
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

# Configure dnsmasq for DHCP
cat > /etc/dnsmasq.conf << EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

# Configure static IP for wlan0
cat >> /etc/dhcpcd.conf << EOF

# Static IP configuration for wlan0 (AP mode)
interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF

# Create web configuration interface
echo "🌐 Creating web configuration interface..."

# Create web directory
mkdir -p /var/www/html

# Create configuration page
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SatPi WiFi Configuration</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
            margin-bottom: 30px;
        }
        .section {
            margin-bottom: 30px;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
        }
        .section h2 {
            color: #555;
            margin-top: 0;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"], input[type="password"], select {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        button {
            background-color: #007bff;
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            margin-right: 10px;
        }
        button:hover {
            background-color: #0056b3;
        }
        .status {
            padding: 10px;
            margin-bottom: 20px;
            border-radius: 4px;
        }
        .status.success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .status.error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .status.info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
        #scanResults {
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #ddd;
            padding: 10px;
            background: #f9f9f9;
        }
        .network-item {
            padding: 5px;
            cursor: pointer;
            border-bottom: 1px solid #eee;
        }
        .network-item:hover {
            background-color: #e9ecef;
        }
        .signal-strength {
            float: right;
            font-size: 0.8em;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🛰️ SatPi WiFi Configuration</h1>
        
        <div id="status" class="status info">
            <strong>Status:</strong> Ready to configure external WiFi connection
        </div>

        <div class="section">
            <h2>📡 External WiFi Configuration (wlan1)</h2>
            <p>Configure the external USB TP-Link WiFi adapter to connect to kkmi-public or other internet networks.</p>
            
            <div class="form-group">
                <button onclick="scanNetworks()">🔍 Scan for Networks</button>
                <button onclick="refreshStatus()">🔄 Refresh Status</button>
            </div>
            
            <div id="scanResults"></div>
            
            <form id="wifiForm">
                <div class="form-group">
                    <label for="ssid">Network Name (SSID):</label>
                    <input type="text" id="ssid" name="ssid" required>
                </div>
                
                <div class="form-group">
                    <label for="security">Security Type:</label>
                    <select id="security" name="security" onchange="togglePassword()">
                        <option value="none">Open (No Password)</option>
                        <option value="wpa">WPA/WPA2 (Password Required)</option>
                    </select>
                </div>
                
                <div class="form-group" id="passwordGroup" style="display: none;">
                    <label for="password">Password:</label>
                    <input type="password" id="password" name="password">
                </div>
                
                <div class="form-group">
                    <button type="submit">💾 Save and Connect</button>
                    <button type="button" onclick="testConnection()">🧪 Test Connection</button>
                </div>
            </form>
        </div>

        <div class="section">
            <h2>📊 System Status</h2>
            <div id="systemStatus">
                <p>Loading system status...</p>
            </div>
        </div>

        <div class="section">
            <h2>🔗 Dynamic DNS Test</h2>
            <p>Test the remote connection to your SatPi system.</p>
            <button onclick="testDynamicDNS()">🌐 Test Remote Access</button>
            <div id="dnsTestResult"></div>
        </div>
    </div>

    <script>
        function togglePassword() {
            const security = document.getElementById('security').value;
            const passwordGroup = document.getElementById('passwordGroup');
            passwordGroup.style.display = security === 'wpa' ? 'block' : 'none';
        }

        function updateStatus(message, type = 'info') {
            const statusDiv = document.getElementById('status');
            statusDiv.className = `status ${type}`;
            statusDiv.innerHTML = `<strong>Status:</strong> ${message}`;
        }

        function scanNetworks() {
            updateStatus('Scanning for networks...', 'info');
            fetch('/cgi-bin/wifi-scan.sh')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('scanResults').innerHTML = data;
                    updateStatus('Network scan completed', 'success');
                })
                .catch(error => {
                    updateStatus('Error scanning networks: ' + error, 'error');
                });
        }

        function selectNetwork(ssid, security) {
            document.getElementById('ssid').value = ssid;
            document.getElementById('security').value = security;
            togglePassword();
        }

        function refreshStatus() {
            fetch('/cgi-bin/wifi-status.sh')
                .then(response => response.text())
                .then(data => {
                    document.getElementById('systemStatus').innerHTML = data;
                })
                .catch(error => {
                    document.getElementById('systemStatus').innerHTML = 'Error loading status: ' + error;
                });
        }

        function testConnection() {
            updateStatus('Testing connection...', 'info');
            fetch('/cgi-bin/wifi-test.sh')
                .then(response => response.text())
                .then(data => {
                    if (data.includes('SUCCESS')) {
                        updateStatus('Connection test successful!', 'success');
                    } else {
                        updateStatus('Connection test failed', 'error');
                    }
                })
                .catch(error => {
                    updateStatus('Error testing connection: ' + error, 'error');
                });
        }

        function testDynamicDNS() {
            const resultDiv = document.getElementById('dnsTestResult');
            resultDiv.innerHTML = '<p>Testing remote access...</p>';
            
            fetch('/cgi-bin/ddns-test.sh')
                .then(response => response.text())
                .then(data => {
                    resultDiv.innerHTML = data;
                })
                .catch(error => {
                    resultDiv.innerHTML = `<p style="color: red;">Error: ${error}</p>`;
                });
        }

        document.getElementById('wifiForm').addEventListener('submit', function(e) {
            e.preventDefault();
            
            const formData = new FormData(this);
            updateStatus('Saving WiFi configuration...', 'info');
            
            fetch('/cgi-bin/wifi-config.sh', {
                method: 'POST',
                body: formData
            })
            .then(response => response.text())
            .then(data => {
                if (data.includes('SUCCESS')) {
                    updateStatus('WiFi configuration saved successfully!', 'success');
                    setTimeout(refreshStatus, 2000);
                } else {
                    updateStatus('Failed to save configuration', 'error');
                }
            })
            .catch(error => {
                updateStatus('Error saving configuration: ' + error, 'error');
            });
        });

        // Load initial status
        refreshStatus();
    </script>
</body>
</html>
EOF

# Create CGI scripts directory
mkdir -p /var/www/cgi-bin

# WiFi scan script
cat > /var/www/cgi-bin/wifi-scan.sh << 'EOF'
#!/bin/bash
echo "Content-Type: text/html"
echo ""

# Scan for networks using wlan1 (USB TP-Link adapter)
networks=$(iwlist wlan1 scan 2>/dev/null | grep -E "ESSID:|Quality=|Encryption" | paste - - - | sort -k2 -nr)

if [[ -z "$networks" ]]; then
    echo "<p>No networks found. Make sure wlan1 is available.</p>"
    exit
fi

echo "<h3>Available Networks:</h3>"
while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    
    ssid=$(echo "$line" | grep -o 'ESSID:"[^"]*"' | cut -d'"' -f2)
    quality=$(echo "$line" | grep -o 'Quality=[0-9]*/[0-9]*' | cut -d'=' -f2)
    encryption=$(echo "$line" | grep -o 'Encryption key:[onf]*' | cut -d':' -f2)
    
    if [[ -n "$ssid" ]]; then
        security="none"
        if [[ "$encryption" == "on" ]]; then
            security="wpa"
        fi
        
        signal=""
        if [[ -n "$quality" ]]; then
            strength=$(echo "scale=0; $(echo $quality | cut -d'/' -f1) * 100 / $(echo $quality | cut -d'/' -f2)" | bc -l 2>/dev/null || echo 0)
            signal="<span class='signal-strength'>${strength}%</span>"
        fi
        
        echo "<div class='network-item' onclick=\"selectNetwork('$ssid', '$security')\">"
        echo "  📶 $ssid $signal"
        if [[ "$security" == "wpa" ]]; then
            echo " 🔒"
        fi
        echo "</div>"
    fi
done <<< "$networks"
EOF

chmod +x /var/www/cgi-bin/wifi-scan.sh

# WiFi status script
cat > /var/www/cgi-bin/wifi-status.sh << 'EOF'
#!/bin/bash
echo "Content-Type: text/html"
echo ""

echo "<h3>Network Interfaces:</h3>"
echo "<pre>"
ip addr show | grep -E "^[0-9]+:|inet "
echo "</pre>"

echo "<h3>WiFi Status:</h3>"
echo "<pre>"
iwconfig 2>/dev/null | grep -E "wlan|ESSID|Access Point"
echo "</pre>"

echo "<h3>Internet Connectivity:</h3>"
if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
    echo "<p style='color: green;'>✅ Internet connection active</p>"
else
    echo "<p style='color: red;'>❌ No internet connection</p>"
fi

echo "<h3>Active Services:</h3>"
echo "<pre>"
systemctl is-active wifi-hunter-dual.service hostapd dnsmasq 2>/dev/null || echo "Services status unknown"
echo "</pre>"
EOF

chmod +x /var/www/cgi-bin/wifi-status.sh

# WiFi configuration script
cat > /var/www/cgi-bin/wifi-config.sh << 'EOF'
#!/bin/bash
echo "Content-Type: text/html"
echo ""

# Read POST data
read -n $CONTENT_LENGTH POST_DATA

# Parse form data
ssid=$(echo "$POST_DATA" | grep -o 'ssid=[^&]*' | cut -d'=' -f2 | sed 's/%20/ /g' | sed 's/+/ /g')
password=$(echo "$POST_DATA" | grep -o 'password=[^&]*' | cut -d'=' -f2 | sed 's/%20/ /g' | sed 's/+/ /g')
security=$(echo "$POST_DATA" | grep -o 'security=[^&]*' | cut -d'=' -f2)

if [[ -z "$ssid" ]]; then
    echo "ERROR: No SSID provided"
    exit 1
fi

# Backup current config
cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.backup

# Add new network to config
if [[ "$security" == "none" ]]; then
    cat >> /etc/wpa_supplicant/wpa_supplicant.conf << CONFEOF

network={
    ssid="$ssid"
    key_mgmt=NONE
    priority=20
    scan_ssid=1
}
CONFEOF
else
    cat >> /etc/wpa_supplicant/wpa_supplicant.conf << CONFEOF

network={
    ssid="$ssid"
    psk="$password"
    priority=20
    scan_ssid=1
}
CONFEOF
fi

# Restart WiFi hunter service
systemctl restart wifi-hunter-dual.service

echo "SUCCESS: WiFi configuration updated for network: $ssid"
EOF

chmod +x /var/www/cgi-bin/wifi-config.sh

# Dynamic DNS test script
cat > /var/www/cgi-bin/ddns-test.sh << 'EOF'
#!/bin/bash
echo "Content-Type: text/html"
echo ""

echo "<h3>Dynamic DNS Test Results:</h3>"

# Get current external IP
external_ip=$(curl -s ifconfig.me || echo "Unable to determine")
echo "<p><strong>Current External IP:</strong> $external_ip</p>"

# Test dynamic DNS hostname (if configured)
if [[ -f "/home/johnc/satpi/ddns_hostname" ]]; then
    hostname=$(cat /home/johnc/satpi/ddns_hostname)
    echo "<p><strong>Configured Hostname:</strong> $hostname</p>"
    
    resolved_ip=$(dig +short "$hostname" || echo "Failed to resolve")
    echo "<p><strong>DNS Resolution:</strong> $resolved_ip</p>"
    
    if [[ "$external_ip" == "$resolved_ip" ]]; then
        echo "<p style='color: green;'>✅ Dynamic DNS is working correctly!</p>"
    else
        echo "<p style='color: orange;'>⚠️ DNS may be updating (IPs don't match)</p>"
    fi
else
    echo "<p style='color: red;'>❌ No dynamic DNS hostname configured</p>"
fi

# Test SSH connectivity (if possible)
echo "<h4>Service Status:</h4>"
if systemctl is-active --quiet ssh; then
    echo "<p>✅ SSH service is running</p>"
else
    echo "<p>❌ SSH service is not running</p>"
fi

if systemctl is-active --quiet wifi-hunter-dual; then
    echo "<p>✅ WiFi hunter service is running</p>"
else
    echo "<p>❌ WiFi hunter service is not running</p>"
fi
EOF

chmod +x /var/www/cgi-bin/ddns-test.sh

# Configure lighttpd
cat > /etc/lighttpd/lighttpd.conf << 'EOF'
server.modules = (
    "mod_indexfile",
    "mod_access",
    "mod_alias",
    "mod_redirect",
    "mod_cgi",
)

server.document-root        = "/var/www/html"
server.upload-dirs          = ( "/var/cache/lighttpd/uploads" )
server.errorlog             = "/var/log/lighttpd/error.log"
server.pid-file             = "/var/run/lighttpd.pid"
server.username             = "www-data"
server.groupname            = "www-data"
server.port                 = 80

index-file.names            = ( "index.php", "index.html", "index.lighttpd.html" )
url.access-deny             = ( "~", ".inc" )
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )

compress.cache-dir          = "/var/cache/lighttpd/compress/"
compress.filetype           = ( "application/javascript", "text/css", "text/html", "text/plain" )

# default listening port for IPv6 falls back to the IPv4 port
include_shell "/usr/share/lighttpd/use-ipv6.pl " + server.port
include_shell "/usr/share/lighttpd/create-mime.assign.pl"
include_shell "/usr/share/lighttpd/include-conf-enabled.pl"

# CGI support
cgi.assign = ( ".sh" => "/bin/bash" )
alias.url += ( "/cgi-bin/" => "/var/www/cgi-bin/" )
$HTTP["url"] =~ "^/cgi-bin/" {
    cgi.assign = ( "" => "" )
}
EOF

# Enable and start services
systemctl enable hostapd
systemctl enable dnsmasq
systemctl enable lighttpd

echo "✅ Web configuration interface created"

echo ""
echo "🎉 Dual WiFi Configuration Complete!"
echo ""
echo "📊 Summary:"
echo "  • wlan0: Access Point mode (SSID: SatPi-Config, Password: satpi123)"
echo "  • wlan1: External connectivity via USB WiFi adapter"
echo "  • Web interface available at: http://192.168.4.1"
echo "  • Enhanced WiFi hunter script created"
echo "  • All services configured and enabled"
echo ""
echo "🚀 To apply configuration:"
echo "  sudo systemctl enable wifi-hunter-dual.service"
echo "  sudo systemctl start wifi-hunter-dual.service"
echo "  sudo systemctl start hostapd"
echo "  sudo systemctl start dnsmasq"
echo "  sudo systemctl start lighttpd"
echo ""
echo "📱 To configure WiFi:"
echo "  1. Connect to 'SatPi-Config' WiFi (password: satpi123)"
echo "  2. Open browser to http://192.168.4.1"
echo "  3. Scan and connect to internet WiFi"
echo "  4. Test dynamic DNS connectivity"
echo ""
echo "📋 To monitor:"
echo "  sudo systemctl status wifi-hunter-dual.service"
echo "  tail -f /var/log/wifi-hunter.log"
EOF

chmod +x configure-dual-wifi.sh 