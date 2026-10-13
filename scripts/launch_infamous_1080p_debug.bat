@echo off
rem SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
rem SPDX-License-Identifier: GPL-2.0-or-later
setlocal
title inFAMOUS Second Son - 1080P Performance Diagnostics
set "EMULATOR_EXE=%~dp0..\Build\x64-Clang-Release\shadps4.exe"
set "GAME_DIR=D:\game\shadPS4QtLauncher\games\CUSA00309"

if not exist "%~dp0run_infamous_hk.ps1" (
    echo ERROR: Keep this BAT beside run_infamous_hk.ps1.
    pause
    exit /b 1
)
echo Starting CUSA00309 1.07 at native 1920x1080, base PS4 mode, with performance diagnostics.
echo Keep this window open. Close the game normally to save the report and restore settings.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_infamous_hk.ps1" -EmulatorPath "%EMULATOR_EXE%" -GameDirectory "%GAME_DIR%" -Resolution 1080p -PerformanceDiagnostic %*
set "LAUNCH_EXIT=%ERRORLEVEL%"
if not "%LAUNCH_EXIT%"=="0" echo Diagnostics ended with an error. See the message above.
pause
exit /b %LAUNCH_EXIT%
