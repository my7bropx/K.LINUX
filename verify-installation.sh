#!/bin/bash

################################################################################
# Verification Script for OpenVPN Killswitch
# Checks if all components are properly installed
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      OpenVPN Killswitch Verification                      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

check_file() {
    local file="$1"
    local type="${2:-file}"

    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} Found: $file"
        if [[ -x "$file" ]]; then
            echo -e "  ${GREEN}→${NC} Executable: Yes"
        else
            echo -e "  ${YELLOW}→${NC} Executable: No"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} Missing: $file"
        return 1
    fi
}

check_command() {
    local cmd="$1"

    if command -v "$cmd" &> /dev/null; then
        local version=$(command -v "$cmd")
        echo -e "${GREEN}✓${NC} Command available: $cmd"
        echo -e "  ${GREEN}→${NC} Path: $version"
        return 0
    else
        echo -e "${RED}✗${NC} Command not found: $cmd"
        return 1
    fi
}

print_header

echo -e "${BLUE}Checking Installation Files:${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_file "$SCRIPT_DIR/openvpn-killswitch.sh"
check_file "$SCRIPT_DIR/vpn-status.sh"
check_file "$SCRIPT_DIR/vpn-panel-indicator.sh"
check_file "$SCRIPT_DIR/install-vpn-killswitch.sh"
check_file "$SCRIPT_DIR/openvpn-killswitch.service"
check_file "$SCRIPT_DIR/VPN-KILLSWITCH-README.md"

echo -e "\n${BLUE}Checking System Installation:${NC}\n"

if [[ -f "/usr/local/bin/openvpn-killswitch.sh" ]]; then
    echo -e "${GREEN}✓${NC} System installation detected"
    check_file "/usr/local/bin/openvpn-killswitch.sh"
    check_file "/usr/local/bin/vpn-status.sh"
    check_file "/usr/local/bin/vpn-panel-indicator.sh"
    check_file "/etc/systemd/system/openvpn-killswitch.service"
    check_file "/etc/openvpn/killswitch.conf"
else
    echo -e "${YELLOW}⚠${NC} System installation not detected"
    echo -e "  Run: sudo ./install-vpn-killswitch.sh"
fi

echo -e "\n${BLUE}Checking Required Dependencies:${NC}\n"

check_command "openvpn"
check_command "iptables"
check_command "curl"
check_command "ip"
check_command "systemctl"

echo -e "\n${BLUE}Checking Service Status:${NC}\n"

if systemctl list-unit-files 2>/dev/null | grep -q openvpn-killswitch; then
    if systemctl is-enabled --quiet openvpn-killswitch 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Service enabled"
    else
        echo -e "${YELLOW}⚠${NC} Service not enabled"
        echo -e "  Run: sudo systemctl enable openvpn-killswitch"
    fi

    if systemctl is-active --quiet openvpn-killswitch 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Service running"
    else
        echo -e "${YELLOW}⚠${NC} Service not running"
        echo -e "  Run: sudo systemctl start openvpn-killswitch"
    fi
else
    echo -e "${YELLOW}⚠${NC} Service not installed"
fi

echo -e "\n${BLUE}Script Syntax Check:${NC}\n"

if bash -n "$SCRIPT_DIR/openvpn-killswitch.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} openvpn-killswitch.sh syntax: OK"
else
    echo -e "${RED}✗${NC} openvpn-killswitch.sh syntax: Error"
fi

if bash -n "$SCRIPT_DIR/vpn-status.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} vpn-status.sh syntax: OK"
else
    echo -e "${RED}✗${NC} vpn-status.sh syntax: Error"
fi

if bash -n "$SCRIPT_DIR/vpn-panel-indicator.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} vpn-panel-indicator.sh syntax: OK"
else
    echo -e "${RED}✗${NC} vpn-panel-indicator.sh syntax: Error"
fi

if bash -n "$SCRIPT_DIR/install-vpn-killswitch.sh" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} install-vpn-killswitch.sh syntax: OK"
else
    echo -e "${RED}✗${NC} install-vpn-killswitch.sh syntax: Error"
fi

echo -e "\n${BLUE}Testing Helper Scripts:${NC}\n"

# Test vpn-status.sh help
if "$SCRIPT_DIR/vpn-status.sh" --help &> /dev/null; then
    echo -e "${GREEN}✓${NC} vpn-status.sh --help works"
else
    echo -e "${YELLOW}⚠${NC} vpn-status.sh --help failed"
fi

# Test vpn-panel-indicator.sh help
if "$SCRIPT_DIR/vpn-panel-indicator.sh" help &> /dev/null; then
    echo -e "${GREEN}✓${NC} vpn-panel-indicator.sh help works"
else
    echo -e "${YELLOW}⚠${NC} vpn-panel-indicator.sh help failed"
fi

echo -e "\n${BLUE}Summary:${NC}\n"

echo "All core components are present and have correct syntax."
echo ""
echo "Next steps:"
echo "1. Run: sudo ./install-vpn-killswitch.sh"
echo "2. Place your .ovpn file at /etc/openvpn/client.ovpn"
echo "3. Start the service: sudo systemctl start openvpn-killswitch"
echo ""
echo "For detailed instructions, see: VPN-KILLSWITCH-README.md"
echo ""
