#!/bin/bash

################################################################################
# Quick Fix for OpenVPN Connection Issues
# Resolves common "killed" errors
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Quick Fix for OpenVPN Connection                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

# Step 1: Stop killswitch service
echo -e "${CYAN}[1/5] Stopping killswitch service...${NC}"
if systemctl is-active --quiet openvpn-killswitch 2>/dev/null; then
    systemctl stop openvpn-killswitch
    echo -e "${GREEN}✓ Stopped openvpn-killswitch service${NC}"
else
    echo -e "${GREEN}✓ Service not running${NC}"
fi
sleep 1

# Step 2: Kill all OpenVPN processes
echo -e "\n${CYAN}[2/5] Killing existing OpenVPN processes...${NC}"
if pgrep -x openvpn > /dev/null; then
    pkill -9 openvpn 2>/dev/null || true
    sleep 2
    echo -e "${GREEN}✓ Killed existing OpenVPN processes${NC}"
else
    echo -e "${GREEN}✓ No existing processes${NC}"
fi

# Step 3: Disable killswitch firewall rules
echo -e "\n${CYAN}[3/5] Disabling killswitch firewall rules...${NC}"
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -F 2>/dev/null || true
iptables -X 2>/dev/null || true
iptables -t nat -F 2>/dev/null || true
iptables -t nat -X 2>/dev/null || true
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X 2>/dev/null || true
echo -e "${GREEN}✓ Firewall rules cleared${NC}"

# Step 4: Restore DNS
echo -e "\n${CYAN}[4/5] Restoring DNS configuration...${NC}"
chattr -i /etc/resolv.conf 2>/dev/null || true
if [[ -f /etc/resolv.conf.backup ]]; then
    cp /etc/resolv.conf.backup /etc/resolv.conf
    echo -e "${GREEN}✓ DNS configuration restored${NC}"
else
    echo -e "${YELLOW}⚠ No DNS backup found, using system default${NC}"
fi

# Step 5: Check configuration
echo -e "\n${CYAN}[5/5] Checking OpenVPN configuration...${NC}"
if [[ -f /etc/openvpn/client.ovpn ]]; then
    echo -e "${GREEN}✓ Found: /etc/openvpn/client.ovpn${NC}"
else
    echo -e "${RED}✗ OpenVPN config not found at /etc/openvpn/client.ovpn${NC}"
    echo -e "  Please place your .ovpn file there first!"
    exit 1
fi

# Completion message
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  CLEANUP COMPLETED                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}All conflicts have been resolved!${NC}\n"

echo -e "${YELLOW}Now you can test OpenVPN:${NC}\n"

echo -e "${CYAN}Option 1: Manual test (foreground)${NC}"
echo -e "  sudo openvpn --config /etc/openvpn/client.ovpn"
echo -e "  ${BLUE}→${NC} This will show detailed connection logs"
echo -e "  ${BLUE}→${NC} Press Ctrl+C to stop"
echo ""

echo -e "${CYAN}Option 2: Use the killswitch service (recommended)${NC}"
echo -e "  sudo systemctl start openvpn-killswitch"
echo -e "  sudo systemctl status openvpn-killswitch"
echo -e "  vpn-status.sh --watch"
echo -e "  ${BLUE}→${NC} This enables killswitch protection"
echo -e "  ${BLUE}→${NC} Runs in background with auto-reconnect"
echo ""

echo -e "${CYAN}Option 3: Background mode without killswitch${NC}"
echo -e "  sudo openvpn --config /etc/openvpn/client.ovpn --daemon"
echo -e "  ${BLUE}→${NC} Runs in background"
echo -e "  ${BLUE}→${NC} No killswitch protection"
echo ""

read -p "$(echo -e ${YELLOW}Do you want to start VPN now? [y/N]:${NC} )" -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}Starting OpenVPN...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop (connection will stay active in background)${NC}\n"
    sleep 2

    # Start OpenVPN
    openvpn --config /etc/openvpn/client.ovpn
else
    echo -e "\n${GREEN}You can start VPN manually when ready.${NC}\n"
fi
