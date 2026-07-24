# DMS Proton VPN Plugin (`pVPN` Backend)

A modern Proton VPN widget plugin for **DMS (Dank Material Shell)** based on the [YourDoritos/pVPN](https://github.com/YourDoritos/pVPN) CLI backend.

## Features

- 🛡️ **VPN Connection Toggle**: Instant status detection & connect/disconnect toggle directly from bar pill, popout modal, or Control Center.
- ⚡ **Quick Connect Presets**: Connect to `fastest` server or specific countries (`US`, `NL`, `JP`, `CH`, `GB`).
- 🔒 **Protocol Selection**: Configurable connection protocol support (`smart`, `wireguard`, `stealth`).
- 📊 **Status Monitoring**: Dynamic status polling via `pvpnctl status --format waybar`.
- ⚙️ **Custom Settings Panel**: Full plugin settings for setting default connect targets and preferred protocols.

## Requirements

- `pvpnd` daemon running (typically managed via `systemd`).
- `pvpnctl` CLI installed and logged into your Proton VPN account (`pvpnctl login <user> <pass>`).

## Installation

Place or symlink this folder into your DMS plugins directory:
`~/.config/dank/plugins/Proton_VPN`
