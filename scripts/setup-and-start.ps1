param(
    [switch]$Force,
    [string]$RealGit,
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper")
)

$ErrorActionPreference = "Stop"

$scriptsDir = Split-Path -Parent $PSCommandPath
$installScript = Join-Path $scriptsDir "install.ps1"
$statusScript = Join-Path $scriptsDir "status.ps1"
$startScript = Join-Path $scriptsDir "start-codex-with-git-wrapper.ps1"

foreach ($script in @($installScript, $statusScript, $startScript)) {
    if (-not (Test-Path -LiteralPath $script)) {
        throw "Required script not found: $script"
    }
}

$installArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $installScript,
    "-InstallDir", $InstallDir
)

if ($RealGit) {
    $installArgs += @("-RealGit", $RealGit)
}

Write-Output "Installing or refreshing Codex Git wrapper..."
& powershell -NoProfile @installArgs

Write-Output ""
Write-Output "Checking wrapper status..."
& powershell -NoProfile -ExecutionPolicy Bypass -File $statusScript -InstallDir $InstallDir

$startArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $startScript,
    "-InstallDir", $InstallDir
)

if ($RealGit) {
    $startArgs += @("-RealGit", $RealGit)
}

$runningCodex = Get-Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessName -in @("Codex", "codex") -and
        $_.Path -like "*OpenAI*Codex*"
    }

if ($runningCodex -and -not $Force) {
    Write-Warning "Codex is already running. Existing Codex processes keep their old PATH, so the wrapper cannot apply yet."
    Write-Warning "Close Codex completely, then run this script again. Or run the following from an external PowerShell window:"
    Write-Output ""
    Write-Output "powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Force"
    exit 2
}

if ($Force) {
    $startArgs += "-Force"
}

Write-Output ""
Write-Output "Starting Codex..."
& powershell -NoProfile @startArgs
