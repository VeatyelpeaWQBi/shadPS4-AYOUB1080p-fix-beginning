# SPDX-FileCopyrightText: 2026 shadPS4-AYOUB1080p contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Windows PowerShell 5.1 and PowerShell 7. Uses installed tools and existing dependencies only.
[CmdletBinding()]
param(
    [ValidateRange(1, 128)]
    [int]$Jobs = [Math]::Min(12, [Environment]::ProcessorCount),
    [switch]$RunCacheTests,
    [switch]$DiagnosticMap,
    [switch]$CheckEnvironment,
    [string]$VisualStudioPath,
    [string]$CMakePath,
    [string]$NinjaPath,
    [string]$ClangPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$buildDirectory = Join-Path $projectRoot 'Build\x64-Clang-Release'
$cache = @{}
$exitCode = 1
$timer = [Diagnostics.Stopwatch]::StartNew()

function Resolve-InstalledTool {
    param([string]$Name, [string]$Explicit, [string]$Configured, [string[]]$Candidates = @())
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) {
            throw "Specified tool does not exist: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }
    if ($Configured -and (Test-Path -LiteralPath $Configured -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $Configured).Path
    }
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { return $command.Source }
    # A desktop-launched shell can have an older PATH than the user/system settings.
    foreach ($scope in @('User', 'Machine')) {
        foreach ($directory in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            $directory = [Environment]::ExpandEnvironmentVariables($directory.Trim().Trim('"'))
            if (-not $directory) { continue }
            $candidate = Join-Path $directory $Name
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Cannot locate installed $Name. Supply its path or configure your existing tools. No tools were downloaded."
}

function Get-VisualStudioRoot {
    if ($VisualStudioPath) { return [IO.Path]::GetFullPath($VisualStudioPath) }
    foreach ($compiler in @($ClangPath, $cache['CMAKE_CXX_COMPILER'])) {
        if ($compiler -and $compiler -match '^(.*)[\\/]VC[\\/]Tools[\\/]Llvm[\\/]') {
            $candidate = $Matches[1]
            if (Test-Path -LiteralPath (Join-Path $candidate 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')) {
                return $candidate
            }
        }
    }
    if ($env:VSINSTALLDIR -and
        (Test-Path -LiteralPath (Join-Path $env:VSINSTALLDIR 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'))) {
        return $env:VSINSTALLDIR
    }
    $vswhere = Resolve-InstalledTool -Name 'vswhere.exe' -Candidates @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe')
    )
    $installation = @(& $vswhere -latest -products '*' `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
    if ($LASTEXITCODE -ne 0 -or $installation.Count -eq 0) {
        throw 'Cannot locate an existing Visual Studio C++ installation. Supply -VisualStudioPath.'
    }
    return $installation[0].Trim()
}

function Invoke-LoggedCommand {
    param([string]$Executable, [string[]]$Arguments, [string]$LogPath)
    # PS 5.1 can turn native stderr warnings into terminating errors with Stop.
    # Classify native success using the actual exit code; retain both streams in the log.
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Executable @Arguments 2>&1 | ForEach-Object { $_.ToString() } |
            Tee-Object -FilePath $LogPath -ErrorAction Stop
        $nativeCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($nativeCode -ne 0) {
        $script:exitCode = $nativeCode
        throw "Command failed with exit code $nativeCode. Log: $LogPath"
    }
}

Push-Location -LiteralPath $projectRoot
try {
    if ($env:OS -ne 'Windows_NT') { throw 'This build entry point requires Windows.' }
    $cacheFile = Join-Path $buildDirectory 'CMakeCache.txt'
    if (Test-Path -LiteralPath $cacheFile -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $cacheFile) {
            if ($line -match '^(CMAKE_(COMMAND|MAKE_PROGRAM|CXX_COMPILER|C_COMPILER|RC_COMPILER|HOME_DIRECTORY|GENERATOR|BUILD_TYPE)):[^=]+=(.*)$') {
                $cache[$Matches[1]] = $Matches[3]
            }
        }
        if ($cache['CMAKE_HOME_DIRECTORY'] -and
            [IO.Path]::GetFullPath($cache['CMAKE_HOME_DIRECTORY']) -ne $projectRoot) {
            throw 'The existing build directory belongs to another source path. Move it aside manually before building.'
        }
        if ($cache['CMAKE_GENERATOR'] -and $cache['CMAKE_GENERATOR'] -ne 'Ninja') {
            throw 'The existing Release directory uses a different generator. Move it aside manually; it will not be deleted.'
        }
    }

    $vsRoot = Get-VisualStudioRoot
    $devShell = Join-Path $vsRoot 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
    if (-not (Test-Path -LiteralPath $devShell -PathType Leaf)) {
        throw "Visual Studio development shell is missing: $devShell"
    }
    Import-Module -Name $devShell
    Enter-VsDevShell -VsInstallPath $vsRoot -SkipAutomaticLocation `
        -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null

    $clang = Resolve-InstalledTool -Name 'clang-cl.exe' -Explicit $ClangPath `
        -Configured $cache['CMAKE_CXX_COMPILER'] -Candidates @(
            (Join-Path $vsRoot 'VC\Tools\Llvm\x64\bin\clang-cl.exe')
        )
    $llvmDirectory = Split-Path -Parent $clang
    $rc = Resolve-InstalledTool -Name 'llvm-rc.exe' -Configured $cache['CMAKE_RC_COMPILER'] `
        -Candidates @((Join-Path $llvmDirectory 'llvm-rc.exe'))
    $cmake = Resolve-InstalledTool -Name 'cmake.exe' -Explicit $CMakePath `
        -Configured $cache['CMAKE_COMMAND'] -Candidates @(
            'C:\msys64\clang64\bin\cmake.exe',
            (Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe')
        )
    $ninja = Resolve-InstalledTool -Name 'ninja.exe' -Explicit $NinjaPath `
        -Configured $cache['CMAKE_MAKE_PROGRAM'] -Candidates @(
            (Join-Path (Split-Path -Parent $cmake) 'ninja.exe'),
            'C:\msys64\clang64\bin\ninja.exe',
            (Join-Path $vsRoot 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe')
        )
    $git = Resolve-InstalledTool -Name 'git.exe'
    $env:PATH = $llvmDirectory + ';' + $env:PATH
    $gitRoot = Split-Path -Parent (Split-Path -Parent $git)
    $gitUtilities = Join-Path $gitRoot 'usr\bin'
    if (Test-Path -LiteralPath $gitUtilities -PathType Container) {
        $env:PATH += ';' + $gitUtilities
    }

    $modules = @(& $git -C $projectRoot submodule status --recursive)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the dependency submodule status.' }
    # Match the platform gates in externals/CMakeLists.txt: date/epoll-shim
    # are Apple/FreeBSD-only; the bundled Vulkan loader/driver are Apple-only.
    # Also exclude descendants if those optional submodules have been initialized.
    $nonWindowsModules = @(
        'externals/date', 'externals/epoll-shim',
        'externals/mesa-kosmickrisp', 'externals/vulkan-loader'
    )
    $unavailable = @($modules | Where-Object {
        if ($_ -notmatch '^[-U][0-9a-f]+\s+(?<modulePath>\S+)') { return $false }
        $modulePath = $Matches['modulePath'].Replace('\', '/')
        foreach ($excluded in $nonWindowsModules) {
            if ($modulePath -eq $excluded -or
                $modulePath.StartsWith($excluded + '/', [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
        }
        return $true
    })
    if ($unavailable.Count -ne 0) {
        throw ("Windows build dependencies are missing or conflicted. Initialize them manually before building:`n" +
            ($unavailable -join "`n"))
    }
    $ffmpegRoot = Join-Path $projectRoot 'externals\ffmpeg-core'
    $sha = @(& $git -C $ffmpegRoot rev-parse --short HEAD)
    if ($LASTEXITCODE -ne 0 -or $sha.Count -ne 1) { throw 'Cannot identify the existing FFmpeg dependency.' }
    $ffmpegDirectory = Join-Path $buildDirectory ('externals\ffmpeg-' + $sha[0].Trim())
    $ffmpegArchive = $ffmpegDirectory + '.zip'
    if (-not (Test-Path -LiteralPath $ffmpegArchive -PathType Leaf) -or
        (Get-Item -LiteralPath $ffmpegArchive).Length -eq 0) {
        throw "Required pre-downloaded FFmpeg archive is missing: $ffmpegArchive. Stopped before CMake could download it."
    }
    foreach ($library in @('avformat', 'avcodec', 'swscale', 'avutil', 'avfilter', 'swresample')) {
        $file = Join-Path $ffmpegDirectory "lib\$library.lib"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Existing FFmpeg library is missing: $file. Prepare the dependency manually; this script does not install dependencies."
        }
    }

    Write-Host "Source: $projectRoot"
    Write-Host "Visual Studio: $vsRoot"
    Write-Host "Compiler: $clang"
    Write-Host "CMake: $cmake"
    Write-Host "Ninja: $ninja"
    Write-Host "Release output: $buildDirectory"
    if ($CheckEnvironment) {
        Write-Host '[OK] Existing tools and dependencies located. No build was started.' -ForegroundColor Green
        $exitCode = 0
    } else {
        Write-Host "Incremental Release build, $Jobs parallel jobs. Existing build files and logs will be updated."
        Write-Host 'No dependency downloads, clean operation, game launch or launcher EXE replacement.'
        $null = [IO.Directory]::CreateDirectory($buildDirectory)
        $configureArguments = @(
            '--preset', 'x64-Clang-Release',
            ('-DCMAKE_C_COMPILER=' + $clang.Replace('\', '/')),
            ('-DCMAKE_CXX_COMPILER=' + $clang.Replace('\', '/')),
            ('-DCMAKE_RC_COMPILER=' + $rc.Replace('\', '/')),
            ('-DCMAKE_MAKE_PROGRAM=' + $ninja.Replace('\', '/')),
            ('-DFETCHCONTENT_SOURCE_DIR_FMT=' + (Join-Path $projectRoot 'externals\fmt').Replace('\', '/')),
            '-DENABLE_TESTS=OFF', '-DCMAKE_TLS_VERIFY=ON', '-DFETCHCONTENT_FULLY_DISCONNECTED=ON'
        )
        if ($DiagnosticMap) { $configureArguments += '-DSHADPS4_DIAGNOSTIC_MAP=ON' }
        Invoke-LoggedCommand $cmake $configureArguments (Join-Path $buildDirectory 'configure-release.log')
        Invoke-LoggedCommand $cmake @('--build', $buildDirectory, '--target', 'shadps4', '--parallel', "$Jobs") `
            (Join-Path $buildDirectory 'build-release.log')
        $exe = Join-Path $buildDirectory 'shadps4.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Build returned success but EXE is missing: $exe" }

        if ($RunCacheTests) {
            $ctest = Resolve-InstalledTool -Name 'ctest.exe' `
                -Candidates @((Join-Path (Split-Path -Parent $cmake) 'ctest.exe'))
            $testDirectory = Join-Path $projectRoot 'Build\cache-runtime-test'
            $null = [IO.Directory]::CreateDirectory($testDirectory)
            Invoke-LoggedCommand $cmake @(
                '-S', (Join-Path $projectRoot 'tests\cache_runtime'), '-B', $testDirectory, '-G', 'Ninja',
                ('-DCMAKE_CXX_COMPILER=' + $clang.Replace('\', '/')),
                ('-DCMAKE_MAKE_PROGRAM=' + $ninja.Replace('\', '/'))
            ) (Join-Path $testDirectory 'configure.log')
            Invoke-LoggedCommand $cmake @('--build', $testDirectory, '--parallel', "$Jobs") `
                (Join-Path $testDirectory 'build.log')
            Invoke-LoggedCommand $ctest @('--test-dir', $testDirectory, '--output-on-failure') `
                (Join-Path $testDirectory 'test.log')
        }
        $timer.Stop()
        Write-Host "[SUCCESS] $exe" -ForegroundColor Green
        Write-Host ('Size: {0:N1} MiB; elapsed: {1}' -f ((Get-Item -LiteralPath $exe).Length / 1MB), $timer.Elapsed)
        Write-Host "Build log: $(Join-Path $buildDirectory 'build-release.log')"
        $exitCode = 0
    }
} catch {
    Write-Host ('[FAILED] ' + $_.Exception.Message) -ForegroundColor Red
} finally {
    Pop-Location
}
exit $exitCode
