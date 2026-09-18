@echo off
setlocal

rem Blender MCP Server Wrapper Script (Windows)
rem Ensures uv/uvx is on PATH and runs the MCP server through uvx.
rem
rem Upstream: https://github.com/ahujasid/blender-mcp (package: mcp-for-blender,
rem formerly published as blender-mcp on PyPI - uvx blender-mcp still works too).

rem uv's default install location may not be on PATH when this script is
rem spawned by a GUI app (Claude Desktop, Cursor, ...) that doesn't inherit
rem the shell's PATH.
set "PATH=%USERPROFILE%\.local\bin;%PATH%"

where uvx >nul 2>nul
if errorlevel 1 (
    echo uvx not found. Install uv first:
    echo   powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
    exit /b 1
)

if not defined BLENDER_HOST set "BLENDER_HOST=localhost"
if not defined BLENDER_PORT set "BLENDER_PORT=9876"

uvx mcp-for-blender %*
