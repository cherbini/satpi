#!/bin/bash
# SatPi startup notification script
# Sends immediate email when device boots and comes online

LOG_FILE="/var/log/startup-notification.log"
STARTUP_MARKER="/tmp/satpi-startup-sent"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

wait_for_network() {
    log "Waiting for network connectivity..."
    local max_attempts=60  # 5 minutes
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log "Network connectivity established"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log "Network attempt $attempt/$max_attempts"
        sleep 5
    done
    
    log "WARNING: Network connectivity not established within timeout"
    return 1
}

send_startup_notification() {
    log "Sending startup notification..."
    
    # Wait a bit more to ensure all services are ready
    sleep 30
    
    # Send immediate location report
    if [[ -f "/home/pi/satpi/location-reporter.py" ]]; then
        python3 /home/pi/satpi/location-reporter.py report
        
        if [[ $? -eq 0 ]]; then
            log "Startup notification sent successfully"
            touch "$STARTUP_MARKER"
        else
            log "Failed to send startup notification"
        fi
    else
        log "ERROR: location-reporter.py not found"
    fi
}

main() {
    log "SatPi startup notification service started"
    
    # Check if we've already sent startup notification this boot
    if [[ -f "$STARTUP_MARKER" ]]; then
        log "Startup notification already sent this boot cycle"
        exit 0
    fi
    
    # Wait for network
    if wait_for_network; then
        send_startup_notification
    else
        log "Skipping startup notification due to network issues"
    fi
    
    log "Startup notification service completed"
}

main