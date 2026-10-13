@echo off
rem SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
rem SPDX-License-Identifier: GPL-2.0-or-later
setlocal
title shadPS4 - Incremental Release Build
set "BUILD_SCRIPT=%~dp0scripts\build_release.ps1"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%BUILD_SCRIPT%" (
    echo ERROR: Build script is missing: "%BUILD_SCRIPT%"
    pause
    exit /b 1
)
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%BUILD_SCRIPT%" %*
set "BUILD_EXIT=%ERRORLEVEL%"
echo.
if "%BUILD_EXIT%"=="0" (echo Build completed successfully.) else (echo Build failed. Review the error and log path above.)
pause
exit /b %BUILD_EXIT%
