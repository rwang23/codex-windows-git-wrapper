$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$entryScript = Join-Path $repoRoot "scripts\codex-guard.ps1"
$setupScript = Join-Path $repoRoot "scripts\setup-and-start.ps1"
$statusScript = Join-Path $repoRoot "scripts\status.ps1"
$healthSnapshotScript = Join-Path $repoRoot "scripts\health-snapshot.ps1"

foreach ($path in @($entryScript, $setupScript, $statusScript, $healthSnapshotScript)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Codex Guard command dependency is missing: $path"
    }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $entryScript,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Codex Guard command entry has PowerShell parse errors: $($parseErrors | Out-String)"
}

$scriptText = [IO.File]::ReadAllText($entryScript)
foreach ($command in @("Check", "Repair", "Stop", "Launch", "Help")) {
    $quotedCommand = '"' + $command + '"'
    if ($scriptText -notmatch [regex]::Escape($quotedCommand)) {
        throw "Codex Guard command entry does not expose the $command command."
    }
}
foreach ($switch in @("-DisableShellSnapshot", "-SuppressProcessSampling", "-UseWindowsConsoleHost")) {
    $quotedSwitch = '"' + $switch + '"'
    if ($scriptText -notmatch [regex]::Escape($quotedSwitch)) {
        throw "Launch does not forward the default switch $switch."
    }
}
if ($scriptText -notmatch '(?s)if\s*\(-not\s*\$Apply\).*?Preview only') {
    throw "Mutating commands are missing the default preview boundary."
}
if ($scriptText -notmatch '(?s)if\s*\(-not\s*\$Apply\).*?stop these exact targets') {
    throw "Stop does not expose the exact-target preview boundary."
}

$help = & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $entryScript Help
if (-not $?) {
    throw "Codex Guard help command failed."
}
$helpText = ($help -join [Environment]::NewLine)
foreach ($word in @("check", "repair", "stop", "launch")) {
    if ($helpText -notmatch "(?im)^\s*$word\s+") {
        throw "Help output is missing the $word command."
    }
}

Write-Output "Codex Guard command regression checks: PASS"
