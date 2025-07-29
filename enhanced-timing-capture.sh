#!/bin/bash
# Enhanced satellite capture with precise timing alignment
# Includes GOES timing optimization and traditional satellite pass prediction

LOG_FILE="$HOME/enhanced-capture.log"
DATA_DIR="$HOME/sat-data"
UPLOAD_QUEUE="/tmp/upload-queue"
TLE_FILE="$HOME/satellite.tle"

# Corrected GOES satellites (2025 frequencies)
declare -A GOES_SATELLITES=(
    ["GOES-18"]="1694.1"    # GOES-West at 137°W (correct HRIT frequency)
    ["GOES-16"]="1694.1"    # GOES-East at 75.2°W (same HRIT frequency)
)

# Traditional weather satellites with updated status (2025)
declare -A WEATHER_SATELLITES=(
    ["NOAA-15"]="137.620"   # Still operational
    ["NOAA-19"]="137.100"   # Still operational
    ["METEOR-M2-3"]="137.100"  # Active METEOR satellite
    ["METEOR-M2-4"]="137.900"  # Active METEOR satellite
)

# Optimized RTL-SDR settings
declare -A RTL_SETTINGS=(
    ["GOES_SAMPLE_RATE"]="2048000"
    ["GOES_GAIN"]="20"
    ["GOES_CAPTURE_DURATION"]="300"  # 5 minutes aligned with full disk scans
    ["VHF_SAMPLE_RATE"]="2048000"
    ["VHF_GAIN"]="49.6"
    ["VHF_CAPTURE_DURATION"]="900"   # 15 minutes for complete pass
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

update_tle_data() {
    log "Updating TLE data for accurate pass predictions..."
    
    # Download current TLE data
    if command -v curl >/dev/null 2>&1; then
        curl -s "https://celestrak.org/NORAD/elements/gp.php?GROUP=weather&FORMAT=tle" > "$TLE_FILE.tmp" && {
            mv "$TLE_FILE.tmp" "$TLE_FILE"
            log "TLE data updated successfully"
            return 0
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TLE_FILE.tmp" "https://celestrak.org/NORAD/elements/gp.php?GROUP=weather&FORMAT=tle" && {
            mv "$TLE_FILE.tmp" "$TLE_FILE"
            log "TLE data updated successfully"
            return 0
        }
    fi
    
    log "WARNING: Could not update TLE data - using cached data if available"
    return 1
}

predict_next_pass() {
    local sat_name="$1"
    local min_elevation="${2:-15}"  # Minimum elevation in degrees
    
    if ! command -v predict >/dev/null 2>&1; then
        log "WARNING: predict not installed - cannot calculate pass times"
        return 1
    fi
    
    if [[ ! -f "$TLE_FILE" ]]; then
        log "WARNING: No TLE file available for pass prediction"
        return 1
    fi
    
    # Get next pass prediction
    local pass_info
    pass_info=$(predict -t "$TLE_FILE" -p "$sat_name" | head -1)
    
    if [[ -n "$pass_info" ]]; then
        local pass_time elevation
        pass_time=$(echo "$pass_info" | awk '{print $1" "$2}')
        elevation=$(echo "$pass_info" | awk '{print $4}')
        
        if (( $(echo "$elevation > $min_elevation" | bc -l) )); then
            echo "$pass_time|$elevation"
            return 0
        fi
    fi
    
    return 1
}

capture_goes_precise() {
    local sat_name="$1"
    local frequency="${GOES_SATELLITES[$sat_name]}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$DATA_DIR/${sat_name}_${timestamp}.raw"
    
    log "🛰️ Starting precise GOES capture: $sat_name at ${frequency}MHz"
    log "Aligned with full disk scan timing (every 10 minutes)"
    
    mkdir -p "$DATA_DIR"
    
    # Capture with optimized settings
    timeout "${RTL_SETTINGS[GOES_CAPTURE_DURATION]}" rtl_sdr \
        -f "${frequency}000000" \
        -s "${RTL_SETTINGS[GOES_SAMPLE_RATE]}" \
        -g "${RTL_SETTINGS[GOES_GAIN]}" \
        "$output_file" || {
        log "❌ GOES capture failed"
        return 1
    }
    
    if [[ -f "$output_file" ]]; then
        local file_size=$(stat -c%s "$output_file")
        local size_mb=$((file_size / 1024 / 1024))
        
        log "✅ Captured ${size_mb}MB of $sat_name data during full disk scan window"
        
        # Add to upload queue if reasonable size
        if [[ $file_size -gt 1000000 ]]; then
            echo "$output_file|$sat_name|$(date -Iseconds)|GOES-HRIT" >> "$UPLOAD_QUEUE"
            log "📤 Added to upload queue"
        fi
        
        return 0
    else
        log "❌ No GOES capture file created"
        return 1
    fi
}

capture_weather_satellite() {
    local sat_name="$1"
    local frequency="${WEATHER_SATELLITES[$sat_name]}"
    local pass_info="$2"  # Optional: pass_time|elevation
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$DATA_DIR/${sat_name}_${timestamp}.raw"
    
    if [[ -n "$pass_info" ]]; then
        local pass_time elevation
        IFS='|' read -r pass_time elevation <<< "$pass_info"
        log "🛰️ Starting weather satellite capture: $sat_name at ${frequency}MHz"
        log "Pass time: $pass_time, Max elevation: ${elevation}°"
    else
        log "🛰️ Starting weather satellite capture: $sat_name at ${frequency}MHz (no pass prediction)"
    fi
    
    mkdir -p "$DATA_DIR"
    
    # Capture with weather satellite settings
    timeout "${RTL_SETTINGS[VHF_CAPTURE_DURATION]}" rtl_sdr \
        -f "${frequency}000000" \
        -s "${RTL_SETTINGS[VHF_SAMPLE_RATE]}" \
        -g "${RTL_SETTINGS[VHF_GAIN]}" \
        "$output_file" || {
        log "❌ Weather satellite capture failed"
        return 1
    }
    
    if [[ -f "$output_file" ]]; then
        local file_size=$(stat -c%s "$output_file")
        local size_mb=$((file_size / 1024 / 1024))
        
        log "✅ Captured ${size_mb}MB of $sat_name data"
        
        # Add to upload queue
        if [[ $file_size -gt 100000 ]]; then
            local sat_type="APT"
            [[ "$sat_name" =~ METEOR ]] && sat_type="LRPT"
            echo "$output_file|$sat_name|$(date -Iseconds)|$sat_type" >> "$UPLOAD_QUEUE"
            log "📤 Added to upload queue as $sat_type"
        fi
        
        return 0
    else
        log "❌ No weather satellite capture file created"
        return 1
    fi
}

auto_capture_enhanced() {
    log "🚀 Starting enhanced automatic capture with precise timing"
    
    # Update TLE data at startup
    update_tle_data
    
    # Track last TLE update
    local last_tle_update=$(date +%s)
    
    while true; do
        local current_time=$(date +%s)
        local current_hour=$(date +%H)
        local current_minute=$(date +%M)
        
        # Update TLE data every 6 hours
        if [[ $((current_time - last_tle_update)) -gt 21600 ]]; then
            update_tle_data
            last_tle_update=$current_time
        fi
        
        # GOES satellites - capture every 10 minutes aligned with full disk scans
        if [[ $((current_minute % 10)) -eq 0 ]]; then
            log "⏰ GOES capture window - full disk scan timing"
            capture_goes_precise "GOES-18"
        fi
        
        # Weather satellites - use pass prediction when available
        if [[ $((current_minute % 30)) -eq 0 ]]; then
            for sat_name in "${!WEATHER_SATELLITES[@]}"; do
                local pass_info
                if pass_info=$(predict_next_pass "$sat_name" 15); then
                    local pass_time elevation
                    IFS='|' read -r pass_time elevation <<< "$pass_info"
                    
                    # Check if pass is within next 30 minutes
                    local pass_timestamp
                    pass_timestamp=$(date -d "$pass_time" +%s 2>/dev/null)
                    
                    if [[ -n "$pass_timestamp" && $((pass_timestamp - current_time)) -lt 1800 && $((pass_timestamp - current_time)) -gt -900 ]]; then
                        log "🎯 Optimal pass detected for $sat_name - starting capture"
                        capture_weather_satellite "$sat_name" "$pass_info"
                        sleep 60  # Brief pause between satellites
                    fi
                fi
            done
        fi
        
        # Check every 30 seconds for precise timing
        sleep 30
    done
}

scheduled_capture() {
    local sat_type="$1"
    local sat_name="$2"
    
    case "$sat_type" in
        "goes")
            if [[ -n "${GOES_SATELLITES[$sat_name]}" ]]; then
                capture_goes_precise "$sat_name"
            else
                log "❌ Invalid GOES satellite: $sat_name"
                exit 1
            fi
            ;;
        "weather")
            if [[ -n "${WEATHER_SATELLITES[$sat_name]}" ]]; then
                local pass_info
                pass_info=$(predict_next_pass "$sat_name" 10)
                capture_weather_satellite "$sat_name" "$pass_info"
            else
                log "❌ Invalid weather satellite: $sat_name"
                exit 1
            fi
            ;;
        *)
            log "❌ Invalid satellite type: $sat_type"
            exit 1
            ;;
    esac
}

