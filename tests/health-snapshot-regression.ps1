$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$snapshotScript = Join-Path $repoRoot "scripts\health-snapshot.ps1"

if (-not (Test-Path -LiteralPath $snapshotScript -PathType Leaf)) {
    throw "Health snapshot script is missing: $snapshotScript"
}

$scriptText = Get-Content -LiteralPath $snapshotScript -Raw
$forbiddenCommands = @(
    "Stop-Process",
    "Start-Process",
    "Remove-Item",
    "Set-Content",
    "Add-Content",
    "Out-File",
    "New-Item",
    "Set-ItemProperty",
    "Remove-ItemProperty"
)
foreach ($command in $forbiddenCommands) {
    if ($scriptText -match "(?im)^\s*$([regex]::Escape($command))\b") {
        throw "Read-only health snapshot contains a mutating command: $command"
    }
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $snapshotScript,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Health snapshot has PowerShell parse errors: $($parseErrors | Out-String)"
}

$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $snapshotScript -AsJson
if ($LASTEXITCODE -ne 0) {
    throw "Health snapshot JSON execution failed with exit code $LASTEXITCODE."
}
$snapshot = $json | ConvertFrom-Json

if ($snapshot.SchemaVersion -ne 1) {
    throw "Unexpected health snapshot schema version: $($snapshot.SchemaVersion)"
}
if ($snapshot.ReadOnly -ne $true) {
    throw "Health snapshot did not declare its read-only contract."
}
if (-not $snapshot.CapturedAtUtc) {
    throw "Health snapshot did not include a capture timestamp."
}
if ($null -eq $snapshot.AppServers -or $null -eq $snapshot.AggregateByKind -or $null -eq $snapshot.NodeRuntimes -or $null -eq $snapshot.RuntimeWarnings -or $null -eq $snapshot.DetachedCandidates) {
    throw "Health snapshot omitted a required collection."
}
if ($snapshot.AutomaticCleanup -ne $false) {
    throw "Health snapshot must explicitly disable automatic cleanup."
}
if ($snapshot.WarningPolicy.KernelWarningPrivateMB -ne 750 -or $snapshot.WarningPolicy.KernelCriticalPrivateMB -ne 1024) {
    throw "Health snapshot warning thresholds changed unexpectedly."
}
if ($json -match '(?i)CommandLine|"token"') {
    throw "Health snapshot exposed a command line or daemon token field."
}
if ($snapshot.BbBrowser.Registered -and -not $snapshot.BbBrowser.DaemonProcessId) {
    throw "Registered BB Browser daemon is missing its process ID."
}
foreach ($runtime in @($snapshot.NodeRuntimes)) {
    $hostComponents = @($runtime.Components | Where-Object { $_.Role -eq "node-repl-host" -and $_.ProcessId -eq $runtime.HostProcessId })
    if ($hostComponents.Count -ne 1) {
        throw "Node runtime did not identify exactly one host component."
    }
    $kernelCount = @($runtime.Components | Where-Object { $_.Role -eq "node-kernel" }).Count
    if ($runtime.KernelCount -ne $kernelCount) {
        throw "Node runtime kernel summary does not match its components."
    }
}

Write-Output "Health snapshot regression checks: PASS"
