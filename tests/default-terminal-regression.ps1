$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$configureScript = Join-Path $repoRoot "scripts\configure-default-terminal.ps1"
$testRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\guard-tests\default-terminal-test-$PID"
$backupPath = Join-Path $testRoot "default-terminal-backup.json"
$registryRoot = "HKCU:\Software\OpenAI\CodexConsoleGuardTests\$PID"
$registryPath = Join-Path $registryRoot "DefaultTerminal"
$automatic = "{00000000-0000-0000-0000-000000000000}"
$consoleHost = "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"

if (-not (Test-Path -LiteralPath $configureScript -PathType Leaf)) {
    throw "Default-terminal configuration script is missing: $configureScript"
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $registryPath | Out-Null
    New-ItemProperty -LiteralPath $registryPath -Name "DelegationConsole" -Value $automatic -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $registryPath -Name "DelegationTerminal" -Value $automatic -PropertyType String -Force | Out-Null

    & $configureScript -Mode ConsoleHost -RegistryPath $registryPath -BackupPath $backupPath
    $configured = Get-ItemProperty -LiteralPath $registryPath
    if ($configured.DelegationConsole -ne $consoleHost -or
        $configured.DelegationTerminal -ne $consoleHost) {
        throw "Console Host delegation values were not applied."
    }
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Default-terminal backup was not created."
    }

    # Reapplying must preserve the original backup rather than backing up the
    # already-modified Console Host values.
    & $configureScript -Mode ConsoleHost -RegistryPath $registryPath -BackupPath $backupPath
    & $configureScript -Mode Restore -RegistryPath $registryPath -BackupPath $backupPath

    $restored = Get-ItemProperty -LiteralPath $registryPath
    if ($restored.DelegationConsole -ne $automatic -or
        $restored.DelegationTerminal -ne $automatic) {
        throw "Default-terminal delegation values were not restored."
    }

    # An unconfigured key is also a valid Automatic baseline. Restore must
    # remove properties that did not exist originally rather than writing
    # synthetic values.
    Remove-ItemProperty -LiteralPath $registryPath -Name "DelegationConsole" -ErrorAction SilentlyContinue
    Remove-ItemProperty -LiteralPath $registryPath -Name "DelegationTerminal" -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupPath -Force
    & $configureScript -Mode ConsoleHost -RegistryPath $registryPath -BackupPath $backupPath
    & $configureScript -Mode Restore -RegistryPath $registryPath -BackupPath $backupPath
    $restoredUnconfigured = Get-ItemProperty -LiteralPath $registryPath
    if ($null -ne $restoredUnconfigured.PSObject.Properties["DelegationConsole"] -or
        $null -ne $restoredUnconfigured.PSObject.Properties["DelegationTerminal"]) {
        throw "Originally absent default-terminal values were not removed during restore."
    }

    Write-Output "Default terminal regression checks: PASS"
}
finally {
    Remove-Item -LiteralPath $registryRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
