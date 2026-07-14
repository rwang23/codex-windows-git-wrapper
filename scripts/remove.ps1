param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin")
)

$ErrorActionPreference = "Stop"

$systemInterposerState = Join-Path $InstallDir "system-git-interposer-state.json"
if (Test-Path -LiteralPath $systemInterposerState -PathType Leaf) {
    throw "A direct Git interposer is active. Run scripts\remove-system-git-interposer.ps1 first so the original Git dispatcher is restored before removing $InstallDir."
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
    Write-Output "Removed $InstallDir"
} else {
    Write-Output "Wrapper directory does not exist: $InstallDir"
}

Write-Output "No Git installation files were changed by the standard wrapper removal."
Write-Output "Open Codex normally from the Start menu to run without the wrapper."
