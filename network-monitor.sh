#!/bin/bash
# Network monitoring and fallback management

LOG_FILE="/var/log/network-monitor.log"
STATUS_FILE="/tmp/network-status"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_connection_quality() {
    local loss
    local avg_time
    
    # Ping test to multiple servers
    local ping_result
    ping_result=$(ping -c 5 -W 3 8.8.8.8 2>/dev/null | tail -1)
    
    if [[ -n "$ping_result" ]]; then
        loss=$(echo "$ping_result" | grep -o '[0-9]*%' | head -1 | tr -d '%')
        avg_time=$(echo "$ping_result" | grep -o 'avg = [0-9.]*' | cut -d' ' -f3)
        
        echo "loss=$loss,avg_time=$avg_time" > "$STATUS_FILE"
        
        # Quality scoring (0-100)
        local quality=100
        quality=$((quality - loss * 2))
        if [[ -n "$avg_time" ]] && (( $(echo "$avg_time > 500" | bc -l) )); then
            quality=$((quality - 30))
        fi
        
        echo "$quality"
        return 0
    else
        echo "0" > "$STATUS_FILE"
        return 1
    fi
}

monitor_bandwidth() {
    local rx1 tx1 rx2 tx2
    
    rx1=$(cat /sys/class/net/wlan1/statistics/rx_bytes 2>/dev/null || echo 0)
    tx1=$(cat /sys/class/net/wlan1/statistics/tx_bytes 2>/dev/null || echo 0)
    
    sleep 10
    
    rx2=$(cat /sys/class/net/wlan1/statistics/rx_bytes 2>/dev/null || echo 0)
    tx2=$(cat /sys/class/net/wlan1/statistics/tx_bytes 2>/dev/null || echo 0)
    
    local rx_rate=$(((rx2 - rx1) / 10))
    local tx_rate=$(((tx2 - tx1) / 10))
    
    echo "rx_rate=$rx_rate,tx_rate=$tx_rate" >> "$STATUS_FILE"
    log "Bandwidth: RX=$rx_rate B/s, TX=$tx_rate B/s"
}

# Main monitoring loop
while true; do
    quality=$(check_connection_quality)
    log "Connection quality: $quality%"
    
    if [[ "$quality" -lt 20 ]]; then
        log "Poor connection quality detected. Triggering WiFi hunter..."
        systemctl restart wifi-hunter
    fi
    
    monitor_bandwidth
    sleep 30
done