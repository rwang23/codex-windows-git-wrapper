<#
.SYNOPSIS
Captures a read-only Codex Desktop and local service process snapshot.

.DESCRIPTION
Reads the current Windows process tree, groups stdio/MCP service roots beneath
each Codex app-server, and reports aggregate memory plus detached candidates.
It also checks the BB Browser daemon registration and listener ownership without
serializing its authentication token. The script does not start, stop, suspend,
or modify processes, files, services, configuration, or the registry.

.PARAMETER AsJson
Writes the versioned snapshot object as JSON instead of the human-readable view.
#>
[CmdletBinding()]
param(
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$capturedAtUtc = [DateTime]::UtcNow.ToString("o")
$allProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop)
$processById = @{}
$childrenByParent = @{}

foreach ($process in $allProcesses) {
    $processId = [int]$process.ProcessId
    $parentId = [int]$process.ParentProcessId
    $processById[$processId] = $process
    if (-not $childrenByParent.ContainsKey($parentId)) {
        $childrenByParent[$parentId] = [System.Collections.ArrayList]::new()
    }
    [void]$childrenByParent[$parentId].Add($processId)
}

function Get-DescendantIds {
    param([int]$RootProcessId)

    $result = [System.Collections.ArrayList]::new()
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($RootProcessId)
    while ($queue.Count -gt 0) {
        $parentId = [int]$queue.Dequeue()
        if (-not $script:childrenByParent.ContainsKey($parentId)) {
            continue
        }
        foreach ($childId in $script:childrenByParent[$parentId]) {
            [void]$result.Add([int]$childId)
            $queue.Enqueue([int]$childId)
        }
    }
    return @($result)
}

function Get-ServiceKind {
    param($ProcessRecord)

    $name = [string]$ProcessRecord.Name
    $commandLine = [string]$ProcessRecord.CommandLine
    if ($name -ieq "node_repl.exe") {
        return "node-repl"
    }
    if ($commandLine -match '(?i)bb-browser.*daemon\.js|daemon\.js.*--cdp-(host|port)') {
        return "bb-browser-daemon"
    }
    if ($commandLine -match '(?i)codegraph(\.js)?\b|@colbymchenry[\\/]codegraph') {
        return "codegraph"
    }
    if ($commandLine -match '(?i)(^|[\\/])mcp[\\/]server\.cjs\b') {
        return "plugin-mcp-cjs"
    }
    if ($commandLine -match '(?i)(^|[\\/])mcp[\\/]server\.mjs\b') {
        return "plugin-mcp-mjs"
    }
    if ($commandLine -match '(?i)\bmcp-remote\b') {
        return "mcp-remote"
    }
    if ($commandLine -match '(?i)(--mcp\b|--stdio\b|\bmcp[_-]server\b)') {
        return "stdio-service"
    }
    return $null
}

function Get-ProcessMetrics {
    param([int]$ProcessId)

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        $startedAtUtc = $null
        try {
            $startedAtUtc = $process.StartTime.ToUniversalTime().ToString("o")
        } catch {
            $startedAtUtc = $null
        }
        return [pscustomobject][ordered]@{
            ProcessId = $ProcessId
            PrivateMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 1)
            WorkingSetMB = [math]::Round($process.WorkingSet64 / 1MB, 1)
            CpuSeconds = if ($null -eq $process.CPU) { 0.0 } else { [math]::Round([double]$process.CPU, 2) }
            StartedAtUtc = $startedAtUtc
        }
    } catch {
        return $null
    }
}

function Get-SubtreeMetrics {
    param([int]$RootProcessId)

    $ids = @($RootProcessId) + @(Get-DescendantIds -RootProcessId $RootProcessId)
    $metrics = @($ids | ForEach-Object { Get-ProcessMetrics -ProcessId $_ } | Where-Object { $null -ne $_ })
    $privateTotal = ($metrics | Measure-Object -Property PrivateMB -Sum).Sum
    $workingSetTotal = ($metrics | Measure-Object -Property WorkingSetMB -Sum).Sum
    $cpuTotal = ($metrics | Measure-Object -Property CpuSeconds -Sum).Sum
    return [pscustomobject][ordered]@{
        ProcessCount = $metrics.Count
        PrivateMB = [math]::Round([double]$privateTotal, 1)
        WorkingSetMB = [math]::Round([double]$workingSetTotal, 1)
        CpuSeconds = [math]::Round([double]$cpuTotal, 2)
    }
}

$appServerProcesses = @($allProcesses | Where-Object {
    $_.Name -ieq "codex.exe" -and ([string]$_.CommandLine) -match '(?i)\bapp-server\b'
})
$appServerReports = [System.Collections.ArrayList]::new()
$allServiceRoots = [System.Collections.ArrayList]::new()
$appServerDescendants = @{}

