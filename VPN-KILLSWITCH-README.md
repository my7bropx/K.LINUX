# OpenVPN Killswitch with DNS Masking

A comprehensive OpenVPN killswitch solution for Linux that ensures your real IP and DNS are never exposed, even if the VPN connection drops.

## Features

- **Killswitch Protection**: Automatically blocks all internet traffic if VPN disconnects
- **DNS Masking**: Forces all DNS queries through VPN DNS servers (default: Cloudflare 1.1.1.1)
- **Auto-Reconnect**: Automatically reconnects to VPN on connection failure
- **Systemd Service**: Runs automatically at boot
- **Comprehensive Logging**: Detailed logs with rotation and error handling
- **Status Monitoring**: Terminal and panel indicators for real-time status
- **Local Network Access**: Optional support for local network access while VPN is active
- **Multiple Panel Support**: Compatible with i3bar, polybar, waybar, XFCE panel, and more

## Components

### 1. Main Killswitch Script (`openvpn-killswitch.sh`)
The core script that manages VPN connection, killswitch, and DNS protection.

**Features:**
- Firewall-based killswitch using iptables
- DNS leak prevention
- Automatic reconnection
- Error handling and recovery
- Comprehensive logging

### 2. Systemd Service (`openvpn-killswitch.service`)
Enables automatic VPN startup at boot with proper dependency management.

### 3. Status Monitor (`vpn-status.sh`)
Terminal-based status display showing:
- Connection status
- Public IP address
- DNS servers
- Traffic statistics
- Recent activity logs
- Killswitch status

### 4. Panel Indicator (`vpn-panel-indicator.sh`)
System panel integration supporting multiple formats:
- i3bar/i3blocks
- Polybar
- Waybar
- XFCE Genmon
- Conky
- Plain text output

## Installation

### Prerequisites

Ensure you have the following packages installed:

```bash
# Debian/Ubuntu/Kali Linux
sudo apt update
sudo apt install -y openvpn iptables curl iproute2 systemd

# Fedora/RHEL
sudo dnf install -y openvpn iptables curl iproute systemd

# Arch Linux
sudo pacman -S openvpn iptables curl iproute2 systemd
```

### Quick Install

1. Clone or download this repository
2. Run the installation script:

```bash
sudo chmod +x install-vpn-killswitch.sh
sudo ./install-vpn-killswitch.sh
```

### Manual Installation

```bash
# Copy scripts to system directories
sudo cp openvpn-killswitch.sh /usr/local/bin/
sudo cp vpn-status.sh /usr/local/bin/
sudo cp vpn-panel-indicator.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/openvpn-killswitch.sh
sudo chmod +x /usr/local/bin/vpn-status.sh
sudo chmod +x /usr/local/bin/vpn-panel-indicator.sh

# Install systemd service
sudo cp openvpn-killswitch.service /etc/systemd/system/
sudo systemctl daemon-reload
```

## Configuration

### 1. OpenVPN Configuration

Place your OpenVPN configuration file at:
```bash
/etc/openvpn/client.ovpn
```

Or specify a custom path in the configuration file.

### 2. Killswitch Configuration

Edit the configuration file:
```bash
sudo nano /etc/openvpn/killswitch.conf
```

**Configuration options:**

```bash
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

# Allowed local network (optional)
# Uncomment to allow access to local network while VPN is active
# ALLOW_LOCAL_NETWORK="192.168.1.0/24"
```

## Usage

### Service Management

```bash
# Enable service to start at boot
sudo systemctl enable openvpn-killswitch

# Start VPN
sudo systemctl start openvpn-killswitch

# Stop VPN
sudo systemctl stop openvpn-killswitch

# Restart VPN
sudo systemctl restart openvpn-killswitch

# Check service status
sudo systemctl status openvpn-killswitch

# View service logs
sudo journalctl -u openvpn-killswitch -f
```

### Status Monitoring

```bash
# Show detailed status
vpn-status.sh

# Continuous monitoring (updates every 3 seconds)
vpn-status.sh --watch

# Compact one-line status
vpn-status.sh --compact

# JSON output (for scripting)
vpn-status.sh --json
```

