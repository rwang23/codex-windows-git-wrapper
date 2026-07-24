$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$helperScript = Join-Path $repoRoot "scripts\codex-package.ps1"
$canonicalLauncher = Join-Path $repoRoot "scripts\start-codex-with-windows-guard.ps1"
$consoleCompatibilityLauncher = Join-Path $repoRoot "scripts\start-codex-with-console-guard.ps1"
$legacyLauncher = Join-Path $repoRoot "scripts\start-codex-with-git-wrapper.ps1"
$setupLauncher = Join-Path $repoRoot "scripts\setup-and-start.ps1"
$defaultTerminalScript = Join-Path $repoRoot "scripts\configure-default-terminal.ps1"
$codexTempScript = Join-Path $repoRoot "scripts\configure-codex-temp.ps1"

if (-not (Test-Path -LiteralPath $helperScript)) {
    throw "Launcher package helper is missing: $helperScript"
}
if (-not (Test-Path -LiteralPath $canonicalLauncher)) {
    throw "Canonical Windows Guard launcher is missing: $canonicalLauncher"
}
if (-not (Test-Path -LiteralPath $consoleCompatibilityLauncher)) {
    throw "Console-named compatibility launcher is missing: $consoleCompatibilityLauncher"
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
if (-not (Test-Path -LiteralPath $codexTempScript)) {
    throw "Codex temporary-directory configuration helper is missing: $codexTempScript"
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
$consoleCompatibilityParameters = @(Get-ScriptParameterNames -Path $consoleCompatibilityLauncher)
$legacyParameters = @(Get-ScriptParameterNames -Path $legacyLauncher)
foreach ($compatibilityParameters in @($consoleCompatibilityParameters, $legacyParameters)) {
    $parameterDifference = Compare-Object -ReferenceObject $canonicalParameters -DifferenceObject $compatibilityParameters
    if ($parameterDifference) {
        throw "Canonical and compatibility launchers do not expose the same parameters: $($parameterDifference | Out-String)"
    }
}
if ($canonicalParameters -notcontains "UseWindowsConsoleHost") {
    throw "Canonical launcher is missing -UseWindowsConsoleHost."
}
if ($canonicalParameters -notcontains "TempDir") {
    throw "Canonical launcher is missing -TempDir."
}
$setupParameters = @(Get-ScriptParameterNames -Path $setupLauncher)
if ($setupParameters -notcontains "UseWindowsConsoleHost") {
    throw "Setup launcher is missing -UseWindowsConsoleHost."
}
if ($setupParameters -notcontains "TempDir") {
    throw "Setup launcher is missing -TempDir."
}
$setupContent = [IO.File]::ReadAllText($setupLauncher)
if ($setupContent -notmatch '(?s)if\s*\(\$Force\)\s*\{\s*\$installArgs\s*\+=\s*"-StopWrapperProcesses"\s*\}') {
    throw "Setup launcher does not forward -Force to the scoped wrapper-process cleanup."
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
