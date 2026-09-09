#!/bin/bash

# Ensure the script is NOT run as root 
# (It must run under the specific user hosting the tunnel, e.g., proxmox)
if [ "$EUID" -eq 0 ]; then
  echo "⚠️  Warning: Running this script as root will configure the /root/.ssh directory."
  echo "Ensure you are logged in specifically as the 'proxmox' user on your VPS."
  read -p "Are you sure you want to proceed as root? (y/N): " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
    exit 1
  fi
fi

echo "=================================================="
echo "         VPS SECURITY CONFIGURATOR                "
echo "=================================================="
echo ""

# 1. Interactive input for the public key generated on Debian
read -r -p "🔑 Please paste the public key copied from Debian (starts with ssh-rsa): " PUBLIC_KEY

# Validate that the input is not empty
if [ -z "$PUBLIC_KEY" ]; then
  echo "❌ Error: Public key cannot be empty."
  exit 1
fi

# 2. Create the .ssh directory and enforce strict SSH permissions
echo "📁 Preparing secure SSH directories..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys

# 3. Define strict sandbox and hardening rules
# no-pty: Disables terminal shell access entirely
# command="/bin/false": Instantly drops the connection upon successful authentication
RESTRICTIONS='no-pty,no-X11-forwarding,permitopen="localhost:22",permitopen="localhost:8006",command="/bin/false"'

# 4. Append the sandboxed public key string to the authorized_keys file
echo "📝 Injecting the hardened key into authorized_keys..."
echo "$RESTRICTIONS $PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo ""
echo "=================================================="
echo "🎉 VPS configured and sandboxed successfully!"
echo "=================================================="
echo "Your cloud gateway is now fully locked down and ready."
