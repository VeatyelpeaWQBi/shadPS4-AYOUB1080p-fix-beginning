# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
      [ValidateRange(20,90)][int]$Seconds=45,
      [int[]]$WindowsKb=@(512,256,128,64,512))
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$run=Join-Path $PSScriptRoot ('..\Build\particle-benchmark\'+$RunName)
$results=[Collections.Generic.List[object]]::new()
function Elapsed {return [double]((Get-Content -LiteralPath (Join-Path $run 'frames.csv') -Tail 1).Split(',')[1])/1e9}
try {
    $null=& (Join-Path $PSScriptRoot 'set_infamous_benchmark_tuning.ps1') -RunName $RunName -Values @(
        'gpu_profile = 0','profile_stacks = 0','perf_log = 1')
    foreach($window in $WindowsKb) {
        if($window-lt64 -or $window-gt1024 -or ($window-band($window-1))-ne0) {throw 'Invalid window.'}
        $null=& (Join-Path $PSScriptRoot 'set_infamous_benchmark_tuning.ps1') -RunName $RunName -Values @('readback_window_kb = '+$window)
        Start-Sleep -Seconds 8
        $start=Elapsed
        $deadline=(Get-Date).AddSeconds($Seconds)
        while((Get-Date)-lt$deadline) {
            if(-not(Test-Path -LiteralPath (Join-Path $run 'perf_tuning.ini'))) {throw 'Game stopped.'}
            Start-Sleep -Milliseconds 250
        }
        $end=Elapsed
        if($end-$start-lt$Seconds-3) {throw 'Frames stopped advancing.'}
        $summary=& (Join-Path $PSScriptRoot 'summarize_infamous_benchmark.ps1') -RunName $RunName -StartSeconds $start -EndSeconds $end
        $summary|Add-Member -NotePropertyName WindowKb -NotePropertyValue $window
        $results.Add($summary)
        [IO.File]::WriteAllText((Join-Path $run 'window-comparison.json'),($results|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
        $summary|ConvertTo-Json -Compress
    }
} finally {
    if(Test-Path -LiteralPath (Join-Path $run 'perf_tuning.ini')) {
        $null=& (Join-Path $PSScriptRoot 'set_infamous_benchmark_tuning.ps1') -RunName $RunName -Values @('readback_window_kb = 512')
    }
}
