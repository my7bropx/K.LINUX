#!/bin/bash

################################################################################
# OpenVPN Killswitch Installation Script
# Installs and configures the VPN killswitch system
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Configuration
################################################################################

INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/openvpn"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      OpenVPN Killswitch Installation Script               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    print_info "Checking dependencies..."

    local missing_deps=()

    for cmd in openvpn iptables curl ip systemctl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install them first:"
        echo ""
        echo "  Debian/Ubuntu/Kali:"
        echo "    sudo apt update && sudo apt install -y openvpn iptables curl iproute2 systemd"
        echo ""
        echo "  Fedora/RHEL:"
        echo "    sudo dnf install -y openvpn iptables curl iproute systemd"
        echo ""
        echo "  Arch Linux:"
        echo "    sudo pacman -S openvpn iptables curl iproute2 systemd"
        echo ""
        exit 1
    fi

    print_success "All dependencies are installed"
}

backup_existing() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_info "Backed up existing file: $backup"
    fi
}

################################################################################
# Installation Functions
################################################################################

install_scripts() {
    print_info "Installing scripts..."

    # Install main killswitch script
    if [[ -f "$SCRIPT_DIR/openvpn-killswitch.sh" ]]; then
        backup_existing "$INSTALL_DIR/openvpn-killswitch.sh"
        cp "$SCRIPT_DIR/openvpn-killswitch.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/openvpn-killswitch.sh"
        print_success "Installed: openvpn-killswitch.sh"
    else
        print_error "openvpn-killswitch.sh not found in $SCRIPT_DIR"
        exit 1
    fi

    # Install status monitor
    if [[ -f "$SCRIPT_DIR/vpn-status.sh" ]]; then
        backup_existing "$INSTALL_DIR/vpn-status.sh"
        cp "$SCRIPT_DIR/vpn-status.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/vpn-status.sh"
        print_success "Installed: vpn-status.sh"
    else
        print_warning "vpn-status.sh not found, skipping"
    fi

    # Install panel indicator
    if [[ -f "$SCRIPT_DIR/vpn-panel-indicator.sh" ]]; then
        backup_existing "$INSTALL_DIR/vpn-panel-indicator.sh"
        cp "$SCRIPT_DIR/vpn-panel-indicator.sh" "$INSTALL_DIR/"
        chmod +x "$INSTALL_DIR/vpn-panel-indicator.sh"
        print_success "Installed: vpn-panel-indicator.sh"
    else
        print_warning "vpn-panel-indicator.sh not found, skipping"
    fi
}

install_service() {
    print_info "Installing systemd service..."

    if [[ -f "$SCRIPT_DIR/openvpn-killswitch.service" ]]; then
        backup_existing "$SERVICE_DIR/openvpn-killswitch.service"
        cp "$SCRIPT_DIR/openvpn-killswitch.service" "$SERVICE_DIR/"
        chmod 644 "$SERVICE_DIR/openvpn-killswitch.service"
        print_success "Installed: openvpn-killswitch.service"

        # Reload systemd
        systemctl daemon-reload
        print_success "Systemd daemon reloaded"
    else
        print_error "openvpn-killswitch.service not found in $SCRIPT_DIR"
        exit 1
    fi
}

setup_config() {
    print_info "Setting up configuration..."

    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"

    # Create default config if it doesn't exist
    if [[ ! -f "$CONFIG_DIR/killswitch.conf" ]]; then
        cat > "$CONFIG_DIR/killswitch.conf" << 'EOF'
# OpenVPN Killswitch Configuration

# Path to your OpenVPN config file
OPENVPN_CONFIG="/etc/openvpn/client.ovpn"

# DNS servers to use when VPN is connected (comma-separated)
VPN_DNS="1.1.1.1,1.0.0.1"

# Enable killswitch (true/false)
KILLSWITCH_ENABLED=true

# Auto-reconnect on failure (true/false)
AUTO_RECONNECT=true

# Delay before reconnect attempt (seconds)
RECONNECT_DELAY=5

# VPN connection check interval (seconds)
CHECK_INTERVAL=10

# Allowed local network (e.g., 192.168.1.0/24) - optional
# Uncomment and set your local network if needed
# ALLOW_LOCAL_NETWORK="192.168.1.0/24"
EOF
        chmod 600 "$CONFIG_DIR/killswitch.conf"
        print_success "Created default configuration: $CONFIG_DIR/killswitch.conf"
    else
        print_info "Configuration file already exists: $CONFIG_DIR/killswitch.conf"
    fi

    # Check for OpenVPN config
    if [[ ! -f "$CONFIG_DIR/client.ovpn" ]]; then
        print_warning "OpenVPN config not found at $CONFIG_DIR/client.ovpn"
        print_info "Please place your .ovpn file at this location or update the path in $CONFIG_DIR/killswitch.conf"
    fi
}

