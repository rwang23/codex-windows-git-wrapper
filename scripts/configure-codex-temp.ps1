param(
    [ValidateSet("Status", "Enable", "Disable")]
    [string]$Mode = "Status",
    [string]$TempDir,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin")
)

$ErrorActionPreference = "Stop"

$configPath = Join-Path $InstallDir "codex-temp-dir.txt"
$backupPath = Join-Path $InstallDir "codex-temp-dir.backup.txt"

function Get-ConfiguredTempDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    $value = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return [Environment]::ExpandEnvironmentVariables($value)
}

function Write-TextWithoutBom {
    param(
        [string]$Path,
        [string]$Value
    )

    $parent = Split-Path -Parent $Path
    if ($parent) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $encoding = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, ($Value + [Environment]::NewLine), $encoding)
}

function Resolve-CodexTempDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "-TempDir is required when enabling the Codex temporary directory."
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if (-not [IO.Path]::IsPathRooted($expanded)) {
        throw "-TempDir must be an absolute path: $Path"
    }

    $fullPath = [IO.Path]::GetFullPath($expanded)
    New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
    $item = Get-Item -LiteralPath $fullPath -Force
    if (-not $item.PSIsContainer) {
        throw "The configured Codex temporary path is not a directory: $fullPath"
    }

    return $item.FullName
}

if ($Mode -eq "Status") {
    $configured = Get-ConfiguredTempDirectory -Path $configPath
    Write-Output "  Enabled: $([bool]$configured)"
    Write-Output "  Config: $configPath"
    if ($configured) {
        Write-Output "  Directory: $configured"
        Write-Output "  Exists: $(Test-Path -LiteralPath $configured -PathType Container)"
    }
    Write-Output "  Backup: $backupPath"
    Write-Output "  Backup exists: $(Test-Path -LiteralPath $backupPath -PathType Leaf)"
    return
}

if ($Mode -eq "Enable") {
    $resolvedTempDir = Resolve-CodexTempDirectory -Path $TempDir
    $existing = Get-ConfiguredTempDirectory -Path $configPath
    if ((Test-Path -LiteralPath $configPath -PathType Leaf) -and
        $existing -ne $resolvedTempDir -and
        -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $configPath -Destination $backupPath
    }

    Write-TextWithoutBom -Path $configPath -Value $resolvedTempDir
    $readback = Get-ConfiguredTempDirectory -Path $configPath
    if ($readback -ne $resolvedTempDir -or -not (Test-Path -LiteralPath $readback -PathType Container)) {
        throw "The Codex temporary directory could not be verified."
    }

    Write-Output "Codex wrapper temporary directory: $readback"
    Write-Output "This applies only to child processes launched through the Codex wrappers; user and system TEMP/TMP are unchanged."
    return
}

if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
    Copy-Item -LiteralPath $backupPath -Destination $configPath -Force
    Remove-Item -LiteralPath $backupPath -Force
    Write-Output "Restored the previous Codex wrapper temporary-directory configuration."
} elseif (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Remove-Item -LiteralPath $configPath -Force
    Write-Output "Disabled the Codex wrapper temporary-directory configuration."
} else {
    Write-Output "No Codex wrapper temporary-directory configuration is present."
}

Write-Output "The temporary directory itself was left unchanged."
