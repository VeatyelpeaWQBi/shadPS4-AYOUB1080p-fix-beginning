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
    [switch]$Performance,
    [switch]$CacheDiagnostic,
    [switch]$PerformanceDiagnostic,
    [switch]$LightProfile,
    [switch]$RuntimeLookupBaseline,
    [switch]$ComputeCompileBaseline,
    [string]$BenchmarkDirectory,
    [string[]]$TuningOverride = @(),
    [switch]$SynchronousReadbacks,
    [switch]$ProtectGuestStack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PerformanceDiagnostic) {
    $Performance = $true
    $CacheDiagnostic = $true
}
if ($LightProfile -and -not $PerformanceDiagnostic) {
    throw 'LightProfile requires PerformanceDiagnostic.'
}
if ($Performance -and ($Diagnostic -or $SynchronousReadbacks)) {
    throw 'Performance cannot be combined with Diagnostic or SynchronousReadbacks.'
}
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
$nativeLogDirectory = Join-Path $UserDirectory 'log'
if ($BenchmarkDirectory) {
    $BenchmarkDirectory = [IO.Path]::GetFullPath($BenchmarkDirectory)
    if (-not (Test-Path -LiteralPath $BenchmarkDirectory -PathType Container)) {
        throw 'Create the isolated benchmark directory before launching.'
    }
    $nativeLogDirectory = Join-Path $BenchmarkDirectory 'log'
}
$emulatorProcessName = [IO.Path]::GetFileNameWithoutExtension($EmulatorPath)
$runningEmulators = @(Get-Process | Where-Object {
    $_.ProcessName -eq $emulatorProcessName -or $_.ProcessName -match '^shadps4($|[-_]|v[0-9])'
})
if ($runningEmulators.Count -ne 0) {
    throw 'Close other shadPS4 instances before using this temporary tuning profile.'
}
$gameHash = (Get-FileHash -LiteralPath $gameExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
if ($gameHash -ne '2d1ca79630d7bbe6fa29575f59aa7996d43071d74ac8e4f7d40137967d9039ab') {
    throw 'This executable differs from the analyzed CUSA00309 01.07 dump. Analyze it before applying these patches.'
}

$profileDirectory = if ($BenchmarkDirectory) { $BenchmarkDirectory } else { $UserDirectory }
$configPath = Join-Path $profileDirectory 'custom_configs\CUSA00309.json'
$patchPath = Join-Path $profileDirectory 'patches\shadPS4-AYOUB1080p\inFAMOUS Second Son CUSA00309.xml'
$tuningPath = Join-Path $profileDirectory 'perf_tuning.ini'
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
        $logPath = Join-Path $nativeLogDirectory $logName
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

function Get-PrivateCacheSnapshot($userPath) {
    $cacheDirectory = Join-Path $userPath 'cache\CUSA00309\pipeline-v2'
    $files = if (Test-Path -LiteralPath $cacheDirectory -PathType Container) {
        @(Get-ChildItem -LiteralPath $cacheDirectory -File)
    } else { @() }
    $driver = @($files | Where-Object Name -eq 'driver.vkc')
    return [PSCustomObject]@{
        Directory = $cacheDirectory
        ComputePipelines = @($files | Where-Object Name -Like 'c_*.key').Count
        GraphicsPipelines = @($files | Where-Object Name -Like 'g_*.key').Count
        ShaderMetadata = @($files | Where-Object Extension -eq '.meta').Count
        ShaderBinaries = @($files | Where-Object Extension -eq '.spv').Count
        DriverBytes = if ($driver.Count) { $driver[0].Length } else { 0 }
        Pipelines = @($files | Where-Object Extension -eq '.key' | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; WrittenAt = $_.LastWriteTime.ToString('o') }
        })
    }
}

function Add-PerformanceMarker($kind) {
    $now = Get-Date
    $event = [PSCustomObject]@{
        Kind = $kind
        Time = $now.ToString('o')
        SecondsSinceLaunch = [Math]::Round(($now - $launchStartedAt).TotalSeconds, 3)
        ConsoleFocusMayAffectFrameTime = $true
    }
    $diagnosticEvents.Add($event)
    Write-Host ('MARKER {0}: {1:HH:mm:ss} ({2:N1} seconds since launch)' -f $kind, $now, $event.SecondsSinceLaunch)
}

