#!/bin/bash
# Aggressive WiFi hunter script for SatPi
# Continuously scans for and connects to available WiFi networks

LOG_FILE="/var/log/wifi-hunter.log"
SCAN_INTERVAL=10
CONNECTION_TIMEOUT=30
MAX_RETRY_COUNT=3

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_internet() {
    ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1
    return $?
}

get_signal_strength() {
    local ssid="$1"
    iwlist wlan1 scan 2>/dev/null | awk -v ssid="$ssid" '
        /Cell/ { cell++ }
        /ESSID:/ && $0 ~ ssid { found_cell = cell }
        /Quality=/ && cell == found_cell { 
            split($0, a, "="); 
            split(a[2], b, "/"); 
            print int((b[1]/b[2])*100) 
        }'
}

scan_networks() {
    iwlist wlan1 scan 2>/dev/null | grep -E "ESSID:|Quality=" | \
    awk 'BEGIN{ORS=""} /Quality/{quality=$0; getline; print quality " " $0 "\n"}' | \
    grep -v 'ESSID:""' | \
    sort -k2 -nr | \
    head -20
}

attempt_connection() {
    local ssid="$1"
    local security="$2"
    
    log "Attempting connection to: $ssid"
    
    # Kill existing wpa_supplicant
    sudo pkill wpa_supplicant 2>/dev/null
    sleep 2
    
    # Create temporary config
    local temp_conf="/tmp/wpa_temp.conf"
    cp /etc/wpa_supplicant/wpa_supplicant.conf "$temp_conf"
    
    # Add network if not already present
    if ! grep -q "ssid=\"$ssid\"" "$temp_conf"; then
        echo "" >> "$temp_conf"
        echo "network={" >> "$temp_conf"
        echo "    ssid=\"$ssid\"" >> "$temp_conf"
        if [[ "$security" == "open" ]]; then
            echo "    key_mgmt=NONE" >> "$temp_conf"
        else
            echo "    key_mgmt=WPA-PSK" >> "$temp_conf"
            echo "    psk=\"\"" >> "$temp_conf"
        fi
        echo "    priority=10" >> "$temp_conf"
        echo "}" >> "$temp_conf"
    fi
    
    # Start wpa_supplicant
    sudo wpa_supplicant -B -i wlan1 -c "$temp_conf" -D nl80211
    sleep 5
    
    # Get IP via DHCP
    sudo dhclient wlan1 -timeout 20
    sleep 5
    
    # Check connection
    if check_internet; then
        log "Successfully connected to: $ssid"
        return 0
    else
        log "Connection failed or no internet: $ssid"
        return 1
    fi
}

handle_captive_portal() {
    local portal_url
    portal_url=$(curl -s -I http://connectivitycheck.gstatic.com/generate_204 | grep -i location | cut -d' ' -f2 | tr -d '\r')
    
    if [[ -n "$portal_url" ]]; then
        log "Captive portal detected: $portal_url"
        # Try common captive portal bypass methods
        curl -s "$portal_url" > /dev/null
        curl -s -d "accept=true" "$portal_url" > /dev/null
        curl -s -X POST "$portal_url" > /dev/null
        
        sleep 10
        if check_internet; then
            log "Captive portal bypassed successfully"
            return 0
        fi
    fi
    return 1
}

main_loop() {
    local retry_count=0
    
    while true; do
        if check_internet; then
            log "Internet connection available"
            retry_count=0
            sleep 60  # Check less frequently when connected
            continue
        fi
        
        log "No internet connection. Scanning for networks..."
        
        # Enable WiFi interface
        sudo ip link set wlan1 up 2>/dev/null
        sleep 2
        
        # Scan for networks
        local networks
        networks=$(scan_networks)
        
        if [[ -z "$networks" ]]; then
            log "No networks found"
            sleep "$SCAN_INTERVAL"
            continue
        fi
        
        # Try each network
        while IFS= read -r network; do
            if [[ -z "$network" ]]; then continue; fi
            
            local ssid
            ssid=$(echo "$network" | grep -o 'ESSID:"[^"]*"' | cut -d'"' -f2)
            
            if [[ -z "$ssid" ]]; then continue; fi
            
            local quality
            quality=$(get_signal_strength "$ssid")
            
            # Skip weak signals
            if [[ "$quality" -lt 30 ]]; then
                log "Skipping weak signal: $ssid ($quality%)"
                continue
            fi
            
            # Determine security type (simplified)
            local security="open"
            if echo "$network" | grep -q "Encryption key:on"; then
                security="encrypted"
            fi
            
            # Try connection
            if attempt_connection "$ssid" "$security"; then
                # Handle potential captive portal
                if ! check_internet; then
                    handle_captive_portal
                fi
                
                if check_internet; then
                    log "Connected successfully to: $ssid"
                    break
                fi
            fi
            
            sleep 5
        done <<< "$networks"
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -ge $MAX_RETRY_COUNT ]]; then
            log "Max retries reached. Waiting longer before next attempt..."
            sleep 300  # Wait 5 minutes
            retry_count=0
        else
            sleep "$SCAN_INTERVAL"
        fi
    done
}

# Initialize
log "WiFi Hunter started"
sudo rfkill unblock wifi
sudo modprobe brcmfmac
sleep 5

main_loop