**Status Display Example:**
```
╔════════════════════════════════════════════════════════════╗
║          OpenVPN Killswitch Status Monitor                ║
╚════════════════════════════════════════════════════════════╝

Status:          ● CONNECTED
Interface:       tun0
Public IP:       203.0.113.45
DNS Server:      1.1.1.1
DNS Status:      Protected
Uptime:          01:23:45
Service:         Active
Killswitch:      ● ENABLED

Traffic Statistics:
  → Downloaded: 245 MB
  → Uploaded:   87 MB
```

### Panel Integration

#### i3blocks Configuration
Add to `~/.config/i3blocks/config`:
```ini
[vpn]
command=/usr/local/bin/vpn-panel-indicator.sh i3bar
interval=5
```

#### Polybar Configuration
Add to `~/.config/polybar/config`:
```ini
[module/vpn]
type = custom/script
exec = /usr/local/bin/vpn-panel-indicator.sh polybar
interval = 5
```

#### Waybar Configuration
Add to `~/.config/waybar/config`:
```json
"custom/vpn": {
    "exec": "/usr/local/bin/vpn-panel-indicator.sh waybar",
    "return-type": "json",
    "interval": 5
}
```

#### XFCE Panel (Generic Monitor)
- Right-click panel → Add New Items → Generic Monitor
- Command: `/usr/local/bin/vpn-panel-indicator.sh genmon`
- Period: 5 seconds

## How It Works

### Killswitch Mechanism

The killswitch uses iptables to implement a strict firewall that:

1. **Blocks all traffic by default** (DROP policy on INPUT, OUTPUT, FORWARD)
2. **Allows loopback traffic** (localhost communication)
3. **Allows VPN connection establishment** (UDP/TCP ports 1194, 443)
4. **Allows all traffic through VPN interface** (tun0/tap0)
5. **Allows DNS queries only to VPN DNS servers**
6. **Optionally allows local network traffic**

If the VPN disconnects, all internet traffic is immediately blocked, preventing IP leaks.

### DNS Protection

The script:
1. Backs up original `/etc/resolv.conf`
2. Replaces it with VPN DNS servers (Cloudflare by default)
3. Makes it immutable to prevent other services from changing it
4. Restores original DNS configuration when VPN is stopped

### Auto-Reconnect

The monitoring loop continuously checks VPN status:
- If VPN is connected: Updates status and continues monitoring
- If VPN disconnects:
  - Logs the disconnection
  - Waits for configured delay
  - Attempts to reconnect
  - Reconfigures DNS and killswitch upon reconnection

## Logging

Logs are written to multiple locations:

1. **Main log file**: `/var/log/openvpn-killswitch.log`
   - All script activities
   - Errors and warnings
   - Connection events
   - Automatic rotation when exceeds 10MB

2. **System journal**:
   ```bash
   sudo journalctl -u openvpn-killswitch -f
   ```

3. **OpenVPN log**: Included in main log file

## Troubleshooting

### VPN Won't Connect

1. Check OpenVPN configuration:
   ```bash
   sudo openvpn --config /etc/openvpn/client.ovpn
   ```

2. Verify configuration file path:
   ```bash
   sudo cat /etc/openvpn/killswitch.conf
   ```

3. Check service logs:
   ```bash
   sudo journalctl -u openvpn-killswitch -n 50
   ```

### No Internet Access

If VPN is disconnected and you have no internet:

1. **Temporary solution** - Disable killswitch:
   ```bash
   sudo iptables -P INPUT ACCEPT
   sudo iptables -P OUTPUT ACCEPT
   sudo iptables -P FORWARD ACCEPT
   sudo iptables -F
   ```

2. **Permanent solution** - Stop the service:
   ```bash
   sudo systemctl stop openvpn-killswitch
   ```

### DNS Not Working

1. Check current DNS servers:
   ```bash
   cat /etc/resolv.conf
   ```

2. Restore original DNS:
   ```bash
   sudo chattr -i /etc/resolv.conf
   sudo mv /etc/resolv.conf.backup /etc/resolv.conf
   ```

### Local Network Access Issues

If you can't access your local network while VPN is active:

1. Edit configuration:
   ```bash
   sudo nano /etc/openvpn/killswitch.conf
   ```

2. Uncomment and set your local network:
   ```bash
   ALLOW_LOCAL_NETWORK="192.168.1.0/24"
   ```

3. Restart service:
   ```bash
   sudo systemctl restart openvpn-killswitch
   ```

## Security Considerations

### What This Protects Against

