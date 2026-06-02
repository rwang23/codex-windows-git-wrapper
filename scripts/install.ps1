param(
    [string]$RealGit,
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper")
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

function Resolve-RealGit {
    param(
        [string]$RequestedRealGit,
        [string]$WrapperInstallDir
    )

    if ($RequestedRealGit) {
        if (-not (Test-Path -LiteralPath $RequestedRealGit)) {
            throw "The provided -RealGit path does not exist: $RequestedRealGit"
        }
        return (Resolve-Path -LiteralPath $RequestedRealGit).Path
    }

    $wrapperPath = Join-Path $WrapperInstallDir "git.exe"
    $commands = Get-Command git -All -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandType -eq "Application" -and
            $_.Source -and
            $_.Source -notlike "$WrapperInstallDir*" -and
            $_.Source -ne $wrapperPath -and
            $_.Source -notlike "*\codex-git-wrapper\git.exe" -and
            $_.Source -notlike "*headless-git.exe"
        }

    $preferred = $commands |
        Sort-Object @{
            Expression = {
                if ($_.Source -like "*\Git\cmd\git.exe") { 0 }
                elseif ($_.Source -like "*\Git\bin\git.exe") { 1 }
                else { 2 }
            }
        }, Source |
        Select-Object -First 1

    if ($preferred) {
        return $preferred.Source
    }

    foreach ($candidate in @(
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe"
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "Could not detect real Git. Run Get-Command git -All, then pass -RealGit with the full path to your real git.exe."
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$source = Join-Path $repoRoot "src\GitHiddenWrapper.cs"
if (-not (Test-Path -LiteralPath $source)) {
    throw "Wrapper source was not found: $source"
}

$resolvedRealGit = Resolve-RealGit -RequestedRealGit $RealGit -WrapperInstallDir $InstallDir
$gitVersion = & $resolvedRealGit --version
$csc = Find-Csc

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$output = Join-Path $InstallDir "git.exe"
& $csc /nologo /target:winexe /optimize+ /out:$output $source

if (-not (Test-Path -LiteralPath $output)) {
    throw "Compilation failed. Wrapper was not created at $output"
}

Set-Content -LiteralPath (Join-Path $InstallDir "real-git.txt") -Value $resolvedRealGit -Encoding ASCII

Write-Output "Installed Codex Git wrapper."
Write-Output "Wrapper:  $output"
Write-Output "Real Git: $resolvedRealGit"
Write-Output "Version:  $gitVersion"
Write-Output ""
Write-Output "Next: close Codex, then run scripts\start-codex-with-git-wrapper.ps1"
