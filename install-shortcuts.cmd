@echo off
REM Convenience wrapper for installing the three VFSOC desktop shortcuts.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-Shortcuts.ps1" %*
