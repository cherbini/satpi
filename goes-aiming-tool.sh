#!/bin/bash
# SatPi GOES Antenna Aiming Tool
# Optimized for Sawbird + GOES Filter + 1690 Directional Antenna Setup
# Specifically designed for GOES-18 West Coast targeting

# GOES frequencies - optimized for Sawbird + GOES filter
GOES_WEST_FREQ=1686.6    # GOES-18 West (primary target)
GOES_EAST_FREQ=1694.1    # GOES-16 East 
DEFAULT_FREQ=$GOES_WEST_FREQ

# RTL-SDR settings optimized for Sawbird LNA + GOES filter setup
SAMPLE_RATE=2048000      # 2.048 MHz - good for 1690 MHz
GAIN=20                  # Lower gain due to Sawbird LNA (prevents overload)
PPM_CORRECTION=0
INTEGRATION_TIME=5       # Longer integration for better SNR

# Display colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           SatPi GOES Antenna Aiming Tool             ║${NC}"
    echo -e "${CYAN}║      Optimized for Sawbird + GOES Filter Setup      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Hardware Setup Detected:${NC}"
    echo "  📡 1690 MHz Directional Antenna"
    echo "  🔋 Sawbird+ GOES LNA (30dB gain, 1dB NF)"
    echo "  🎛️  GOES Bandpass Filter (1680-1700 MHz)"
    echo "  📻 RTL-SDR (tuned for high-gain setup)"
    echo ""
    echo -e "${YELLOW}Optimized Settings:${NC}"
    echo "  • RTL-SDR Gain: ${GAIN}dB (reduced for LNA)"
    echo "  • Integration: ${INTEGRATION_TIME}s (improved SNR)"
    echo "  • Target: GOES-18 West (${GOES_WEST_FREQ} MHz)"
    echo ""
}

check_system() {
    if ! command -v rtl_sdr >/dev/null 2>&1; then
        echo -e "${RED}❌ RTL-SDR tools not found${NC}"
        exit 1
    fi
    
    if ! rtl_test -t >/dev/null 2>&1; then
        echo -e "${RED}❌ RTL-SDR device not detected${NC}"
        echo ""
        echo "Hardware checklist:"
        echo "  1. RTL-SDR connected to USB"
        echo "  2. Antenna → GOES Filter → Sawbird LNA → RTL-SDR"
        exit 1
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "Installing bc calculator..."
        sudo apt install -y bc >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}✓ System check passed${NC}"
    echo ""
}

calculate_signal_strength() {
    local power_db="$1"
    local color
    
    if (( $(echo "$power_db > -60" | bc -l) )); then
        color=$GREEN
    elif (( $(echo "$power_db > -80" | bc -l) )); then
        color=$YELLOW
    else
        color=$RED
    fi
    
    echo -e "${color}${power_db}dB${NC}"
}

draw_signal_bar() {
    local power_db="$1"
    local bars=""
    local color
    
    # Normalize signal: -120dB = 0 bars, -40dB = 20 bars
    local normalized=$(echo "scale=0; ($power_db + 120) / 4" | bc -l)
    if (( normalized < 0 )); then normalized=0; fi
    if (( normalized > 20 )); then normalized=20; fi
    
    if (( normalized > 15 )); then
        color=$GREEN
    elif (( normalized > 10 )); then
        color=$YELLOW
    else
        color=$RED
    fi
    
    for ((i=0; i<normalized; i++)); do
        bars="${bars}█"
    done
    
    for ((i=normalized; i<20; i++)); do
        bars="${bars}░"
    done
    
    echo -e "${color}$bars${NC}"
}

