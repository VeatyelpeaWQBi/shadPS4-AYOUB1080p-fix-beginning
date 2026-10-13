# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Fixed scene comparisons. Measures before screenshot capture so capture stalls are excluded.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
      [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,40}$')][string]$Tag,
      [Parameter(Mandatory)][string]$PhasesPath,
      [ValidateRange(20,90)][int]$Seconds=45,
      [ValidateRange(0,60)][int]$WarmupSeconds=35,
      [switch]$NoCounters,
      [switch]$ConfirmTuning)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Build\particle-benchmark'))
$run=Join-Path $root $RunName
$path=[IO.Path]::GetFullPath($PhasesPath)
if(-not $path.StartsWith($run+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Keep phases in this prepared benchmark.'}
$phases=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
if(@($phases).Count-gt12) {throw 'At most twelve bounded phases.'}
$results=[Collections.Generic.List[object]]::new()
$originalProcessMask=$null
function Elapsed {return [double]((Get-Content -LiteralPath (Join-Path $run 'frames.csv') -Tail 1).Split(',')[1])/1e9}
$warmDeadline=(Get-Date).AddSeconds(90)
do {
    Start-Sleep -Milliseconds 250
    $ready=$false
    if(Test-Path -LiteralPath (Join-Path $run 'frames.csv')) {
        try {$ready=(Elapsed)-ge$WarmupSeconds}catch {}
    }
} while(-not$ready -and (Get-Date)-lt$warmDeadline)
if(-not$ready) {throw 'Scene did not start or warm up within 90 seconds.'}
$null=& (Join-Path $PSScriptRoot 'set_infamous_benchmark_tuning.ps1') -RunName $RunName -Values @(
    'gpu_profile = 0','profile_stacks = 0',('perf_log = '+$(if($NoCounters){'0'}else{'1'})))
foreach($phase in $phases) {
    if($phase.name-isnot[string] -or $phase.name-notmatch '^[a-z0-9-]{1,40}$') {throw 'Invalid phase name.'}
    $null=& (Join-Path $PSScriptRoot 'set_infamous_benchmark_tuning.ps1') -RunName $RunName -Values @($phase.values)
    Start-Sleep -Seconds 8
    $status=$null
    if($ConfirmTuning) {
        $null=& (Join-Path $PSScriptRoot 'infamous_benchmark_command.ps1') -RunDirectory $run -Action status
        $expected=(Get-Content -LiteralPath (Join-Path $run 'command.json') -Raw|ConvertFrom-Json).sequence
        $deadline=(Get-Date).AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 100
            try {$status=Get-Content -LiteralPath (Join-Path $run 'status.json') -Raw|ConvertFrom-Json}catch {$status=$null}
        } while(( -not $status -or $status.sequence-ne$expected) -and (Get-Date)-lt$deadline)
        if(-not $status -or $status.sequence-ne$expected -or $status.game_serial-ne'CUSA00309') {throw 'Engine did not confirm the applied settings.'}
        foreach($setting in $phase.values) {
            $parts=$setting.Split('=');$key=$parts[0].Trim();$value=$parts[1].Trim()
            if($key-eq'cpu_affinity') {$wanted=[Convert]::ToUInt64($value,16)}
            elseif($key-in@('gpu_threads_affinity','other_threads_affinity')) {
                $wanted=if($value-eq'auto'){$value}else{[Convert]::ToUInt64($value,16)}
            }
            elseif($key-in@('asc_queue','readback_prefetch')) {$wanted=$value-ne'0'}
            elseif($key-in@('readback_window_kb','recorder_spin_us')) {$wanted=[long]$value}
            else {continue}
            if($status.$key-ne$wanted) {throw ('Engine setting mismatch: '+$key)}
            if($key-eq'cpu_affinity' -and $status.PSObject.Properties['process_affinity']) {
                if($wanted-eq0) {
                    if($null-eq$originalProcessMask){$originalProcessMask=$status.process_affinity}
                    elseif($status.process_affinity-ne$originalProcessMask){throw 'Original process affinity was not restored.'}
                } elseif($status.process_affinity-ne$wanted) {throw 'OS process affinity did not match the requested mask.'}
            }
        }
        if($NoCounters -and $status.perf_log) {throw 'Counters are active during a final performance comparison.'}
    }
    $start=Elapsed
    $startTime=(Get-Date).ToString('o')
    $deadline=(Get-Date).AddSeconds($Seconds)
    while((Get-Date)-lt$deadline) {
        if(-not(Test-Path -LiteralPath (Join-Path $run 'perf_tuning.ini'))) {throw 'Game stopped.'}
        Start-Sleep -Milliseconds 250
    }
    $end=Elapsed
    $endTime=(Get-Date).ToString('o')
    if($end-$start-lt$Seconds-3) {throw 'Frames stopped advancing.'}
    $summary=& (Join-Path $PSScriptRoot 'summarize_infamous_benchmark.ps1') -RunName $RunName -StartSeconds $start -EndSeconds $end
    $summary|Add-Member -NotePropertyName Phase -NotePropertyValue $phase.name
    $summary|Add-Member -NotePropertyName StartTime -NotePropertyValue $startTime
    $summary|Add-Member -NotePropertyName EndTime -NotePropertyValue $endTime
    $summary|Add-Member -NotePropertyName Values -NotePropertyValue @($phase.values)
    if($status){$summary|Add-Member -NotePropertyName EngineStatus -NotePropertyValue $status}
    $results.Add($summary)
    [IO.File]::WriteAllText((Join-Path $run ($Tag+'-comparison.json')),($results|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    $summary|ConvertTo-Json -Compress
}
