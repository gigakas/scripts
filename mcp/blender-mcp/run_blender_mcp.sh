#!/bin/bash
# Blender MCP Server Wrapper Script (Linux/macOS)
# Ensures uv/uvx is on PATH and execs the MCP server through uvx.
#
# Upstream: https://github.com/ahujasid/blender-mcp (package: mcp-for-blender,
# formerly published as blender-mcp on PyPI — uvx blender-mcp still works too).

set -e

# uv's default install location (~/.local/bin) may not be on PATH when this
# script is spawned by a GUI app (Claude Desktop, Cursor, ...) that doesn't
# inherit the shell's PATH.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v uvx >/dev/null 2>&1; then
    echo "uvx not found. Install uv first:" >&2
    echo "  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
    exit 1
fi

# Allow overrides if already provided in the environment
export BLENDER_HOST="${BLENDER_HOST:-localhost}"
export BLENDER_PORT="${BLENDER_PORT:-9876}"

exec uvx mcp-for-blender "$@"