- ✅ IP address leaks when VPN disconnects
- ✅ DNS leaks (all queries go through VPN DNS)
- ✅ WebRTC leaks (no direct internet access without VPN)
- ✅ Application-level leaks (all traffic blocked without VPN)

### What This Doesn't Protect Against

- ❌ IPv6 leaks (disable IPv6 if not using IPv6 VPN)
- ❌ Browser fingerprinting
- ❌ Malware/tracking cookies
- ❌ Application-level tracking
- ❌ Compromised VPN provider

### Additional Security Recommendations

1. **Disable IPv6** if your VPN doesn't support it:
   ```bash
   sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
   sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
   ```

2. **Use DNS leak testing tools**:
   - https://dnsleaktest.com
   - https://ipleak.net

3. **Regularly update OpenVPN**:
   ```bash
   sudo apt update && sudo apt upgrade openvpn
   ```

4. **Use strong VPN providers** with:
   - No-logs policy
   - Strong encryption (AES-256)
   - Modern protocols (OpenVPN, WireGuard)

## Uninstallation

To remove the killswitch system:

```bash
sudo ./install-vpn-killswitch.sh uninstall
```

Or manually:

```bash
# Stop and disable service
sudo systemctl stop openvpn-killswitch
sudo systemctl disable openvpn-killswitch

# Remove files
sudo rm /usr/local/bin/openvpn-killswitch.sh
sudo rm /usr/local/bin/vpn-status.sh
sudo rm /usr/local/bin/vpn-panel-indicator.sh
sudo rm /etc/systemd/system/openvpn-killswitch.service

# Reload systemd
sudo systemctl daemon-reload

# Optional: Remove configuration
sudo rm /etc/openvpn/killswitch.conf
```

## Advanced Usage

### Custom DNS Servers

To use different DNS servers (e.g., Quad9):
```bash
# Edit configuration
sudo nano /etc/openvpn/killswitch.conf

# Set DNS servers
VPN_DNS="9.9.9.9,149.112.112.112"

# Restart service
sudo systemctl restart openvpn-killswitch
```

### Multiple VPN Configurations

To use different VPN configs:
```bash
# Create separate config files
sudo cp /etc/openvpn/killswitch.conf /etc/openvpn/killswitch-work.conf
sudo cp /etc/openvpn/killswitch.conf /etc/openvpn/killswitch-personal.conf

# Edit each config to point to different .ovpn files
sudo nano /etc/openvpn/killswitch-work.conf
# Set: OPENVPN_CONFIG="/etc/openvpn/work.ovpn"

# Create separate service files
sudo cp /etc/systemd/system/openvpn-killswitch.service \
       /etc/systemd/system/openvpn-killswitch-work.service

# Edit service to use different config
# ExecStart=/usr/local/bin/openvpn-killswitch.sh start /etc/openvpn/killswitch-work.conf
```

### Scripting with JSON Output

```bash
#!/bin/bash
# Example: Send notification when VPN disconnects

while true; do
    STATUS=$(vpn-status.sh --json | jq -r '.status')

    if [ "$STATUS" = "disconnected" ]; then
        notify-send "VPN Alert" "VPN is disconnected!" --urgency=critical
    fi

    sleep 10
done
```

## FAQ

**Q: Will this work with any VPN provider?**
A: Yes, as long as they provide an OpenVPN configuration file (.ovpn).

**Q: Can I use this with WireGuard?**
A: This script is specifically for OpenVPN. For WireGuard, you'd need a different implementation.

**Q: Does this work on Kali Linux?**
A: Yes, it's been tested on Kali Linux, Ubuntu, Debian, and other Linux distributions.

**Q: Can I access my local printer/NAS while VPN is active?**
A: Yes, set the `ALLOW_LOCAL_NETWORK` option in the configuration file.

**Q: What happens if my VPN provider's servers are down?**
A: The auto-reconnect feature will keep trying. Meanwhile, the killswitch blocks all internet access.

**Q: Can I temporarily disable the killswitch?**
A: Yes, set `KILLSWITCH_ENABLED=false` in the config file and restart the service.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is open source and available under the MIT License.

## Credits

Created for secure and private internet browsing on Linux systems.

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check the logs: `sudo journalctl -u openvpn-killswitch -f`
- Review the troubleshooting section above

---

**Stay safe, stay private!** 🔒