monitor_goes_signal() {
    local freq=$1
    local satellite_name="GOES-18 West"
    
    if (( $(echo "$freq == $GOES_EAST_FREQ" | bc -l) )); then
        satellite_name="GOES-16 East"
    fi
    
    echo -e "${GREEN}🛰️  Starting $satellite_name Signal Monitor${NC}"
    echo "================================================"
    echo -e "${BLUE}Frequency: $freq MHz${NC}"
    echo -e "${BLUE}Hardware: Sawbird + GOES Filter + RTL-SDR${NC}"
    echo ""
    echo -e "${YELLOW}Aiming Instructions:${NC}"
    echo "  1. Point antenna towards satellite (see coordinates below)"
    echo "  2. Watch signal strength meter below"
    echo "  3. Adjust antenna for maximum signal"
    echo "  4. Press Ctrl+C when satisfied with signal level"
    echo ""
    
    if (( $(echo "$freq == $GOES_WEST_FREQ" | bc -l) )); then
        echo -e "${CYAN}GOES-18 West Pointing (from US West Coast):${NC}"
        echo "  🧭 Azimuth: ~200° (SSW)"
        echo "  📐 Elevation: ~50° above horizon"
        echo "  🌍 Satellite position: 137.2°W longitude"
    else
        echo -e "${CYAN}GOES-16 East Pointing (from US East Coast):${NC}"
        echo "  🧭 Azimuth: ~180° (South)"  
        echo "  📐 Elevation: ~45° above horizon"
        echo "  🌍 Satellite position: 75.2°W longitude"
    fi
    
    echo ""
    echo -e "${YELLOW}Signal Strength Monitor:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Set frequency in Hz
    local freq_hz=$(echo "$freq * 1000000" | bc -l | cut -d. -f1)
    
    # Continuous signal monitoring
    while true; do
        # Use rtl_power for quick power measurement
        local power=$(timeout 2s rtl_power -f "$freq_hz":"$freq_hz":1000 -g $GAIN -i 0.1 -1 /dev/stdout 2>/dev/null | awk -F, '{print $6}' | head -1)
        
        if [[ -n "$power" ]]; then
            local timestamp=$(date '+%H:%M:%S')
            local strength=$(calculate_signal_strength "$power")
            local bar=$(draw_signal_bar "$power")
            
            printf "\r${BLUE}%s${NC} | Signal: %s | %s | %.1f MHz     " "$timestamp" "$strength" "$bar" "$freq"
            
            # Log strong signals
            if (( $(echo "$power > -70" | bc -l) )); then
                echo ""
                echo -e "${GREEN}🎯 Strong signal detected! Current pointing looks good.${NC}"
                echo ""
            fi
        else
            printf "\r${RED}Signal measurement failed - check hardware connection${NC}                    "
        fi
        
        sleep 1
    done
}

