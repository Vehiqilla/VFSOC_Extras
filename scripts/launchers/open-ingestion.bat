@echo off
REM VFSOC Ingestion - starts Docker infra and launches the WPF client.
REM Closing this CMD window will automatically stop the app, free its port,
REM and (when nothing else is running) shut the Docker services down too.
title VFSOC Ingestion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0VFSOC-Launch.ps1" -App ingestion
