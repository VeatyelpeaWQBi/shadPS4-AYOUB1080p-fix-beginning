# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RunName,
    [double]$StartSeconds=35,
    [double]$EndSeconds=110
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-z0-9-]{1,64}$'){throw 'Invalid run name.'}
if($EndSeconds -le $StartSeconds){throw 'EndSeconds must exceed StartSeconds.'}
$root=Join-Path (Join-Path $PSScriptRoot '..\Build\particle-benchmark') $RunName
$frames=@(Import-Csv -LiteralPath (Join-Path $root 'frames.csv') | Where-Object {
    [double]$_.elapsed_ns -ge $StartSeconds*1e9 -and
    [double]$_.elapsed_ns -le $EndSeconds*1e9 -and [double]$_.interval_ns -gt 0
})
if($frames.Count -lt 2){throw 'The requested measurement window has no frames yet.'}
$intervals=@($frames | ForEach-Object {[double]$_.interval_ns/1e6} | Sort-Object)
$duration=($frames | Measure-Object interval_ns -Sum).Sum/1e9
[pscustomobject]@{
    Run=$RunName; StartSeconds=$StartSeconds; EndSeconds=$EndSeconds
    Frames=$frames.Count; MeasuredSeconds=[Math]::Round($duration,3)
    FPS=[Math]::Round($frames.Count/$duration,3)
    MeanMs=[Math]::Round($duration*1000/$frames.Count,3)
    P95Ms=[Math]::Round($intervals[[Math]::Ceiling($intervals.Count*0.95)-1],3)
    MaxMs=[Math]::Round($intervals[-1],3)
}
