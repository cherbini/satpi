#!/bin/bash
# Process GOES data and upload images
# Integrates SatDump processing with upload pipeline

LOG_FILE="$HOME/process-upload.log"
DATA_DIR="$HOME/sat-data"
PROCESSED_DIR="$HOME/sat-data/processed"
UPLOAD_QUEUE="/tmp/upload-queue"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

process_goes_file() {
    local raw_file="$1"
    local base_name=$(basename "$raw_file" .raw)
    local output_dir="$PROCESSED_DIR/$base_name"
    
    log "🔄 Processing GOES data: $base_name"
    
    # Create output directory
    mkdir -p "$output_dir"
    
    # Process with SatDump GOES HRIT pipeline (our proven frequency + HRIT)
    timeout 1200 satdump goes_hrit baseband "$raw_file" "$output_dir" \
        --samplerate 2048000 --baseband_format u8 --dc_block --fill_missing 2>&1 | tee -a "$LOG_FILE"
    
    if [[ $? -eq 0 ]]; then
        log "✅ SatDump processing completed for $base_name"
        
        # Find generated images
        local image_count=0
        find "$output_dir" -name "*.jpg" -o -name "*.png" | while read image_file; do
            if [[ -f "$image_file" ]]; then
                log "📸 Found image: $(basename "$image_file")"
                # Add to upload queue
                echo "$image_file|GOES-18|$(date -Iseconds)|IMAGE" >> "$UPLOAD_QUEUE"
                ((image_count++))
            fi
        done
        
        if [[ $image_count -gt 0 ]]; then
            log "🎉 Generated $image_count images for upload"
        else
            log "⚠️ No images generated from processing"
        fi
        
        return 0
    else
        log "❌ SatDump processing failed for $base_name"
        return 1
    fi
}

# Main processing loop
mkdir -p "$PROCESSED_DIR"
log "🚀 GOES processing daemon started"

while true; do
    # Look for unprocessed raw files
    for raw_file in "$DATA_DIR"/GOES-18_*.raw; do
        if [[ -f "$raw_file" ]]; then
            base_name=$(basename "$raw_file" .raw)
            processed_marker="$PROCESSED_DIR/$base_name.processed"
            
            # Skip if already processed
            if [[ -f "$processed_marker" ]]; then
                continue
            fi
            
            # Check file age (wait 5 minutes after capture)
            file_age=$(($(date +%s) - $(stat -c %Y "$raw_file")))
            if [[ $file_age -lt 300 ]]; then
                continue
            fi
            
            log "🔍 Found unprocessed file: $base_name"
            
            if process_goes_file "$raw_file"; then
                # Mark as processed
                touch "$processed_marker"
                log "✅ Marked as processed: $base_name"
            else
                log "❌ Processing failed: $base_name"
                # Wait before retry
                sleep 300
            fi
        fi
    done
    
    # Check every 2 minutes
    sleep 120
done