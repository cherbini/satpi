#!/bin/bash
# Dynamic DNS updater for SatPi
# Updates a public DNS record with current IP for remote access

LOG_FILE="/var/log/dynamic-dns.log"
STATUS_FILE="/tmp/current-ip"
DDNS_CONFIG="/home/pi/satpi/ddns-config.json"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

get_public_ip() {
    local ip
    
    # Try multiple IP detection services
    for service in "http://ip-api.com/line/?fields=query" "https://ipv4.icanhazip.com" "https://api.ipify.org"; do
        ip=$(curl -s --connect-timeout 10 --max-time 15 "$service" 2>/dev/null | tr -d '\n\r')
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    
    log "ERROR: Could not determine public IP"
    return 1
}

update_noip() {
    local hostname="$1"
    local username="$2"
    local password="$3"
    local ip="$4"
    
    local auth=$(echo -n "$username:$password" | base64)
    local url="http://dynupdate.no-ip.com/nic/update?hostname=$hostname&myip=$ip"
    
    local response=$(curl -s -A "SatPi DDNS Client/1.0" -H "Authorization: Basic $auth" "$url")
    
    if [[ "$response" =~ ^(good|nochg) ]]; then
        log "No-IP update successful: $response"
        return 0
    else
        log "No-IP update failed: $response"
        return 1
    fi
}

update_duckdns() {
    local domain="$1"
    local token="$2"
    local ip="$3"
    
    local url="https://www.duckdns.org/update?domains=$domain&token=$token&ip=$ip"
    local response=$(curl -s "$url")
    
    if [[ "$response" == "OK" ]]; then
        log "DuckDNS update successful"
        return 0
    else
        log "DuckDNS update failed: $response"
        return 1
    fi
}

update_dynu() {
    local hostname="$1"
    local username="$2"
    local password="$3"
    local ip="$4"
    
    local url="https://api.dynu.com/nic/update?hostname=$hostname&myip=$ip&username=$username&password=$password"
    local response=$(curl -s "$url")
    
    if [[ "$response" =~ ^(good|nochg) ]]; then
        log "Dynu update successful: $response"
        return 0
    else
        log "Dynu update failed: $response"
        return 1
    fi
}

create_default_config() {
    log "Creating default DDNS configuration"
    cat > "$DDNS_CONFIG" << 'EOF'
{
    "enabled": false,
    "providers": [
        {
            "name": "noip",
            "enabled": false,
            "hostname": "your-satpi.ddns.net",
            "username": "your-username",
            "password": "your-password"
        },
        {
            "name": "duckdns",
            "enabled": false,
            "domain": "your-satpi",
            "token": "your-token"
        },
        {
            "name": "dynu",
            "enabled": false,
            "hostname": "your-satpi.freeddns.org",
            "username": "your-username",
            "password": "your-password"
        }
    ]
}
EOF
    log "DDNS configuration created at $DDNS_CONFIG"
    log "Please edit the configuration file to enable and configure your preferred provider"
}

load_config() {
    if [[ ! -f "$DDNS_CONFIG" ]]; then
        create_default_config
        return 1
    fi
    
    if ! jq empty "$DDNS_CONFIG" 2>/dev/null; then
        log "ERROR: Invalid JSON in configuration file"
        return 1
    fi
    
    local enabled=$(jq -r '.enabled' "$DDNS_CONFIG")
    if [[ "$enabled" != "true" ]]; then
        log "DDNS is disabled in configuration"
        return 1
    fi
    
    return 0
}

