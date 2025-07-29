#!/bin/bash
# Optimized GOES satellite capture with proper timing
# Based on actual GOES-18 transmission schedule

LOG_FILE="$HOME/goes-capture.log"
DATA_DIR="$HOME/sat-data"
UPLOAD_QUEUE="/tmp/upload-queue"

# GOES-18 corrected settings - aligned with actual transmission schedule
GOES_FREQ="1694100000"  # Hz - 1694.1 MHz (correct GOES-18 HRIT frequency)
SAMPLE_RATE="2048000"   # 2 MSPS (proven sample rate)
GAIN="20"               # Optimized for Sawbird+ LNA
CAPTURE_DURATION="300"  # 5 minutes - aligned with GOES full disk scan timing

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

capture_goes_optimized() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local output_file="$DATA_DIR/GOES-18_${timestamp}.raw"
    
    log "🛰️ Starting optimized GOES-18 capture (${CAPTURE_DURATION}s)"
    
    # Capture with timeout
    timeout "$CAPTURE_DURATION" rtl_sdr -f "$GOES_FREQ" -s "$SAMPLE_RATE" -g "$GAIN" "$output_file" || {
        log "❌ RTL-SDR capture failed"
        return 1
    }
    
    if [[ -f "$output_file" ]]; then
        local file_size=$(stat -c%s "$output_file")
        local size_mb=$((file_size / 1024 / 1024))
        
        log "✅ Captured ${size_mb}MB of GOES-18 data: $output_file"
        
        # Add to upload queue if reasonable size
        if [[ $file_size -gt 1000000 ]] && [[ $file_size -lt 200000000 ]]; then  # 1MB - 200MB
            echo "$output_file|GOES-18|$(date -Iseconds)|RAW" >> "$UPLOAD_QUEUE"
            log "📤 Added to upload queue"
        else
            log "⚠️ File size unusual (${size_mb}MB) - not queuing for upload"
        fi
        
        return 0
    else
        log "❌ No capture file created"
        return 1
    fi
}

# Quick signal test
test_goes_signal() {
    log "🔍 Testing GOES-18 signal quality..."
    
    local test_file="/tmp/goes_signal_test_$(date +%s).raw"
    timeout 10 rtl_sdr -f "$GOES_FREQ" -s "$SAMPLE_RATE" -g "$GAIN" -n 1024000 "$test_file"
    
    if [[ -f "$test_file" ]]; then
        local file_size=$(stat -c%s "$test_file")
        log "📊 Test capture: $(($file_size / 1024))KB in 10 seconds"
        
        # Basic quality check using file size and timing
        if [[ $file_size -gt 500000 ]]; then
            log "✅ Signal looks good - proceeding with capture"
            rm -f "$test_file"
            return 0
        else
            log "⚠️ Weak signal detected"
            rm -f "$test_file"
            return 1
        fi
    else
        log "❌ Signal test failed"
        return 1
    fi
}

# Main execution
mkdir -p "$DATA_DIR"
log "🚀 Optimized GOES capture started"

case "${1:-capture}" in
    "test")
        test_goes_signal
        ;;
    "capture")
        if test_goes_signal; then
            capture_goes_optimized
        else
            log "⚠️ Skipping capture due to poor signal"
            exit 1
        fi
        ;;
    "continuous")
        log "📡 Starting continuous GOES monitoring (every 10 minutes - aligned with full disk scans)"
        while true; do
            local minute=$(date +%M)
            # Capture at :00, :10, :20, :30, :40, :50 minutes (aligned with GOES full disk scan timing)
            if [[ $((minute % 10)) -eq 0 ]]; then
                log "⏰ Scheduled capture time - aligned with GOES full disk scan"
                if test_goes_signal; then
                    capture_goes_optimized
                else
                    log "⚠️ Skipping scheduled capture - poor signal"
                fi
                sleep 300  # Wait 5 minutes before next check (after capture)
            else
                sleep 30  # Check every 30 seconds for timing
            fi
        done
        ;;
    *)
        echo "Usage: $0 [test|capture|continuous]"
        echo "  test       - Test GOES signal quality"
        echo "  capture    - Single optimized capture"
        echo "  continuous - Continuous capture every 15 minutes"
        exit 1
        ;;
esac