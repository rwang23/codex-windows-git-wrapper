param(
    [string]$RealGit,
    [string]$RealPowerShell,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin")
)

$ErrorActionPreference = "Stop"

function Find-Csc {
    $candidates = @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe"),
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\Roslyn\csc.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\Roslyn\csc.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $fromPath = Get-Command csc.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    throw "Could not find csc.exe. Install .NET Framework developer tools or Visual Studio Build Tools."
}

function Find-NativeCompiler {
    foreach ($name in @("cl.exe", "clang.exe", "gcc.exe")) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return [pscustomobject]@{
                Name = $name
                Path = $command.Source
                EnvScript = $null
            }
        }
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $installPaths = @()
    if (Test-Path -LiteralPath $vswhere) {
        $detected = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($detected) {
            $installPaths += $detected
        }
    }

    $installPaths += @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools"
    )

    foreach ($installPath in ($installPaths | Select-Object -Unique)) {
        $vcvars = Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"
        $toolsRoot = Join-Path $installPath "VC\Tools\MSVC"
        if (-not (Test-Path -LiteralPath $vcvars) -or -not (Test-Path -LiteralPath $toolsRoot)) {
            continue
        }

        $cl = Get-ChildItem -LiteralPath $toolsRoot -Recurse -Filter cl.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like "*\bin\Hostx64\x64\cl.exe" } |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($cl) {
            return [pscustomobject]@{
                Name = "cl.exe"
                Path = $cl.FullName
                EnvScript = $vcvars
            }
        }
    }

    return $null
}

