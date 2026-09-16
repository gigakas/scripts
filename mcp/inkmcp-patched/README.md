# inkmcp (patched) — MCP server for live Inkscape control

Patched copy of [inkmcp](https://github.com/Shriinivas/inkmcp) (by Shriinivas, AGPL-3.0)
adapted to work on this machine with the **snap build of Inkscape 1.4** and
**opencode** as the MCP client.

The agent can create/modify/inspect the document **live in the running Inkscape
GUI** — changes appear instantly on the canvas, no reload needed.

## Architecture

```
opencode ──spawns──> inkscape_mcp_server.py (FastMCP, stdio)
                          │ gdbus call (org.freedesktop.Application.Activate)
                          ▼
              D-Bus session bus: org.inkscape.Inkscape
                          ▼
              Inkscape runs extension org.khema.inkscape.mcp
                          ▼
              effect() edits the LIVE document in memory
                          ▼
              response written back via shared files
```

## Patches applied vs upstream

### 1. Shared temp directory (required for the snap sandbox)
The snap gives Inkscape a **private `/tmp`**, so files used for server↔extension
communication (params, responses) must live in a directory visible to both
processes. All `tempfile.mkstemp()` / `tempfile.gettempdir()` usages were
replaced with a fixed shared dir:

```
/home/gnino/.config/inkscape/inkmcp/
```

(inside the snap, `/home/gnino/.config/inkscape` is the same real folder thanks
to the `dot-config-inkscape` personal-files interface).

Files changed: `inkscape_mcp.py`, `inkscape_mcp_server.py`, `inkmcpcli.py`.
The helper `_inkmcp_tmpdir()` honors the `INKMCP_TMPDIR` env var as override
(set it on other platforms, e.g. Windows).

### 2. `mcp` SDK pinned to 1.x
The code imports the v1 SDK API (`from mcp.server.fastmcp import FastMCP`).
Newer `mcp>=2` renamed it, so the venv pins:

```
mcp>=1.9,<2
```

(`fastmcp` and `lxml` install fine; **`inkex` is intentionally NOT installed in
the venv** — it pulls PyGObject, which needs system build deps, and the
extension-side code uses the inkex bundled inside Inkscape anyway.)

## Installed locations

| Component | Path |
|---|---|
| Extension + MCP server (live install) | `~/snap/inkscape/common/extensions/inkmcp/` |
| Python venv for the server | `~/snap/inkscape/common/extensions/inkmcp/venv/` |
| opencode MCP registration | `~/.config/opencode/opencode.jsonc` → `"mcp": {"inkscape": {...}}` |
| Shared temp dir | `~/.config/inkscape/inkmcp/` |
| Upstream reference | https://github.com/Shriinivas/inkmcp |

Note: the snap's user extensions dir is `~/snap/inkscape/common/extensions/`
(**not** `~/.config/inkscape/extensions/` — check
*Edit ▸ Preferences ▸ System ▸ User extensions* if this ever changes).

## Agent configurations

Universal command (same for every client):

```
/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh
```

The script self-manages its Python venv and injects the D-Bus session env.

### opencode (`~/.config/opencode/opencode.jsonc`)

```jsonc
"mcp": {
  "inkscape": {
    "type": "local",
    "command": ["/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"],
    "enabled": true
  }
}
```

opencode spawns the server per session; tools appear as `inkscape_inkscape_operation`.
Requires **starting a new session** after editing the config.

### Claude Code (CLI) — configured on this machine ✔

```bash
claude mcp add --scope user inkscape /home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh
claude mcp list   # → inkscape ... ✔ Connected
```

Stored in `~/.claude.json` (user scope). Manual equivalent:

```json
{
  "mcpServers": {
    "inkscape": {
      "type": "stdio",
      "command": "/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"
    }
  }
}
```

### Claude Desktop (macOS/Windows only — no official Linux build)

`Claude ▸ Settings ▸ Developer ▸ Edit Config` → `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "inkscape": {
      "command": "/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"
    }
  }
}
```

(On Windows, use the path of `run_inkscape_mcp.bat` if you create one, and a
Windows-compatible shared temp dir via the `INKMCP_TMPDIR` env var.)

### Cursor

`~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "inkscape": {
      "command": "/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"
    }
  }
}
```

(or `cursor mcp add inkscape -- <script>` from the CLI.)

### Codex CLI (`~/.codex/config.toml`)

```toml
[mcp_servers.inkscape]
command = "/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"
```

### Gemini CLI (`~/.gemini/settings.json`)

```json
{
  "mcpServers": {
    "inkscape": {
      "command": "/home/gnino/snap/inkscape/common/extensions/inkmcp/run_inkscape_mcp.sh"
    }
  }
}
```

### Requirements for every client

- Inkscape (snap) **running** with any document open — the extension registers
  the D-Bus service `org.inkscape.Inkscape` at startup
- Restart Inkscape after (re)installing the extension files
- First launch of a client may take ~30 s while the venv is created

## Usage

Just ask opencode normally in any new session, e.g.:

- *"In Inkscape, draw a golden spiral made of circles"*
- *"Get the document info"*
- *"Export the current document as PNG"*
- *"Execute inkex code that adds a drop shadow to the selected object"*

The tool exposed is `inkscape_inkscape_operation` (single universal tool).

Direct CLI testing (bypasses the AI):

```bash
cd ~/snap/inkscape/common/extensions/inkmcp
./venv/bin/python inkmcpcli.py get-info --parse-out --pretty
./venv/bin/python inkmcpcli.py circle "cx=200 cy=200 r=60 fill=#ff8800"
./venv/bin/python inkmcpcli.py execute-code "code='...'"
```

## Parallel agents

Multiple agents (opencode + Claude Code, or several sessions) can drive the
same Inkscape at the same time: every session gets its own MCP server, and all
of them converge on the same live document through D-Bus.

Safety: operations from all servers are serialized through a cooperative queue
(`_wait_params_free`) plus atomic `os.replace()` writes of the shared
`mcp_params.json`, so concurrent tool calls cannot overwrite each other's
operations. Caveats:

- All agents share the **same canvas and active document** — pair them with
  complementary roles (e.g. one draws, another styles/exports) rather than
  editing the same objects
- The undo stack is shared: `Ctrl+Z` in the GUI undoes any agent's last op
- Saving (`Ctrl+S`) persists the combined result

## Notes / caveats

- Agent edits happen **in memory of the GUI**: visible instantly, but press
  `Ctrl+S` in Inkscape to persist them to disk.
- Inkscape must be running with the extension loaded (any document open).
- If Inkscape is restarted, nothing else needs restarting: opencode spawns a
  fresh MCP server per session.
- To update upstream: `git pull` in a clone, re-copy files into the extension
  dir, and re-apply the two patches above.
