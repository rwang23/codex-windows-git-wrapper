param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin")
)

$ErrorActionPreference = "Stop"

$consoleWindowGuard = Join-Path $InstallDir "codex-console-window-guard.exe"
$runningGuards = Get-Process -Name "codex-console-window-guard" -ErrorAction SilentlyContinue |
    Where-Object { try { $_.Path -eq $consoleWindowGuard } catch { $false } }
if ($runningGuards) {
    $runningGuards | Stop-Process -Force
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Output "Removed $InstallDir"
} else {
    Write-Output "Wrapper directory does not exist: $InstallDir"
}

Write-Output "No Git installation files were changed."
Write-Output "Open Codex normally from the Start menu to run without the wrapper."