quick_goes_scan() {
    echo -e "${GREEN}🔍 Quick GOES Band Scan${NC}"
    echo "======================="
    echo "Scanning 1680-1700 MHz for GOES signals..."
    echo ""
    
    # Scan the GOES band with high resolution
    timeout 20s rtl_power -f 1680000000:1700000000:50000 -g $GAIN -i 2 -1 /tmp/goes_scan.csv 2>/dev/null
    
    if [ -f /tmp/goes_scan.csv ]; then
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
        echo ""
        echo -e "${YELLOW}💡 Tip: Strongest signal should be around $DEFAULT_FREQ MHz${NC}"
    else
        echo -e "${RED}❌ Scan failed - check RTL-SDR connection${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

check_lna_performance() {
    echo -e "${GREEN}🔋 Sawbird+ LNA Performance Check${NC}"
    echo "=================================="
    echo "Testing for LNA saturation"
    local test_freqs=("$GOES_WEST_FREQ" "$GOES_EAST_FREQ")
    
    for freq in "${test_freqs[@]}"; do
        local freq_hz=$(echo "$freq * 1000000" | bc -l | cut -d. -f1)
        local sat_name="GOES-18 West"
        if (( $(echo "$freq == $GOES_EAST_FREQ" | bc -l) )); then
            sat_name="GOES-16 East"
        fi
        
        echo "Testing $sat_name ($freq MHz):"
        
        for gain in 10 20 30; do
            echo -n "  RTL Gain ${gain}dB: "
            local power=$(timeout 2s rtl_power -f "$freq_hz":"$freq_hz":1000 -g $gain -i 0.1 -1 /dev/stdout 2>/dev/null | awk -F, '{print $6}' | head -1)
            
            if [[ -n "$power" ]]; then
                if (( $(echo "$power > -40" | bc -l) )); then
                    echo -e "${RED}${power}dB - SATURATED!${NC}"
                elif (( $(echo "$power > -60" | bc -l) )); then
                    echo -e "${YELLOW}${power}dB - Strong${NC}"
                else
                    echo -e "${GREEN}${power}dB - Good${NC}"
                fi
            else
                echo -e "${RED}Failed${NC}"
            fi
        done
        echo ""
    done
    
    echo -e "${CYAN}Recommended Settings:${NC}"
    echo "  • If signals are saturated (>-40dB): Lower RTL-SDR gain to 10-15dB"
    echo "  • If signals are weak (<-80dB): Check antenna pointing and connections"
    echo "  • Current setting: ${GAIN}dB (optimized for Sawbird+ LNA)"
    echo ""
    read -p "Press Enter to continue..."
}

main_menu() {
    while true; do
        show_header
        
        echo -e "${YELLOW}🎯 GOES Aiming Options:${NC}"
        echo "1) 🎯 Monitor GOES-18 West signal (recommended)"
        echo "2) 🎯 Monitor GOES-16 East signal"
        echo "3) 🔍 Quick GOES band scan"
        echo "4) 🔋 Check LNA performance"
        echo "5) ℹ️  Show pointing information"
        echo "6) 🚪 Exit"
        echo ""
        read -p "Choose option (1-6): " choice
        
        case $choice in
            1) monitor_goes_signal $GOES_WEST_FREQ ;;
            2) monitor_goes_signal $GOES_EAST_FREQ ;;
            3) quick_goes_scan ;;
            4) check_lna_performance ;;
            5) show_pointing_info ;;
            6) echo "👋 Goodbye!"; exit 0 ;;
            *) echo -e "${RED}❌ Invalid choice${NC}" ;;
        esac
    done
}

show_pointing_info() {
    echo -e "${GREEN}📡 GOES Satellite Pointing Information${NC}"
    echo "====================================="
    echo ""
    echo -e "${BLUE}🛰️  GOES-18 West (Primary Target):${NC}"
    echo "  📍 Position: 137.2°W longitude"
    echo "  📻 Frequency: $GOES_WEST_FREQ MHz"
    echo "  🧭 Azimuth: ~200° (SSW from US West Coast)"
    echo "  📐 Elevation: ~50° above horizon"
    echo "  🌎 Coverage: Western US, Pacific Ocean"
    echo ""
    echo -e "${BLUE}🛰️  GOES-16 East:${NC}"
    echo "  📍 Position: 75.2°W longitude" 
    echo "  📻 Frequency: $GOES_EAST_FREQ MHz"
    echo "  🧭 Azimuth: ~180° (South from US East Coast)"
    echo "  📐 Elevation: ~45° above horizon"
    echo "  🌎 Coverage: Eastern US, Atlantic Ocean"
    echo ""
    echo -e "${YELLOW}🔧 Hardware Setup Checklist:${NC}"
    echo "  ✓ 1690 MHz directional antenna mounted"
    echo "  ✓ GOES filter installed (1680-1700 MHz)"
    echo "  ✓ Sawbird+ LNA connected (provides 30dB gain)"
    echo "  ✓ RTL-SDR gain set to 15-25dB (avoid saturation)"
    echo "  ✓ Antenna pointed towards target satellite"
    echo ""
    echo -e "${CYAN}📶 Signal Quality Tips:${NC}"
    echo "  • Signal strength > -60dB = Excellent"
    echo "  • Signal strength > -70dB = Good"
    echo "  • Signal strength > -80dB = Usable"
    echo "  • Signal strength < -90dB = Poor (check pointing)"
    echo ""
    read -p "Press Enter to continue..."
}

# Initialize
show_header
echo "Initializing GOES aiming tool..."
check_system

# Start main menu
main_menu 