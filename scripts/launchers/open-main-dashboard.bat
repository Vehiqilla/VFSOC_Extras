@echo off
REM VFSOC Main Dashboard - starts Docker infra and the Next.js dev server.
REM Closing this CMD window will stop the dev server, free port 3000, and
REM (when nothing else is running) shut the Docker services down too.
title VFSOC Main Dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VFSOC-Launch.ps1" -App siem
