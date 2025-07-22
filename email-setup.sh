#!/bin/bash
# Email configuration setup for SatPi notifications

EMAIL_CREDS_FILE="/home/pi/satpi/email-credentials"
SMTP_CONFIG_FILE="/home/pi/satpi/email-config.json"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

create_email_config() {
    local email_user="$1"
    local email_pass="$2"
    
    log "Creating email credentials file..."
    cat > "$EMAIL_CREDS_FILE" << EOF
SATPI_EMAIL_USER=$email_user
SATPI_EMAIL_PASS=$email_pass
EOF
    
    # Secure the credentials file
    chmod 600 "$EMAIL_CREDS_FILE"
    chown pi:pi "$EMAIL_CREDS_FILE"
    
    log "Creating email configuration..."
    cat > "$SMTP_CONFIG_FILE" << EOF
{
    "smtp_server": "smtp-mail.outlook.com",
    "smtp_port": 587,
    "use_tls": true,
    "notification_email": "johncherbini@hotmail.com",
    "from_name": "SatPi Device",
    "report_frequency_hours": 24
}
EOF
    
    chown pi:pi "$SMTP_CONFIG_FILE"
    
    log "Email configuration completed"
}

test_email_setup() {
    log "Testing email configuration..."
    
    if [[ ! -f "$EMAIL_CREDS_FILE" ]]; then
        log "ERROR: Email credentials not configured"
        return 1
    fi
    
    # Source credentials
    source "$EMAIL_CREDS_FILE"
    
    if [[ -z "$SATPI_EMAIL_PASS" ]]; then
        log "ERROR: Email password not set"
        return 1
    fi
    
    # Test email sending
    export SATPI_EMAIL_USER SATPI_EMAIL_PASS
    python3 /home/pi/satpi/location-reporter.py email send
    
    if [[ $? -eq 0 ]]; then
        log "Email test successful"
        return 0
    else
        log "Email test failed"
        return 1
    fi
}

setup_gmail() {
    log "Setting up Gmail SMTP..."
    echo "For Gmail, you need to:"
    echo "1. Enable 2-factor authentication on your Google account"
    echo "2. Generate an App Password for SatPi"
    echo "3. Use the App Password (not your regular password)"
    echo ""
    read -p "Enter your Gmail address: " gmail_addr
    read -s -p "Enter your App Password: " gmail_pass
    echo ""
    
    # Update SMTP config for Gmail
    cat > "$SMTP_CONFIG_FILE" << EOF
{
    "smtp_server": "smtp.gmail.com",
    "smtp_port": 587,
    "use_tls": true,
    "notification_email": "johncherbini@hotmail.com",
    "from_name": "SatPi Device",
    "report_frequency_hours": 24
}
EOF
    
    create_email_config "$gmail_addr" "$gmail_pass"
}

setup_outlook() {
    log "Setting up Outlook/Hotmail SMTP..."
    echo "For Outlook/Hotmail accounts:"
    echo ""
    read -p "Enter your Outlook/Hotmail address: " outlook_addr
    read -s -p "Enter your password: " outlook_pass
    echo ""
    
    create_email_config "$outlook_addr" "$outlook_pass"
}

setup_custom() {
    log "Setting up custom SMTP..."
    echo "Enter your SMTP server details:"
    read -p "SMTP Server: " smtp_server
    read -p "SMTP Port (usually 587): " smtp_port
    read -p "Email address: " email_addr
    read -s -p "Password: " email_pass
    echo ""
    
    # Create custom SMTP config
    cat > "$SMTP_CONFIG_FILE" << EOF
{
    "smtp_server": "$smtp_server",
    "smtp_port": $smtp_port,
    "use_tls": true,
    "notification_email": "johncherbini@hotmail.com",
    "from_name": "SatPi Device",
    "report_frequency_hours": 24
}
EOF
    
    create_email_config "$email_addr" "$email_pass"
}

main() {
    log "SatPi Email Setup"
    echo ""
    echo "This will configure email notifications for your SatPi device."
    echo "Daily status reports will be sent to: johncherbini@hotmail.com"
    echo ""
    echo "Choose your email provider:"
    echo "1) Outlook/Hotmail (recommended)"
    echo "2) Gmail"
    echo "3) Custom SMTP"
    echo "4) Test current configuration"
    echo ""
    read -p "Select option (1-4): " choice
    
    case "$choice" in
        1)
            setup_outlook
            test_email_setup
            ;;
        2)
            setup_gmail
            test_email_setup
            ;;
        3)
            setup_custom
            test_email_setup
            ;;
        4)
            test_email_setup
            ;;
        *)
            log "Invalid choice"
            exit 1
            ;;
    esac
    
    if [[ -f "$EMAIL_CREDS_FILE" ]]; then
        log "Email setup completed!"
        log "Credentials stored in: $EMAIL_CREDS_FILE"
        log "Configuration stored in: $SMTP_CONFIG_FILE"
        log ""
        log "The location-reporter service will now send daily status reports."
        log "You can test it manually with:"
        log "  python3 /home/pi/satpi/location-reporter.py email send"
    fi
}

# Handle command line arguments
case "${1:-main}" in
    "outlook")
        setup_outlook
        ;;
    "gmail")
        setup_gmail
        ;;
    "test")
        test_email_setup
        ;;
    *)
        main
        ;;
esac