# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunName, [string]$ThreadName='GpuCommandProcessor', [int]$Last=45,
      [string]$MapPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($RunName -notmatch '^[a-z0-9-]{1,64}$'){throw 'Invalid run name.'}
$root=Join-Path (Join-Path $PSScriptRoot '..\Build\particle-benchmark') $RunName
$symbols=@{}
# Match function starts exactly. Nearest preceding symbols are unreliable for folded code,
# private symbols and exception funclets. The caller must keep the map from this exact build.
if(-not $MapPath) {$MapPath=Join-Path $root 'compiled.map'}
foreach($line in [IO.File]::ReadLines($MapPath)) {
    if($line -match '^\s*0001:[0-9a-fA-F]+\s+(\S+)\s+([0-9a-fA-F]{16})\s+') {
        $address=[Convert]::ToUInt64($Matches[2],16)-[Convert]::ToUInt64('0000700000000000',16)
        $key=$address.ToString('x')
        if(-not $symbols.ContainsKey($key)){$symbols[$key]=$Matches[1]}
    }
}
$pattern='Perf (inclusive|profile|hot|path) \[shadPS4:'+ [regex]::Escape($ThreadName) +'\]'
$lines=@(Get-Content -LiteralPath (Join-Path $root 'log\CUSA00309.log') | Where-Object {$_ -match $pattern} | Select-Object -Last $Last)
foreach($line in $lines) {
    foreach($match in [regex]::Matches($line,'shadps4\.exe\+0x([0-9a-f]+)')) {
        $key=$match.Groups[1].Value.TrimStart('0')
        if($symbols.ContainsKey($key)) {
            $name=$symbols[$key]
            if($name.Length -gt 140){$name=$name.Substring(0,140)+'...'}
            $line=$line.Replace($match.Value,$match.Value+' '+$name)
        }
    }
    $line
}