setup_resolv_conf_script() {
    print_info "Setting up DNS update scripts..."

    # Create update-resolv-conf script if it doesn't exist
    if [[ ! -f "$CONFIG_DIR/update-resolv-conf" ]]; then
        cat > "$CONFIG_DIR/update-resolv-conf" << 'EOF'
#!/bin/bash
# OpenVPN DNS update script
# This script is called by OpenVPN when connection goes up or down

case "$script_type" in
    up)
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 1.0.0.1" >> /etc/resolv.conf
        ;;
    down)
        if [[ -f /etc/resolv.conf.backup ]]; then
            mv /etc/resolv.conf.backup /etc/resolv.conf
        fi
        ;;
esac
EOF
        chmod +x "$CONFIG_DIR/update-resolv-conf"
        print_success "Created DNS update script"
    fi
}

################################################################################
# Post-Installation
################################################################################

post_install() {
    print_info "Running post-installation tasks..."

    # Create log file
    touch "$LOG_DIR/openvpn-killswitch.log"
    chmod 644 "$LOG_DIR/openvpn-killswitch.log"
    print_success "Created log file: $LOG_DIR/openvpn-killswitch.log"

    # Create status directory
    mkdir -p /var/run
    chmod 755 /var/run

    print_success "Post-installation tasks completed"
}

print_usage_instructions() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo ""
    echo "1. Configure your VPN:"
    echo "   - Place your .ovpn file at: $CONFIG_DIR/client.ovpn"
    echo "   - Or update the path in: $CONFIG_DIR/killswitch.conf"
    echo ""
    echo "2. Edit configuration (optional):"
    echo "   sudo nano $CONFIG_DIR/killswitch.conf"
    echo ""
    echo "3. Enable and start the service:"
    echo "   sudo systemctl enable openvpn-killswitch"
    echo "   sudo systemctl start openvpn-killswitch"
    echo ""
    echo "4. Check VPN status:"
    echo "   vpn-status.sh"
    echo "   vpn-status.sh --watch    # Continuous monitoring"
    echo ""
    echo "5. View logs:"
    echo "   sudo journalctl -u openvpn-killswitch -f"
    echo "   sudo tail -f $LOG_DIR/openvpn-killswitch.log"
    echo ""
    echo -e "${BLUE}Panel Integration:${NC}"
    echo ""
    echo "For i3bar/polybar/waybar panel integration, run:"
    echo "   vpn-panel-indicator.sh help"
    echo ""
    echo -e "${BLUE}Service Management:${NC}"
    echo ""
    echo "   sudo systemctl start openvpn-killswitch     # Start VPN"
    echo "   sudo systemctl stop openvpn-killswitch      # Stop VPN"
    echo "   sudo systemctl restart openvpn-killswitch   # Restart VPN"
    echo "   sudo systemctl status openvpn-killswitch    # Check status"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "- Make sure your OpenVPN config file is properly configured"
    echo "- The killswitch will block all traffic except through VPN"
    echo "- Local network access can be allowed in the config file"
    echo ""
}

################################################################################
# Uninstallation
################################################################################

uninstall() {
    print_info "Uninstalling OpenVPN Killswitch..."

    # Stop and disable service
    if systemctl is-active --quiet openvpn-killswitch 2>/dev/null; then
        systemctl stop openvpn-killswitch
        print_success "Stopped service"
    fi

    if systemctl is-enabled --quiet openvpn-killswitch 2>/dev/null; then
        systemctl disable openvpn-killswitch
        print_success "Disabled service"
    fi

    # Remove files
    rm -f "$INSTALL_DIR/openvpn-killswitch.sh"
    rm -f "$INSTALL_DIR/vpn-status.sh"
    rm -f "$INSTALL_DIR/vpn-panel-indicator.sh"
    rm -f "$SERVICE_DIR/openvpn-killswitch.service"

    # Reload systemd
    systemctl daemon-reload

    print_success "Uninstallation completed"
    print_warning "Configuration files in $CONFIG_DIR were kept"
    print_warning "To remove them: sudo rm -rf $CONFIG_DIR/killswitch.conf"
}

################################################################################
# Main
################################################################################

main() {
    print_header

    check_root
    check_dependencies

    echo ""
    install_scripts
    install_service
    setup_config
    setup_resolv_conf_script
    post_install

    print_usage_instructions
}

################################################################################
# Command Line Interface
################################################################################

case "${1:-install}" in
    install)
        main
        ;;
    uninstall)
        check_root
        uninstall
        ;;
    help|--help|-h)
        echo "OpenVPN Killswitch Installation Script"
        echo ""
        echo "Usage: $0 [COMMAND]"
        echo ""
        echo "Commands:"
        echo "  install     Install the VPN killswitch system (default)"
        echo "  uninstall   Remove the VPN killswitch system"
        echo "  help        Show this help message"
        echo ""
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
