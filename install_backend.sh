#!/bin/bash
echo "Installing / Updating pVPN backend..."
curl -fsSL https://raw.githubusercontent.com/YourDoritos/pVPN/main/install.sh | sudo bash
echo "Done! Press Enter to exit."
read -r _
