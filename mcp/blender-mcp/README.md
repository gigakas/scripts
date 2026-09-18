# blender-mcp — MCP server for live Blender control

Wrapper scripts around [MCP for Blender](https://github.com/ahujasid/blender-mcp)
(by ahujasid, MIT). The PyPI package was renamed `blender-mcp` → `mcp-for-blender`;
`uvx blender-mcp` still works, but new installs should use `mcp-for-blender`.

Unlike the Inkscape MCP setup, this one is **not patched** — it runs the
upstream package as-is via [`uv`](https://docs.astral.sh/uv/)/`uvx`, which
manages its own isolated environment (no manual venv needed). The scripts here
only make sure `uvx` is reachable from GUI-launched MCP clients (which don't
inherit your shell's `PATH`) and set sane defaults.

## Architecture

```
Claude / Cursor / etc. ──spawns──> uvx mcp-for-blender (stdio)
                                        │ TCP socket (localhost:9876)
                                        ▼
                          Blender addon "MCP for Blender"
                          (Edit ▸ Preferences ▸ Add-ons)
                                        │
                          executes Python inside the running
                          Blender GUI — changes appear live
```

## Files

| File | Purpose |
|---|---|
| `install_addon.sh` / `install_addon.bat` | Installs `uv` if missing, then copies the addon into Blender's addons folder (`uvx mcp-for-blender install-addon`) |
| `run_blender_mcp.sh` / `run_blender_mcp.bat` | The command your MCP client actually spawns — ensures `uvx` is on `PATH`, sets `BLENDER_HOST`/`BLENDER_PORT` defaults, execs `uvx mcp-for-blender` |

## 1. Prerequisites

- Blender 3.0+
- Python 3.10+
- `uv` — **use the official installer, not `pip install uv`** (pip installs can hide `uvx` from GUI clients)

### Linux

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Lands in `~/.local/bin` — open a new shell so it's on `PATH`.

### Windows

```powershell
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

Then add it to your user `PATH` (restart any MCP client afterwards):

```powershell
$localBin = "$env:USERPROFILE\.local\bin"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$localBin", "User")
```

## 2. Install the Blender addon

```bash
# Linux
./install_addon.sh
```

```powershell
:: Windows
install_addon.bat
```

Then in Blender: **Edit ▸ Preferences ▸ Add-ons** → enable **Interface: MCP for
Blender** (search for it; if it's not listed yet, click **Install…** and pick
the copied `blender_mcp.py`, or restart Blender).

Open the 3D viewport sidebar (press `N`) → **MCP for Blender** tab → **Start
MCP Server**.

## 3. Agent configurations

The command your client should spawn is this repo's wrapper script:

- Linux: `/home/gnino/Documents/scripts/mcp/blender-mcp/run_blender_mcp.sh`
- Windows: `<path-to-repo>\mcp\blender-mcp\run_blender_mcp.bat`

### Claude Code (CLI)

```bash
# Linux
claude mcp add --scope user blender /home/gnino/Documents/scripts/mcp/blender-mcp/run_blender_mcp.sh
```

```powershell
:: Windows
claude mcp add --scope user blender cmd /c "C:\path\to\scripts\mcp\blender-mcp\run_blender_mcp.bat"
```

### Claude Desktop (`claude_desktop_config.json`)

**Linux/macOS:**

```json
{
  "mcpServers": {
    "blender": {
      "command": "/home/gnino/Documents/scripts/mcp/blender-mcp/run_blender_mcp.sh"
    }
  }
}
```

**Windows** — wrap with `cmd /c` (GUI clients can fail to spawn `.bat` files
directly, `spawn ENOENT`):

```json
{
  "mcpServers": {
    "blender": {
      "command": "cmd",
      "args": ["/c", "C:\\path\\to\\scripts\\mcp\\blender-mcp\\run_blender_mcp.bat"]
    }
  }
}
```

### Cursor (`~/.cursor/mcp.json` or `.cursor/mcp.json`)

**Linux/macOS:**

```json
{
  "mcpServers": {
    "blender": {
      "command": "/home/gnino/Documents/scripts/mcp/blender-mcp/run_blender_mcp.sh"
    }
  }
}
```

**Windows:**

```json
{
  "mcpServers": {
    "blender": {
      "command": "cmd",
      "args": ["/c", "C:\\path\\to\\scripts\\mcp\\blender-mcp\\run_blender_mcp.bat"]
    }
  }
}
```

### Codex CLI (`~/.codex/config.toml`)

```toml
[mcp_servers.blender]
command = "/home/gnino/Documents/scripts/mcp/blender-mcp/run_blender_mcp.sh"
```

(Windows: `command = "cmd"`, `args = ["/c", "C:\\path\\to\\run_blender_mcp.bat"]`)

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `BLENDER_HOST` | `localhost` | Host of the Blender socket server |
| `BLENDER_PORT` | `9876` | Port of the Blender socket server |
| `BLENDER_MCP_SAFE_MODE` | off | `1` validates scripts before running them in Blender (blocks file/network/process access) |

Set them before running the wrapper script, or add an `"env"` block in the
client's MCP config. To run several Blender instances side by side, add a
second `mcpServers` entry with a different `--port`/`BLENDER_PORT` and match it
in the addon panel.

## Requirements for every client

- Blender running with the addon enabled and **Start MCP Server** clicked
  (the addon opens the local socket at startup of that action)
- Restart Blender after (re)installing/updating the addon
- Only run **one** MCP server instance against a given Blender at a time
- First launch of a client may take a few seconds while `uv` fetches the
  package

## Notes / caveats

- The addon's socket has **no auth/encryption** — keep `BLENDER_HOST` on
  `localhost` unless on a trusted network; prefer an SSH tunnel over exposing
  it remotely.
- Agent edits happen live in the GUI; `Ctrl+S` in Blender persists them.
- To upgrade: re-run `install_addon.sh`/`.bat` (keeps a `.bak` of the replaced
  file), then disable/re-enable the addon in Blender.
