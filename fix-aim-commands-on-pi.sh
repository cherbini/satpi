#!/bin/bash
# Copy and paste these commands on the Pi to fix aim-antenna and aim-simple

echo "🛰️  Fixing aim-antenna and aim-simple commands on Pi"
echo "================================================="

# Create the corrected aim-antenna command
sudo tee /usr/local/bin/aim-antenna > /dev/null << 'EOF'
#!/bin/bash
# aim-antenna - Interactive GOES Antenna Aiming Tool
# Wrapper for goes-aiming-tool.sh with direct access to aiming functions

SATPI_DIR="/home/johnc/satpi"
GOES_TOOL="$SATPI_DIR/goes-aiming-tool.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                aim-antenna v2.0                      ║${NC}"
    echo -e "${CYAN}║         GOES Satellite Antenna Aiming Tool          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if goes-aiming-tool.sh exists
if [[ ! -f "$GOES_TOOL" ]]; then
    echo -e "${RED}❌ Error: goes-aiming-tool.sh not found at $GOES_TOOL${NC}"
    echo "Please ensure the SatPi system is properly installed."
    exit 1
fi

# Check if RTL-SDR is available
if ! command -v rtl_sdr >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: RTL-SDR tools not found${NC}"
    echo "Please install RTL-SDR tools: sudo apt install rtl-sdr"
    exit 1
fi

if ! rtl_test -t >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: RTL-SDR device not detected${NC}"
    echo ""
    echo "Hardware checklist:"
    echo "  1. RTL-SDR connected to USB"
    echo "  2. Antenna → GOES Filter → Sawbird LNA → RTL-SDR"
    exit 1
fi

show_header

echo -e "${GREEN}🛰️  Quick GOES Aiming Options:${NC}"
echo ""
echo "1) 🎯 Start full interactive aiming tool"
echo "2) 📡 Quick GOES-18 West signal monitor"
echo "3) 📡 Quick GOES-16 East signal monitor"
echo "4) 🔍 GOES band scan (1680-1700 MHz)"
echo "5) 🚪 Exit"
echo ""

read -p "Choose option (1-5): " choice

case $choice in
    1)
        echo -e "${BLUE}🚀 Starting full interactive aiming tool...${NC}"
        exec "$GOES_TOOL"
        ;;
    2)
        echo -e "${BLUE}🛰️  Monitoring GOES-18 West (1686.6 MHz)...${NC}"
        echo "Press Ctrl+C to stop monitoring"
        echo ""
        # Monitor GOES-18 directly using rtl_power
        rtl_power -f 1686600000:1686600000:1000 -g 20 -i 1 -e 3600 /dev/stdout 2>/dev/null | \
        while IFS=, read date time start_hz end_hz step power samples; do
            timestamp=$(date '+%H:%M:%S')
            printf "\r${GREEN}%s${NC} | GOES-18 Signal: ${YELLOW}%.1f dB${NC} | 1686.6 MHz     " "$timestamp" "$power"
            if (( $(echo "$power > -70" | bc -l 2>/dev/null || echo 0) )); then
                echo ""
                echo -e "${GREEN}🎯 Strong GOES-18 signal detected!${NC}"
                echo ""
            fi
            sleep 1
        done
        ;;
    3)
        echo -e "${BLUE}🛰️  Monitoring GOES-16 East (1694.1 MHz)...${NC}"
        echo "Press Ctrl+C to stop monitoring"
        echo ""
        # Monitor GOES-16 directly using rtl_power
        rtl_power -f 1694100000:1694100000:1000 -g 20 -i 1 -e 3600 /dev/stdout 2>/dev/null | \
        while IFS=, read date time start_hz end_hz step power samples; do
            timestamp=$(date '+%H:%M:%S')
            printf "\r${GREEN}%s${NC} | GOES-16 Signal: ${YELLOW}%.1f dB${NC} | 1694.1 MHz     " "$timestamp" "$power"
            if (( $(echo "$power > -70" | bc -l 2>/dev/null || echo 0) )); then
                echo ""
                echo -e "${GREEN}🎯 Strong GOES-16 signal detected!${NC}"
                echo ""
            fi
            sleep 1
        done
        ;;
    4)
        echo -e "${BLUE}🔍 Scanning GOES band (1680-1700 MHz)...${NC}"
        echo ""
        rtl_power -f 1680000000:1700000000:50000 -g 20 -i 2 -1 /tmp/goes_scan.csv 2>/dev/null
        
        if [[ -f /tmp/goes_scan.csv ]]; then
            echo "Strongest signals in GOES band:"
            echo "==============================="
            sort -t, -k6 -nr /tmp/goes_scan.csv | head -8 | while IFS=, read date time start_hz end_hz step power samples; do
                freq_mhz=$(echo "scale=1; $start_hz / 1000000" | bc -l)
                
                # Identify known GOES frequencies
                sat_info=""
                if (( $(echo "$freq_mhz >= 1686.0 && $freq_mhz <= 1687.0" | bc -l) )); then
                    sat_info=" (GOES-18 West)"
                elif (( $(echo "$freq_mhz >= 1694.0 && $freq_mhz <= 1695.0" | bc -l) )); then
                    sat_info=" (GOES-16 East)"
                fi
                
                printf "  📡 %6.1f MHz: %6.1f dB%s\n" "$freq_mhz" "$power" "$sat_info"
            done
            
            rm -f /tmp/goes_scan.csv
        else
            echo -e "${RED}❌ Scan failed - check RTL-SDR connection${NC}"
        fi
        echo ""
        ;;
    5)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Invalid choice${NC}"
        exit 1
        ;;
