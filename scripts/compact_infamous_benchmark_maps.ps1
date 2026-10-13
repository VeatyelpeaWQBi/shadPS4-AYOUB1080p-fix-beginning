# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Losslessly compact only generated benchmark linker maps, verifying before removing originals.
[CmdletBinding()]
param([switch]$IncludeLogs, [switch]$IncludeFrames)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\Build\particle-benchmark'))
$records=[Collections.Generic.List[object]]::new()
$recordPath=Join-Path $root 'map-archives.json'
$activeRun=$null
$statusPath=Join-Path $root 'worker-status.json'
$commandPath=Join-Path $root 'worker-command.json'
if((Test-Path -LiteralPath $statusPath) -and (Test-Path -LiteralPath $commandPath)) {
    $status=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json
    $command=Get-Content -LiteralPath $commandPath -Raw|ConvertFrom-Json
    if($status.State-eq'running' -and $command.action-eq'run') {
        $activeRun=[IO.Path]::GetFullPath((Join-Path $root $command.run_name))
    }
}
if(Test-Path -LiteralPath $recordPath) {
    $previous=Get-Content -LiteralPath $recordPath -Raw|ConvertFrom-Json
    foreach($record in $previous) {if($record){$records.Add($record)}}
}
foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.Extension-eq'.map' -or ($IncludeLogs -and $_.Extension-eq'.log' -and $_.Length-gt512KB) -or
    ($IncludeFrames -and $_.Name-eq'frames.csv' -and $_.Length-gt128KB -and
     $_.DirectoryName-ne$activeRun)
}) {
    $path=[IO.Path]::GetFullPath($file.FullName)
    if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Invalid map path.'}
    $archive=$path+'.zip'
    if(Test-Path -LiteralPath $archive) {continue}
    $originalHash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $output=[IO.File]::Open($archive,[IO.FileMode]::CreateNew)
    try {
        $zip=[IO.Compression.ZipArchive]::new($output,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            $entry=$zip.CreateEntry($file.Name,[IO.Compression.CompressionLevel]::Optimal)
            $target=$entry.Open()
            $source=[IO.File]::OpenRead($path)
            try {$source.CopyTo($target)} finally {$source.Dispose();$target.Dispose()}
        } finally {$zip.Dispose()}
    } finally {$output.Dispose()}
    $input=[IO.File]::OpenRead($archive)
    try {
        $zip=[IO.Compression.ZipArchive]::new($input,[IO.Compression.ZipArchiveMode]::Read,$true)
        try {
            $entry=$zip.GetEntry($file.Name)
            if($zip.Entries.Count-ne1 -or $entry.Length-ne$file.Length) {throw 'Archive length mismatch.'}
            $stream=$entry.Open()
            $sha=[Security.Cryptography.SHA256]::Create()
            try {$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}
            finally {$stream.Dispose();$sha.Dispose()}
            if($hash-ne$originalHash) {throw 'Archive checksum mismatch; source retained.'}
        } finally {$zip.Dispose()}
    } finally {$input.Dispose()}
    $records.Add([pscustomobject]@{Source=$path;Archive=$archive;SHA256=$originalHash;
        OriginalBytes=$file.Length;ArchiveBytes=(Get-Item -LiteralPath $archive).Length})
    # Only this absolute, verified, generated map is removed. No directory deletion.
    Remove-Item -LiteralPath $path
}
$records|ConvertTo-Json -Depth 3|Set-Content -LiteralPath $recordPath -Encoding utf8
$records|Select-Object Source,OriginalBytes,ArchiveBytes|ConvertTo-Json -Compress
