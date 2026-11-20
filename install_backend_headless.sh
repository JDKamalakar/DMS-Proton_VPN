#!/bin/bash
set -e

# Run the official installer
curl -fsSL https://raw.githubusercontent.com/YourDoritos/pVPN/main/install.sh | bash

# Ensure pvpnctl & pvpnd do not require password when invoked
SUDOERS_FILE="/etc/sudoers.d/pvpn"
SUDO_RULE="%pvpn ALL=(ALL) NOPASSWD: /usr/local/bin/pvpnctl, /usr/local/bin/pvpnd, /usr/local/bin/pvpn"

if [ ! -f "$SUDOERS_FILE" ] || ! grep -q "NOPASSWD: /usr/local/bin/pvpnctl" "$SUDOERS_FILE"; then
    echo "$SUDO_RULE" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"
fi

# Ensure Proton API floor version compatibility override is in place
OVERRIDE_DIR="/etc/systemd/system/pvpnd.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/version.conf"
mkdir -p "$OVERRIDE_DIR"
cat << 'EOF' > "$OVERRIDE_FILE"
[Service]
Environment=PVPN_APPVERSION=linux-vpn@4.20.0
Environment=PVPN_USERAGENT="ProtonVPN/4.20.0 (Linux; go-pvpn)"
EOF

# Ensure invoking user is added to pvpn group
INVOKING_USER="${PKEXEC_UID:-$SUDO_USER}"
if [ -n "$INVOKING_USER" ]; then
    USERNAME=$(id -nu "$INVOKING_USER" 2>/dev/null || echo "")
    if [ -n "$USERNAME" ]; then
        usermod -aG pvpn "$USERNAME" 2>/dev/null || true
    fi
fi

systemctl daemon-reload 2>/dev/null || true
systemctl restart pvpnd 2>/dev/null || true
exit 0
