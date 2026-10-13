# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Capture the engine's game-only screenshots, without desktop or other-app capture.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
      [Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9-]{1,40}$')][string]$Tag,
      [ValidateRange(8,48)][int]$Frames=32,
      [ValidateRange(400,2000)][int]$IntervalMs=500,
      [switch]$CompressEachFrame)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Build\particle-benchmark'))
$runRoot=Join-Path $root $RunName
$framePath=Join-Path $runRoot 'frames.csv'
$shots=Join-Path $runRoot 'screenshots'
$output=Join-Path $runRoot ($Tag+'-capture.csv')
if(-not(Test-Path -LiteralPath (Join-Path $runRoot 'perf_tuning.ini'))){throw 'No active isolated game.'}
if(Test-Path -LiteralPath $output){throw 'Choose a new capture tag.'}
$used=(Get-ChildItem -LiteralPath $root -Recurse -File | Measure-Object Length -Sum).Sum
# For sequential native 1080p capture: retained PNGs <=4 MiB each, plus room for
# one raw PNG, one verified compression temporary and the bounded game log.
# Leave a further 4 MiB below the authorized 1 GiB directory budget.
$reservation=if($CompressEachFrame){$Frames*4MB+32MB}else{$Frames*8MB}
$ceiling=if($CompressEachFrame){1020MB}else{960MB}
if($used+$reservation-gt$ceiling){throw 'The authorized 1 GiB test-data budget would be exceeded.'}
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
Get-ChildItem -LiteralPath $shots -Filter '*.png' -File|ForEach-Object {[void]$seen.Add($_.FullName)}
$results=[Collections.Generic.List[object]]::new()
$timer=[Diagnostics.Stopwatch]::StartNew()
for($i=0;$i-lt$Frames;$i++) {
    $frame=(Get-Content -LiteralPath $framePath -Tail 1).Split(',')
    $requested=Get-Date
    $null=& (Join-Path $PSScriptRoot 'infamous_benchmark_command.ps1') -RunDirectory $runRoot -Action screenshot
    $deadline=(Get-Date).AddSeconds(4)
    $found=$null
    do {
        Start-Sleep -Milliseconds 40
        $new=@(Get-ChildItem -LiteralPath $shots -Filter '*.png' -File|Where-Object {-not $seen.Contains($_.FullName)})
        if($new.Count) {
            $candidate=$new|Sort-Object LastWriteTime|Select-Object -First 1
            # The PNG pathname exists before its writer closes it. Never open a partial image.
            try {
                $stream=[IO.File]::Open($candidate.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
                try {if($stream.Length-gt1024){$found=$candidate}} finally {$stream.Dispose()}
            } catch [IO.IOException] {}
        }
    } while(-not$found -and (Get-Date)-lt$deadline)
    if(-not$found){throw 'Screenshot timeout; stop rather than fabricate an animation sequence.'}
    if($CompressEachFrame) {
        $null=& 'C:\Users\USER\AppData\Local\Programs\Python\Python312\python.exe' -B (Join-Path $PSScriptRoot 'compress_infamous_captures.py') $RunName --file $found.FullName
        if($LASTEXITCODE-ne0) {throw 'Frame pixel verification failed.'}
        $found.Refresh()
        if($found.Length-gt4MB) {throw 'Frame exceeded the bounded compressed-frame reservation; stop capture.'}
    }
    [void]$seen.Add($found.FullName)
    $results.Add([pscustomobject]@{Index=$i;RequestedAt=$requested.ToString('o');
        Frame=$frame[0];GameElapsedSeconds=([double]$frame[1]/1e9);File=$found.FullName})
    $results|Export-Csv -LiteralPath $output -NoTypeInformation -Encoding UTF8
    $wait=($i+1)*$IntervalMs-$timer.ElapsedMilliseconds
    if($wait-gt0){Start-Sleep -Milliseconds ([int]$wait)}
}
[pscustomobject]@{Run=$RunName;Tag=$Tag;Frames=$results.Count;Seconds=$timer.Elapsed.TotalSeconds;Manifest=$output}|ConvertTo-Json -Compress