show_schedule() {
    echo "Enhanced Satellite Capture Schedule:"
    echo ""
    echo "GOES Satellites (Geostationary - 24/7 available):"
    for sat in "${!GOES_SATELLITES[@]}"; do
        echo "  $sat: ${GOES_SATELLITES[$sat]} MHz (Full disk scans every 10 minutes)"
    done
    echo ""
    echo "Weather Satellites (Polar-orbiting - pass prediction required):"
    for sat in "${!WEATHER_SATELLITES[@]}"; do
        echo "  $sat: ${WEATHER_SATELLITES[$sat]} MHz"
        if command -v predict >/dev/null 2>&1 && [[ -f "$TLE_FILE" ]]; then
            local next_pass
            if next_pass=$(predict_next_pass "$sat" 15); then
                local pass_time elevation
                IFS='|' read -r pass_time elevation <<< "$next_pass"
                echo "    Next pass: $pass_time (${elevation}° elevation)"
            else
                echo "    Next pass: No high-elevation passes in next 24 hours"
            fi
        else
            echo "    Next pass: Install 'predict' for pass prediction"
        fi
    done
}

# Initialize
mkdir -p "$DATA_DIR"
touch "$UPLOAD_QUEUE"

case "${1:-auto}" in
    "auto")
        auto_capture_enhanced
        ;;
    "capture")
        scheduled_capture "$2" "$3"
        ;;
    "schedule")
        show_schedule
        ;;
    "update-tle")
        update_tle_data
        ;;
    "test-goes")
        capture_goes_precise "GOES-18"
        ;;
    *)
        echo "Usage: $0 [auto|capture <type> <satellite>|schedule|update-tle|test-goes]"
        echo ""
        echo "Examples:"
        echo "  $0 auto                           # Enhanced automatic mode"
        echo "  $0 capture goes GOES-18           # Capture GOES-18"
        echo "  $0 capture weather NOAA-19        # Capture NOAA-19 with pass prediction"
        echo "  $0 schedule                       # Show satellite schedule"
        echo "  $0 update-tle                     # Update TLE data"
        echo "  $0 test-goes                      # Test GOES capture"
        exit 1
        ;;
esac