# Legacy compatibility entry point. Prefer start-codex-with-windows-guard.ps1
# for new integrations and documentation.
param(
    [switch]$Force,
    [switch]$DisableShellSnapshot,
    [switch]$SuppressProcessSampling,
    [switch]$UseWindowsConsoleHost,
    [string]$TempDir,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin"),
    [string]$RealGit,
    [string]$RealPowerShell
)

$ErrorActionPreference = "Stop"
$canonicalLauncher = Join-Path $PSScriptRoot "start-codex-with-windows-guard.ps1"
if (-not (Test-Path -LiteralPath $canonicalLauncher)) {
    throw "Canonical Windows Guard launcher is missing: $canonicalLauncher"
}

$forwardedArguments = @{ InstallDir = $InstallDir }
if ($Force) {
    $forwardedArguments.Force = $true
}
if ($DisableShellSnapshot) {
    $forwardedArguments.DisableShellSnapshot = $true
}
if ($SuppressProcessSampling) {
    $forwardedArguments.SuppressProcessSampling = $true
}
if ($UseWindowsConsoleHost) {
    $forwardedArguments.UseWindowsConsoleHost = $true
}
if ($TempDir) {
    $forwardedArguments.TempDir = $TempDir
}
if ($RealGit) {
    $forwardedArguments.RealGit = $RealGit
}
if ($RealPowerShell) {
    $forwardedArguments.RealPowerShell = $RealPowerShell
}

& $canonicalLauncher @forwardedArguments
