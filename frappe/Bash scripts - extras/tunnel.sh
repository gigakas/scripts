#!/bin/bash

# Ensure the script is run as root (required to install packages and create services)
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: This script must be run with administrative privileges (sudo)."
  exit 1
fi

echo "=================================================="
echo "   SSH Reverse Tunnel Configurator for Ubuntu     "
echo "=================================================="
echo ""

# 1. Request the password securely
echo "Please enter the password for the 'tunnel' SSH user."
read -sp "Password: " SSH_PASSWORD
echo "" # Necessary line break after read -s

# Validate that the password is not empty
if [ -z "$SSH_PASSWORD" ]; then
  echo "❌ Error: Password cannot be empty."
  exit 1
fi

# 2. Install required dependencies
echo "🔄 Updating repositories and installing sshpass..."
apt update && apt install -y sshpass

# 3. Create the systemd service file
SERVICE_PATH="/etc/systemd/system/ssh-tunnel.service"
echo "⚙️  Creating system service at: $SERVICE_PATH"

cat << EOF > $SERVICE_PATH
[Unit]
Description=SSH Reverse Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/sshpass -p '$SSH_PASSWORD' ssh -o StrictHostKeyChecking=no -N -R 2222:localhost:22 tunnel@www.albanss.com -p 1981
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable and start the service
echo "🔄 Reloading systemd and enabling the service..."
systemctl daemon-reload
systemctl enable ssh-tunnel.service
systemctl start ssh-tunnel.service

# 5. Final check
echo ""
echo "=================================================="
echo "🎉 All done! The service is configured and started."
echo "=================================================="
echo ""
echo "Current service status:"
echo "--------------------------------------------------"
systemctl status ssh-tunnel.service --no-pager