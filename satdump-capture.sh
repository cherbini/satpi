#!/bin/bash
# Satellite data capture script using RTL-SDR and SatDump

LOG_FILE="/var/log/satdump.log"
DATA_DIR="/home/pi/sat-data"
UPLOAD_QUEUE="/tmp/upload-queue"

# Satellite frequencies and configurations
declare -A SATELLITES=(
    ["NOAA-15"]="137.620"
    ["NOAA-18"]="137.912"
    ["NOAA-19"]="137.100"
    ["METEOR-M2"]="137.100"
    ["ISS"]="145.800"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_rtlsdr() {
    if ! rtl_test -t >/dev/null 2>&1; then
        log "ERROR: RTL-SDR device not found"
        return 1
    fi
    
    # Reset RTL-SDR device
    rtl_test -s 2000000 -d 0 -t 1 >/dev/null 2>&1
    log "RTL-SDR device detected and reset"
    return 0
}

predict_passes() {
    local sat_name="$1"
    local current_time=$(date +%s)
    local end_time=$((current_time + 86400))  # Next 24 hours
    
    # Use predict or similar tool to get pass predictions
    # This is a simplified version - you'd want to integrate with actual orbital prediction
    predict -t "$sat_name" -s "$current_time" -e "$end_time" 2>/dev/null || {
        log "WARNING: Pass prediction failed for $sat_name"
        return 1
    }
}

capture_satellite_data() {
    local sat_name="$1"
    local frequency="$2"
    local duration="$3"
    local output_file="$4"
    
    log "Starting capture: $sat_name at ${frequency}MHz for ${duration}s"
    
    # Set optimal RTL-SDR parameters
    local sample_rate="2048000"
    local gain="49.6"
    
    # Capture raw IQ data
    timeout "$duration" rtl_sdr -f "${frequency}000000" -s "$sample_rate" -g "$gain" "$output_file.raw" || {
        log "ERROR: RTL-SDR capture failed for $sat_name"
        return 1
    }
    
    log "Raw capture completed: $output_file.raw"
    
    # Process with SatDump if available
    if command -v satdump >/dev/null 2>&1; then
        log "Processing with SatDump..."
        satdump live noaa_apt "$output_file.raw" "$DATA_DIR/processed" --samplerate "$sample_rate" --baseband_format i16 || {
            log "WARNING: SatDump processing failed"
        }
    else
        log "WARNING: SatDump not available, keeping raw data"
    fi
    
    # Add to upload queue
    echo "$output_file.raw|$sat_name|$(date -Iseconds)" >> "$UPLOAD_QUEUE"
    
    return 0
}

auto_capture_mode() {
    log "Starting automatic capture mode"
    
    while true; do
        for sat_name in "${!SATELLITES[@]}"; do
            local frequency="${SATELLITES[$sat_name]}"
            
            # Check if satellite might be overhead (simplified)
            local current_hour=$(date +%H)
            if [[ $((current_hour % 3)) -eq 0 ]]; then
                local timestamp=$(date +%Y%m%d_%H%M%S)
                local output_file="$DATA_DIR/${sat_name}_${timestamp}"
                
                mkdir -p "$DATA_DIR"
                
                if capture_satellite_data "$sat_name" "$frequency" 900 "$output_file"; then
                    log "Successfully captured data from $sat_name"
                else
                    log "Failed to capture data from $sat_name"
                fi
                
                # Wait between captures
                sleep 300
            fi
        done
        
        # Check every 15 minutes
        sleep 900
    done
}

scheduled_capture() {
    local sat_name="$1"
    local duration="${2:-600}"
    
    if [[ -z "$sat_name" ]] || [[ -z "${SATELLITES[$sat_name]}" ]]; then
        log "ERROR: Invalid satellite name: $sat_name"
        return 1
    fi
    
    local frequency="${SATELLITES[$sat_name]}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$DATA_DIR/${sat_name}_${timestamp}"
    
    mkdir -p "$DATA_DIR"
    capture_satellite_data "$sat_name" "$frequency" "$duration" "$output_file"
}

# Initialize
log "SatDump capture system started"

if ! check_rtlsdr; then
    log "FATAL: RTL-SDR initialization failed"
    exit 1
fi

# Create directories
mkdir -p "$DATA_DIR"
touch "$UPLOAD_QUEUE"

# Parse command line arguments
case "${1:-auto}" in
    "auto")
        auto_capture_mode
        ;;
    "capture")
        scheduled_capture "$2" "$3"
        ;;
    "test")
        log "Testing RTL-SDR capture for 10 seconds..."
        rtl_sdr -f 137500000 -s 2048000 -g 49.6 /tmp/test_capture.raw &
        PID=$!
        sleep 10
        kill $PID 2>/dev/null
        if [[ -s /tmp/test_capture.raw ]]; then
            log "Test capture successful: $(wc -c < /tmp/test_capture.raw) bytes"
            rm /tmp/test_capture.raw
        else
            log "Test capture failed"
        fi
        ;;
    *)
        echo "Usage: $0 [auto|capture <satellite> <duration>|test]"
        exit 1
        ;;
esac