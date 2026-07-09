$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$helperScript = Join-Path $repoRoot "scripts\codex-package.ps1"

if (-not (Test-Path -LiteralPath $helperScript)) {
    throw "Launcher package helper is missing: $helperScript"
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
