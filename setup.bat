@echo off
chcp 65001 >nul
title lite-screen-recorder setup
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"
