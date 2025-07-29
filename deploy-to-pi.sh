#!/bin/bash
# Automated deployment script for GOES updates
# Run this from your local machine where you can reach 192.168.99.31

PI_IP="192.168.99.31"
PI_USER="johnc"
PI_SATPI_DIR="/home/johnc/satpi"

set -e

echo "🛰️  Deploying GOES Updates to SatPi"
echo "==================================="
echo ""

# Test connectivity
echo "📡 Testing connection to Pi..."
if ! ping -c 1 -W 5 "$PI_IP" >/dev/null 2>&1; then
    echo "❌ Cannot reach Pi at $PI_IP"
    echo "Make sure you're on the same network and the Pi is powered on"
    exit 1
fi
echo "✅ Pi is reachable"
echo ""

# Copy updated files
echo "📤 Copying updated files to Pi..."
scp -o StrictHostKeyChecking=no \
    satdump-capture.sh \
    goes-aiming-tool.sh \
    data-uploader.py \
    location-reporter.py \
    README.md \
    aim-antenna \
    aim-simple \
    "${PI_USER}@${PI_IP}:${PI_SATPI_DIR}/"

echo "✅ Files copied successfully"
echo ""

# SSH in and make executable, restart services
echo "🔧 Configuring files on Pi..."
ssh -o StrictHostKeyChecking=no "${PI_USER}@${PI_IP}" << 'EOF'
    set -e
    
    # Make scripts executable
    sudo chmod +x /home/johnc/satpi/satdump-capture.sh
    sudo chmod +x /home/johnc/satpi/goes-aiming-tool.sh
    sudo chmod +x /home/johnc/satpi/aim-antenna
    sudo chmod +x /home/johnc/satpi/aim-simple
    
    # Install aim commands in /usr/local/bin for system-wide access
    sudo cp /home/johnc/satpi/aim-antenna /usr/local/bin/
    sudo cp /home/johnc/satpi/aim-simple /usr/local/bin/
    sudo chmod +x /usr/local/bin/aim-antenna
    sudo chmod +x /usr/local/bin/aim-simple
    
    # Set ownership
    sudo chown -R johnc:johnc /home/johnc/satpi/
    
    # Restart services to pick up changes
    echo "🔄 Restarting SatPi services..."
    sudo systemctl restart satdump-capture.service data-uploader.service || true
    
    echo "✅ Configuration complete"
EOF

echo ""
echo "🎉 GOES Deployment Complete!"
echo ""
echo "New capabilities added:"
echo "  • GOES-18 West Coast targeting (1686.6 MHz)"
echo "  • Sawbird+ LNA optimized settings (20dB RTL-SDR gain)"
echo "  • Interactive antenna aiming tool"
echo "  • Automatic GOES capture every 30 minutes"
echo "  • Fixed aim-antenna and aim-simple commands"
echo ""
echo "🧪 Test commands (run these on the Pi):"
echo "  ssh ${PI_USER}@${PI_IP}"
echo "  aim-antenna                    # Interactive aiming tool"
echo "  aim-simple                     # Quick signal test"
echo "  ./satdump-capture.sh list"
echo "  ./satdump-capture.sh goes test"
echo "  ./goes-aiming-tool.sh"
echo ""
echo "📊 Monitor logs:"
echo "  tail -f /var/log/satdump.log" 