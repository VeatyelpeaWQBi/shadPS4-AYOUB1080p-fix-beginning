# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Run explicitly from the user's existing PowerShell environment. No tools are installed.
[CmdletBinding()]
param(
    [string]$EmulatorPath = 'D:\game\shadPS4-AYOUB1080p-1.0-windows-x64\shadPS4-AYOUB1080p-1.0\shadps4.exe',
    [string]$GameDirectory = 'D:\game\shadPS4QtLauncher\games\CUSA00309',
    [string]$UserDirectory = (Join-Path $env:APPDATA 'shadPS4'),
    [ValidateSet('1080p', '1440p', '1800p', '4k')]
    [string]$Resolution = '1800p',
    [switch]$Diagnostic,
    [switch]$SynchronousReadbacks,
    [switch]$ProtectGuestStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$gameExecutable = Join-Path $GameDirectory 'eboot.bin'
$sourcePatch = Join-Path $repoRoot 'package\user-files\patches\shadPS4-AYOUB1080p\inFAMOUS Second Son CUSA00309.xml'
$sourceConfig = Join-Path $repoRoot 'package\user-files\custom_configs\CUSA00309.json'
$sourceTuning = Join-Path $repoRoot 'documents\Debugging\infamous-CUSA00309-perf.ini'
foreach ($inputPath in @($EmulatorPath, $gameExecutable, $sourcePatch, $sourceConfig, $sourceTuning)) {
    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) {
        throw "Required file does not exist: $inputPath"
    }
}
# The emulator chooses CWD/user when it exists, otherwise the platform's AppData directory.
# --override-root overrides the GAME mount root; it does not select a configuration directory.
$EmulatorPath = (Get-Item -LiteralPath $EmulatorPath).FullName
$gameExecutable = (Get-Item -LiteralPath $gameExecutable).FullName
$launchDirectory = Split-Path -Parent $EmulatorPath
$standardUserDirectory = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'shadPS4'))
if ($PSBoundParameters.ContainsKey('UserDirectory')) {
    $UserDirectory = [IO.Path]::GetFullPath($UserDirectory)
    if ((Split-Path -Leaf $UserDirectory) -eq 'user' -and
        (Test-Path -LiteralPath $UserDirectory -PathType Container)) {
        $launchDirectory = Split-Path -Parent $UserDirectory
    }
}
$portableDirectory = Join-Path $launchDirectory 'user'
$nativeUserDirectory = if (Test-Path -LiteralPath $portableDirectory -PathType Container) {
    [IO.Path]::GetFullPath($portableDirectory)
} else { $standardUserDirectory }
if ($PSBoundParameters.ContainsKey('UserDirectory') -and
    -not [string]::Equals($UserDirectory, $nativeUserDirectory, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'UserDirectory must match the native AppData directory or an existing portable directory named user.'
}
$UserDirectory = $nativeUserDirectory
if (@(Get-Process -Name shadps4 -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Close other shadPS4 instances before using this temporary tuning profile.'
}
$gameHash = (Get-FileHash -LiteralPath $gameExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
if ($gameHash -ne '2d1ca79630d7bbe6fa29575f59aa7996d43071d74ac8e4f7d40137967d9039ab') {
    throw 'This executable differs from the analyzed CUSA00309 01.07 dump. Analyze it before applying these patches.'
}

$configPath = Join-Path $UserDirectory 'custom_configs\CUSA00309.json'
$patchPath = Join-Path $UserDirectory 'patches\shadPS4-AYOUB1080p\inFAMOUS Second Son CUSA00309.xml'
$tuningPath = Join-Path $UserDirectory 'perf_tuning.ini'
$originalFiles = @()
foreach ($targetPath in @($configPath, $patchPath, $tuningPath)) {
    $existed = Test-Path -LiteralPath $targetPath -PathType Leaf
    $originalBytes = if ($existed) { [IO.File]::ReadAllBytes($targetPath) } else { $null }
    $originalFiles += [PSCustomObject]@{ Path = $targetPath; Existed = $existed; Bytes = $originalBytes }
}

function Merge-ConfigGroups($destination, $overrides) {
    foreach ($group in $overrides.PSObject.Properties) {
        if ($null -eq $destination.PSObject.Properties[$group.Name]) {
            $destination | Add-Member -MemberType NoteProperty -Name $group.Name -Value ([PSCustomObject]@{})
        }
        $targetGroup = $destination.PSObject.Properties[$group.Name].Value
        foreach ($setting in $group.Value.PSObject.Properties) {
            $targetGroup | Add-Member -MemberType NoteProperty -Name $setting.Name -Value $setting.Value -Force
        }
    }
}

function Get-LaunchExitDetails($process, $startedAt, $userPath) {
    $process.WaitForExit()
    $message = 'Simulator exited (exit code {0}).' -f $process.ExitCode
    foreach ($logName in @('shadps4.log', 'CUSA00309.log')) {
        $logPath = Join-Path $userPath ('log\' + $logName)
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $logFile = Get-Item -LiteralPath $logPath
            if ($logFile.LastWriteTime -ge $startedAt.AddSeconds(-1)) {
                $errors = @(Get-Content -LiteralPath $logPath -Tail 30 |
                    Where-Object { $_ -match '<Error>|<Critical>' } | Select-Object -Last 5)
                if ($errors.Count -gt 0) {
                    $message += "`n" + $logPath + "`n" + ($errors -join "`n")
                }
            }
        }
    }
    return $message
}

$config = if ($originalFiles[0].Existed) {
    [Text.Encoding]::UTF8.GetString([byte[]]$originalFiles[0].Bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
} else { [PSCustomObject]@{} }
Merge-ConfigGroups $config (Get-Content -LiteralPath $sourceConfig -Raw | ConvertFrom-Json)
Merge-ConfigGroups $config ([PSCustomObject]@{
    GPU = [PSCustomObject]@{ null_gpu = $false; dump_shaders = $false }
    Vulkan = [PSCustomObject]@{ renderdoc_enabled = $false; vkvalidation_enabled = $false }
})
if ($Diagnostic) {
    Merge-ConfigGroups $config ([PSCustomObject]@{
        Log = [PSCustomObject]@{
            enable = $true; filter = '*:info Input:debug'; separate = $true; sync = $true
            skip_duplicate = $true; size_limit = 16777216; append = $false
        }
    })
}
$enableStackProtection = $ProtectGuestStack -or [bool]$config.General.redzone_patches
if ($enableStackProtection) {
    # The HK profile enables this after the user verified the opening on 0.19.0 and AYOUB 1.0.
    # Keep the explicit switch compatible with previously documented commands.
    # Override an inherited legacy Disabled mode as well as the current setting.
    Merge-ConfigGroups $config ([PSCustomObject]@{
        General = [PSCustomObject]@{ redzone_patches = $true }
        WindowsGuestRedZoneProtection = [PSCustomObject]@{
            windows_guest_red_zone_protection_mode = 'StaticPatching'
        }
    })
    if ($Diagnostic) {
        $config.Log.filter = '*:info Core.Linker:debug Input:debug'
    }
}
$config.General.neo_mode = $Resolution -ne '1080p'

[xml]$patch = Get-Content -LiteralPath $sourcePatch -Raw
$selectedResolution = switch ($Resolution) {
    '1080p' { '' }
    '1440p' { 'PS4 Pro mode: native 2560x1440 without checkerboard' }
    '1800p' { 'PS4 Pro mode: native 3200x1800 without checkerboard' }
    '4k' { 'PS4 Pro mode: native 3840x2160 without checkerboard' }
}
foreach ($metadata in $patch.SelectNodes('/Patch/Metadata')) {
    $patchName = $metadata.GetAttribute('Name')
    if ($patchName.StartsWith('Native ') -or $patchName.StartsWith('PS4 Pro mode:')) {
        $metadata.SetAttribute('isEnabled', ($patchName -eq $selectedResolution).ToString().ToLowerInvariant())
    }
}
$tuning = Get-Content -LiteralPath $sourceTuning -Raw
if (-not $Diagnostic) {
    $tuning = $tuning.Replace('perf_log = 1', 'perf_log = 0').Replace('profile_stacks = 1', 'profile_stacks = 0')
} else {
    # Measure actual GPU submissions; a disabled profiler reports zero-valued timing counters.
    $tuning += "`n# GPU submission timing for diagnostics.`ngpu_profile = 1`n"
}
if ($SynchronousReadbacks) {
    # The parser applies later entries last. Isolate the background/second-queue readback path.
    $tuning += "`n# Synchronous readback comparison.`nasync_readbacks = 0`nreadback_queue = 0`nreadback_prefetch = 0`n"
}
$utf8 = New-Object Text.UTF8Encoding($false)
$gameProcess = $null

Write-Host 'Temporarily applying HK configuration, patches and tuning (about 16 KiB).'
Write-Host 'Previous files are held in memory and restored when the game exits.'
if ($Diagnostic) {
    Write-Host 'Diagnostic log limit: 16 MiB. Existing same-name logs may be overwritten.'
}
Write-Host 'The game may generate its normal shader cache. No game files or global environment settings are changed.'
if ($SynchronousReadbacks) {
    Write-Host 'Synchronous GPU readbacks selected for comparison; performance may be lower.'
}
if ($enableStackProtection) {
    Write-Host 'Windows guest stack protection enabled for HK; startup analysis may take longer.'
    Write-Host 'Verify isRedZonePatchingEnabled: true and the linker protection coverage in the diagnostic log.'
}
try {
    foreach ($targetPath in @($configPath, $patchPath, $tuningPath)) {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath))
    }
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20), $utf8)
    [IO.File]::WriteAllText($patchPath, $patch.OuterXml, $utf8)
    [IO.File]::WriteAllText($tuningPath, $tuning, $utf8)
    # An explicit XML patch selects this file directly. Keep the game's update overlay enabled.
    $arguments = '-p "{0}" -g "{1}"' -f $patchPath, $gameExecutable
    $launchStartedAt = Get-Date
    $gameProcess = Start-Process -FilePath $EmulatorPath -ArgumentList $arguments -WorkingDirectory $launchDirectory -PassThru
    # Retain the handle so Windows PowerShell can report ExitCode after the process exits.
    $null = $gameProcess.Handle
    if ($gameProcess.WaitForExit(1500)) {
        throw (Get-LaunchExitDetails $gameProcess $launchStartedAt $UserDirectory)
    }
    if ($Diagnostic) {
        $null = Read-Host 'When the opening reaches the sky or an interactive prompt, return here and press Enter'
        $gameProcess.Refresh()
        if (-not $gameProcess.HasExited) {
            [IO.File]::WriteAllText($tuningPath, $tuning.Replace('dump_frames = 0', 'dump_frames = 2'), $utf8)
            Write-Host 'Two-frame command capture requested. Keep the scene running for at least 40 seconds, then close the game normally.'
        } else {
            Write-Warning ((Get-LaunchExitDetails $gameProcess $launchStartedAt $UserDirectory) + ' No two-frame capture was made.')
        }
    }
    $gameProcess.WaitForExit()
    if ($gameProcess.ExitCode -ne 0) {
        throw (Get-LaunchExitDetails $gameProcess $launchStartedAt $UserDirectory)
    }
    if ($Diagnostic) {
        Write-Host ('Log: ' + (Join-Path $UserDirectory 'log\CUSA00309.log'))
    }
} finally {
    # No recursive cleanup: restore only the three specifically named files above.
    foreach ($saved in $originalFiles) {
        if ($saved.Existed) {
            [IO.File]::WriteAllBytes($saved.Path, [byte[]]$saved.Bytes)
        } elseif (Test-Path -LiteralPath $saved.Path -PathType Leaf) {
            Remove-Item -LiteralPath $saved.Path -Force
        }
    }
}
