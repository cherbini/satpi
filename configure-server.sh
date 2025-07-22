#!/bin/bash
# Server configuration setup script for SatPi

CONFIG_FILE="/home/pi/satpi/server-config.json"
BACKUP_FILE="/home/pi/satpi/server-config.json.backup"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_backup() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        log "Created backup: $BACKUP_FILE"
    fi
}

setup_custom_server() {
    log "Setting up custom server configuration..."
    echo ""
    echo "Current default server: https://boatwizards.com/satellite"
    echo ""
    read -p "Enter your server base URL (e.g., https://myserver.com/api): " base_url
    
    if [[ -z "$base_url" ]]; then
        log "No URL provided, keeping default"
        return
    fi
    
    # Remove trailing slash
    base_url="${base_url%/}"
    
    read -p "Upload endpoint [/upload]: " upload_endpoint
    upload_endpoint="${upload_endpoint:-/upload}"
    
    read -p "Status endpoint [/status]: " status_endpoint
    status_endpoint="${status_endpoint:-/status}"
    
    read -p "Location reporting endpoint [/location]: " location_endpoint
    location_endpoint="${location_endpoint:-/location}"
    
    read -p "API key [satpi-client]: " api_key
    api_key="${api_key:-satpi-client}"
    
    read -p "Notification email [johncherbini@hotmail.com]: " notification_email
    notification_email="${notification_email:-johncherbini@hotmail.com}"
    
    read -p "Max file size in MB [100]: " max_file_size
    max_file_size="${max_file_size:-100}"
    
    read -p "Delete files after upload? [y/N]: " cleanup_choice
    cleanup_after_upload="false"
    if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
        cleanup_after_upload="true"
    fi
    
    # Create configuration
    create_backup
    
    cat > "$CONFIG_FILE" << EOF
{
  "upload_server": {
    "base_url": "$base_url",
    "upload_endpoint": "$upload_endpoint",
    "status_endpoint": "$status_endpoint",
    "location_endpoint": "$location_endpoint",
    "api_key": "$api_key",
    "timeout": 300,
    "max_file_size_mb": $max_file_size,
    "retry_attempts": 5,
    "retry_delay_seconds": 300
  },
  "notification": {
    "email": "$notification_email",
    "device_name": "SatPi Device",
    "report_frequency_hours": 24
  },
  "system": {
    "data_directory": "/home/pi/sat-data",
    "log_directory": "/var/log",
    "cleanup_after_upload": $cleanup_after_upload,
    "max_local_storage_gb": 10
  }
}
EOF
    
    chown pi:pi "$CONFIG_FILE"
    log "Server configuration saved to: $CONFIG_FILE"
}

test_configuration() {
    log "Testing server configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "ERROR: No configuration file found at $CONFIG_FILE"
        return 1
    fi
    
    # Test JSON validity
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        log "ERROR: Invalid JSON in configuration file"
        return 1
    fi
    
    # Extract server URL
    base_url=$(jq -r '.upload_server.base_url' "$CONFIG_FILE")
    status_endpoint=$(jq -r '.upload_server.status_endpoint' "$CONFIG_FILE")
    
    log "Testing connection to: ${base_url}${status_endpoint}"
    
    # Test connection
    if curl -s --connect-timeout 10 --max-time 15 "${base_url}${status_endpoint}" >/dev/null; then
        log "✓ Server connection test passed"
    else
        log "✗ Server connection test failed"
        log "  Make sure your server is running and accessible"
    fi
    
    # Test data uploader configuration
    log "Testing data uploader configuration..."
    export SATPI_CONFIG_TEST=1
    python3 /home/pi/satpi/data-uploader.py test
    
    log "Configuration test completed"
}

show_current_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Current configuration:"
        jq . "$CONFIG_FILE"
    else
        log "No configuration file found. Using defaults:"
        log "  Server: https://boatwizards.com/satellite"
        log "  Email: johncherbini@hotmail.com"
    fi
}

setup_environment_variables() {
    log "Setting up environment variable overrides..."
    echo ""
    echo "You can override configuration with environment variables:"
    echo ""
    echo "Available variables:"
    echo "  SATPI_UPLOAD_URL - Override server base URL"
    echo "  SATPI_API_KEY - Override API key"
    echo "  SATPI_NOTIFICATION_EMAIL - Override notification email"
    echo ""
    
    read -p "Set SATPI_UPLOAD_URL? [current: $(printenv SATPI_UPLOAD_URL)]: " upload_url
    if [[ -n "$upload_url" ]]; then
        echo "export SATPI_UPLOAD_URL=\"$upload_url\"" >> /home/pi/.bashrc
        export SATPI_UPLOAD_URL="$upload_url"
        log "Set SATPI_UPLOAD_URL=$upload_url"
    fi
    
    read -p "Set SATPI_API_KEY? [current: $(printenv SATPI_API_KEY)]: " api_key
    if [[ -n "$api_key" ]]; then
        echo "export SATPI_API_KEY=\"$api_key\"" >> /home/pi/.bashrc
        export SATPI_API_KEY="$api_key"
        log "Set SATPI_API_KEY=$api_key"
    fi
    
    read -p "Set SATPI_NOTIFICATION_EMAIL? [current: $(printenv SATPI_NOTIFICATION_EMAIL)]: " email
    if [[ -n "$email" ]]; then
        echo "export SATPI_NOTIFICATION_EMAIL=\"$email\"" >> /home/pi/.bashrc
        export SATPI_NOTIFICATION_EMAIL="$email"
        log "Set SATPI_NOTIFICATION_EMAIL=$email"
    fi
    
    log "Environment variables configured. Source ~/.bashrc or restart services to apply."
}

restore_backup() {
    if [[ -f "$BACKUP_FILE" ]]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE"
        log "Configuration restored from backup"
    else
        log "No backup file found"
    fi
}

restart_services() {
    log "Restarting SatPi services to apply configuration changes..."
    systemctl restart data-uploader.service
    systemctl restart location-reporter.service
    systemctl restart satdump-capture.service
    log "Services restarted"
}

main() {
    log "SatPi Server Configuration Tool"
    echo ""
    echo "Choose an option:"
    echo "1) Configure custom server"
    echo "2) Test current configuration"
    echo "3) Show current configuration"
    echo "4) Set environment variable overrides"
    echo "5) Restore from backup"
    echo "6) Restart services"
    echo ""
    read -p "Select option (1-6): " choice
    
    case "$choice" in
        1)
            setup_custom_server
            restart_services
            ;;
        2)
            test_configuration
            ;;
        3)
            show_current_config
            ;;
        4)
            setup_environment_variables
            ;;
        5)
            restore_backup
            restart_services
            ;;
        6)
            restart_services
            ;;
        *)
            log "Invalid choice"
            exit 1
            ;;
    esac
}

# Handle command line arguments
case "${1:-main}" in
    "setup")
        setup_custom_server
        restart_services
        ;;
    "test")
        test_configuration
        ;;
    "show")
        show_current_config
        ;;
    "env")
        setup_environment_variables
        ;;
    "restore")
        restore_backup
        restart_services
        ;;
    "restart")
        restart_services
        ;;
    *)
        main
        ;;
esac