foreach ($appServer in $appServerProcesses) {
    $appServerId = [int]$appServer.ProcessId
    $descendantIds = @(Get-DescendantIds -RootProcessId $appServerId)
    foreach ($descendantId in $descendantIds) {
        $appServerDescendants[[int]$descendantId] = $true
    }

    $candidateKinds = @{}
    foreach ($descendantId in $descendantIds) {
        if (-not $processById.ContainsKey([int]$descendantId)) {
            continue
        }
        $kind = Get-ServiceKind -ProcessRecord $processById[[int]$descendantId]
        if ($kind) {
            $candidateKinds[[int]$descendantId] = $kind
        }
    }

    $serviceRootIds = [System.Collections.ArrayList]::new()
    foreach ($candidateId in $candidateKinds.Keys) {
        $ancestorId = [int]$processById[[int]$candidateId].ParentProcessId
        $hasServiceAncestor = $false
        while ($ancestorId -ne 0 -and $ancestorId -ne $appServerId) {
            if ($candidateKinds.ContainsKey($ancestorId)) {
                $hasServiceAncestor = $true
                break
            }
            if (-not $processById.ContainsKey($ancestorId)) {
                break
            }
            $ancestorId = [int]$processById[$ancestorId].ParentProcessId
        }
        if (-not $hasServiceAncestor) {
            [void]$serviceRootIds.Add([int]$candidateId)
        }
    }

    $serviceRoots = [System.Collections.ArrayList]::new()
    foreach ($serviceRootId in ($serviceRootIds | Sort-Object)) {
        $record = $processById[[int]$serviceRootId]
        $metrics = Get-SubtreeMetrics -RootProcessId ([int]$serviceRootId)
        $rootMetrics = Get-ProcessMetrics -ProcessId ([int]$serviceRootId)
        $serviceRoot = [pscustomobject][ordered]@{
            ProcessId = [int]$serviceRootId
            ParentProcessId = [int]$record.ParentProcessId
            Kind = [string]$candidateKinds[[int]$serviceRootId]
            StartedAtUtc = if ($rootMetrics) { $rootMetrics.StartedAtUtc } else { $null }
            ProcessCount = $metrics.ProcessCount
            PrivateMB = $metrics.PrivateMB
            WorkingSetMB = $metrics.WorkingSetMB
            CpuSeconds = $metrics.CpuSeconds
        }
        [void]$serviceRoots.Add($serviceRoot)
        [void]$allServiceRoots.Add($serviceRoot)
    }

    $appMetrics = Get-ProcessMetrics -ProcessId $appServerId
    $parentId = [int]$appServer.ParentProcessId
    $parentName = if ($processById.ContainsKey($parentId)) { [string]$processById[$parentId].Name } else { $null }
    $hostKind = if ($parentName -ieq "ChatGPT.exe") { "desktop" } elseif ($parentName) { "other" } else { "detached" }
    [void]$appServerReports.Add([pscustomobject][ordered]@{
        ProcessId = $appServerId
        ParentProcessId = $parentId
        ParentName = $parentName
        HostKind = $hostKind
        StartedAtUtc = if ($appMetrics) { $appMetrics.StartedAtUtc } else { $null }
        PrivateMB = if ($appMetrics) { $appMetrics.PrivateMB } else { 0.0 }
        WorkingSetMB = if ($appMetrics) { $appMetrics.WorkingSetMB } else { 0.0 }
        DescendantCount = $descendantIds.Count
        ServiceRootCount = $serviceRoots.Count
        ServiceRoots = @($serviceRoots)
    })
}

$aggregateByKind = @($allServiceRoots |
    Group-Object -Property Kind |
    Sort-Object -Property Name |
    ForEach-Object {
        [pscustomobject][ordered]@{
            Kind = $_.Name
            RootCount = $_.Count
            ProcessCount = [int](($_.Group | Measure-Object -Property ProcessCount -Sum).Sum)
            PrivateMB = [math]::Round([double](($_.Group | Measure-Object -Property PrivateMB -Sum).Sum), 1)
            WorkingSetMB = [math]::Round([double](($_.Group | Measure-Object -Property WorkingSetMB -Sum).Sum), 1)
        }
    })

