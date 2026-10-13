# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][ValidateSet('button','axis','screenshot','quit','status')][string]$Action,
    [ValidateSet('cross','circle','options','up','down','left','right','square','triangle')][string]$Button='cross',
    [ValidateRange(50,2000)][int]$DurationMs=200,
    [ValidateRange(0,3)][int]$Axis=2,
    [ValidateRange(0,255)][int]$Value=128
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$benchmarkRoot = Join-Path $projectRoot 'Build\particle-benchmark'
$runRoot = [IO.Path]::GetFullPath($RunDirectory)
if (-not $runRoot.StartsWith($benchmarkRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath (Join-Path $runRoot 'scene.json'))) {
    throw 'Only a prepared project benchmark directory is allowed.'
}
$path = Join-Path $runRoot 'command.json'
$sequence = 1L
if (Test-Path -LiteralPath $path) { $sequence = [long](Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).sequence + 1 }
$command = [ordered]@{sequence=$sequence;action=$Action}
if ($Action-eq 'button') {$command.button=$Button;$command.duration_ms=$DurationMs}
if ($Action-eq 'axis') {$command.axis=$Axis;$command.value=$Value}
[IO.File]::WriteAllText($path,($command|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output ('Command {0}: {1}' -f $sequence,$Action)
