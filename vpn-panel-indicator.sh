#!/bin/bash

################################################################################
# VPN Panel Indicator
# Displays VPN status in system panel (i3bar, polybar, xfce-panel, etc.)
################################################################################

STATUS_FILE="/var/run/vpn-status"

# Icons (you can customize these)
ICON_CONNECTED="🔒"
ICON_DISCONNECTED="🔓"
ICON_WARNING="⚠️"

# Alternative text icons for terminals that don't support emojis
TEXT_CONNECTED="[VPN:ON]"
TEXT_DISCONNECTED="[VPN:OFF]"
TEXT_WARNING="[VPN:!]"

# Colors (hex format for panels)
COLOR_CONNECTED="#00FF00"
COLOR_DISCONNECTED="#FF0000"
COLOR_WARNING="#FFFF00"

################################################################################
# Helper Functions
################################################################################

get_vpn_interface() {
    ip link show 2>/dev/null | grep -E "tun[0-9]|tap[0-9]" | head -n1 | awk -F: '{print $2}' | xargs
}

get_public_ip() {
    local ip
    ip=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null || echo "N/A")
    echo "$ip"
}

check_vpn_status() {
    local vpn_iface=$(get_vpn_interface)
    if [[ -n "$vpn_iface" ]] && pgrep -x openvpn > /dev/null 2>&1; then
        return 0  # Connected
    else
        return 1  # Disconnected
    fi
}

################################################################################
# Output Formats
################################################################################

# i3bar/i3blocks format (JSON)
output_i3bar() {
    local status_text=""
    local color=""
    local icon=""

    if check_vpn_status; then
        local ip=$(get_public_ip)
        status_text="VPN: $ip"
        color="$COLOR_CONNECTED"
        icon="$ICON_CONNECTED"
    else
        status_text="VPN: OFF"
        color="$COLOR_DISCONNECTED"
        icon="$ICON_DISCONNECTED"
    fi

    # i3bar JSON format
    cat << EOF
{
  "text": "$icon $status_text",
  "tooltip": "Click to view VPN status",
  "color": "$color",
  "urgent": false
}
EOF
}

# Polybar format
output_polybar() {
    local status_text=""
    local color=""

    if check_vpn_status; then
        local ip=$(get_public_ip)
        local vpn_iface=$(get_vpn_interface)
        status_text="%{F$COLOR_CONNECTED}$ICON_CONNECTED $ip%{F-}"
    else
        status_text="%{F$COLOR_DISCONNECTED}$ICON_DISCONNECTED OFF%{F-}"
    fi

    echo "$status_text"
}

# Waybar format (JSON)
output_waybar() {
    local text=""
    local tooltip=""
    local class=""

    if check_vpn_status; then
        local ip=$(get_public_ip)
        local vpn_iface=$(get_vpn_interface)
        text="$ICON_CONNECTED $ip"
        tooltip="VPN Connected\nInterface: $vpn_iface\nPublic IP: $ip"
        class="connected"
    else
        text="$ICON_DISCONNECTED OFF"
        tooltip="VPN Disconnected\nClick to start"
        class="disconnected"
    fi

    cat << EOF
{
  "text": "$text",
  "tooltip": "$tooltip",
  "class": "$class"
}
EOF
}

# Conky format
output_conky() {
    if check_vpn_status; then
        local ip=$(get_public_ip)
        echo "\${color green}$ICON_CONNECTED VPN: $ip\${color}"
    else
        echo "\${color red}$ICON_DISCONNECTED VPN: OFF\${color}"
    fi
}

# Generic text format (for any panel)
output_text() {
    if check_vpn_status; then
        local ip=$(get_public_ip)
        echo "$TEXT_CONNECTED $ip"
    else
        echo "$TEXT_DISCONNECTED"
    fi
}

# Simple colored text (ANSI colors)
output_colored() {
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local NC='\033[0m'

    if check_vpn_status; then
        local ip=$(get_public_ip)
        echo -e "${GREEN}${TEXT_CONNECTED} ${ip}${NC}"
    else
        echo -e "${RED}${TEXT_DISCONNECTED}${NC}"
    fi
}

# Minimal format (just status)
output_minimal() {
    if check_vpn_status; then
        echo "ON"
    else
        echo "OFF"
    fi
}

# Full detailed format
output_full() {
    if check_vpn_status; then
        local ip=$(get_public_ip)
        local vpn_iface=$(get_vpn_interface)
        local uptime=""

        if [[ -f /var/run/openvpn.pid ]]; then
            local pid=$(cat /var/run/openvpn.pid)
            if ps -p "$pid" > /dev/null 2>&1; then
                uptime=$(ps -o etime= -p "$pid" | xargs)
            fi
        fi

        echo "VPN: Connected | IP: $ip | Interface: $vpn_iface | Uptime: $uptime"
    else
        echo "VPN: Disconnected | Status: No active connection"
    fi
}

