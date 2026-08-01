$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $repoRoot "scripts\install.ps1"
$tempConfigScript = Join-Path $repoRoot "scripts\configure-codex-temp.ps1"
$guardTestRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\wrapper-bin\guard-tests"
$testInstall = Join-Path $guardTestRoot "codex-wrapper-install-test-$PID"
$realGit = (Get-Command git.exe -All -CommandType Application | Where-Object {
    $_.Source -notlike "*codex-git-wrapper*" -and
    $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar).cache$([IO.Path]::DirectorySeparatorChar)codex-runtimes*" -and
    $_.Source -notlike "*$([IO.Path]::DirectorySeparatorChar)AppData$([IO.Path]::DirectorySeparatorChar)Local$([IO.Path]::DirectorySeparatorChar)OpenAI$([IO.Path]::DirectorySeparatorChar)Codex*"
} | Select-Object -First 1).Source
if (-not $realGit) {
    throw "No non-Codex Git installation was available for the install regression test."
}
$windowsPowerShell = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
    throw "Windows PowerShell was not available for the explicit override test."
}

function Get-PowerShellEdition {
    param([string]$FilePath)

    $edition = @(& $FilePath -NoLogo -NoProfile -NonInteractive -Command '$PSVersionTable.PSEdition' 2>$null) |
        Select-Object -Last 1
    if ($LASTEXITCODE -ne 0 -or -not $edition) {
        return $null
    }
    return $edition.Trim()
}

$realPowerShell7 = $null
$powerShell7Candidates = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe")
) + @(
    Get-Command pwsh.exe -All -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Source
)
foreach ($candidate in ($powerShell7Candidates | Select-Object -Unique)) {
    if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and
        (Get-PowerShellEdition -FilePath $candidate) -eq "Core") {
        $realPowerShell7 = (Resolve-Path -LiteralPath $candidate).Path
        break
    }
}
$expectedDefaultPowerShell = if ($realPowerShell7) { $realPowerShell7 } else { $windowsPowerShell }
$expectedDefaultEdition = if ($realPowerShell7) { "Core" } else { "Desktop" }
$guardEnvironmentNames = @("CODEX_REAL_GIT", "CODEX_REAL_POWERSHELL", "CODEX_REAL_CMD", "CODEX_TEMP_DIR")
$inheritedGuardEnvironment = @{}
foreach ($name in $guardEnvironmentNames) {
    $inheritedGuardEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
}

function Invoke-Wrapper {
    param([string]$FilePath, [string[]]$ArgumentList)

    $stdout = Join-Path $testInstall "$([System.IO.Path]::GetRandomFileName()).out"
    $stderr = Join-Path $testInstall "$([System.IO.Path]::GetRandomFileName()).err"
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $stdoutText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
    $stderrText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = if ($null -eq $stdoutText) { "" } else { $stdoutText.Trim() }
        Stderr = if ($null -eq $stderrText) { "" } else { $stderrText.Trim() }
    }
}

