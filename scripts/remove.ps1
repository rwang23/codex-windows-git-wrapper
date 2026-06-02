param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE ".codex\codex-git-wrapper")
)

$ErrorActionPreference = "Stop"

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Output "Removed $InstallDir"
} else {
    Write-Output "Wrapper directory does not exist: $InstallDir"
}

Write-Output "No Git installation files were changed."
Write-Output "Open Codex normally from the Start menu to run without the wrapper."

