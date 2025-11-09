#!/bin/bash

################################################################################
# VPN Status Monitor - Terminal Display
# Shows VPN connection status, IP address, and DNS information
################################################################################

STATUS_FILE="/var/run/vpn-status"
LOG_FILE="/var/log/openvpn-killswitch.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# Symbols
CONNECTED_SYMBOL="●"
DISCONNECTED_SYMBOL="○"
ARROW="→"

################################################################################
# Helper Functions
################################################################################

get_vpn_interface() {
    ip link show 2>/dev/null | grep -E "tun[0-9]|tap[0-9]" | head -n1 | awk -F: '{print $2}' | xargs
}

get_public_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Unable to fetch")
    echo "$ip"
}

get_dns_servers() {
    if command -v resolvectl &> /dev/null; then
        resolvectl status 2>/dev/null | grep "DNS Servers" | head -n1 | awk '{print $3}'
    else
        grep "nameserver" /etc/resolv.conf 2>/dev/null | head -n1 | awk '{print $2}'
    fi
}

get_vpn_uptime() {
    if [[ -f /var/run/openvpn.pid ]]; then
        local pid=$(cat /var/run/openvpn.pid)
        if ps -p "$pid" > /dev/null 2>&1; then
            ps -o etime= -p "$pid" | xargs
        else
            echo "N/A"
        fi
    else
        echo "N/A"
    fi
}

check_dns_leak() {
    local current_dns=$(get_dns_servers)
    local vpn_dns="1.1.1.1"  # Default, should match config

    if [[ "$current_dns" == *"$vpn_dns"* ]] || [[ "$current_dns" == *"1.0.0.1"* ]]; then
        echo -e "${GREEN}Protected${NC}"
    else
        echo -e "${RED}Potential Leak${NC}"
    fi
}

################################################################################
# Display Functions
################################################################################

