@echo off
chcp 65001 >nul
title Zoom Recorder
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\record.ps1"
