function Resolve-CodexDesktopPackage {
    $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if (-not $package) {
        throw "OpenAI.Codex AppX package was not found."
    }

    $manifest = Get-AppxPackageManifest -Package $package
    $application = $manifest.Package.Applications.Application | Select-Object -First 1
    if (-not $application -or -not $application.Executable) {
        throw "The Codex AppX manifest does not declare an executable."
    }

    $relativeExecutable = ([string]$application.Executable).Replace("/", "\")
    $executablePath = Join-Path $package.InstallLocation $relativeExecutable

    [pscustomobject]@{
        Package = $package
        ApplicationId = [string]$application.Id
        AppUserModelId = "$($package.PackageFamilyName)!$($application.Id)"
        ExecutablePath = $executablePath
        ProcessName = [System.IO.Path]::GetFileNameWithoutExtension($relativeExecutable)
    }
}

function Get-RunningCodexDesktopProcesses {
    param(
        [Parameter(Mandatory)]
        $PackageInfo
    )

    Get-Process -Name $PackageInfo.ProcessName -ErrorAction SilentlyContinue
}

function Get-CodexProcessStateHealth {
    param(
        [string]$Path = (Join-Path $env:USERPROFILE ".codex\process_manager\chat_processes.json")
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Path = $Path; Exists = $false; Invalid = $false; Reason = "missing" }
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0 -or -not ($bytes | Where-Object { $_ -ne 0 } | Select-Object -First 1)) {
        return [pscustomobject]@{ Path = $Path; Exists = $true; Invalid = $true; Reason = "empty-or-all-zero" }
    }

    try {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes).Trim([char]0).Trim()
        if (-not $text) {
            throw "Empty JSON content"
        }
        $null = $text | ConvertFrom-Json -ErrorAction Stop
        return [pscustomobject]@{ Path = $Path; Exists = $true; Invalid = $false; Reason = "valid-json" }
    }
    catch {
        return [pscustomobject]@{ Path = $Path; Exists = $true; Invalid = $true; Reason = "invalid-json" }
    }
}

function Backup-InvalidCodexProcessState {
    param(
        [string]$Path = (Join-Path $env:USERPROFILE ".codex\process_manager\chat_processes.json")
    )

    $health = Get-CodexProcessStateHealth -Path $Path
    if (-not $health.Exists -or -not $health.Invalid) {
        return $null
    }

    $backupPath = "$Path.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Move-Item -LiteralPath $Path -Destination $backupPath
    return $backupPath
}
