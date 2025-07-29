#!/bin/bash
# Enhanced satellite data capture script with proper image processing and upload
# Updated to create actual satellite images and upload to boatwizards.com/satellite

# Enable debug mode with verbose output
set -x
DEBUG=1
VERBOSE=1

LOG_FILE="/var/log/satdump.log"
DATA_DIR="$HOME/sat-data"
PROCESSED_DIR="$DATA_DIR/processed"
IMAGES_DIR="$DATA_DIR/images"
UPLOAD_QUEUE="/tmp/upload-queue"

# Satellite frequencies and configurations
declare -A SATELLITES=(
    ["NOAA-15"]="137.620"
    ["NOAA-18"]="137.912"
    ["NOAA-19"]="137.100"
    ["METEOR-M2"]="137.100"
    ["ISS"]="145.800"
)

# GOES geostationary satellites (L-band HRIT frequencies - corrected for 2025)
declare -A GOES_SATELLITES=(
    ["GOES-18"]="1694.1"    # GOES-West at 137°W (correct HRIT frequency)
    ["GOES-16"]="1694.1"    # GOES-East at 75.2°W (same HRIT frequency)
    ["GOES-17"]="1694.1"    # Backup (if operational) - standardized HRIT frequency
)

# RTL-SDR settings optimized for different hardware setups
declare -A RTL_SETTINGS=(
    ["VHF_SAMPLE_RATE"]="2048000"
    ["VHF_GAIN"]="49.6"
    ["GOES_SAMPLE_RATE"]="2048000"
    ["GOES_GAIN"]="20"
    ["GOES_PPM"]="0"
    ["GOES_INTEGRATION"]="300"  # 5 minutes for better GOES data
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

debug_log() {
    if [[ "$DEBUG" == "1" ]]; then
        echo "[DEBUG $(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    fi
}

check_rtlsdr() {
    debug_log "Running RTL-SDR device detection test..."
    
    if ! rtl_test -t 2>&1 | tee -a "$LOG_FILE"; then
        log "ERROR: RTL-SDR device not found"
        return 1
    fi
    
    log "RTL-SDR device detected and ready"
    return 0
}

process_satellite_data() {
    local raw_file="$1"
    local satellite_name="$2"
    local satellite_type="$3"
    local timestamp="$4"
    
    log "Processing satellite data: $raw_file for $satellite_name ($satellite_type)"
    
    # Create processing directories
    mkdir -p "$PROCESSED_DIR" "$IMAGES_DIR"
    
    local base_name="${satellite_name}_${timestamp}"
    local output_dir="$PROCESSED_DIR/$base_name"
    mkdir -p "$output_dir"
    
    # Process based on satellite type
    if [[ "$satellite_type" == "GOES" ]]; then
        log "Processing GOES satellite data with SatDump..."
        
        # Try GOES GVAR processing first
        if satdump live goes_gvar "$raw_file" "$output_dir" \
            --samplerate "${RTL_SETTINGS[GOES_SAMPLE_RATE]}" \
            --baseband_format f32 \
            --timeout 30; then
            log "GOES GVAR processing successful"
        else
            log "GOES GVAR failed, trying generic processing..."
            # Fallback to generic processing
            satdump live generic_baseband "$raw_file" "$output_dir" \
                --samplerate "${RTL_SETTINGS[GOES_SAMPLE_RATE]}" \
                --baseband_format f32 \
                --timeout 30 || {
                log "WARNING: All GOES processing failed"
                return 1
            }
        fi
        
        # Convert processed data to images
        convert_goes_to_images "$output_dir" "$base_name"
        
    else
        log "Processing weather satellite data with SatDump..."
        
        # Process traditional weather satellites
        if satdump live noaa_apt "$raw_file" "$output_dir" \
            --samplerate "${RTL_SETTINGS[VHF_SAMPLE_RATE]}" \
            --baseband_format f32 \
            --timeout 30; then
            log "Weather satellite processing successful"
        else
            log "Weather satellite processing failed, trying generic..."
            satdump live generic_baseband "$raw_file" "$output_dir" \
                --samplerate "${RTL_SETTINGS[VHF_SAMPLE_RATE]}" \
                --baseband_format f32 \
                --timeout 30 || {
                log "WARNING: Weather satellite processing failed"
                return 1
            }
        fi
        
        # Convert processed data to images
        convert_weather_to_images "$output_dir" "$base_name"
    fi
    
    return 0
}

convert_goes_to_images() {
    local output_dir="$1"
    local base_name="$2"
    
    log "Converting GOES data to images..."
    
    # Look for processed image files in the output directory
    local image_count=0
    
    # SatDump typically creates various output files, look for images
    find "$output_dir" -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | while read -r img_file; do
        if [[ -f "$img_file" ]]; then
            local img_name="$(basename "$img_file")"
            local final_image="$IMAGES_DIR/${base_name}_${img_name}"
            
            # Copy and optimize the image
            cp "$img_file" "$final_image"
            
            # Optimize image size for web upload
            if command -v convert >/dev/null 2>&1; then
                convert "$final_image" -quality 85 -resize 2048x2048\> "$final_image"
            fi
            
            log "Created GOES image: $final_image"
            
            # Add to upload queue
            echo "$final_image|GOES-18|$(date -Iseconds)|IMAGE" >> "$UPLOAD_QUEUE"
            image_count=$((image_count + 1))
        fi
    done
    
    # If no images found, create a visualization from raw data
    if [[ $image_count -eq 0 ]]; then
        create_raw_visualization "$output_dir" "$base_name" "GOES"
    fi
}

convert_weather_to_images() {
    local output_dir="$1"
    local base_name="$2"
    
    log "Converting weather satellite data to images..."
    
    local image_count=0
    
    # Look for processed image files
    find "$output_dir" -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" | while read -r img_file; do
        if [[ -f "$img_file" ]]; then
            local img_name="$(basename "$img_file")"
            local final_image="$IMAGES_DIR/${base_name}_${img_name}"
            
            cp "$img_file" "$final_image"
            
            # Optimize image size
            if command -v convert >/dev/null 2>&1; then
                convert "$final_image" -quality 85 -resize 1024x1024\> "$final_image"
            fi
            
            log "Created weather satellite image: $final_image"
            
            # Add to upload queue
            echo "$final_image|${base_name%_*}|$(date -Iseconds)|IMAGE" >> "$UPLOAD_QUEUE"
            image_count=$((image_count + 1))
        fi
    done
    
    if [[ $image_count -eq 0 ]]; then
        create_raw_visualization "$output_dir" "$base_name" "WEATHER"
    fi
}

create_raw_visualization() {
    local output_dir="$1"
    local base_name="$2"
    local sat_type="$3"
    
    log "Creating raw data visualization for $base_name"
    
    # Create a basic visualization using Python if available
    python3 -c "
import numpy as np
import matplotlib.pyplot as plt
import sys
import os

try:
    # Look for any data files in the output directory
    data_files = []
    for root, dirs, files in os.walk('$output_dir'):
        for file in files:
            if file.endswith(('.bin', '.dat', '.raw')):
                data_files.append(os.path.join(root, file))
    
    if data_files:
        # Read the first data file found
        data_file = data_files[0]
        with open(data_file, 'rb') as f:
            # Read a sample of the data
            raw_data = f.read(1024*1024)  # 1MB sample
        
        # Convert to numpy array (assuming 8-bit unsigned)
        data = np.frombuffer(raw_data, dtype=np.uint8)
        
        # Create a simple plot
        plt.figure(figsize=(12, 8))
        plt.subplot(2, 1, 1)
        plt.plot(data[:10000])
        plt.title('$base_name - Raw Signal Data')
        plt.xlabel('Sample')
        plt.ylabel('Amplitude')
        
        plt.subplot(2, 1, 2)
        plt.specgram(data[:50000].astype(float), Fs=2048000/1000, cmap='viridis')
        plt.title('Spectrogram')
        plt.xlabel('Time')
        plt.ylabel('Frequency (kHz)')
        
        plt.tight_layout()
        output_file = '$IMAGES_DIR/${base_name}_visualization.png'
        plt.savefig(output_file, dpi=150, bbox_inches='tight')
        
        print(f'Created visualization: {output_file}')
        
        # Add to upload queue
        with open('$UPLOAD_QUEUE', 'a') as f:
            f.write(f'{output_file}|${base_name%_*}|$(date -Iseconds)|VISUALIZATION\n')
    
except Exception as e:
    print(f'Visualization failed: {e}')
    sys.exit(1)
" 2>/dev/null || log "Python visualization failed"
}

capture_satellite_data() {
    local sat_name="$1"
    local frequency="$2"
    local duration="$3"
    local output_file="$4"
    local satellite_type="${5:-VHF}"
    
    log "Starting capture: $sat_name at ${frequency}MHz for ${duration}s (Type: $satellite_type)"
    
    # Set RTL-SDR parameters based on satellite type
    local sample_rate gain
    if [[ "$satellite_type" == "GOES" ]]; then
        sample_rate="${RTL_SETTINGS[GOES_SAMPLE_RATE]}"
        gain="${RTL_SETTINGS[GOES_GAIN]}"
        log "Using GOES-optimized settings: ${gain}dB gain"
    else
        sample_rate="${RTL_SETTINGS[VHF_SAMPLE_RATE]}"
        gain="${RTL_SETTINGS[VHF_GAIN]}"
        log "Using VHF settings: ${gain}dB gain"  
    fi
    
    # Capture raw IQ data with limited file size
    local max_size=$((500 * 1024 * 1024))  # 500MB max per file
    
    timeout "$duration" rtl_sdr -f "${frequency}000000" -s "$sample_rate" -g "$gain" "$output_file.raw" || {
        log "ERROR: RTL-SDR capture failed for $sat_name"
        return 1
    }
    
    # Check if file was created and has reasonable size
    if [[ -f "$output_file.raw" ]]; then
        local file_size=$(stat -c%s "$output_file.raw")
        log "Raw capture completed: $output_file.raw ($(($file_size / 1024 / 1024))MB)"
        
        # Process the raw data into images
        local timestamp=$(basename "$output_file" | cut -d'_' -f2-)
        if process_satellite_data "$output_file.raw" "$sat_name" "$satellite_type" "$timestamp"; then
            log "Processing successful for $sat_name"
            
            # Clean up raw file to save space (keep only images)
            if [[ "$file_size" -gt "$max_size" ]]; then
                log "Removing large raw file to save space: $output_file.raw"
                rm -f "$output_file.raw"
            fi
        else
            log "Processing failed for $sat_name, keeping raw data"
            # Still add raw file to upload queue as backup
            echo "$output_file.raw|$sat_name|$(date -Iseconds)|RAW" >> "$UPLOAD_QUEUE"
        fi
    else
        log "ERROR: No capture file created for $sat_name"
        return 1
    fi
    
    return 0
}

auto_capture_mode() {
    log "Starting automatic capture mode with enhanced image processing"
    
    # Create directories
    mkdir -p "$DATA_DIR" "$PROCESSED_DIR" "$IMAGES_DIR"
    
    while true; do
        local current_hour=$(date +%H)
        local current_minute=$(date +%M)
        
        # GOES satellites - capture every 10 minutes (aligned with full disk scans)
        # GOES transmits 24/7 but full disk scans occur every 10 minutes
        if [[ $((current_minute % 10)) -eq 0 ]]; then
            log "Starting scheduled GOES-18 capture session - aligned with full disk scan"
            local timestamp=$(date +%Y%m%d_%H%M%S)
            local output_file="$DATA_DIR/GOES-18_${timestamp}"
            
            # Capture GOES-18 for 5 minutes for optimal data quality during full disk scan window
            if capture_satellite_data "GOES-18" "${GOES_SATELLITES[GOES-18]}" "${RTL_SETTINGS[GOES_INTEGRATION]}" "$output_file" "GOES"; then
                log "Successfully captured and processed GOES-18 data during full disk scan window"
            else
                log "Failed to capture GOES-18 data"
            fi
        fi
        
        # Traditional LEO satellite captures (every 2 hours)
        if [[ $((current_hour % 2)) -eq 0 ]] && [[ $current_minute -lt 5 ]]; then
            for sat_name in "${!SATELLITES[@]}"; do
                local frequency="${SATELLITES[$sat_name]}"
                local timestamp=$(date +%Y%m%d_%H%M%S)
                local output_file="$DATA_DIR/${sat_name}_${timestamp}"
                
                if capture_satellite_data "$sat_name" "$frequency" 600 "$output_file" "VHF"; then
                    log "Successfully captured and processed data from $sat_name"
                else
                    log "Failed to capture data from $sat_name"
                fi
                
                # Wait between different satellite captures
                sleep 30
            done
        fi
        
        # Check every 30 seconds for more precise timing
        sleep 30
    done
}

# Initialize
log "Enhanced SatDump capture system started with image processing"
log "Hardware: 1690MHz Antenna + Sawbird+ GOES LNA + GOES Filter + RTL-SDR"

if ! check_rtlsdr; then
    log "FATAL: RTL-SDR initialization failed" 
    exit 1
fi

# Create directories
mkdir -p "$DATA_DIR" "$PROCESSED_DIR" "$IMAGES_DIR"
touch "$UPLOAD_QUEUE"

# Parse command line arguments
case "${1:-auto}" in
    "auto")
        auto_capture_mode
        ;;
    "capture")
        local sat_name="$2"
        local duration="${3:-600}"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local output_file="$DATA_DIR/${sat_name}_${timestamp}"
        
        # Determine satellite type
        local satellite_type="VHF"
        local frequency
        if [[ -n "${GOES_SATELLITES[$sat_name]}" ]]; then
            satellite_type="GOES"
            frequency="${GOES_SATELLITES[$sat_name]}"
        elif [[ -n "${SATELLITES[$sat_name]}" ]]; then
            frequency="${SATELLITES[$sat_name]}"
        else
            log "ERROR: Invalid satellite name: $sat_name"
            exit 1
        fi
        
        capture_satellite_data "$sat_name" "$frequency" "$duration" "$output_file" "$satellite_type"
        ;;
    "process")
        # Process existing raw file
        raw_file="$2"
        sat_name="$3"
        sat_type="${4:-VHF}"
        
        if [[ -f "$raw_file" ]]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            process_satellite_data "$raw_file" "$sat_name" "$sat_type" "$timestamp"
        else
            log "ERROR: Raw file not found: $raw_file"
            exit 1
        fi
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
        echo "Usage: $0 [auto|capture <satellite> <duration>|process <raw_file> <satellite> <type>|test]"
        echo ""
        echo "Examples:"
        echo "  $0 auto                              # Automatic mode with image processing"
        echo "  $0 capture GOES-18 300               # Capture GOES-18 for 5 minutes"
        echo "  $0 process file.raw GOES-18 GOES     # Process existing raw file"
        echo "  $0 test                              # Test RTL-SDR"
        exit 1
        ;;
esac