# XFCE Genmon format (with click action)
output_genmon() {
    local text=""
    local tooltip=""

    if check_vpn_status; then
        local ip=$(get_public_ip)
        text="<txt>$ICON_CONNECTED $ip</txt>"
        tooltip="<tool>VPN Connected\nPublic IP: $ip\nClick to view details</tool>"
    else
        text="<txt><span color='red'>$ICON_DISCONNECTED OFF</span></txt>"
        tooltip="<tool>VPN Disconnected\nClick to start</tool>"
    fi

    cat << EOF
<txt>$text</txt>
<tool>$tooltip</tool>
<click>vpn-status.sh</click>
EOF
}

# Prometheus metrics format
output_prometheus() {
    local status_value=0
    local ip=$(get_public_ip)

    if check_vpn_status; then
        status_value=1
    fi

    cat << EOF
# HELP vpn_status VPN connection status (1=connected, 0=disconnected)
# TYPE vpn_status gauge
vpn_status $status_value

# HELP vpn_public_ip Current public IP address
# TYPE vpn_public_ip gauge
vpn_public_ip{ip="$ip"} 1
EOF
}

################################################################################
# Interactive Panel Widget
################################################################################

output_interactive() {
    echo "======================================"
    echo "   VPN Status Panel Widget"
    echo "======================================"

    while true; do
        clear
        echo "======================================"
        echo "   VPN Status Panel Widget"
        echo "======================================"
        echo ""

        if check_vpn_status; then
            local ip=$(get_public_ip)
            local vpn_iface=$(get_vpn_interface)
            echo "Status:    CONNECTED"
            echo "IP:        $ip"
            echo "Interface: $vpn_iface"
            echo ""
            echo "[Press 's' to stop VPN, 'q' to quit]"
        else
            echo "Status:    DISCONNECTED"
            echo ""
            echo "[Press 'r' to start VPN, 'q' to quit]"
        fi

        read -t 5 -n 1 key
        case "$key" in
            s|S)
                if check_vpn_status; then
                    sudo systemctl stop openvpn-killswitch
                    echo "Stopping VPN..."
                    sleep 2
                fi
                ;;
            r|R)
                if ! check_vpn_status; then
                    sudo systemctl start openvpn-killswitch
                    echo "Starting VPN..."
                    sleep 2
                fi
                ;;
            q|Q)
                exit 0
                ;;
        esac
    done
}

################################################################################
# Main
################################################################################

FORMAT="${1:-text}"

case "$FORMAT" in
    i3bar|i3blocks)
        output_i3bar
        ;;
    polybar)
        output_polybar
        ;;
    waybar)
        output_waybar
        ;;
    conky)
        output_conky
        ;;
    text|txt)
        output_text
        ;;
    colored|color)
        output_colored
        ;;
    minimal|min)
        output_minimal
        ;;
    full|detailed)
        output_full
        ;;
    genmon|xfce)
        output_genmon
        ;;
    prometheus|metrics)
        output_prometheus
        ;;
    interactive|widget)
        output_interactive
        ;;
    help|--help|-h)
        cat << EOF
VPN Panel Indicator - Display VPN status in system panel

Usage: $0 [FORMAT]

Formats:
  i3bar, i3blocks     JSON format for i3bar/i3blocks
  polybar             Format for polybar
  waybar              JSON format for waybar
  conky               Format for conky
  text, txt           Plain text format (default)
  colored, color      Colored text with ANSI codes
  minimal, min        Minimal output (ON/OFF)
  full, detailed      Full detailed status
  genmon, xfce        XFCE Genmon format
  prometheus, metrics Prometheus metrics format
  interactive, widget Interactive terminal widget
  help, --help, -h    Show this help message

Examples:
  $0 text             # Plain text output
  $0 polybar          # For use in polybar
  $0 i3bar            # For use in i3bar
  $0 interactive      # Run interactive widget

Panel Configuration Examples:

i3blocks (~/.config/i3blocks/config):
  [vpn]
  command=/usr/local/bin/vpn-panel-indicator.sh i3bar
  interval=5

Polybar (~/.config/polybar/config):
  [module/vpn]
  type = custom/script
  exec = /usr/local/bin/vpn-panel-indicator.sh polybar
  interval = 5

Waybar (~/.config/waybar/config):
  "custom/vpn": {
    "exec": "/usr/local/bin/vpn-panel-indicator.sh waybar",
    "return-type": "json",
    "interval": 5
  }

XFCE Panel (Generic Monitor):
  Command: /usr/local/bin/vpn-panel-indicator.sh genmon
  Period: 5

EOF
        ;;
    *)
        echo "Unknown format: $FORMAT"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
