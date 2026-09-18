@echo off
setlocal

rem Installs uv (if missing) and copies the MCP-for-Blender addon into
rem Blender's addons folder. Run this once per machine, then enable the
rem addon inside Blender.
rem
rem Upstream: https://github.com/ahujasid/blender-mcp

set "PATH=%USERPROFILE%\.local\bin;%PATH%"

where uvx >nul 2>nul
if errorlevel 1 (
    echo uv not found, installing...
    powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
    set "PATH=%USERPROFILE%\.local\bin;%PATH%"
)

uvx mcp-for-blender install-addon

echo.
echo Addon copied. Now, in Blender:
echo   1. Edit ^> Preferences ^> Add-ons
echo   2. Search "MCP for Blender" and enable "Interface: MCP for Blender"
echo      (if it doesn't show up, click Install... and pick the copied
echo      blender_mcp.py, or restart Blender)
echo   3. Press N in the 3D viewport, open the "MCP for Blender" tab,
echo      click "Start MCP Server"