esac
EOF

# Create the corrected aim-simple command
sudo tee /usr/local/bin/aim-simple > /dev/null << 'EOF'
#!/bin/bash
# aim-simple - Simple GOES Signal Strength Test
# Quick signal strength check for GOES satellites without menus

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# GOES frequencies
GOES_WEST_FREQ=1686600000    # GOES-18 West (1686.6 MHz)
GOES_EAST_FREQ=1694100000    # GOES-16 East (1694.1 MHz)

echo -e "${CYAN}aim-simple - GOES Signal Strength Test${NC}"
echo "======================================="
echo ""

# Check if RTL-SDR is available
if ! command -v rtl_sdr >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: RTL-SDR tools not found${NC}"
    echo "Please install RTL-SDR tools: sudo apt install rtl-sdr"
    exit 1
fi

if ! rtl_test -t >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: RTL-SDR device not detected${NC}"
    echo ""
    echo "Hardware checklist:"
    echo "  1. RTL-SDR connected to USB"
    echo "  2. Antenna → GOES Filter → Sawbird LNA → RTL-SDR"
    exit 1
fi

echo -e "${GREEN}✓ RTL-SDR device detected${NC}"
echo ""

# Test GOES-18 West signal
echo -e "${BLUE}📡 Testing GOES-18 West (1686.6 MHz)...${NC}"
echo -n "Measuring signal strength... "

goes18_power=$(timeout 5s rtl_power -f "$GOES_WEST_FREQ":"$GOES_WEST_FREQ":1000 -g 20 -i 1 -1 /dev/stdout 2>/dev/null | awk -F, '{print $6}' | head -1)

