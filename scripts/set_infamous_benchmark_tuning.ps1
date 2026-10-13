# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunName,
      [Parameter(Mandatory=$true)][string[]]$Values)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-z0-9-]{1,64}$'){throw 'Invalid run name.'}
foreach($value in $Values){if($value -notmatch '^[a-z_]+\s*=\s*[a-zA-Z0-9_,. -]+$'){throw 'Invalid tuning value.'}}
$root=Join-Path (Join-Path $PSScriptRoot '..\Build\particle-benchmark') $RunName
$path=Join-Path $root 'perf_tuning.ini'
if(-not(Test-Path -LiteralPath $path)){throw 'The isolated game configuration is not active.'}
$last=Get-Content -LiteralPath (Join-Path $root 'frames.csv') -Tail 1
$fields=$last.Split(',')
$event=[ordered]@{time=(Get-Date).ToString('o');frame=$fields[0];elapsed_ns=$fields[1];values=$Values}
Add-Content -LiteralPath (Join-Path $root 'tuning-switches.jsonl') -Value ($event|ConvertTo-Json -Compress) -Encoding utf8
Add-Content -LiteralPath $path -Value ("`n"+($Values -join "`n"))
Copy-Item -LiteralPath $path -Destination (Join-Path $root 'tuning-applied.ini') -Force
$event|ConvertTo-Json -Compress