update_dns_records() {
    local current_ip="$1"
    local success=false
    
    # Process each enabled provider
    while IFS= read -r provider; do
        local name=$(echo "$provider" | jq -r '.name')
        local enabled=$(echo "$provider" | jq -r '.enabled')
        
        if [[ "$enabled" != "true" ]]; then
            continue
        fi
        
        log "Updating $name with IP: $current_ip"
        
        case "$name" in
            "noip")
                local hostname=$(echo "$provider" | jq -r '.hostname')
                local username=$(echo "$provider" | jq -r '.username')
                local password=$(echo "$provider" | jq -r '.password')
                if update_noip "$hostname" "$username" "$password" "$current_ip"; then
                    success=true
                fi
                ;;
            "duckdns")
                local domain=$(echo "$provider" | jq -r '.domain')
                local token=$(echo "$provider" | jq -r '.token')
                if update_duckdns "$domain" "$token" "$current_ip"; then
                    success=true
                fi
                ;;
            "dynu")
                local hostname=$(echo "$provider" | jq -r '.hostname')
                local username=$(echo "$provider" | jq -r '.username')
                local password=$(echo "$provider" | jq -r '.password')
                if update_dynu "$hostname" "$username" "$password" "$current_ip"; then
                    success=true
                fi
                ;;
            *)
                log "Unknown provider: $name"
                ;;
        esac
    done < <(jq -c '.providers[]' "$DDNS_CONFIG")
    
    if [[ "$success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

check_ip_change() {
    local current_ip="$1"
    local last_ip=""
    
    if [[ -f "$STATUS_FILE" ]]; then
        last_ip=$(cat "$STATUS_FILE")
    fi
    
    if [[ "$current_ip" != "$last_ip" ]]; then
        log "IP changed from '$last_ip' to '$current_ip'"
        echo "$current_ip" > "$STATUS_FILE"
        return 0
    else
        log "IP unchanged: $current_ip"
        return 1
    fi
}

setup_port_forwarding_guide() {
    local current_ip="$1"
    
    # Generate helpful information for port forwarding
    cat > "/tmp/port-forwarding-info.txt" << EOF
SatPi Remote Access Setup Guide
===============================

Your SatPi device is currently at:
Public IP: $current_ip
Local IP: $(hostname -I | awk '{print $1}')

To access your SatPi remotely, you need to set up port forwarding on your router:

1. Log into your router's admin interface (usually http://192.168.1.1 or http://192.168.0.1)
2. Find the "Port Forwarding" or "NAT" section
3. Add these rules:

   SSH Access:
   - External Port: 2222
   - Internal Port: 22
   - Internal IP: $(hostname -I | awk '{print $1}')
   - Protocol: TCP
   
   Optional - Web Interface:
   - External Port: 8080
   - Internal Port: 80
   - Internal IP: $(hostname -I | awk '{print $1}')
   - Protocol: TCP

4. Save and restart your router

Then you can access your SatPi with:
ssh -p 2222 pi@$current_ip

Security Note: Consider changing SSH port and using key authentication instead of passwords.
EOF

    log "Port forwarding guide created at /tmp/port-forwarding-info.txt"
}

main() {
    log "Starting Dynamic DNS update"
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR: jq is required but not installed. Installing..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y jq
        else
            log "ERROR: Cannot install jq automatically"
            exit 1
        fi
    fi
    
    # Load configuration
    if ! load_config; then
        exit 0  # Not an error, just disabled or no config
    fi
    
    # Get current public IP
    current_ip=$(get_public_ip)
    if [[ -z "$current_ip" ]]; then
        log "ERROR: Could not determine public IP"
        exit 1
    fi
    
    log "Current public IP: $current_ip"
    
    # Check if IP has changed
    if check_ip_change "$current_ip"; then
        # Update DNS records
        if update_dns_records "$current_ip"; then
            log "DNS update completed successfully"
            
            # Generate port forwarding guide
            setup_port_forwarding_guide "$current_ip"
            
            # Trigger location report update
            if [[ -f "/home/pi/satpi/location-reporter.py" ]]; then
                python3 /home/pi/satpi/location-reporter.py report &
            fi
        else
            log "ERROR: DNS update failed"
            exit 1
        fi
    fi
    
    log "Dynamic DNS update completed"
}

# Handle command line arguments
case "${1:-main}" in
    "setup")
        create_default_config
        ;;
    "test")
        current_ip=$(get_public_ip)
        echo "Current IP: $current_ip"
        echo "Config valid: $(load_config && echo "yes" || echo "no")"
        ;;
    "force")
        # Force update regardless of IP change
        log "Force updating DNS records"
        load_config || exit 1
        current_ip=$(get_public_ip)
        [[ -n "$current_ip" ]] || exit 1
        echo "$current_ip" > "$STATUS_FILE"
        update_dns_records "$current_ip"
        ;;
    "main"|*)
        main
        ;;
esac