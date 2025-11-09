#!/bin/bash

################################################################################
# OpenVPN Killswitch Script with DNS Masking
# Features: Killswitch, DNS protection, Auto-reconnect, Logging, Error handling
################################################################################

set -euo pipefail

# Configuration
CONFIG_FILE="/etc/openvpn/killswitch.conf"
LOG_FILE="/var/log/openvpn-killswitch.log"
STATUS_FILE="/var/run/vpn-status"
PID_FILE="/var/run/openvpn-killswitch.pid"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# Default values (can be overridden in config file)
OPENVPN_CONFIG="${OPENVPN_CONFIG:-/etc/openvpn/client.ovpn}"
VPN_DNS="${VPN_DNS:-1.1.1.1,1.0.0.1}"  # Cloudflare DNS
KILLSWITCH_ENABLED="${KILLSWITCH_ENABLED:-true}"
AUTO_RECONNECT="${AUTO_RECONNECT:-true}"
RECONNECT_DELAY="${RECONNECT_DELAY:-5}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Logging Functions
################################################################################

rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local log_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $log_size -gt $MAX_LOG_SIZE ]]; then
            mv "$LOG_FILE" "$LOG_FILE.old"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Log rotated" > "$LOG_FILE"
        fi
    fi
}

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    rotate_log
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"

    # Also log to syslog
    logger -t openvpn-killswitch "[$level] $message"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

################################################################################
# Error Handler
################################################################################

error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "Script failed at line $line_no with exit code $error_code"
    cleanup
    exit $error_code
}

trap 'error_handler ${LINENO} $?' ERR

################################################################################
# Configuration Loading
################################################################################

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log_info "Loading configuration from $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log_warning "Config file not found at $CONFIG_FILE, using defaults"
        create_default_config
    fi
}

create_default_config() {
    log_info "Creating default configuration at $CONFIG_FILE"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << 'EOF'
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
# ALLOW_LOCAL_NETWORK="192.168.1.0/24"
EOF
    chmod 600 "$CONFIG_FILE"
}

################################################################################
# Network Interface Detection
################################################################################

get_default_interface() {
    ip route | grep default | head -n1 | awk '{print $5}'
}

get_vpn_interface() {
    ip link show | grep -E "tun[0-9]|tap[0-9]" | head -n1 | awk -F: '{print $2}' | xargs
}

get_public_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "Unknown")
    echo "$ip"
}

get_dns_servers() {
    if command -v resolvectl &> /dev/null; then
        resolvectl status | grep "DNS Servers" | head -n1 | awk '{print $3}'
    else
        grep "nameserver" /etc/resolv.conf | head -n1 | awk '{print $2}'
    fi
}

################################################################################
# Killswitch Functions
################################################################################

enable_killswitch() {
    log_info "Enabling killswitch..."

    # Flush existing rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    # Set default policies to DROP
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT DROP

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow local network if specified
    if [[ -n "${ALLOW_LOCAL_NETWORK:-}" ]]; then
        log_info "Allowing local network: $ALLOW_LOCAL_NETWORK"
        iptables -A INPUT -s "$ALLOW_LOCAL_NETWORK" -j ACCEPT
        iptables -A OUTPUT -d "$ALLOW_LOCAL_NETWORK" -j ACCEPT
    fi

    # Allow VPN connection establishment
    local default_iface=$(get_default_interface)
    if [[ -n "$default_iface" ]]; then
        # Allow outgoing connections to OpenVPN server
        iptables -A OUTPUT -o "$default_iface" -p udp --dport 1194 -j ACCEPT
        iptables -A OUTPUT -o "$default_iface" -p tcp --dport 1194 -j ACCEPT
        iptables -A OUTPUT -o "$default_iface" -p udp --dport 443 -j ACCEPT
        iptables -A OUTPUT -o "$default_iface" -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -i "$default_iface" -m state --state ESTABLISHED,RELATED -j ACCEPT
    fi

    # Allow all traffic through VPN interface
    local vpn_iface=$(get_vpn_interface)
    if [[ -n "$vpn_iface" ]]; then
        log_info "Allowing traffic through VPN interface: $vpn_iface"
        iptables -A INPUT -i "$vpn_iface" -j ACCEPT
        iptables -A OUTPUT -o "$vpn_iface" -j ACCEPT
        iptables -A FORWARD -i "$vpn_iface" -j ACCEPT
        iptables -A FORWARD -o "$vpn_iface" -j ACCEPT
    fi

    # Allow DNS queries to VPN DNS servers only
    IFS=',' read -ra DNS_ARRAY <<< "$VPN_DNS"
    for dns in "${DNS_ARRAY[@]}"; do
        iptables -A OUTPUT -p udp --dport 53 -d "$dns" -j ACCEPT
        iptables -A OUTPUT -p tcp --dport 53 -d "$dns" -j ACCEPT
    done

    log_success "Killswitch enabled successfully"
}

disable_killswitch() {
    log_info "Disabling killswitch..."

    # Restore default policies
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    # Flush all rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X

    log_success "Killswitch disabled successfully"
}

################################################################################
# DNS Management
################################################################################

backup_dns() {
    if [[ ! -f /etc/resolv.conf.backup ]]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup
        log_info "DNS configuration backed up"
    fi
}