function Copy-BoundedDiagnosticLog($source, $target) {
    $remaining = 16777216L
    $inputStream = [IO.File]::OpenRead($source)
    try {
        $outputStream = [IO.File]::Create($target)
        try {
            $buffer = [byte[]]::new(65536)
            while ($remaining -gt 0) {
                $count = $inputStream.Read($buffer, 0, [int][Math]::Min($remaining, $buffer.Length))
                if ($count -eq 0) { break }
                $outputStream.Write($buffer, 0, $count)
                $remaining -= $count
            }
        } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
}

function Save-PerformanceReport {
    if (-not $PerformanceDiagnostic -or -not $diagnosticRun) { return }
    try {
        $after = Get-PrivateCacheSnapshot $UserDirectory
        $beforeNames = @($cacheBefore.Pipelines | ForEach-Object Name)
        $newPipelines = @($after.Pipelines | Where-Object { $_.Name -notin $beforeNames })
        $diagnosticRun.FinishedAt = (Get-Date).ToString('o')
        $diagnosticRun.ExitCode = if ($gameProcess -and $gameProcess.HasExited) { $gameProcess.ExitCode } else { $null }
        $diagnosticRun.Markers = @($diagnosticEvents.ToArray())
        $diagnosticRun.CacheAfter = $after | Select-Object -Property * -ExcludeProperty Pipelines
        $diagnosticRun.NewPipelines = $newPipelines
        $diagnosticRun.Logs = @()
        $diagnosticRun.LogsAtLimit = @()
        foreach ($logName in @('CUSA00309.log', 'shadps4.log')) {
            if (-not $launchStartedAt) { continue }
            $source = Join-Path $nativeLogDirectory $logName
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $log = Get-Item -LiteralPath $source
            if ($log.LastWriteTime -lt $launchStartedAt.AddSeconds(-1)) { continue }
            $target = Join-Path $diagnosticDirectory $logName
            if ($log.Length -ge 16777216) {
                $diagnosticRun.LogsAtLimit += $logName
                Copy-BoundedDiagnosticLog $source $target
                Write-Warning ("$logName reached the 16 MiB budget; only its first 16 MiB are archived. Use a shorter next test.")
            } else {
                Copy-Item -LiteralPath $source -Destination $target
            }
            $diagnosticRun.Logs += $logName
        }
        [IO.File]::WriteAllText((Join-Path $diagnosticDirectory 'run.json'),
            ($diagnosticRun | ConvertTo-Json -Depth 8), $utf8)
        Write-Host ('Diagnostic report: ' + $diagnosticDirectory)
    } catch {
        Write-Warning ('Could not save the complete diagnostic report: ' + $_.Exception.Message)
    }
}

$config = if ($originalFiles[0].Existed) {
    [Text.Encoding]::UTF8.GetString([byte[]]$originalFiles[0].Bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
} else { [PSCustomObject]@{} }
Merge-ConfigGroups $config (Get-Content -LiteralPath $sourceConfig -Raw | ConvertFrom-Json)
Merge-ConfigGroups $config ([PSCustomObject]@{
    GPU = [PSCustomObject]@{ null_gpu = $false; dump_shaders = $false }
    Vulkan = [PSCustomObject]@{ renderdoc_enabled = $false; vkvalidation_enabled = $false }
})
if ($Performance) {
    # Reuse the established Infamous profile, with precise readbacks and graphics-only
    # asynchronous pipelines. Remove diagnostic overhead without skipping compute work.
    Merge-ConfigGroups $config ([PSCustomObject]@{
        General = [PSCustomObject]@{ dev_kit_mode = $false }
        Debug = [PSCustomObject]@{ debug_dump = $false; shader_collect = $false }
        Input = [PSCustomObject]@{ motion_controls_enabled = $true }
        Log = [PSCustomObject]@{
            enable = $true; filter = '*:error'; separate = $true; sync = $false
            skip_duplicate = $true; size_limit = 16777216; append = $false
        }
        GPU = [PSCustomObject]@{
            copy_gpu_buffers = $false; vblank_frequency = 60
            full_screen = $true; full_screen_mode = 'Fullscreen (Borderless)'
            present_mode = 'Mailbox'; fsr_enabled = $false
        }
        Vulkan = [PSCustomObject]@{
            gpu_id = -1; pipeline_cache_enabled = $true
            vkvalidation_core_enabled = $false; vkvalidation_sync_enabled = $false
            vkvalidation_gpu_enabled = $false; vkcrash_diagnostic_enabled = $false
            vkhost_markers = $false; vkguest_markers = $false
        }
    })
}
if ($Diagnostic) {
    Merge-ConfigGroups $config ([PSCustomObject]@{
        Log = [PSCustomObject]@{
            enable = $true; filter = '*:info Input:debug'; separate = $true; sync = $true
            skip_duplicate = $true; size_limit = 16777216; append = $false
        }
    })
}
if ($CacheDiagnostic -and -not $Diagnostic) {
    Merge-ConfigGroups $config ([PSCustomObject]@{
        Log = [PSCustomObject]@{
            enable = $true; filter = '*:warning Render:info Render_Vulkan:info Debug:info'; separate = $true
            sync = $false; skip_duplicate = $true; size_limit = 16777216; append = $false
        }
    })
}
if ($PerformanceDiagnostic) {
    Merge-ConfigGroups $config ([PSCustomObject]@{
        Log = [PSCustomObject]@{
            enable = $true
            filter = '*:warning Config:info Debug:info Render:info Render_Vulkan:info Core.Linker:info'
            separate = $true; sync = $false; skip_duplicate = $true
            size_limit = 16777216; append = $false
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
if ($Performance) {
    $tuning += "`n# Performance run: keep asynchronous readbacks, disable profiling.`nasync_readbacks = 1`nreadback_prefetch = 1`ngpu_profile = 0`nperf_log = 0`nprofile_stacks = 0`ndump_frames = 0`n"
}
if ($CacheDiagnostic) {
    # Cold/warm comparison with compact cache and slow-frame reports; no stack sampling or capture.
    $tuning += "`n# Cache diagnostics.`nperf_log = 1`nprofile_stacks = 0`ngpu_profile = 1`ndump_frames = 0`n"
}
if ($PerformanceDiagnostic -and -not $LightProfile) {
    # Detailed sampling is diagnostic-only. Keep all rendering optimizations and precise reads.
    $tuning += "`n# CPU stacks and per-compute-dispatch GPU timings.`nprofile_stacks = 1`ngpu_profile = 2`n"
}
if ($RuntimeLookupBaseline) {
    # A/B comparison of the new CPU lookup/upload paths, with all earlier tuning retained.
    $tuning += "`n# Runtime lookup baseline comparison.`nruntime_lookup_memo = 0`n"
}
if ($ComputeCompileBaseline) {
    # Retain warmed caches and CPU improvements; compare first-use compute scheduling only.
    $tuning += "`n# Serial compute compile baseline.`ncompute_compile_parallel = 0`nasync_pipelines = 1`n"
}
if ($BenchmarkDirectory) {
    $startupTuningPath = Join-Path $BenchmarkDirectory 'tuning-startup.json'
    if (Test-Path -LiteralPath $startupTuningPath) {
        if ((Get-Item -LiteralPath $startupTuningPath).Length -gt 8192) { throw 'Oversized benchmark startup tuning.' }
        $startupTuning = Get-Content -LiteralPath $startupTuningPath -Raw | ConvertFrom-Json
        if (@($startupTuning).Count -gt 32) { throw 'Too many benchmark startup settings.' }
        foreach ($value in $startupTuning) {
            if ($value -isnot [string]) { throw 'Benchmark startup settings must be strings.' }
            $TuningOverride += $value
        }
    }
}
foreach ($override in $TuningOverride) {
    if ($override -notmatch '^[a-z_]+\s*=\s*[a-zA-Z0-9_,.x\-]+$') {
        throw "Invalid tuning override: $override"
    }
    $tuning += "`n$override`n"
}
$utf8 = New-Object Text.UTF8Encoding($false)
$gameProcess = $null
$launchStartedAt = $null
$diagnosticDirectory = $null
$diagnosticRun = $null
$cacheBefore = $null
$diagnosticEvents = [Collections.Generic.List[object]]::new()
$savedSampler = [Environment]::GetEnvironmentVariable('SHADPS4_PERF_SAMPLER', 'Process')

Write-Host 'Temporarily applying HK configuration, patches and tuning (about 16 KiB).'
Write-Host 'Previous files are held in memory and restored when the game exits.'
if ($Diagnostic) {
    Write-Host 'Diagnostic log limit: 16 MiB. Existing same-name logs may be overwritten.'
}
if ($Performance) {
    Write-Host ('Performance profile: {0}; PS4 Pro: {1}; native rendering; fullscreen; FPS counter.' -f $Resolution, $config.General.neo_mode)
    Write-Host 'Pipeline cache and existing Infamous optimizations enabled; validation disabled.'
    if (-not $CacheDiagnostic) {
        Write-Host 'Profiling disabled; only error/critical logs retained (16 MiB limit).'
    }
    Write-Host 'Close the game normally; keep this window open until settings are restored.'
}
if ($CacheDiagnostic -and -not $PerformanceDiagnostic) {
    Write-Host 'Cache diagnostics: preload/save counts and slow-frame reports enabled; stack sampling and frame capture disabled.'
}
if ($PerformanceDiagnostic) {
    $detail = if ($LightProfile) { 'overview (GPU submissions, CPU thread usage and hotspots)' } else {
        'detailed (CPU stacks and per-compute-shader GPU timing)'
    }
    Write-Host ('Performance diagnostics: ' + $detail)
    Write-Host 'Async log limit: 16 MiB. Each report may copy up to 32 MiB of logs plus small JSON metadata into Build\diagnostics.'
    Write-Host 'Profiling has overhead. Use the ordinary launch BAT to judge final FPS.'
    Write-Host 'Optional markers in THIS console: 1 = stutter, 2 = particle-heavy scene, 3 = normal scene.'
    Write-Host 'Switching to this console may itself affect frame time; markers record that interruption.'
    Write-Host 'Close the game normally; logs and run metadata will then be saved automatically.'
}
Write-Host 'The game may generate its normal shader cache. No game files or global environment settings are changed.'
if ($SynchronousReadbacks) {
    Write-Host 'Synchronous GPU readbacks selected for comparison; performance may be lower.'
}
if ($enableStackProtection) {
    Write-Host 'Windows guest stack protection enabled for HK; startup analysis may take longer.'
    if ($Diagnostic) {
        Write-Host 'Verify isRedZonePatchingEnabled: true and the linker protection coverage in the diagnostic log.'
    }
}
try {
    if ($PerformanceDiagnostic) {
        $runName = 'CUSA00309-{0}-{1}-{2}' -f $Resolution, (Get-Date -Format 'yyyyMMdd-HHmmss'),
            ([Guid]::NewGuid().ToString('N').Substring(0, 8))
        $diagnosticDirectory = if ($BenchmarkDirectory) {
            Join-Path $BenchmarkDirectory 'report'
        } else { Join-Path $repoRoot ('Build\diagnostics\' + $runName) }
        $null = [IO.Directory]::CreateDirectory($diagnosticDirectory)
        $cacheBefore = Get-PrivateCacheSnapshot $UserDirectory
        $diagnosticRun = [PSCustomObject]@{
            Schema = 1; GameSerial = 'CUSA00309'; GameVersion = '01.07'
            Resolution = $Resolution; Ps4Pro = [bool]$config.General.neo_mode
            Emulator = $EmulatorPath
            EmulatorSha256 = (Get-FileHash -LiteralPath $EmulatorPath -Algorithm SHA256).Hash
            EmulatorModifiedAt = (Get-Item -LiteralPath $EmulatorPath).LastWriteTime.ToString('o')
            StartedAt = $null; FinishedAt = $null; ExitCode = $null
            Profile = if ($LightProfile) { 'overview' } else { 'detailed' }
            GpuProfile = if ($LightProfile) { 1 } else { 2 }
            CpuStacks = -not [bool]$LightProfile
            RuntimeLookupBaseline = [bool]$RuntimeLookupBaseline
            ComputeCompileBaseline = [bool]$ComputeCompileBaseline
            BenchmarkDirectory = $BenchmarkDirectory
            TuningOverride = $TuningOverride
            CacheBefore = $cacheBefore | Select-Object -Property * -ExcludeProperty Pipelines
            CacheAfter = $null; NewPipelines = @(); Markers = @(); Logs = @(); LogsAtLimit = @()
        }
        # The game's child process inherits this setting; no user/system environment is changed.
        [Environment]::SetEnvironmentVariable('SHADPS4_PERF_SAMPLER', '1', 'Process')
    }
    foreach ($targetPath in @($configPath, $patchPath, $tuningPath)) {
        $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $targetPath))
    }
    [IO.File]::WriteAllText($configPath, ($config | ConvertTo-Json -Depth 20), $utf8)
    [IO.File]::WriteAllText($patchPath, $patch.OuterXml, $utf8)
    [IO.File]::WriteAllText($tuningPath, $tuning, $utf8)
    # An explicit XML patch selects this file directly. Keep the game's update overlay enabled.
    $arguments = '-p "{0}" -g "{1}"' -f $patchPath, $gameExecutable
    if ($BenchmarkDirectory) {
        $arguments += ' --benchmark-dir "{0}"' -f $BenchmarkDirectory
    }
    if ($Performance) {
        $arguments += ' --show-fps -f true'
    }
    $launchStartedAt = Get-Date
    if ($diagnosticRun) {
        $diagnosticRun.StartedAt = $launchStartedAt.ToString('o')
        [IO.File]::WriteAllText((Join-Path $diagnosticDirectory 'run.json'),
            ($diagnosticRun | ConvertTo-Json -Depth 8), $utf8)
    }
    $gameProcess = Start-Process -FilePath $EmulatorPath -ArgumentList $arguments -WorkingDirectory $launchDirectory -WindowStyle Hidden -PassThru
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
    if ($PerformanceDiagnostic) {
        $consoleMarkers = $true
        while (-not $gameProcess.WaitForExit(250)) {
            if (-not $consoleMarkers) { continue }
            try {
                if ([Console]::KeyAvailable) {
                    switch ([Console]::ReadKey($true).KeyChar) {
                        '1' { Add-PerformanceMarker 'stutter' }
                        '2' { Add-PerformanceMarker 'particle-heavy' }
                        '3' { Add-PerformanceMarker 'normal' }
                    }
                }
            } catch {
                # Redirected input / non-console hosts do not support ReadKey; logging still works.
                $consoleMarkers = $false
            }
        }
    } else {
        $gameProcess.WaitForExit()
    }
    if ($gameProcess.ExitCode -ne 0) {
        throw (Get-LaunchExitDetails $gameProcess $launchStartedAt $UserDirectory)
    }
    if ($Diagnostic -or $CacheDiagnostic) {
        Write-Host ('Log: ' + (Join-Path $nativeLogDirectory 'CUSA00309.log'))
    }
} finally {
    if ($PerformanceDiagnostic) {
        [Environment]::SetEnvironmentVariable('SHADPS4_PERF_SAMPLER', $savedSampler, 'Process')
        if ($diagnosticRun) { Save-PerformanceReport }
    }
    # No recursive cleanup: restore only the three specifically named files above.
    foreach ($saved in $originalFiles) {
        if ($saved.Existed) {
            [IO.File]::WriteAllBytes($saved.Path, [byte[]]$saved.Bytes)
        } elseif (Test-Path -LiteralPath $saved.Path -PathType Leaf) {
            Remove-Item -LiteralPath $saved.Path -Force
        }
    }
    Write-Host 'Previous configuration, patches and tuning restored.'
}