try {
    foreach ($name in $guardEnvironmentNames) {
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }

    & $installScript -InstallDir $testInstall

    if (-not (Test-Path -LiteralPath $tempConfigScript -PathType Leaf)) {
        throw "Codex temporary-directory configuration script is missing: $tempConfigScript"
    }

    $gitWrapper = Join-Path $testInstall "git.exe"
    $powerShellWrapper = Join-Path $testInstall "powershell.exe"
    $cmdWrapper = Join-Path $testInstall "cmd.exe"
    $codexGuardCommand = Join-Path $testInstall "codexguard.cmd"
    $consoleWindowGuard = Join-Path $testInstall "codex-console-window-guard.exe"
    if (-not (Test-Path -LiteralPath $gitWrapper)) {
        throw "Git wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $powerShellWrapper)) {
        throw "PowerShell wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $cmdWrapper)) {
        throw "Command Prompt wrapper was not installed."
    }
    if (-not (Test-Path -LiteralPath $codexGuardCommand -PathType Leaf)) {
        throw "CodexGuard command shim was not installed."
    }
    $codexGuardShim = Get-Content -LiteralPath $codexGuardCommand -Raw
    $expectedGuardScript = Join-Path $repoRoot "scripts\codex-guard.ps1"
    if ($codexGuardShim -notmatch [regex]::Escape($expectedGuardScript)) {
        throw "CodexGuard command shim does not point to the canonical command script."
    }
    if (Test-Path -LiteralPath (Join-Path $testInstall "codeguard.cmd") -PathType Leaf) {
        throw "Legacy codeguard command shim should not remain after installation."
    }
    $buildKind = (Get-Content -LiteralPath (Join-Path $testInstall 'wrapper-kind.txt') -Raw).Trim()
    if ($buildKind -like 'native-*' -and -not (Test-Path -LiteralPath $consoleWindowGuard)) {
        throw "Console window guard was not installed with the native wrapper build."
    }

    $originalPath = $env:Path
    try {
        $env:Path = "$testInstall;$originalPath"
        $resolvedCodexGuard = Get-Command codexguard -All -CommandType Application -ErrorAction Stop |
            Select-Object -First 1
        if ($resolvedCodexGuard.Source -ne $codexGuardCommand) {
            throw "Process-local PATH did not resolve codexguard to the installed shim. Resolved: $($resolvedCodexGuard.Source)"
        }
        $codexGuardHelp = @(& codexguard help)
        if ($LASTEXITCODE -ne 0 -or ($codexGuardHelp -join "`n") -notmatch "codexguard check") {
            throw "Installed codexguard command did not execute the canonical help output."
        }
    }
    finally {
        $env:Path = $originalPath
    }

    $configuredGit = (Get-Content -LiteralPath (Join-Path $testInstall 'real-git.txt') -Raw).Trim()
    $expectedGit = $realGit
    if ($realGit -match '[\\/]cmd[\\/]git\.exe$') {
        $directGit = Join-Path (Split-Path -Parent (Split-Path -Parent $realGit)) 'mingw64\bin\git.exe'
        if (Test-Path -LiteralPath $directGit) {
            $expectedGit = (Resolve-Path -LiteralPath $directGit).Path
        }
    }
    if ($configuredGit -ne $expectedGit) {
        throw "Installer did not select the direct Git executable. Expected: $expectedGit; Actual: $configuredGit"
    }
    if ($configuredGit -like "*$([IO.Path]::DirectorySeparatorChar).cache$([IO.Path]::DirectorySeparatorChar)codex-runtimes*") {
        throw "Installer selected Codex's private runtime Git instead of the user's Git installation: $configuredGit"
    }

    $configuredDefaultPowerShell = (Get-Content -LiteralPath (Join-Path $testInstall 'real-powershell.txt') -Raw).Trim()
    if ($configuredDefaultPowerShell -ne $expectedDefaultPowerShell) {
        throw "Installer did not select the expected default PowerShell. Expected: $expectedDefaultPowerShell; Actual: $configuredDefaultPowerShell"
    }

    $gitResult = Invoke-Wrapper -FilePath $gitWrapper -ArgumentList @("--version")
    if ($gitResult.ExitCode -ne 0 -or $gitResult.Stdout -notmatch '^git version ') {
        throw "Git wrapper did not forward correctly: $($gitResult.Stdout) $($gitResult.Stderr)"
    }

    $powerShellResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", "Write-Output 'wrapper-powershell-ok'")
    if ($powerShellResult.ExitCode -ne 0 -or $powerShellResult.Stdout -ne "wrapper-powershell-ok") {
        throw "PowerShell wrapper did not forward correctly: $($powerShellResult.Stdout) $($powerShellResult.Stderr)"
    }

    $defaultEditionResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", '$PSVersionTable.PSEdition')
    if ($defaultEditionResult.ExitCode -ne 0 -or $defaultEditionResult.Stdout -ne $expectedDefaultEdition) {
        throw "PowerShell wrapper did not use the expected default edition: $($defaultEditionResult.Stdout) $($defaultEditionResult.Stderr)"
    }

    $legacyCommand = Join-Path $testInstall "codeguard.cmd"
    Set-Content -LiteralPath $legacyCommand -Value "legacy" -Encoding ASCII
    & $installScript -InstallDir $testInstall -RealPowerShell $windowsPowerShell
    if (Test-Path -LiteralPath $legacyCommand -PathType Leaf) {
        throw "Installer did not remove the legacy codeguard command shim."
    }
    $configuredOverridePowerShell = (Get-Content -LiteralPath (Join-Path $testInstall 'real-powershell.txt') -Raw).Trim()
    if ($configuredOverridePowerShell -ne $windowsPowerShell) {
        throw "Installer did not preserve the explicit Windows PowerShell override. Expected: $windowsPowerShell; Actual: $configuredOverridePowerShell"
    }
    $overrideEditionResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", '$PSVersionTable.PSEdition')
    if ($overrideEditionResult.ExitCode -ne 0 -or $overrideEditionResult.Stdout -ne "Desktop") {
        throw "PowerShell wrapper did not honor the explicit Windows PowerShell override: $($overrideEditionResult.Stdout) $($overrideEditionResult.Stderr)"
    }

    $managedCsc = @(
        (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
        (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($managedCsc) {
        $managedWrapperDir = Join-Path $testInstall "managed-wrapper"
        $managedPowerShellWrapper = Join-Path $managedWrapperDir "powershell.exe"
        $managedPowerShellConfig = Join-Path $managedWrapperDir "real-powershell.txt"
        New-Item -ItemType Directory -Force -Path $managedWrapperDir | Out-Null
        & $managedCsc /nologo /target:winexe "/out:$managedPowerShellWrapper" (Join-Path $repoRoot "src\GitHiddenWrapper.cs")
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $managedPowerShellWrapper -PathType Leaf)) {
            throw "Managed C# wrapper compilation failed."
        }

        Set-Content -LiteralPath $managedPowerShellConfig -Value $expectedDefaultPowerShell -Encoding ASCII
        $managedConfiguredResult = Invoke-Wrapper -FilePath $managedPowerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", '$PSVersionTable.PSEdition')
        if ($managedConfiguredResult.ExitCode -ne 0 -or $managedConfiguredResult.Stdout -ne $expectedDefaultEdition) {
            throw "Managed PowerShell wrapper did not honor the configured default: $($managedConfiguredResult.Stdout) $($managedConfiguredResult.Stderr)"
        }

        Set-Content -LiteralPath $managedPowerShellConfig -Value $windowsPowerShell -Encoding ASCII
        $managedOverrideResult = Invoke-Wrapper -FilePath $managedPowerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", '$PSVersionTable.PSEdition')
        if ($managedOverrideResult.ExitCode -ne 0 -or $managedOverrideResult.Stdout -ne "Desktop") {
            throw "Managed PowerShell wrapper did not honor the explicit Windows PowerShell override: $($managedOverrideResult.Stdout) $($managedOverrideResult.Stderr)"
        }

        Set-Content -LiteralPath $managedPowerShellConfig -Value "" -Encoding ASCII
        $managedFallbackResult = Invoke-Wrapper -FilePath $managedPowerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", '$PSVersionTable.PSEdition')
        if ($managedFallbackResult.ExitCode -ne 0 -or $managedFallbackResult.Stdout -ne $expectedDefaultEdition) {
            throw "Managed PowerShell wrapper did not use the expected fallback edition: $($managedFallbackResult.Stdout) $($managedFallbackResult.Stderr)"
        }
    }

    $sleepCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Start-Sleep -Seconds 30"))
    $wrapperLockProcess = Start-Process -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-EncodedCommand", $sleepCommand) -PassThru
    $unrelatedPowerShellProcess = Start-Process -FilePath $windowsPowerShell -ArgumentList @("-NoProfile", "-NonInteractive", "-EncodedCommand", $sleepCommand) -PassThru
    try {
        $deadline = (Get-Date).AddSeconds(5)
        do {
            $runningWrapper = Get-Process -Id $wrapperLockProcess.Id -ErrorAction SilentlyContinue
            $wrapperIsLocked = $false
            if ($runningWrapper) {
                try {
                    $wrapperIsLocked = $runningWrapper.Path -eq $powerShellWrapper
                }
                catch {
                    $wrapperIsLocked = $false
                }
            }
            if ($wrapperIsLocked) {
                break
            }
            Start-Sleep -Milliseconds 100
        } while ((Get-Date) -lt $deadline)

        if (-not $wrapperIsLocked) {
            throw "Test wrapper PowerShell process did not remain running at the expected path."
        }

        & $installScript -InstallDir $testInstall -RealGit $realGit -RealPowerShell $windowsPowerShell -StopWrapperProcesses

        if (Get-Process -Id $wrapperLockProcess.Id -ErrorAction SilentlyContinue) {
            throw "Forced wrapper refresh did not stop the locked wrapper process."
        }
        if (-not (Get-Process -Id $unrelatedPowerShellProcess.Id -ErrorAction SilentlyContinue)) {
            throw "Forced wrapper refresh stopped an unrelated PowerShell process."
        }

        $refreshedPowerShellResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", "Write-Output 'wrapper-refresh-ok'")
        if ($refreshedPowerShellResult.ExitCode -ne 0 -or $refreshedPowerShellResult.Stdout -ne "wrapper-refresh-ok") {
            throw "PowerShell wrapper did not work after the forced refresh: $($refreshedPowerShellResult.Stdout) $($refreshedPowerShellResult.Stderr)"
        }
    }
    finally {
        foreach ($process in @($wrapperLockProcess, $unrelatedPowerShellProcess)) {
            if ($process -and (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $codexTemp = Join-Path $testInstall "codex-temp"
    & $tempConfigScript -Mode Enable -TempDir $codexTemp -InstallDir $testInstall
    $tempProbeCommand = '$env:TEMP + "|" + $env:TMP'
    $encodedTempProbe = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($tempProbeCommand))
    $tempProbeResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-EncodedCommand", $encodedTempProbe)
    $expectedTempProbe = "$codexTemp|$codexTemp"
    if ($tempProbeResult.ExitCode -ne 0 -or $tempProbeResult.Stdout -ne $expectedTempProbe) {
        throw "PowerShell wrapper did not inherit the configured Codex TEMP/TMP: $($tempProbeResult.Stdout) $($tempProbeResult.Stderr)"
    }

    $cmdResult = Invoke-Wrapper -FilePath $cmdWrapper -ArgumentList @("/d", "/s", "/c", "echo wrapper-cmd-ok")
    if ($cmdResult.ExitCode -ne 0 -or $cmdResult.Stdout -ne "wrapper-cmd-ok") {
        throw "Command Prompt wrapper did not forward correctly: $($cmdResult.Stdout) $($cmdResult.Stderr)"
    }

    $sampleCommand = "`$ErrorActionPreference = 'Stop'; Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId | ConvertTo-Json -Depth 2"
    $quotedSample = '"' + $sampleCommand.Replace('"', '\"') + '"'
    $env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING = "1"
    try {
        $samplingResult = Invoke-Wrapper -FilePath $powerShellWrapper -ArgumentList @("-NoProfile", "-NonInteractive", "-Command", $quotedSample)
    } finally {
        Remove-Item Env:CODEX_WRAPPER_SUPPRESS_PROCESS_SAMPLING -ErrorAction SilentlyContinue
    }
    if ($samplingResult.ExitCode -ne 0 -or $samplingResult.Stdout -ne "[]") {
        throw "Process sampling was not suppressed: $($samplingResult.Stdout) $($samplingResult.Stderr)"
    }

    Write-Output "Install regression checks: PASS"
}
finally {
    if ($testInstall -notlike "$(Join-Path $guardTestRoot 'codex-wrapper-install-test-*')") {
        throw "Refusing to remove an unexpected test path: $testInstall"
    }
    Remove-Item -LiteralPath $testInstall -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($name in $guardEnvironmentNames) {
        $inheritedValue = $inheritedGuardEnvironment[$name]
        if ($null -eq $inheritedValue) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item -LiteralPath "Env:$name" -Value $inheritedValue
        }
    }
}
