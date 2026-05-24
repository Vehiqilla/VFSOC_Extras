@echo off
REM Convenience wrapper for starting all VFSOC services.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-vfsoc.ps1" %*
