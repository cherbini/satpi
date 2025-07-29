#!/bin/bash

DATA_DIR="/home/johnc/sat-data"
MAX_SIZE_GB=20
MAX_SIZE_BYTES=$((MAX_SIZE_GB * 1024 * 1024 * 1024))

# Function to get directory size in bytes
get_dir_size() {
    du -sb "$DATA_DIR" 2>/dev/null | cut -f1
}

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/satdump.log
}

log "Starting data directory cleanup (max size: ${MAX_SIZE_GB}GB)"

current_size=$(get_dir_size)
log "Current directory size: $((current_size / 1024 / 1024 / 1024))GB"

if [ "$current_size" -gt "$MAX_SIZE_BYTES" ]; then
    log "Directory size exceeds limit, cleaning up oldest files..."
    
    # Remove oldest .raw files first until under limit
    while [ "$(get_dir_size)" -gt "$MAX_SIZE_BYTES" ]; do
        oldest_raw=$(find "$DATA_DIR" -name "*.raw" -type f -printf '%T@ %p\n' | sort -n | head -1 | cut -d' ' -f2-)
        
        if [ -n "$oldest_raw" ] && [ -f "$oldest_raw" ]; then
            file_size=$(stat -c%s "$oldest_raw")
            log "Removing oldest raw file: $oldest_raw ($((file_size / 1024 / 1024))MB)"
            rm -f "$oldest_raw"
        else
            break
        fi
    done
    
    # If still over limit, remove oldest processed files
    while [ "$(get_dir_size)" -gt "$MAX_SIZE_BYTES" ]; do
        oldest_file=$(find "$DATA_DIR" -type f ! -name "*.raw" -printf '%T@ %p\n' | sort -n | head -1 | cut -d' ' -f2-)
        
        if [ -n "$oldest_file" ] && [ -f "$oldest_file" ]; then
            log "Removing oldest processed file: $oldest_file"
            rm -f "$oldest_file"
        else
            break
        fi
    done
    
    final_size=$(get_dir_size)
    log "Cleanup complete. Final size: $((final_size / 1024 / 1024 / 1024))GB"
else
    log "Directory size within limit, no cleanup needed"
fi