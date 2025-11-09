#!/bin/bash

################################################################################
# OpenVPN Connection Troubleshooter
# Diagnoses why OpenVPN gets killed
################################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        OpenVPN Connection Troubleshooter                  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

# 1. Check if killswitch service is running
echo -e "${CYAN}[1] Checking for killswitch service...${NC}"
if systemctl is-active --quiet openvpn-killswitch 2>/dev/null; then
    echo -e "${YELLOW}⚠ OpenVPN killswitch service is RUNNING${NC}"
    echo -e "  This might be causing conflicts!"
    echo -e "  ${GREEN}Solution:${NC} Stop it before manual testing:"
    echo -e "  ${BLUE}sudo systemctl stop openvpn-killswitch${NC}\n"
else
    echo -e "${GREEN}✓ Killswitch service is not running${NC}\n"
fi

# 2. Check for other OpenVPN processes
echo -e "${CYAN}[2] Checking for other OpenVPN processes...${NC}"
OPENVPN_PROCS=$(pgrep -a openvpn)
if [[ -n "$OPENVPN_PROCS" ]]; then
    echo -e "${YELLOW}⚠ Found running OpenVPN processes:${NC}"
    echo "$OPENVPN_PROCS" | while read -r line; do
        echo -e "  ${YELLOW}→${NC} $line"
    done
    echo -e "\n  ${GREEN}Solution:${NC} Kill them before testing:"
    echo -e "  ${BLUE}sudo pkill -9 openvpn${NC}\n"
else
    echo -e "${GREEN}✓ No other OpenVPN processes running${NC}\n"
fi

# 3. Check recent system logs for OOM killer
echo -e "${CYAN}[3] Checking for OOM (Out of Memory) kills...${NC}"
OOM_LOGS=$(journalctl -k --since "5 minutes ago" 2>/dev/null | grep -i "killed process\|out of memory\|oom" | grep -i openvpn)
if [[ -n "$OOM_LOGS" ]]; then
    echo -e "${RED}✗ Found OOM killer events:${NC}"
    echo "$OOM_LOGS"
    echo -e "\n  ${GREEN}Solution:${NC} System is low on memory. Close some applications.\n"
else
    echo -e "${GREEN}✓ No OOM killer events found${NC}\n"
fi

# 4. Check dmesg for kills
echo -e "${CYAN}[4] Checking kernel logs (dmesg) for kills...${NC}"
DMESG_LOGS=$(dmesg -T 2>/dev/null | tail -50 | grep -i "killed\|openvpn\|signal")
if [[ -n "$DMESG_LOGS" ]]; then
    echo -e "${YELLOW}⚠ Found relevant kernel messages:${NC}"
    echo "$DMESG_LOGS" | tail -10
    echo ""
else
    echo -e "${GREEN}✓ No suspicious kernel messages${NC}\n"
fi

# 5. Check memory availability
echo -e "${CYAN}[5] Checking system memory...${NC}"
MEM_INFO=$(free -h | grep "Mem:")
AVAILABLE=$(echo "$MEM_INFO" | awk '{print $7}')
echo -e "  Available memory: ${GREEN}$AVAILABLE${NC}"
echo -e "  ${MEM_INFO}\n"

# 6. Check if update-resolv-conf script exists
echo -e "${CYAN}[6] Checking DNS update script...${NC}"
if [[ -f /etc/openvpn/update-resolv-conf ]]; then
    if [[ -x /etc/openvpn/update-resolv-conf ]]; then
        echo -e "${GREEN}✓ DNS update script exists and is executable${NC}\n"
    else
        echo -e "${YELLOW}⚠ DNS update script exists but is NOT executable${NC}"
        echo -e "  ${GREEN}Solution:${NC}"
        echo -e "  ${BLUE}sudo chmod +x /etc/openvpn/update-resolv-conf${NC}\n"
    fi
else
    echo -e "${YELLOW}⚠ DNS update script NOT found at /etc/openvpn/update-resolv-conf${NC}"
    echo -e "  This is okay, but may cause DNS issues.\n"
fi

# 7. Check current iptables rules
echo -e "${CYAN}[7] Checking iptables killswitch rules...${NC}"
if iptables -L -n 2>/dev/null | grep -q "policy DROP"; then
    echo -e "${YELLOW}⚠ Killswitch firewall rules are ACTIVE${NC}"
    echo -e "  This will block all traffic except through VPN!"
    echo -e "\n  Current policies:"
    iptables -L -n | grep "Chain\|policy" | head -6
    echo -e "\n  ${GREEN}Solution:${NC} Disable killswitch before manual testing:"
    echo -e "  ${BLUE}sudo iptables -P INPUT ACCEPT${NC}"
    echo -e "  ${BLUE}sudo iptables -P OUTPUT ACCEPT${NC}"
    echo -e "  ${BLUE}sudo iptables -P FORWARD ACCEPT${NC}"
    echo -e "  ${BLUE}sudo iptables -F${NC}\n"
else
    echo -e "${GREEN}✓ No killswitch rules active${NC}\n"
fi

# 8. Check systemd kill settings
echo -e "${CYAN}[8] Checking systemd configuration...${NC}"
if systemctl show openvpn@client 2>/dev/null | grep -q "KillMode"; then
    KILL_MODE=$(systemctl show openvpn@client 2>/dev/null | grep KillMode)
    echo -e "  ${BLUE}→${NC} $KILL_MODE"
fi
echo ""

# 9. Check ulimit settings
echo -e "${CYAN}[9] Checking process limits (ulimit)...${NC}"
echo -e "  Max processes: $(ulimit -u)"
echo -e "  Max open files: $(ulimit -n)"
echo ""

# 10. Recommendations
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                    RECOMMENDATIONS                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${YELLOW}The 'zsh: killed' error usually means:${NC}"
echo -e "  1. ${RED}OOM Killer${NC} - System ran out of memory"
echo -e "  2. ${RED}Conflict${NC} - Another OpenVPN instance is running"
echo -e "  3. ${RED}Killswitch${NC} - Firewall rules blocking the connection"
echo -e "  4. ${RED}Systemd${NC} - Service manager killed the process"
echo ""

echo -e "${GREEN}SOLUTION - Try running OpenVPN with these steps:${NC}\n"

echo -e "${CYAN}Step 1: Clean up existing processes${NC}"
echo -e "sudo systemctl stop openvpn-killswitch"
echo -e "sudo pkill -9 openvpn"
echo ""

echo -e "${CYAN}Step 2: Disable killswitch temporarily${NC}"
echo -e "sudo iptables -P INPUT ACCEPT"
echo -e "sudo iptables -P OUTPUT ACCEPT"
echo -e "sudo iptables -P FORWARD ACCEPT"
echo -e "sudo iptables -F"
echo ""

echo -e "${CYAN}Step 3: Test OpenVPN without daemon mode${NC}"
echo -e "sudo openvpn --config /etc/openvpn/client.ovpn"
echo ""

echo -e "${CYAN}Alternative: Use the killswitch service (recommended)${NC}"
echo -e "Instead of running OpenVPN manually, use the service:"
echo -e "sudo systemctl start openvpn-killswitch"
echo -e "sudo journalctl -u openvpn-killswitch -f"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}\n"
