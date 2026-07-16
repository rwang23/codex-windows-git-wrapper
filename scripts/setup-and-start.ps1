param(
    [switch]$Force,
    [switch]$DisableShellSnapshot,
    [switch]$SuppressProcessSampling,
    [switch]$UseWindowsConsoleHost,
    [string]$RealGit,
    [string]$RealPowerShell,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin")
)

$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $PSCommandPath
$installScript = Join-Path $scriptsDir "install.ps1"
$statusScript = Join-Path $scriptsDir "status.ps1"
$startScript = Join-Path $scriptsDir "start-codex-with-console-guard.ps1"
$packageScript = Join-Path $scriptsDir "codex-package.ps1"
$defaultTerminalScript = Join-Path $scriptsDir "configure-default-terminal.ps1"

foreach ($script in @($installScript, $statusScript, $startScript, $packageScript, $defaultTerminalScript)) {
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Required script not found: $script"
    }
}

. $packageScript

$packageInfo = Resolve-CodexDesktopPackage
$runningCodex = Get-RunningCodexDesktopProcesses -PackageInfo $packageInfo

if ($runningCodex -and -not $Force) {
    Write-Warning "Codex is already running. Existing Codex processes keep their old PATH, so the wrapper cannot be safely refreshed."
    Write-Warning "Close Codex completely, then run this script again, or rerun it with -Force from an external PowerShell window."
    exit 2
}

if ($runningCodex -and $Force) {
    Write-Output "Stopping the running $($packageInfo.ProcessName).exe app before refreshing wrappers..."
    $runningCodex | Stop-Process -Force
    Start-Sleep -Seconds 2
}

$installArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $installScript,
    "-InstallDir", $InstallDir
)

if ($RealGit) {
    $installArgs += @("-RealGit", $RealGit)
}
if ($RealPowerShell) {
    $installArgs += @("-RealPowerShell", $RealPowerShell)
}

Write-Output "Installing or refreshing Codex Windows Console Guard..."
& powershell -NoProfile @installArgs
if ($LASTEXITCODE -ne 0) {
    throw "Console Guard installation failed with exit code $LASTEXITCODE."
}

if ($UseWindowsConsoleHost) {
    Write-Output ""
    Write-Output "Applying the reversible Windows Console Host compatibility mode..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $defaultTerminalScript `
        -Mode ConsoleHost `
        -BackupPath (Join-Path $InstallDir "default-terminal-backup.json")
    if ($LASTEXITCODE -ne 0) {
        throw "Default-terminal configuration failed with exit code $LASTEXITCODE."
    }
}

Write-Output ""
Write-Output "Checking wrapper status..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $statusScript -InstallDir $InstallDir
if ($LASTEXITCODE -ne 0) {
    throw "Console Guard status check failed with exit code $LASTEXITCODE."
}

$startArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $startScript,
    "-InstallDir", $InstallDir
)

if ($RealGit) {
    $startArgs += @("-RealGit", $RealGit)
}
if ($RealPowerShell) {
    $startArgs += @("-RealPowerShell", $RealPowerShell)
}

if ($DisableShellSnapshot) {
    $startArgs += "-DisableShellSnapshot"
}
if ($SuppressProcessSampling) {
    $startArgs += "-SuppressProcessSampling"
}
if ($UseWindowsConsoleHost) {
    $startArgs += "-UseWindowsConsoleHost"
}

if ($Force) {
    $startArgs += "-Force"
}

Write-Output ""
Write-Output "Starting Codex..."
& powershell -NoProfile @startArgs
if ($LASTEXITCODE -ne 0) {
    throw "Codex launcher failed with exit code $LASTEXITCODE."
}