$detachedCandidates = [System.Collections.ArrayList]::new()
foreach ($process in $allProcesses) {
    $processId = [int]$process.ProcessId
    if ($appServerDescendants.ContainsKey($processId)) {
        continue
    }
    $kind = Get-ServiceKind -ProcessRecord $process
    if (-not $kind) {
        continue
    }
    $parentId = [int]$process.ParentProcessId
    if ($parentId -ne 0 -and $processById.ContainsKey($parentId)) {
        continue
    }
    $metrics = Get-ProcessMetrics -ProcessId $processId
    [void]$detachedCandidates.Add([pscustomobject][ordered]@{
        ProcessId = $processId
        ParentProcessId = $parentId
        Kind = $kind
        Disposition = if ($kind -eq "bb-browser-daemon") { "expected-detached-service" } else { "review-candidate" }
        StartedAtUtc = if ($metrics) { $metrics.StartedAtUtc } else { $null }
        PrivateMB = if ($metrics) { $metrics.PrivateMB } else { 0.0 }
        WorkingSetMB = if ($metrics) { $metrics.WorkingSetMB } else { 0.0 }
    })
}

$bbRegistrationPath = Join-Path $env:USERPROFILE ".bb-browser\daemon.json"
$bbRegistered = Test-Path -LiteralPath $bbRegistrationPath -PathType Leaf
$bbDaemonId = $null
$bbPort = $null
$bbCdpPort = $null
if ($bbRegistered) {
    try {
        $bbRegistration = Get-Content -LiteralPath $bbRegistrationPath -Raw | ConvertFrom-Json
        $bbDaemonId = [int]$bbRegistration.pid
        $bbPort = [int]$bbRegistration.port
        $bbCdpPort = [int]$bbRegistration.cdpPort
    } catch {
        $bbRegistered = $false
    }
}

$bbPortOwner = $null
$bbCdpPortOwner = $null
try {
    if ($bbPort) {
        $listener = Get-NetTCPConnection -LocalPort $bbPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) { $bbPortOwner = [int]$listener.OwningProcess }
    }
    if ($bbCdpPort) {
        $listener = Get-NetTCPConnection -LocalPort $bbCdpPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($listener) { $bbCdpPortOwner = [int]$listener.OwningProcess }
    }
} catch {
    $bbPortOwner = $null
    $bbCdpPortOwner = $null
}

$bbBrowser = [pscustomobject][ordered]@{
    Registered = [bool]$bbRegistered
    DaemonProcessId = $bbDaemonId
    DaemonPort = $bbPort
    DaemonPortOwnerProcessId = $bbPortOwner
    CdpPort = $bbCdpPort
    CdpPortOwnerProcessId = $bbCdpPortOwner
    Healthy = [bool]($bbRegistered -and $bbDaemonId -and $bbPortOwner -eq $bbDaemonId -and $bbCdpPortOwner)
}

$packageVersion = $null
try {
    $scriptsDir = Split-Path -Parent $PSCommandPath
    . (Join-Path $scriptsDir "codex-package.ps1")
    $packageInfo = Resolve-CodexDesktopPackage
    if ($packageInfo.Package) {
        $packageVersion = [string]$packageInfo.Package.Version
    }
} catch {
    $packageVersion = $null
}

$snapshot = [pscustomobject][ordered]@{
    SchemaVersion = 1
    CapturedAtUtc = $capturedAtUtc
    ReadOnly = $true
    CodexDesktopPackageVersion = $packageVersion
    AppServerCount = $appServerReports.Count
    AppServers = @($appServerReports)
    AggregateByKind = @($aggregateByKind)
    DetachedCandidates = @($detachedCandidates)
    BbBrowser = $bbBrowser
}

if ($AsJson) {
    $snapshot | ConvertTo-Json -Depth 8
    return
}

Write-Output "Codex health snapshot (read-only)"
Write-Output "Captured UTC: $($snapshot.CapturedAtUtc)"
Write-Output "Desktop package: $($snapshot.CodexDesktopPackageVersion)"
Write-Output "App servers: $($snapshot.AppServerCount)"
Write-Output ""
Write-Output "Service roots by kind:"
if ($snapshot.AggregateByKind.Count -gt 0) {
    $snapshot.AggregateByKind | Format-Table Kind, RootCount, ProcessCount, PrivateMB, WorkingSetMB -AutoSize | Out-String -Width 200 | Write-Output
} else {
    Write-Output "  None"
}

Write-Output "BB Browser:"
Write-Output "  Registered: $($snapshot.BbBrowser.Registered)"
Write-Output "  Healthy: $($snapshot.BbBrowser.Healthy)"
Write-Output "  Daemon PID/port: $($snapshot.BbBrowser.DaemonProcessId) / $($snapshot.BbBrowser.DaemonPort)"
Write-Output "  CDP owner/port: $($snapshot.BbBrowser.CdpPortOwnerProcessId) / $($snapshot.BbBrowser.CdpPort)"
Write-Output ""
Write-Output "Detached service candidates:"
if ($snapshot.DetachedCandidates.Count -gt 0) {
    $snapshot.DetachedCandidates | Format-Table ProcessId, ParentProcessId, Kind, Disposition, PrivateMB, WorkingSetMB -AutoSize | Out-String -Width 200 | Write-Output
} else {
    Write-Output "  None"
}
