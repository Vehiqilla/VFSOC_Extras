@echo off
REM Convenience wrapper for stopping all VFSOC services.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop-vfsoc.ps1" %*
