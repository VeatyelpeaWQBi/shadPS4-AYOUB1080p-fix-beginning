# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Read-only Windows CPU-set metadata; uses the installed PowerShell runtime.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not('InfamousCpuSetQuery' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class InfamousCpuSetQuery {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetSystemCpuSetInformation(IntPtr data, uint size,
        out uint needed, IntPtr process, uint flags);
}
'@
}
[uint32]$needed=0
$null=[InfamousCpuSetQuery]::GetSystemCpuSetInformation([IntPtr]::Zero,0,[ref]$needed,[IntPtr]::Zero,0)
if($needed-eq0 -or $needed-gt1MB){throw 'CPU-set metadata unavailable.'}
$data=[Runtime.InteropServices.Marshal]::AllocHGlobal([int]$needed)
try {
    if(-not[InfamousCpuSetQuery]::GetSystemCpuSetInformation($data,$needed,[ref]$needed,[IntPtr]::Zero,0)) {
        throw 'Could not read CPU-set metadata.'
    }
    $rows=@(for($offset=0;$offset+8-le$needed;) {
        $entry=[IntPtr]::Add($data,$offset)
        $size=[Runtime.InteropServices.Marshal]::ReadInt32($entry,0)
        $kind=[Runtime.InteropServices.Marshal]::ReadInt32($entry,4)
        if($size-lt8 -or $size-gt$needed-$offset){throw 'Invalid CPU-set record.'}
        if($kind-eq0 -and $size-ge32) {
            [pscustomobject]@{
                Group=[Runtime.InteropServices.Marshal]::ReadInt16($entry,12)
                Logical=[Runtime.InteropServices.Marshal]::ReadByte($entry,14)
                Core=[Runtime.InteropServices.Marshal]::ReadByte($entry,15)
                Efficiency=[Runtime.InteropServices.Marshal]::ReadByte($entry,18)
                Flags=[Runtime.InteropServices.Marshal]::ReadByte($entry,19)
                SchedulingClass=[Runtime.InteropServices.Marshal]::ReadByte($entry,20)
            }
        }
        $offset+=$size
    })
    $rows|ConvertTo-Json
} finally {[Runtime.InteropServices.Marshal]::FreeHGlobal($data)}