set_vpn_dns() {
    log_info "Setting VPN DNS servers..."
    backup_dns

    # Create new resolv.conf with VPN DNS
    cat > /etc/resolv.conf << EOF
# Generated by openvpn-killswitch
# Original DNS backed up to /etc/resolv.conf.backup
EOF

    IFS=',' read -ra DNS_ARRAY <<< "$VPN_DNS"
    for dns in "${DNS_ARRAY[@]}"; do
        echo "nameserver $dns" >> /etc/resolv.conf
    done

    # Make it immutable to prevent other services from changing it
    chattr +i /etc/resolv.conf 2>/dev/null || true

    log_success "VPN DNS servers set: $VPN_DNS"
}

restore_dns() {
    log_info "Restoring original DNS configuration..."

    # Remove immutable flag
    chattr -i /etc/resolv.conf 2>/dev/null || true

    if [[ -f /etc/resolv.conf.backup ]]; then
        mv /etc/resolv.conf.backup /etc/resolv.conf
        log_success "Original DNS configuration restored"
    fi
}

################################################################################
# VPN Connection Management
################################################################################

start_vpn() {
    log_info "Starting OpenVPN connection..."

    if [[ ! -f "$OPENVPN_CONFIG" ]]; then
        log_error "OpenVPN config file not found: $OPENVPN_CONFIG"
        return 1
    fi

    # Kill any existing OpenVPN processes
    pkill -9 openvpn 2>/dev/null || true
    sleep 2

    # Start OpenVPN in background
    openvpn --config "$OPENVPN_CONFIG" \
            --daemon \
            --log-append "$LOG_FILE" \
            --writepid /var/run/openvpn.pid \
            --script-security 2 \
            --up /etc/openvpn/update-resolv-conf \
            --down /etc/openvpn/update-resolv-conf

    # Wait for VPN interface to come up
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        local vpn_iface=$(get_vpn_interface)
        if [[ -n "$vpn_iface" ]]; then
            log_success "VPN connected on interface: $vpn_iface"
            return 0
        fi
        sleep 1
        ((attempts++))
    done

    log_error "VPN connection timeout"
    return 1
}

stop_vpn() {
    log_info "Stopping OpenVPN connection..."
    pkill -TERM openvpn 2>/dev/null || true
    sleep 2
    pkill -9 openvpn 2>/dev/null || true
    rm -f /var/run/openvpn.pid
    log_success "VPN connection stopped"
}

check_vpn_status() {
    local vpn_iface=$(get_vpn_interface)
    if [[ -n "$vpn_iface" ]] && pgrep -x openvpn > /dev/null; then
        return 0  # VPN is running
    else
        return 1  # VPN is not running
    fi
}

################################################################################
# Status Management
################################################################################

update_status() {
    local status="$1"
    local ip="$2"
    local dns="$3"

    mkdir -p "$(dirname "$STATUS_FILE")"
    cat > "$STATUS_FILE" << EOF
STATUS=$status
IP=$ip
DNS=$dns
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
EOF
    chmod 644 "$STATUS_FILE"
}

################################################################################
# Main Monitoring Loop
################################################################################

monitor_vpn() {
    log_info "Starting VPN monitor..."

    while true; do
        if check_vpn_status; then
            local ip=$(get_public_ip)
            local dns=$(get_dns_servers)
            update_status "CONNECTED" "$ip" "$dns"
            log_info "VPN Status: CONNECTED | IP: $ip | DNS: $dns"
        else
            update_status "DISCONNECTED" "N/A" "N/A"
            log_warning "VPN disconnected!"

            if [[ "$AUTO_RECONNECT" == "true" ]]; then
                log_info "Attempting to reconnect in $RECONNECT_DELAY seconds..."
                sleep "$RECONNECT_DELAY"

                if start_vpn; then
                    sleep 3
                    set_vpn_dns
                    if [[ "$KILLSWITCH_ENABLED" == "true" ]]; then
                        enable_killswitch
                    fi
                else
                    log_error "Reconnection failed"
                fi
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

################################################################################
# Cleanup
################################################################################

cleanup() {
    log_info "Cleaning up..."

    stop_vpn

    if [[ "$KILLSWITCH_ENABLED" == "true" ]]; then
        disable_killswitch
    fi

    restore_dns

    rm -f "$PID_FILE" "$STATUS_FILE"

    log_info "Cleanup completed"
}

trap cleanup EXIT INT TERM

################################################################################
# Main Function
################################################################################

main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    # Check if already running
    if [[ -f "$PID_FILE" ]]; then
        local old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            log_error "Script is already running (PID: $old_pid)"
            exit 1
        else
            rm -f "$PID_FILE"
        fi
    fi

    # Save PID
    echo $$ > "$PID_FILE"

    log_info "=== OpenVPN Killswitch Starting ==="

    # Load configuration
    load_config

    # Check for required commands
    for cmd in iptables openvpn curl ip; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Start VPN
    if ! start_vpn; then
        log_error "Failed to start VPN"
        exit 1
    fi

    # Wait for connection to stabilize
    sleep 3

    # Set VPN DNS
    set_vpn_dns

    # Enable killswitch
    if [[ "$KILLSWITCH_ENABLED" == "true" ]]; then
        enable_killswitch
    fi

    # Display initial status
    local ip=$(get_public_ip)
    local dns=$(get_dns_servers)
    log_success "VPN is active"
    log_success "Public IP: $ip"
    log_success "DNS Server: $dns"

    # Start monitoring
    monitor_vpn
}

################################################################################
# Command Line Interface
################################################################################

case "${1:-start}" in
    start)
        main
        ;;
    stop)
        cleanup
        ;;
    restart)
        cleanup
        sleep 2
        main
        ;;
    status)
        if [[ -f "$STATUS_FILE" ]]; then
            cat "$STATUS_FILE"
        else
            echo "VPN status not available"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
