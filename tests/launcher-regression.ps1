$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$helperScript = Join-Path $repoRoot "scripts\codex-package.ps1"
$canonicalLauncher = Join-Path $repoRoot "scripts\start-codex-with-console-guard.ps1"
$legacyLauncher = Join-Path $repoRoot "scripts\start-codex-with-git-wrapper.ps1"
$setupLauncher = Join-Path $repoRoot "scripts\setup-and-start.ps1"
$defaultTerminalScript = Join-Path $repoRoot "scripts\configure-default-terminal.ps1"

if (-not (Test-Path -LiteralPath $helperScript)) {
    throw "Launcher package helper is missing: $helperScript"
}
if (-not (Test-Path -LiteralPath $canonicalLauncher)) {
    throw "Canonical console-guard launcher is missing: $canonicalLauncher"
}
if (-not (Test-Path -LiteralPath $legacyLauncher)) {
    throw "Legacy Git-wrapper launcher is missing: $legacyLauncher"
}
if (-not (Test-Path -LiteralPath $setupLauncher)) {
    throw "Setup launcher is missing: $setupLauncher"
}
if (-not (Test-Path -LiteralPath $defaultTerminalScript)) {
    throw "Default-terminal configuration helper is missing: $defaultTerminalScript"
}

function Get-ScriptParameterNames {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse errors in ${Path}: $($errors | Out-String)"
    }
    return @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath | Sort-Object)
}

$canonicalParameters = @(Get-ScriptParameterNames -Path $canonicalLauncher)
$legacyParameters = @(Get-ScriptParameterNames -Path $legacyLauncher)
$parameterDifference = Compare-Object -ReferenceObject $canonicalParameters -DifferenceObject $legacyParameters
if ($parameterDifference) {
    throw "Canonical and legacy launchers do not expose the same parameters: $($parameterDifference | Out-String)"
}
if ($canonicalParameters -notcontains "UseWindowsConsoleHost") {
    throw "Canonical launcher is missing -UseWindowsConsoleHost."
}
$setupParameters = @(Get-ScriptParameterNames -Path $setupLauncher)
if ($setupParameters -notcontains "UseWindowsConsoleHost") {
    throw "Setup launcher is missing -UseWindowsConsoleHost."
}

. $helperScript

$packageInfo = Resolve-CodexDesktopPackage
$manifest = Get-AppxPackageManifest -Package $packageInfo.Package
$application = $manifest.Package.Applications.Application | Select-Object -First 1
$expectedRelativePath = ([string]$application.Executable).Replace("/", "\")
$expectedExecutablePath = Join-Path $packageInfo.Package.InstallLocation $expectedRelativePath

if ($packageInfo.ExecutablePath -ne $expectedExecutablePath) {
    throw "Launcher executable does not match the MSIX manifest. Expected: $expectedExecutablePath; Actual: $($packageInfo.ExecutablePath)"
}

$chatGpt = Get-Process -Name ChatGPT -ErrorAction SilentlyContinue | Select-Object -First 1
if ($chatGpt) {
    $running = @(Get-RunningCodexDesktopProcesses -PackageInfo $packageInfo)
    if ($running.Id -notcontains $chatGpt.Id) {
        throw "Running ChatGPT.exe process was not recognized as Codex Desktop."
    }
}

$invalidState = Join-Path $env:TEMP "codex-wrapper-invalid-process-state-$PID.json"
[System.IO.File]::WriteAllBytes($invalidState, [byte[]](0, 0, 0, 0))
try {
    $backupPath = Backup-InvalidCodexProcessState -Path $invalidState
    if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath)) {
        throw "Invalid process-manager state was not backed up."
    }
    if (Test-Path -LiteralPath $invalidState) {
        throw "Invalid process-manager state remained at the active path."
    }
} finally {
    Remove-Item -LiteralPath $invalidState -Force -ErrorAction SilentlyContinue
    if ($backupPath) {
        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "Launcher regression checks: PASS"