print_header() {
    echo -e "\n${BOLD}${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║          OpenVPN Killswitch Status Monitor                ║${NC}"
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

show_status() {
    clear
    print_header

    # Check if VPN service is running
    local service_status="Unknown"
    local status_color="$YELLOW"

    if systemctl is-active --quiet openvpn-killswitch 2>/dev/null; then
        service_status="Active"
        status_color="$GREEN"
    elif systemctl list-unit-files | grep -q openvpn-killswitch 2>/dev/null; then
        service_status="Inactive"
        status_color="$RED"
    fi

    # Get VPN interface
    local vpn_iface=$(get_vpn_interface)

    # Check VPN connection
    if [[ -n "$vpn_iface" ]] && pgrep -x openvpn > /dev/null 2>&1; then
        # VPN is connected
        echo -e "${BOLD}Status:${NC}          ${GREEN}${CONNECTED_SYMBOL} CONNECTED${NC}"
        echo -e "${BOLD}Interface:${NC}       ${GREEN}$vpn_iface${NC}"

        local ip=$(get_public_ip)
        echo -e "${BOLD}Public IP:${NC}       ${GREEN}$ip${NC}"

        local dns=$(get_dns_servers)
        echo -e "${BOLD}DNS Server:${NC}      ${GREEN}$dns${NC}"

        local dns_status=$(check_dns_leak)
        echo -e "${BOLD}DNS Status:${NC}      $dns_status"

        local uptime=$(get_vpn_uptime)
        echo -e "${BOLD}Uptime:${NC}          ${GREEN}$uptime${NC}"

        echo -e "${BOLD}Service:${NC}         ${status_color}$service_status${NC}"

        # Check killswitch status
        if iptables -L -n 2>/dev/null | grep -q "policy DROP"; then
            echo -e "${BOLD}Killswitch:${NC}      ${GREEN}${CONNECTED_SYMBOL} ENABLED${NC}"
        else
            echo -e "${BOLD}Killswitch:${NC}      ${YELLOW}${DISCONNECTED_SYMBOL} DISABLED${NC}"
        fi

    else
        # VPN is not connected
        echo -e "${BOLD}Status:${NC}          ${RED}${DISCONNECTED_SYMBOL} DISCONNECTED${NC}"
        echo -e "${BOLD}Interface:${NC}       ${RED}None${NC}"

        local ip=$(get_public_ip)
        echo -e "${BOLD}Public IP:${NC}       ${RED}$ip ${YELLOW}(EXPOSED!)${NC}"

        local dns=$(get_dns_servers)
        echo -e "${BOLD}DNS Server:${NC}      ${RED}$dns${NC}"

        echo -e "${BOLD}Service:${NC}         ${status_color}$service_status${NC}"

        echo -e "\n${YELLOW}⚠  WARNING: VPN is not connected! Your traffic is not protected.${NC}"
    fi

    print_separator

    # Traffic statistics
    if [[ -n "$vpn_iface" ]]; then
        echo -e "\n${BOLD}${BLUE}Traffic Statistics:${NC}"
        local rx_bytes=$(cat "/sys/class/net/$vpn_iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        local tx_bytes=$(cat "/sys/class/net/$vpn_iface/statistics/tx_bytes" 2>/dev/null || echo 0)

        local rx_mb=$((rx_bytes / 1024 / 1024))
        local tx_mb=$((tx_bytes / 1024 / 1024))

        echo -e "  ${ARROW} Downloaded: ${GREEN}${rx_mb} MB${NC}"
        echo -e "  ${ARROW} Uploaded:   ${GREEN}${tx_mb} MB${NC}"
    fi

    # Recent logs
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "\n${BOLD}${BLUE}Recent Activity:${NC}"
        tail -n 5 "$LOG_FILE" | while read -r line; do
            if [[ "$line" == *"ERROR"* ]]; then
                echo -e "  ${RED}•${NC} ${line:0:80}"
            elif [[ "$line" == *"WARNING"* ]]; then
                echo -e "  ${YELLOW}•${NC} ${line:0:80}"
            elif [[ "$line" == *"SUCCESS"* ]]; then
                echo -e "  ${GREEN}•${NC} ${line:0:80}"
            else
                echo -e "  ${BLUE}•${NC} ${line:0:80}"
            fi
        done
    fi

    print_separator
    echo -e "\n${BOLD}Commands:${NC}"
    echo -e "  ${CYAN}sudo systemctl start openvpn-killswitch${NC}   - Start VPN"
    echo -e "  ${CYAN}sudo systemctl stop openvpn-killswitch${NC}    - Stop VPN"
    echo -e "  ${CYAN}sudo systemctl restart openvpn-killswitch${NC} - Restart VPN"
    echo -e "  ${CYAN}sudo journalctl -u openvpn-killswitch -f${NC}  - View logs\n"
}

show_watch() {
    while true; do
        show_status
        echo -e "${BOLD}${YELLOW}Refreshing every 3 seconds... (Press Ctrl+C to exit)${NC}"
        sleep 3
    done
}

show_compact() {
    local vpn_iface=$(get_vpn_interface)

    if [[ -n "$vpn_iface" ]] && pgrep -x openvpn > /dev/null 2>&1; then
        local ip=$(get_public_ip)
        echo -e "${GREEN}${CONNECTED_SYMBOL}${NC} VPN: ${GREEN}Connected${NC} | IP: ${GREEN}$ip${NC} | Interface: ${GREEN}$vpn_iface${NC}"
    else
        local ip=$(get_public_ip)
        echo -e "${RED}${DISCONNECTED_SYMBOL}${NC} VPN: ${RED}Disconnected${NC} | IP: ${RED}$ip${NC} ${YELLOW}(EXPOSED)${NC}"
    fi
}

show_json() {
    local vpn_iface=$(get_vpn_interface)
    local status="disconnected"
    local ip=$(get_public_ip)
    local dns=$(get_dns_servers)

    if [[ -n "$vpn_iface" ]] && pgrep -x openvpn > /dev/null 2>&1; then
        status="connected"
    fi

    cat << EOF
{
  "status": "$status",
  "interface": "${vpn_iface:-null}",
  "public_ip": "$ip",
  "dns_server": "$dns",
  "uptime": "$(get_vpn_uptime)",
  "timestamp": "$(date -Iseconds)"
}
EOF
}

################################################################################
# Main
################################################################################

case "${1:-status}" in
    status|--status|-s)
        show_status
        ;;
    watch|--watch|-w)
        show_watch
        ;;
    compact|--compact|-c)
        show_compact
        ;;
    json|--json|-j)
        show_json
        ;;
    help|--help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  status, -s, --status     Show detailed VPN status (default)"
        echo "  watch, -w, --watch       Continuously monitor VPN status"
        echo "  compact, -c, --compact   Show compact one-line status"
        echo "  json, -j, --json         Output status as JSON"
        echo "  help, -h, --help         Show this help message"
        echo ""
        ;;
    *)
        echo "Invalid option. Use --help for usage information."
        exit 1
        ;;
esac
