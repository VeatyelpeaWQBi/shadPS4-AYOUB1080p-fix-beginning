# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
      [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,40}$')][string]$Tag)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Build\particle-benchmark'))
$run=Join-Path $root $RunName
$phases=Get-Content -LiteralPath (Join-Path $run ($Tag+'-comparison.json')) -Raw|ConvertFrom-Json
$samples=@(Get-Content -LiteralPath (Join-Path $run 'gpu-context.jsonl')|ForEach-Object {$_|ConvertFrom-Json})
$results=@(foreach($phase in $phases) {
    if(-not$phase.PSObject.Properties['StartTime']) {throw 'Comparison has no wall-clock timing.'}
    $start=[DateTimeOffset]::Parse($phase.StartTime).AddSeconds(2)
    $end=[DateTimeOffset]::Parse($phase.EndTime)
    $total=[Collections.Generic.List[double]]::new()
    $apps=[Collections.Generic.List[double]]::new()
    $unresolved=0
    foreach($sample in $samples) {
        $time=[DateTimeOffset]::Parse($sample.Time)
        if($time-lt$start -or $time-gt$end -or -not$sample.Valid -or $sample.InvalidInstances-ne0) {continue}
        $game=@($sample.Engines|Where-Object {$_.ProcessId-eq$sample.GameId -and $_.Type-eq'3d'}|
                    Sort-Object Percent -Descending)
        if(-not$game.Count){continue}
        $domain=$game[0].Engine-replace'_eng_\d+$',''
        $other=@($sample.Engines|Where-Object {$_.ProcessId-ne$sample.GameId -and $_.Type-eq'3d' -and
                 $_.Engine.StartsWith($domain)})
        $sum=0.0
        foreach($row in $other){$sum+=[double]$row.Percent}
        $total.Add($sum)
        $missing=@($other|Where-Object {-not$_.PSObject.Properties['Name'] -or $_.Name-eq'exited'})
        if($missing.Count) {$unresolved++;continue}
        $sum=0.0
        foreach($row in $other){if($row.Name-ne'dwm'){$sum+=[double]$row.Percent}}
        $apps.Add($sum)
    }
    [pscustomobject]@{Phase=$phase.Phase;FPS=$phase.FPS;Samples=$total.Count;
        Other3DMean=if($total.Count){[math]::Round(($total|Measure-Object -Average).Average,3)}else{$null};
        Other3DMax=if($total.Count){[math]::Round(($total|Measure-Object -Maximum).Maximum,3)}else{$null};
        OtherApp3DMean=if($apps.Count){[math]::Round(($apps|Measure-Object -Average).Average,3)}else{$null};
        OtherApp3DMax=if($apps.Count){[math]::Round(($apps|Measure-Object -Maximum).Maximum,3)}else{$null};
        UnresolvedNameSamples=$unresolved}
})
$results|ConvertTo-Json -Depth 3
