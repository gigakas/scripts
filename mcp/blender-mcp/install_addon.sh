#!/bin/bash
# Installs uv (if missing) and copies the MCP-for-Blender addon into
# Blender's addons folder. Run this once per machine, then enable the
# addon inside Blender.
#
# Upstream: https://github.com/ahujasid/blender-mcp

set -e

export PATH="$HOME/.local/bin:$PATH"

if ! command -v uvx >/dev/null 2>&1; then
    echo "uv not found, installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

uvx mcp-for-blender install-addon

cat <<'EOF'

Addon copied. Now, in Blender:
  1. Edit > Preferences > Add-ons
  2. Search "MCP for Blender" and enable "Interface: MCP for Blender"
     (if it doesn't show up, click Install... and pick the copied
     blender_mcp.py, or restart Blender)
  3. Press N in the 3D viewport, open the "MCP for Blender" tab,
     click "Start MCP Server"
EOF
