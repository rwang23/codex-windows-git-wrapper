param(
    [ValidateSet("Status", "ConsoleHost", "Restore")]
    [string]$Mode = "Status",
    [string]$RegistryPath = "HKCU:\Console\%%Startup",
    [string]$BackupPath = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\default-terminal-backup.json")
)

$ErrorActionPreference = "Stop"

$automatic = "{00000000-0000-0000-0000-000000000000}"
$consoleHost = "{B23D10C0-E52E-411E-9D5B-C09FDF709C7D}"
$windowsTerminalConsole = "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}"
$windowsTerminalTerminal = "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}"
$windowsTerminalPreviewConsole = "{06EC847C-C0A5-46B8-92CB-7C92F6E35CD5}"
$windowsTerminalPreviewTerminal = "{86633F1F-6454-40EC-89CE-DA4EBA977EE2}"

function Get-RegistryStringState {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }

    $item = Get-ItemProperty -LiteralPath $Path
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return [pscustomobject]@{ Exists = $false; Value = $null }
    }

    return [pscustomobject]@{ Exists = $true; Value = [string]$property.Value }
}

function Get-DefaultTerminalState {
    param([string]$Path)

    $delegationConsole = Get-RegistryStringState -Path $Path -Name "DelegationConsole"
    $delegationTerminal = Get-RegistryStringState -Path $Path -Name "DelegationTerminal"
    return [pscustomobject]@{
        DelegationConsole = $delegationConsole
        DelegationTerminal = $delegationTerminal
    }
}

function Get-DefaultTerminalMode {
    param($State)

    $console = [string]$State.DelegationConsole.Value
    $terminal = [string]$State.DelegationTerminal.Value
    if ($console -eq $automatic -and $terminal -eq $automatic) {
        return "Automatic"
    }
    if ($console -eq $consoleHost -and $terminal -eq $consoleHost) {
        return "Windows Console Host"
    }
    if ($console -eq $windowsTerminalConsole -and $terminal -eq $windowsTerminalTerminal) {
        return "Windows Terminal"
    }
    if ($console -eq $windowsTerminalPreviewConsole -and $terminal -eq $windowsTerminalPreviewTerminal) {
        return "Windows Terminal Preview"
    }
    if (-not $State.DelegationConsole.Exists -and -not $State.DelegationTerminal.Exists) {
        return "Automatic (not explicitly configured)"
    }
    return "Custom or unknown"
}

function Save-DefaultTerminalBackup {
    param(
        [string]$Path,
        [string]$Destination,
        $State
    )

    $parent = Split-Path -Parent $Destination
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    [pscustomobject]@{
        SchemaVersion = 1
        RegistryPath = $Path
        CreatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        DelegationConsole = [pscustomobject]@{
            Exists = [bool]$State.DelegationConsole.Exists
            Value = $State.DelegationConsole.Value
        }
        DelegationTerminal = [pscustomobject]@{
            Exists = [bool]$State.DelegationTerminal.Exists
            Value = $State.DelegationTerminal.Value
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Destination -Encoding UTF8
}

function Set-RegistryStringState {
    param(
        [string]$Path,
        [string]$Name,
        $State
    )

    if ($State.Exists) {
        New-ItemProperty -LiteralPath $Path -Name $Name -Value ([string]$State.Value) -PropertyType String -Force | Out-Null
    } else {
        Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
    }
}

$current = Get-DefaultTerminalState -Path $RegistryPath
$currentMode = Get-DefaultTerminalMode -State $current

if ($Mode -eq "Status") {
    Write-Output "  Mode: $currentMode"
    Write-Output "  Registry: $RegistryPath"
    Write-Output "  DelegationConsole: $($current.DelegationConsole.Value)"
    Write-Output "  DelegationTerminal: $($current.DelegationTerminal.Value)"
    Write-Output "  Backup: $BackupPath"
    Write-Output "  Backup exists: $(Test-Path -LiteralPath $BackupPath -PathType Leaf)"
    exit 0
}

if ($Mode -eq "ConsoleHost") {
    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        if ($currentMode -eq "Windows Console Host") {
            Write-Warning "Windows Console Host is already selected, so no original-value backup was created."
        } else {
            Save-DefaultTerminalBackup -Path $RegistryPath -Destination $BackupPath -State $current
        }
    }

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        New-Item -ItemType Directory -Force -Path $RegistryPath | Out-Null
    }
    New-ItemProperty -LiteralPath $RegistryPath -Name "DelegationConsole" -Value $consoleHost -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $RegistryPath -Name "DelegationTerminal" -Value $consoleHost -PropertyType String -Force | Out-Null

    $configured = Get-DefaultTerminalState -Path $RegistryPath
    if ((Get-DefaultTerminalMode -State $configured) -ne "Windows Console Host") {
        throw "Windows Console Host delegation could not be verified."
    }

    Write-Output "Default terminal application: Windows Console Host"
    if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
        Write-Output "Backup: $BackupPath"
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
    throw "Default-terminal backup was not found: $BackupPath"
}

$backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
if ($backup.SchemaVersion -ne 1 -or [string]$backup.RegistryPath -ne $RegistryPath) {
    throw "Default-terminal backup does not match the requested registry path."
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    New-Item -ItemType Directory -Force -Path $RegistryPath | Out-Null
}
Set-RegistryStringState -Path $RegistryPath -Name "DelegationConsole" -State $backup.DelegationConsole
Set-RegistryStringState -Path $RegistryPath -Name "DelegationTerminal" -State $backup.DelegationTerminal

$restored = Get-DefaultTerminalState -Path $RegistryPath
if ([bool]$restored.DelegationConsole.Exists -ne [bool]$backup.DelegationConsole.Exists -or
    [bool]$restored.DelegationTerminal.Exists -ne [bool]$backup.DelegationTerminal.Exists -or
    [string]$restored.DelegationConsole.Value -ne [string]$backup.DelegationConsole.Value -or
    [string]$restored.DelegationTerminal.Value -ne [string]$backup.DelegationTerminal.Value) {
    throw "Default-terminal delegation could not be restored exactly."
}

Write-Output "Default terminal application restored from: $BackupPath"
