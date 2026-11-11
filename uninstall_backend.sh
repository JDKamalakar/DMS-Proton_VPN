#!/bin/bash
echo "Uninstalling pVPN backend..."
curl -fsSL https://raw.githubusercontent.com/YourDoritos/pVPN/main/uninstall.sh | sudo bash
echo "Done! Press Enter to exit."
read -r _
