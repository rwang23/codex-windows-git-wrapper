param(
    [switch]$Force,
    [switch]$DisableShellSnapshot,
    [switch]$SuppressProcessSampling,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin"),
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

function Start-ConsoleWindowGuard {
    param(
        [string]$Path,
        [string]$LogPath
    )

    $lastError = $null
    $previousLogPath = [Environment]::GetEnvironmentVariable("CODEX_CONSOLE_GUARD_LOG", "Process")
    try {
        [Environment]::SetEnvironmentVariable("CODEX_CONSOLE_GUARD_LOG", $LogPath, "Process")
        for ($attempt = 1; $attempt -le 10; $attempt++) {
            try {
                Start-Process -FilePath $Path -ErrorAction Stop
                return
            }
            catch {
                $lastError = $_
                if ($attempt -lt 10) {
                    Start-Sleep -Milliseconds 300
                }
            }
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("CODEX_CONSOLE_GUARD_LOG", $previousLogPath, "Process")
    }

    throw "Could not start the Codex Git console window guard: $($lastError.Exception.Message)"
}

$wrapper = Join-Path $InstallDir "git.exe"
$powerShellWrapper = Join-Path $InstallDir "powershell.exe"
$consoleWindowGuard = Join-Path $InstallDir "codex-console-window-guard.exe"
$consoleWindowGuardLog = Join-Path $InstallDir "codex-console-window-guard.log"
if (-not (Test-Path -LiteralPath $wrapper -ErrorAction SilentlyContinue)) {
    throw "Git wrapper was not found at $wrapper. Run scripts\install.ps1 first."
}
if (-not (Test-Path -LiteralPath $powerShellWrapper -ErrorAction SilentlyContinue)) {
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
if ($SuppressProcessSampling) {
    $env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING = "1"
} else {
    Remove-Item Env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING -ErrorAction SilentlyContinue
}
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

if (Test-Path -LiteralPath $consoleWindowGuard -ErrorAction SilentlyContinue) {
    $runningGuard = Get-Process -Name "codex-console-window-guard" -ErrorAction SilentlyContinue |
        Where-Object { try { $_.Path -eq $consoleWindowGuard } catch { $false } } |
        Select-Object -First 1
    if (-not $runningGuard) {
        Start-ConsoleWindowGuard -Path $consoleWindowGuard -LogPath $consoleWindowGuardLog
        Write-Output "Started the Codex Git console window guard."
    } else {
        Write-Output "Codex Git console window guard is already running."
    }
} else {
    Write-Warning "Codex Git console window guard is missing. Run scripts\install.ps1 to build it."
}

Write-Output "Starting Codex with Git wrapper."
Write-Output "Codex:   $codexExe"
Write-Output "Wrapper: $wrapper"
Write-Output "PowerShell wrapper: $powerShellWrapper"
Write-Output "Console window guard: $consoleWindowGuard"
Write-Output "Console guard log: $consoleWindowGuardLog"
Write-Output "RealGit: $realGitPath"
Write-Output "RealPowerShell: $realPowerShellPath"
if ($DisableShellSnapshot) {
    Write-Output "Feature: shell_snapshot disabled"
}
if ($SuppressProcessSampling) {
    Write-Output "Feature: Desktop PowerShell process sampling suppressed"
}

try {
    # MSIX files under WindowsApps may deny Test-Path to an external PowerShell
    # even though Windows can execute the packaged binary. Do not preflight the
    # protected path. Current ChatGPT/Codex packages can activate through SIHost
    # and bypass this process-local PATH; the console window guard above hides
    # only Git console windows whose ancestry includes ChatGPT.
    Start-Process -FilePath $codexExe -ErrorAction Stop
}
catch {
    Write-Warning "Direct MSIX launch was denied: $($_.Exception.Message)"
    Write-Warning "Falling back to the registered Windows AppX launch entry."
    Start-Process -FilePath "explorer.exe" -ArgumentList "shell:AppsFolder\$appUserModelId"
    Write-Warning "The AppX fallback may not inherit the process-local Git wrapper PATH."
}
