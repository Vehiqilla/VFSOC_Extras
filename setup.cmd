@echo off
REM Convenience wrapper for the one-time VFSOC setup script.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-vfsoc.ps1" %*