function Build-NativeWrapper {
    param(
        [string]$CompilerName,
        [string]$CompilerPath,
        [string]$EnvScript,
        [string]$Source,
        [string]$Output,
        [string]$BuildDir
    )

    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
    Push-Location $BuildDir
    try {
        if ($CompilerName -eq "cl.exe") {
            if ($EnvScript) {
                $command = "call `"$EnvScript`" >nul && `"$CompilerPath`" /nologo /O2 /EHsc /DUNICODE /D_UNICODE /Fe`"$Output`" `"$Source`" /link /SUBSYSTEM:WINDOWS"
                cmd.exe /c $command | Write-Output
            } else {
                & $CompilerPath /nologo /O2 /EHsc /DUNICODE /D_UNICODE "/Fe$Output" $Source /link /SUBSYSTEM:WINDOWS | Write-Output
            }
        } elseif ($CompilerName -eq "clang.exe") {
            & $CompilerPath -O2 -municode -mwindows -o $Output $Source | Write-Output
        } elseif ($CompilerName -eq "gcc.exe") {
            & $CompilerPath -O2 -municode -mwindows -o $Output $Source | Write-Output
        } else {
            throw "Unsupported native compiler: $CompilerName"
        }

        if ($LASTEXITCODE -ne 0) {
            throw "Native wrapper compilation failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Resolve-RealGit {
    param(
        [string]$RequestedRealGit,
        [string]$WrapperInstallDir
    )

    function Prefer-DirectGitExecutable {
        param([string]$GitPath)

        $resolved = (Resolve-Path -LiteralPath $GitPath).Path
        if ($resolved -match '[\\/]cmd[\\/]git\.exe$') {
            $gitRoot = Split-Path -Parent (Split-Path -Parent $resolved)
            $directGit = Join-Path $gitRoot 'mingw64\bin\git.exe'
            if (Test-Path -LiteralPath $directGit) {
                return (Resolve-Path -LiteralPath $directGit).Path
            }
        }

        return $resolved
    }

    if ($RequestedRealGit) {
        if (-not (Test-Path -LiteralPath $RequestedRealGit)) {
            throw "The provided -RealGit path does not exist: $RequestedRealGit"
        }
        return Prefer-DirectGitExecutable -GitPath $RequestedRealGit
    }

    $wrapperPath = Join-Path $WrapperInstallDir "git.exe"
    $codexRuntimeRoot = Join-Path $env:USERPROFILE ".cache\codex-runtimes"
    $codexAppRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex"
    $commands = Get-Command git -All -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandType -eq "Application" -and
            $_.Source -and
            $_.Source -notlike "$WrapperInstallDir*" -and
            $_.Source -ne $wrapperPath -and
            $_.Source -notlike "*\codex-git-wrapper\git.exe" -and
            $_.Source -notlike "*headless-git.exe" -and
            $_.Source -notlike "$codexRuntimeRoot*" -and
            $_.Source -notlike "$codexAppRoot*"
        }

    $preferred = $commands |
        Sort-Object @{
            Expression = {
                if ($_.Source -like "*\Git\mingw64\bin\git.exe") { 0 }
                elseif ($_.Source -like "*\Git\cmd\git.exe") { 1 }
                elseif ($_.Source -like "*\Git\bin\git.exe") { 2 }
                else { 3 }
            }
        }, Source |
        Select-Object -First 1

    if ($preferred) {
        return Prefer-DirectGitExecutable -GitPath $preferred.Source
    }

    foreach ($candidate in @(
        "C:\Program Files\Git\mingw64\bin\git.exe",
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\mingw64\bin\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return Prefer-DirectGitExecutable -GitPath $candidate
        }
    }

    throw "Could not detect real Git. Run Get-Command git -All, then pass -RealGit with the full path to your real git.exe."
}

function Resolve-RealPowerShell {
    param(
        [string]$RequestedRealPowerShell,
        [string]$WrapperInstallDir
    )

    if ($RequestedRealPowerShell) {
        if (-not (Test-Path -LiteralPath $RequestedRealPowerShell)) {
            throw "The provided -RealPowerShell path does not exist: $RequestedRealPowerShell"
        }
        return (Resolve-Path -LiteralPath $RequestedRealPowerShell).Path
    }

    $commands = Get-Command powershell.exe -All -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandType -eq "Application" -and
            $_.Source -and
            $_.Source -notlike "$WrapperInstallDir*"
        } |
        Select-Object -First 1

    if ($commands) {
        return $commands.Source
    }

    $candidate = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw "Could not detect Windows PowerShell. Pass -RealPowerShell with the full path to powershell.exe."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$source = Join-Path $repoRoot "src\GitHiddenWrapper.cs"
$nativeSource = Join-Path $repoRoot "src\GitHiddenWrapper.cpp"
$consoleWindowGuardSource = Join-Path $repoRoot "src\CodexConsoleWindowGuard.cpp"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Wrapper source was not found: $source"
}

$resolvedRealGit = Resolve-RealGit -RequestedRealGit $RealGit -WrapperInstallDir $InstallDir
$resolvedRealPowerShell = Resolve-RealPowerShell -RequestedRealPowerShell $RealPowerShell -WrapperInstallDir $InstallDir
$resolvedRealCmd = Join-Path $env:WINDIR "System32\cmd.exe"
if (-not (Test-Path -LiteralPath $resolvedRealCmd)) {
    throw "Could not find the built-in Command Prompt executable: $resolvedRealCmd"
}
$gitVersion = & $resolvedRealGit --version
$powerShellVersion = & $resolvedRealPowerShell -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$output = Join-Path $InstallDir "git.exe"
$buildKind = "managed-csharp"
$nativeCompiler = $null

if (Test-Path -LiteralPath $nativeSource) {
    $nativeCompiler = Find-NativeCompiler
}

if ($nativeCompiler) {
    $buildKind = "native-$($nativeCompiler.Name)"
    Build-NativeWrapper -CompilerName $nativeCompiler.Name -CompilerPath $nativeCompiler.Path -EnvScript $nativeCompiler.EnvScript -Source $nativeSource -Output $output -BuildDir (Join-Path $repoRoot "obj\native")
} else {
    $csc = Find-Csc
    & $csc /nologo /target:winexe /optimize+ /out:$output $source
}

if (-not (Test-Path -LiteralPath $output)) {
    throw "Compilation failed. Wrapper was not created at $output"
}

$powerShellOutput = Join-Path $InstallDir "powershell.exe"
Copy-Item -LiteralPath $output -Destination $powerShellOutput -Force
$cmdOutput = Join-Path $InstallDir "cmd.exe"
Copy-Item -LiteralPath $output -Destination $cmdOutput -Force
$consoleWindowGuardOutput = Join-Path $InstallDir "codex-console-window-guard.exe"

if ($nativeCompiler -and (Test-Path -LiteralPath $consoleWindowGuardSource)) {
    $existingGuards = Get-Process -Name "codex-console-window-guard" -ErrorAction SilentlyContinue |
        Where-Object { try { $_.Path -eq $consoleWindowGuardOutput } catch { $false } }
    if ($existingGuards) {
        $existingGuards | Stop-Process -Force
    }
    Build-NativeWrapper -CompilerName $nativeCompiler.Name -CompilerPath $nativeCompiler.Path -EnvScript $nativeCompiler.EnvScript -Source $consoleWindowGuardSource -Output $consoleWindowGuardOutput -BuildDir (Join-Path $repoRoot "obj\console-window-guard")
    if (-not (Test-Path -LiteralPath $consoleWindowGuardOutput)) {
        throw "Console window guard compilation failed."
    }
} elseif (Test-Path -LiteralPath $consoleWindowGuardOutput) {
    Write-Warning "Retaining the existing console window guard because no native C++ compiler is currently available to rebuild it."
}

Set-Content -LiteralPath (Join-Path $InstallDir "real-git.txt") -Value $resolvedRealGit -Encoding ASCII
Set-Content -LiteralPath (Join-Path $InstallDir "real-powershell.txt") -Value $resolvedRealPowerShell -Encoding ASCII
Set-Content -LiteralPath (Join-Path $InstallDir "real-cmd.txt") -Value $resolvedRealCmd -Encoding ASCII
Set-Content -LiteralPath (Join-Path $InstallDir "wrapper-kind.txt") -Value $buildKind -Encoding ASCII

Write-Output "Installed Codex Git wrapper."
Write-Output "Wrapper:  $output"
Write-Output "PowerShell wrapper: $powerShellOutput"
Write-Output "Command Prompt wrapper: $cmdOutput"
if (Test-Path -LiteralPath $consoleWindowGuardOutput) {
    Write-Output "Console window guard: $consoleWindowGuardOutput"
} else {
    Write-Warning "Console window guard was not built because no native C++ compiler was available."
}
Write-Output "Build:    $buildKind"
Write-Output "Real Git: $resolvedRealGit"
Write-Output "Real PowerShell: $resolvedRealPowerShell"
Write-Output "Real Command Prompt: $resolvedRealCmd"
Write-Output "Version:  $gitVersion"
Write-Output "PowerShell version: $powerShellVersion"
Write-Output ""
Write-Output "Next: close Codex, then run scripts\start-codex-with-git-wrapper.ps1"
