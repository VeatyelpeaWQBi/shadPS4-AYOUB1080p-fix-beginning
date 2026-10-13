# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName,
    [ValidateSet('car', 'selection')][string]$Scene = 'car'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$benchmarkRoot = Join-Path $projectRoot 'Build\particle-benchmark'
$runRoot = [IO.Path]::GetFullPath((Join-Path $benchmarkRoot $RunName))
if (-not $runRoot.StartsWith($benchmarkRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Benchmark path is outside the project test directory.'
}
if (Test-Path -LiteralPath $runRoot) { throw 'Use a new RunName; previous measurements are retained.' }
$saveRoot = Join-Path $env:APPDATA 'shadPS4\home\1000\savedata\CUSA00309'
$source = Join-Path $saveRoot $(if ($Scene -eq 'car') {'in car accident'} else {'in selection'})
$slots = @('infamousssAuto0', 'infamousssAuto1')
foreach ($slot in $slots) {
    if (-not (Test-Path -LiteralPath (Join-Path $source ($slot + '\dis.dat')) -PathType Leaf)) {
        throw "Missing backed-up save: $slot"
    }
}
$existingBytes = 0L
if (Test-Path -LiteralPath $benchmarkRoot) {
    $measure = Get-ChildItem -LiteralPath $benchmarkRoot -Recurse -File | Measure-Object Length -Sum
    if ($measure.Sum) { $existingBytes = [long]$measure.Sum }
}
if ($existingBytes -gt 960MB) { throw 'The 1 GiB test-data budget is nearly exhausted.' }
$destination = Join-Path $runRoot 'home\1000\savedata\CUSA00309'
$null = [IO.Directory]::CreateDirectory($destination)
foreach ($slot in $slots) {
    Copy-Item -LiteralPath (Join-Path $source $slot) -Destination $destination -Recurse
}
# A single recoverable progress snapshot; the original home is never mounted for test writes.
$progressBackup = Join-Path $benchmarkRoot 'current-progress'
if (-not (Test-Path -LiteralPath $progressBackup)) {
    $null = [IO.Directory]::CreateDirectory($progressBackup)
    foreach ($slot in @('infamousssAuto0','infamousssAuto1','infamousssUser0')) {
        $path = Join-Path $saveRoot $slot
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $progressBackup -Recurse }
    }
}
$manifest = [ordered]@{
    RunName = $RunName; Scene = $Scene; Source = $source; RunDirectory = $runRoot
    PreparedAt = (Get-Date).ToString('o'); ActiveSavesTouched = $false
    SaveFiles = @(Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
        [ordered]@{Path=$_.FullName.Substring($source.Length+1);Bytes=$_.Length;
                   Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
}
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $runRoot 'scene.json'), ($manifest|ConvertTo-Json -Depth 5), $utf8)
Write-Output $runRoot
