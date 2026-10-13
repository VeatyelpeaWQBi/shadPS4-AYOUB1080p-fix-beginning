# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Read-only GPU context telemetry, separate from emulator counters and frame timing.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
      [ValidateRange(20,1200)][int]$Seconds=180,
      [switch]$ObserveAfterExit)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root=Join-Path $taskRoot 'Build\particle-benchmark'
$run=Join-Path $root $RunName
if(-not(Test-Path -LiteralPath (Join-Path $run 'scene.json'))){throw 'Use a prepared benchmark.'}
$engine=Join-Path $taskRoot 'Build\x64-Clang-Release\shadps4.exe'
$path=Join-Path $run 'gpu-context.jsonl'
$deadline=(Get-Date).AddSeconds($Seconds)
$utf8=[Text.UTF8Encoding]::new($false)
while((Get-Date)-lt$deadline) {
    if((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length-gt1MB) {
        throw 'GPU telemetry reached its 1 MiB bound.'
    }
    $games=@(Get-Process shadps4 -ErrorAction SilentlyContinue | Where-Object Path -eq $engine)
    if($games.Count-gt1){throw 'More than one project engine; comparison is ambiguous.'}
    if($games.Count-eq0 -and -not$ObserveAfterExit){break}
    $gameId=if($games.Count-eq1){$games[0].Id}else{0}
    # Counters of a process that just exited can be invalid. Retain the valid instances of
    # the same sample; do not terminate the observer or interpret invalid data as zero load.
    $sample=Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage' `
        -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
    $rows=@()
    $invalid=0
    $names=@{}
    if($sample) {
        $rows=@(foreach($counter in $sample.CounterSamples) {
            if($counter.Status-ne0){$invalid++;continue}
            if(($counter.CookedValue-gt0.1 -or $counter.InstanceName-like ('pid_'+$gameId+'_*')) -and
               $counter.InstanceName-match '^pid_(\d+)_(.*)_engtype_(.*)$') {
                $processId=[int]$Matches[1];$engineName=$Matches[2];$engineType=$Matches[3]
                if(-not$names.ContainsKey($processId)) {
                    $process=Get-Process -Id $processId -ErrorAction SilentlyContinue
                    $names[$processId]=if($process){$process.ProcessName}else{'exited'}
                }
                [pscustomobject]@{ProcessId=$processId;Name=$names[$processId];Engine=$engineName;Type=$engineType;
                    Percent=[math]::Round($counter.CookedValue,3)}
            }
        })
    }
    $value=[ordered]@{Time=(Get-Date).ToString('o');GameId=$gameId;
        Valid=($null-ne$sample);InvalidInstances=$invalid;Engines=$rows}
    [IO.File]::AppendAllText($path,($value|ConvertTo-Json -Depth 4 -Compress)+[Environment]::NewLine,$utf8)
    Start-Sleep -Milliseconds 500
}
Write-Output 'GPU context observation finished.'
