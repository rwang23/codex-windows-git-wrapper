param(
    [switch]$Force,
    [switch]$DisableShellSnapshot,
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper"),
    [string]$RealGit,
    [string]$RealPowerShell
)

$ErrorActionPreference = "Stop"
$scriptsDir = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptsDir "codex-package.ps1")

function Resolve-ConfiguredRealGit {
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

    $configPath = Join-Path $WrapperInstallDir "real-git.txt"
    if (Test-Path -LiteralPath $configPath) {
        $configured = (Get-Content -LiteralPath $configPath -Raw).Trim()
        if ($configured -and (Test-Path -LiteralPath $configured)) {
            return $configured
        }
    }

    throw "Real Git path is not configured. Run scripts\install.ps1 first, or pass -RealGit."
}

function Resolve-ConfiguredRealPowerShell {
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

    $configPath = Join-Path $WrapperInstallDir "real-powershell.txt"
    if (Test-Path -LiteralPath $configPath) {
        $configured = (Get-Content -LiteralPath $configPath -Raw).Trim()
        if ($configured -and (Test-Path -LiteralPath $configured)) {
            return $configured
        }
    }

    throw "Real PowerShell path is not configured. Run scripts\install.ps1 first, or pass -RealPowerShell."
}

$wrapper = Join-Path $InstallDir "git.exe"
$powerShellWrapper = Join-Path $InstallDir "powershell.exe"
if (-not (Test-Path -LiteralPath $wrapper)) {
    throw "Git wrapper was not found at $wrapper. Run scripts\install.ps1 first."
}
if (-not (Test-Path -LiteralPath $powerShellWrapper)) {
    throw "PowerShell wrapper was not found at $powerShellWrapper. Run scripts\install.ps1 first."
}

$realGitPath = Resolve-ConfiguredRealGit -RequestedRealGit $RealGit -WrapperInstallDir $InstallDir
$realPowerShellPath = Resolve-ConfiguredRealPowerShell -RequestedRealPowerShell $RealPowerShell -WrapperInstallDir $InstallDir

$packageInfo = Resolve-CodexDesktopPackage
$codexExe = $packageInfo.ExecutablePath
$appUserModelId = $packageInfo.AppUserModelId
$runningCodex = Get-RunningCodexDesktopProcesses -PackageInfo $packageInfo

if ($runningCodex -and -not $Force) {
    Write-Warning "Codex is already running. Close Codex completely first, then run this script again."
    Write-Warning "Existing Codex processes keep their old PATH, so the wrapper will not apply to them."
    Write-Warning "To force-close Codex first, run this script with -Force."
    exit 2
}

if ($runningCodex -and $Force) {
    $runningCodex | Stop-Process -Force
    Start-Sleep -Seconds 2
}

if ($Force) {
    try {
        $processStateBackup = Backup-InvalidCodexProcessState
        if ($processStateBackup) {
            Write-Warning "Backed up invalid Codex process-manager state: $processStateBackup"
        }
    }
    catch {
        Write-Warning "Could not back up invalid Codex process-manager state: $($_.Exception.Message)"
    }
}

$env:CODEX_REAL_GIT = $realGitPath
$env:CODEX_REAL_POWERSHELL = $realPowerShellPath
$env:Path = "$InstallDir;$env:Path"

if ($DisableShellSnapshot) {
    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $codexCommand) {
        throw "The codex CLI was not found. Install or expose codex before using -DisableShellSnapshot."
    }

    Write-Output "Disabling shell_snapshot for the Codex user configuration..."
    & $codexCommand.Source features disable shell_snapshot
    if ($LASTEXITCODE -ne 0) {
        throw "Could not disable shell_snapshot. Exit code: $LASTEXITCODE"
    }
}

Write-Output "Starting Codex with Git wrapper."
Write-Output "Codex:   $codexExe"
Write-Output "Wrapper: $wrapper"
Write-Output "PowerShell wrapper: $powerShellWrapper"
Write-Output "RealGit: $realGitPath"
Write-Output "RealPowerShell: $realPowerShellPath"
if ($DisableShellSnapshot) {
    Write-Output "Feature: shell_snapshot disabled"
}

try {
    # MSIX files under WindowsApps may deny Test-Path to an external PowerShell
    # even though Windows can execute the packaged binary. Do not preflight the
    # protected path; direct launch preserves the process-local wrapper PATH.
    Start-Process -FilePath $codexExe -ErrorAction Stop
}
catch {
    Write-Warning "Direct MSIX launch was denied: $($_.Exception.Message)"
    Write-Warning "Falling back to the registered Windows AppX launch entry."
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\$appUserModelId"
    Write-Warning "The AppX fallback may not inherit the process-local Git wrapper PATH."
}
