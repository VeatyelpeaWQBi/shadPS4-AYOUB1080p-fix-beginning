@echo off
rem SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
rem SPDX-License-Identifier: GPL-2.0-or-later
setlocal
title inFAMOUS Second Son - PS4 Pro Native 4K Performance
set "EMULATOR_EXE=D:\projects\shadPS4-AYOUB1080p-fix-beginning\Build\x64-Clang-Release\shadps4.exe"
set "GAME_DIR=D:\game\shadPS4QtLauncher\games\CUSA00309"

if not exist "%~dp0run_infamous_hk.ps1" (
    echo ERROR: Keep this BAT in the project's scripts folder beside run_infamous_hk.ps1.
    pause
    exit /b 1
)

echo Starting CUSA00309 1.07 at native 3840x2160, PS4 Pro mode.
echo Keep this window open. Close the game normally to restore your settings.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_infamous_hk.ps1" -EmulatorPath "%EMULATOR_EXE%" -GameDirectory "%GAME_DIR%" -Resolution 4k -Performance %*
set "LAUNCH_EXIT=%ERRORLEVEL%"

if not "%LAUNCH_EXIT%"=="0" echo Launch failed or the emulator exited with an error. See the message above.
pause
exit /b %LAUNCH_EXIT%