if [[ -n "$goes18_power" ]]; then
    if (( $(echo "$goes18_power > -60" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${GREEN}${goes18_power} dB (Excellent)${NC}"
    elif (( $(echo "$goes18_power > -70" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YELLOW}${goes18_power} dB (Good)${NC}"
    elif (( $(echo "$goes18_power > -80" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YELLOW}${goes18_power} dB (Usable)${NC}"
    else
        echo -e "${RED}${goes18_power} dB (Poor - check antenna pointing)${NC}"
    fi
else
    echo -e "${RED}Failed to measure signal${NC}"
fi

# Test GOES-16 East signal
echo -e "${BLUE}📡 Testing GOES-16 East (1694.1 MHz)...${NC}"
echo -n "Measuring signal strength... "

goes16_power=$(timeout 5s rtl_power -f "$GOES_EAST_FREQ":"$GOES_EAST_FREQ":1000 -g 20 -i 1 -1 /dev/stdout 2>/dev/null | awk -F, '{print $6}' | head -1)

if [[ -n "$goes16_power" ]]; then
    if (( $(echo "$goes16_power > -60" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${GREEN}${goes16_power} dB (Excellent)${NC}"
    elif (( $(echo "$goes16_power > -70" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YELLOW}${goes16_power} dB (Good)${NC}"
    elif (( $(echo "$goes16_power > -80" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${YELLOW}${goes16_power} dB (Usable)${NC}"
    else
        echo -e "${RED}${goes16_power} dB (Poor - check antenna pointing)${NC}"
    fi
else
    echo -e "${RED}Failed to measure signal${NC}"
fi

echo ""

# Determine best satellite
if [[ -n "$goes18_power" && -n "$goes16_power" ]]; then
    if (( $(echo "$goes18_power > $goes16_power" | bc -l 2>/dev/null || echo 0) )); then
        echo -e "${GREEN}📡 Recommendation: GOES-18 West has stronger signal${NC}"
        echo "   Target frequency: 1686.6 MHz"
        echo "   Pointing: ~200° azimuth, ~50° elevation (from US West Coast)"
    else
        echo -e "${GREEN}📡 Recommendation: GOES-16 East has stronger signal${NC}"
        echo "   Target frequency: 1694.1 MHz"
        echo "   Pointing: ~180° azimuth, ~45° elevation (from US East Coast)"
    fi
elif [[ -n "$goes18_power" ]]; then
    echo -e "${BLUE}📡 GOES-18 West signal detected${NC}"
    echo "   Use frequency: 1686.6 MHz"
elif [[ -n "$goes16_power" ]]; then
    echo -e "${BLUE}📡 GOES-16 East signal detected${NC}"
    echo "   Use frequency: 1694.1 MHz"
else
    echo -e "${RED}❌ No GOES signals detected${NC}"
    echo "   Check antenna pointing and hardware connections"
fi

echo ""
echo -e "${CYAN}Signal Quality Guide:${NC}"
echo "  > -60 dB = Excellent signal"
echo "  > -70 dB = Good signal"
echo "  > -80 dB = Usable signal"
echo "  < -90 dB = Poor signal (adjust antenna)"
echo ""

# Offer to run continuous monitoring
read -p "Run continuous monitoring? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}🔄 Starting continuous GOES-18 monitoring...${NC}"
    echo "Press Ctrl+C to stop"
    echo ""
    
    rtl_power -f "$GOES_WEST_FREQ":"$GOES_WEST_FREQ":1000 -g 20 -i 1 -e 3600 /dev/stdout 2>/dev/null | \
    while IFS=, read date time start_hz end_hz step power samples; do
        timestamp=$(date '+%H:%M:%S')
        
        # Color code the signal strength
        if (( $(echo "$power > -60" | bc -l 2>/dev/null || echo 0) )); then
            color=$GREEN
        elif (( $(echo "$power > -80" | bc -l 2>/dev/null || echo 0) )); then
            color=$YELLOW
        else
            color=$RED
        fi
        
        printf "\r${BLUE}%s${NC} | GOES-18: ${color}%.1f dB${NC} | 1686.6 MHz    " "$timestamp" "$power"
        
        # Alert on strong signals
        if (( $(echo "$power > -65" | bc -l 2>/dev/null || echo 0) )); then
            echo ""
            echo -e "${GREEN}🎯 Excellent signal detected! Antenna pointing is good.${NC}"
            echo ""
        fi
        
        sleep 1
    done
fi

echo ""
echo "👋 aim-simple completed"
EOF

# Make both commands executable
sudo chmod +x /usr/local/bin/aim-antenna
sudo chmod +x /usr/local/bin/aim-simple

echo ""
echo "✅ Fixed aim-antenna and aim-simple commands!"
echo ""
echo "🧪 Test the fixed commands:"
echo "  aim-antenna    # Interactive GOES aiming tool"
echo "  aim-simple     # Quick signal strength test" 