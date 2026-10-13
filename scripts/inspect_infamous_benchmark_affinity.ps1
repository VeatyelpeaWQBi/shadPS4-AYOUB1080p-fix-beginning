# SPDX-FileCopyrightText: Copyright 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$RunName)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runRoot=Join-Path $projectRoot ('Build\particle-benchmark\'+$RunName)
if(-not(Test-Path -LiteralPath (Join-Path $runRoot 'scene.json'))){throw 'Missing isolated scene.'}
if(-not('BenchmarkThreadQuery' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BenchmarkThreadQuery {
    [StructLayout(LayoutKind.Sequential)]
    public struct BasicInfo {
        public int ExitStatus;
        public IntPtr Teb;
        public IntPtr ProcessId;
        public IntPtr ThreadId;
        public UIntPtr Affinity;
        public int Priority;
        public int BasePriority;
    }
    [DllImport("kernel32.dll")] public static extern IntPtr OpenThread(uint access, bool inherit, uint id);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] public static extern int GetThreadPriority(IntPtr handle);
    [DllImport("kernel32.dll")] public static extern int GetThreadDescription(IntPtr handle, out IntPtr description);
    [DllImport("kernel32.dll")] public static extern IntPtr LocalFree(IntPtr memory);
    [DllImport("ntdll.dll")] public static extern int NtQueryInformationThread(IntPtr handle, int kind,
        out BasicInfo information, int bytes, IntPtr returned);
}
'@
}
$games=@(Get-Process shadps4 -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -eq (Join-Path $projectRoot 'Build\x64-Clang-Release\shadps4.exe')
})
if($games.Count-ne1){throw 'Expected one project benchmark engine.'}
$game=$games[0]
$threads=@(foreach($thread in $game.Threads) {
    $handle=[BenchmarkThreadQuery]::OpenThread(0x840,$false,[uint32]$thread.Id)
    if($handle-eq[IntPtr]::Zero){continue}
    try {
        $info=New-Object BenchmarkThreadQuery+BasicInfo
        $status=[BenchmarkThreadQuery]::NtQueryInformationThread($handle,0,[ref]$info,
            [Runtime.InteropServices.Marshal]::SizeOf($info),[IntPtr]::Zero)
        $description=[IntPtr]::Zero
        $null=[BenchmarkThreadQuery]::GetThreadDescription($handle,[ref]$description)
        $name=''
        if($description-ne[IntPtr]::Zero) {
            $name=[Runtime.InteropServices.Marshal]::PtrToStringUni($description)
            $null=[BenchmarkThreadQuery]::LocalFree($description)
        }
        [pscustomobject]@{Id=$thread.Id;Name=$name;Status=$status;
            Affinity=if($status-eq0){'{0:x}' -f $info.Affinity.ToUInt64()}else{'unavailable'};
            Priority=[BenchmarkThreadQuery]::GetThreadPriority($handle)}
    } finally {$null=[BenchmarkThreadQuery]::CloseHandle($handle)}
})
$result=[ordered]@{Time=(Get-Date).ToString('o');ProcessId=$game.Id;
    ProcessAffinity=('{0:x}' -f $game.ProcessorAffinity.ToInt64());Threads=$threads}
$json=$result|ConvertTo-Json -Depth 4
Add-Content -LiteralPath (Join-Path $runRoot 'affinity-observations.jsonl') -Value ($result|ConvertTo-Json -Depth 4 -Compress) -Encoding utf8
$json
