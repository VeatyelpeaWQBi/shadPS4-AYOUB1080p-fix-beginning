# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# A scoped local build/test worker. It accepts no arbitrary commands or external paths.
[CmdletBinding()]
param([ValidateRange(1,240)][int]$Minutes=180)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $projectRoot 'Build\particle-benchmark'
$null=[IO.Directory]::CreateDirectory($root)
$commandPath=Join-Path $root 'worker-command.json'
$statusPath=Join-Path $root 'worker-status.json'
$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$utf8=[Text.UTF8Encoding]::new($false)
$deadline=(Get-Date).AddMinutes($Minutes)
$lastSequence=0L
$child=$null
$current=$null
$nextGpu=Get-Date
function Save-WorkerStatus($state,$detail) {
    $value=[ordered]@{State=$state;Detail=$detail;Sequence=$lastSequence;UpdatedAt=(Get-Date).ToString('o');
                     ChildPid=if($child){$child.Id}else{$null}}
    [IO.File]::WriteAllText($statusPath,($value|ConvertTo-Json -Compress),$utf8)
}
Save-WorkerStatus 'ready' 'Existing system tools; isolated benchmark saves/configuration.'
try {
    while((Get-Date)-lt $deadline) {
        if($child) {
            if($child.WaitForExit(200)) {
                $code=$child.ExitCode
                $child=$null
                Save-WorkerStatus $(if($code-eq0){'completed'}else{'failed'}) ('Exit code '+$code)
                $current=$null
            } elseif($current.action-eq 'run' -and (Get-Date)-ge $nextGpu) {
                $nextGpu=(Get-Date).AddSeconds(5)
                $gpu=& 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=pstate,temperature.gpu,clocks.gr,clocks.mem,power.draw,utilization.gpu,memory.used --format=csv,noheader,nounits 2>$null
                Add-Content -LiteralPath (Join-Path $current.runRoot 'gpu.csv') -Value ((Get-Date).ToString('o')+', '+$gpu) -Encoding utf8
            }
            continue
        }
        Start-Sleep -Milliseconds 200
        if(-not(Test-Path -LiteralPath $commandPath)) {continue}
        try {$command=Get-Content -LiteralPath $commandPath -Raw|ConvertFrom-Json}catch{continue}
        if([long]$command.sequence-le $lastSequence){continue}
        $lastSequence=[long]$command.sequence
        if($command.action-eq 'stop'){Save-WorkerStatus 'stopped' 'Requested worker stop.';break}
        $bytes=(Get-ChildItem -LiteralPath $root -Recurse -File|Measure-Object Length -Sum).Sum
        if($bytes-gt 960MB){Save-WorkerStatus 'blocked' '1 GiB test-data budget nearly exhausted.';continue}
        $prefix=Join-Path $root ('worker-'+$lastSequence)
        if($command.action-eq 'build') {
            $script=Join-Path $PSScriptRoot 'build_release.ps1'
            $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -DiagnosticMap -RunCacheTests -Jobs 12' -f $script
            $current=@{action='build'}
        } elseif($command.action-eq 'run') {
            if($command.run_name-notmatch '^[a-z0-9-]{1,64}$'){throw 'Invalid benchmark run name.'}
            $runRoot=Join-Path $root $command.run_name
            if(-not(Test-Path -LiteralPath (Join-Path $runRoot 'scene.json'))){throw 'Prepare the scene first.'}
            # The older benchmark baseline exhibited cyclic fire resets and is invalid.
            $exe=Join-Path $projectRoot ('Build\x64-Clang-Release\'+$(if($command.baseline){'shadps4-fire-correct-baseline.exe'}else{'shadps4.exe'}))
            if($command.baseline -and
               (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash-ne
               '3A74A1808D65C0408F11324E6F1929F28A08A558CF7C8449D850ED4FDEB4A4F7') {
                throw 'The correct-fire reference build does not match the recorded baseline.'
            }
            $script=Join-Path $PSScriptRoot 'run_infamous_hk.ps1'
            $mode=if($command.PSObject.Properties['performance'] -and [bool]$command.performance) {
                '-Performance'
            } else {'-PerformanceDiagnostic -LightProfile'}
            $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -EmulatorPath "{1}" -Resolution 1080p {2} -BenchmarkDirectory "{3}"' -f $script,$exe,$mode,$runRoot
            $current=@{action='run';runRoot=$runRoot}
        } else {throw 'Only build, run and stop actions are allowed.'}
        $child=Start-Process -FilePath $psExe -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput ($prefix+'-stdout.txt') -RedirectStandardError ($prefix+'-stderr.txt')
        $null=$child.Handle
        Save-WorkerStatus 'running' $current.action
    }
} finally {
    $finished=$true
    # Normal closing is requested through the engine; original saves are never mounted.
    if($child -and $current.action-eq 'run') {
        & (Join-Path $PSScriptRoot 'infamous_benchmark_command.ps1') -RunDirectory $current.runRoot -Action quit
        $finished=$child.WaitForExit(30000)
    } elseif($child) {
        $finished=$child.HasExited
    }
    if($finished) {
        $child=$null
        Save-WorkerStatus 'stopped' 'Worker ended; no active child process.'
    } else {
        Save-WorkerStatus 'attention' 'Worker ended; child is still finishing.'
    }
}
