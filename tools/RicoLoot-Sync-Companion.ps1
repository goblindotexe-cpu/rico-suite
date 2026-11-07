#Requires -Version 5.1
<#
.SYNOPSIS
Runs the local companion for RicoLoot's Fetch latest button.
.DESCRIPTION
Reads only the standalone RicoLootSyncRequest marker from RicoLoot's saved
variables. It never executes or uploads SavedVariables. Valid fresh requests
invoke the public-JSON updater and write a small status file for the next UI
reload. Data and status files live in the separate RicoLootEverloot cache addon.
The companion runs in the current Windows session until asked to stop.
#>
[CmdletBinding()]
param(
    [ValidateSet('Run','Start','Stop','Once')][string]$Mode = 'Run',
    [string]$GameDirectory,
    [switch]$FunctionsOnly
)

$script:RicoLootCompanionRoot = $PSScriptRoot
$script:RicoLootRequestCache = @{}
$companionImportOnly = [bool]$FunctionsOnly
$updaterScript = Join-Path $PSScriptRoot 'RicoLoot-Everloot-Updater.ps1'
if (-not [IO.File]::Exists($updaterScript)) { throw 'Keep the companion beside RicoLoot-Everloot-Updater.ps1.' }
. $updaterScript -FunctionsOnly

function Get-RicoLootUnixTime {
    return [long][math]::Floor(([DateTimeOffset]::UtcNow - [DateTimeOffset]'1970-01-01T00:00:00Z').TotalSeconds)
}

function Get-RicoLootRequestFromText {
    param([AllowEmptyString()][string]$Text, [long]$NowUnix = (Get-RicoLootUnixTime))
    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -gt 10MB) { return $null }
    $pattern = '(?m)^[ \t]*RicoLootSyncRequest[ \t]*=[ \t]*"(?<request>RICOLOOT-SYNC-1:(?<seconds>[0-9]{10}):(?<nonce>[A-Za-z0-9_-]{8,64}))"[ \t]*;?[ \t]*\r?$'
    $candidates = [regex]::Matches($Text, $pattern)
    if ($candidates.Count -eq 0) { return $null }
    # Recognise comments, quoted strings, long strings and nesting. A lookalike
    # marker inside somebody else's data or a comment is never an instruction.
    $lexical = '(?s)(?<comment>--\[(?<ceq>=*)\[.*?(?:\]\k<ceq>\]|$)|--[^\r\n]*)|(?<quoted>"(?:\\.|[^"\\])*(?:"|$)|''(?:\\.|[^''\\])*(?:''|$))|(?<long>\[(?<seq>=*)\[.*?(?:\]\k<seq>\]|$))|(?<open>[{(\[])|(?<close>[})\]])|(?<block>\b(?:function|if|do|repeat|end|until)\b)'
    $tokens = [regex]::Matches($Text, $lexical)
    $accepted = New-Object 'System.Collections.Generic.List[object]'
    foreach ($candidate in $candidates) {
        $depth, $blocks, $inside = 0, 0, $false
        foreach ($token in $tokens) {
            if ($token.Index -ge $candidate.Index) { break }
            if (($token.Index + $token.Length) -gt $candidate.Index) { $inside = $true; break }
            if ($token.Groups['open'].Success) { $depth++ }
            elseif ($token.Groups['close'].Success) { $depth-- }
            elseif ($token.Groups['block'].Success) {
                if ($token.Value -in @('end','until')) { $blocks-- } else { $blocks++ }
            }
        }
        if ($inside -or $depth -ne 0 -or $blocks -ne 0) { continue }
        $seconds = [long]$candidate.Groups['seconds'].Value
        if ($seconds -lt ($NowUnix - 600) -or $seconds -gt ($NowUnix + 120)) { continue }
        $accepted.Add([pscustomobject]@{
            RequestId=$candidate.Groups['request'].Value; UnixSeconds=$seconds; Nonce=$candidate.Groups['nonce'].Value
        })
    }
    if ($accepted.Count -ne 1) { return $null }
    return $accepted[0]
}

function Get-RicoLootSyncRequests {
    param([Parameter(Mandatory=$true)][string]$AccountRoot, [long]$NowUnix = (Get-RicoLootUnixTime))
    if (-not [IO.Directory]::Exists($AccountRoot)) { return }
    $root = [IO.Path]::GetFullPath($AccountRoot).TrimEnd('\','/')
    $directories = [IO.DirectoryInfo]::new($root).GetDirectories()
    foreach ($account in $directories) {
        if (($account.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $savedDirectory = Join-Path $account.FullName 'SavedVariables'
        if (-not [IO.Directory]::Exists($savedDirectory)) { continue }
        $savedInfo = [IO.DirectoryInfo]::new($savedDirectory)
        if (($savedInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $path = [IO.Path]::GetFullPath((Join-Path $savedDirectory 'RicoLoot.lua'))
        if (-not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or -not [IO.File]::Exists($path)) { continue }
        try {
            $info = [IO.FileInfo]::new($path)
            if ($info.Length -gt 10MB -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $cache = $script:RicoLootRequestCache[$path]
            if ($null -ne $cache -and $cache.Ticks -eq $info.LastWriteTimeUtc.Ticks -and $cache.Length -eq $info.Length) {
                $request = $cache.Request
            } else {
                $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
                try {
                    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8, $true)
                    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
                } finally { $stream.Dispose() }
                $request = Get-RicoLootRequestFromText -Text $text -NowUnix $NowUnix
                $script:RicoLootRequestCache[$path] = @{ Ticks=$info.LastWriteTimeUtc.Ticks; Length=$info.Length; Request=$request }
            }
            if ($null -ne $request -and $request.UnixSeconds -ge ($NowUnix - 600) -and $request.UnixSeconds -le ($NowUnix + 120)) {
                [pscustomobject]@{ RequestId=$request.RequestId; UnixSeconds=$request.UnixSeconds; Nonce=$request.Nonce; File=$path }
            }
        } catch {
            # A game save may be in progress. Read again on the next pass.
            $script:RicoLootRequestCache.Remove($path)
        }
    }
}

function Write-RicoLootSyncStatus {
    param([string]$CacheDirectory, [string]$RequestId, [ValidateSet('fetching','success','error')][string]$State,
        [string]$Message, [string]$CheckedAt, [string]$ErrorCode = '')
    if ($RequestId -notmatch '^RICOLOOT-SYNC-1:[0-9]{10}:[A-Za-z0-9_-]{8,64}$') { throw 'Invalid companion request ID.' }
    if ($Message.Length -gt 200) { $Message = $Message.Substring(0, 200) }
    $lua = "-- Local RicoLoot sync status; no player data.`nlocal _, Cache = ...`nfunction Cache.ApplyStatus(R)`nR.Data.syncStatus = { schema=1, requestId=" +
        (ConvertTo-EverlootLuaString $RequestId) + ', state=' + (ConvertTo-EverlootLuaString $State) +
        ', checkedAt=' + (ConvertTo-EverlootLuaString $CheckedAt) + ', message=' + (ConvertTo-EverlootLuaString $Message) +
        ', errorCode=' + (ConvertTo-EverlootLuaString $ErrorCode) + " }`nend`n"
    $null = Write-AtomicUtf8 -Path (Join-Path $CacheDirectory 'DataSyncStatus.lua') -Content $lua
}

function Show-RicoLootCompanionNotice {
    param([bool]$Succeeded)
    $notice = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $notice = New-Object Windows.Forms.NotifyIcon
        $notice.Icon = [Drawing.SystemIcons]::Information
        $notice.Text = 'RicoLoot database updater'
        $notice.Visible = $true
        $message = if ($Succeeded) { 'Everloot check completed. Click Reload & view in RicoLoot.' }
            else { 'Everloot check failed. Your working database was kept. Reload RicoLoot to view the status.' }
        $notice.ShowBalloonTip(4500, 'RicoLoot', $message, [Windows.Forms.ToolTipIcon]::Info)
        $until = [DateTimeOffset]::UtcNow.AddSeconds(4)
        while ([DateTimeOffset]::UtcNow -lt $until) { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    } catch {
        # A notification is optional; the status file remains authoritative.
    } finally { if ($null -ne $notice) { $notice.Dispose() } }
}

function Invoke-RicoLootCompanionPass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$GameDirectory,
        [string]$StateDirectory = (Join-Path $script:RicoLootCompanionRoot 'updater-state'),
        [long]$NowUnix = (Get-RicoLootUnixTime),
        [switch]$Notify,
        [scriptblock]$UpdateAction = { param($requestId, $addon) Invoke-RicoLootUpdate -AddonDirectory $addon -RequestId $requestId }
    )
    $game = [IO.Path]::GetFullPath($GameDirectory)
    $addon = Join-Path $game 'Interface\AddOns\RicoLoot'
    if (-not [IO.File]::Exists((Join-Path $addon 'RicoLoot.toc')) -or -not [IO.File]::Exists((Join-Path $addon 'Data.lua'))) {
        throw 'The configured game drive or RicoLoot installation is unavailable.'
    }
    $stateRoot = [IO.Path]::GetFullPath($StateDirectory)
    $null = [IO.Directory]::CreateDirectory($stateRoot)
    $passLock = $null
    try {
        try { $passLock = [IO.File]::Open((Join-Path $stateRoot 'companion-pass.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { return }
        $statePath = Join-Path $stateRoot 'companion-requests.json'
        $processed = New-Object 'System.Collections.Generic.List[string]'
        if ([IO.File]::Exists($statePath)) {
            $saved = ConvertFrom-EverlootJson ([IO.File]::ReadAllText($statePath))
            if ($saved.schema -ne 1 -or -not (Test-EverlootProperty $saved 'processedIds')) { throw 'Companion request state is invalid.' }
            foreach ($id in @($saved.processedIds)) {
                if ($id -isnot [string] -or $id -notmatch '^RICOLOOT-SYNC-1:[0-9]{10}:[A-Za-z0-9_-]{8,64}$') { throw 'Companion request state is invalid.' }
                if (-not $processed.Contains($id)) { $processed.Add($id) }
            }
        }
        $accountRoot = Join-Path $game 'WTF\Account'
        $requests = @(Get-RicoLootSyncRequests -AccountRoot $accountRoot -NowUnix $NowUnix | Sort-Object UnixSeconds,RequestId)
        $cache = $null
        foreach ($request in $requests) {
            if ($processed.Contains($request.RequestId)) { continue }
            if ($null -eq $cache) { $cache = Get-RicoLootEverlootCache -AddonDirectory $addon }
            # Persist consumption before fetching, so a crash never loops the same
            # request against the public API. A new button click creates a new ID.
            $processed.Add($request.RequestId)
            while ($processed.Count -gt 256) { $processed.RemoveAt(0) }
            $state = [ordered]@{ schema=1; processedIds=@($processed.ToArray()) }
            $null = Write-AtomicUtf8 -Path $statePath -Content (($state | ConvertTo-Json -Depth 3) + "`n")
            $checkedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
            try {
                Write-RicoLootSyncStatus -CacheDirectory $cache -RequestId $request.RequestId -State fetching -CheckedAt $checkedAt -Message 'Downloading the latest public Everloot observations.'
                $result = & $UpdateAction $request.RequestId $addon
                if ($null -eq $result -or $result.CompletedRequestId -cne $request.RequestId) { throw 'The updater did not confirm this request.' }
                $checkedAt = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
                Write-RicoLootSyncStatus -CacheDirectory $cache -RequestId $request.RequestId -State success -CheckedAt $checkedAt -Message 'Everloot check completed. Reload the UI to view the comparison.'
                [IO.File]::AppendAllText((Join-Path $stateRoot 'companion.log'), ($checkedAt + ' SUCCESS request=' + $request.RequestId + [Environment]::NewLine))
                if ($Notify) { Show-RicoLootCompanionNotice -Succeeded $true }
                [pscustomobject]@{ RequestId=$request.RequestId; State='success'; Result=$result }
            } catch {
                $failure = $_
                try { Write-RicoLootSyncStatus -CacheDirectory $cache -RequestId $request.RequestId -State error -CheckedAt $checkedAt -ErrorCode 'fetch_failed' -Message 'The Everloot check failed. The last working database is retained. Please try again later.' } catch { }
                # Use a fixed error message: request files, account paths and other
                # SavedVariables content never enter the companion log.
                [IO.File]::AppendAllText((Join-Path $stateRoot 'companion.log'), ($checkedAt + ' FAILED request=' + $request.RequestId + ' error=fetch_failed' + [Environment]::NewLine))
                if ($Notify) { Show-RicoLootCompanionNotice -Succeeded $false }
                [pscustomobject]@{ RequestId=$request.RequestId; State='error'; Error='fetch_failed' }
            }
        }
    } finally { if ($null -ne $passLock) { $passLock.Dispose() } }
}

function Start-RicoLootCompanion {
    param([Parameter(Mandatory=$true)][string]$GameDirectory)
    $scriptPath = Join-Path $script:RicoLootCompanionRoot 'RicoLoot-Sync-Companion.ps1'
    $game = [IO.Path]::GetFullPath($GameDirectory)
    # Trailing backslashes must be doubled before the closing Windows argument quote.
    $quotedGame = '"' + [regex]::Replace($game, '\\+$', '$0$0') + '"'
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
    $start.WorkingDirectory = $script:RicoLootCompanionRoot
    $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Mode Run -GameDirectory ' + $quotedGame
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $child = [System.Diagnostics.Process]::Start($start)
    try { return [pscustomobject]@{ Started=$true; ProcessId=$child.Id } }
    finally { $child.Dispose() }
}

if (-not $companionImportOnly) {
    $ErrorActionPreference = 'Stop'
    $stateRoot = Join-Path $script:RicoLootCompanionRoot 'updater-state'
    $null = [IO.Directory]::CreateDirectory($stateRoot)
    $stopPath = Join-Path $stateRoot 'companion.stop'
    if ($Mode -eq 'Stop') { [IO.File]::WriteAllText($stopPath, 'stop'); Write-Output 'Companion stop requested.'; exit 0 }
    if ([string]::IsNullOrWhiteSpace($GameDirectory)) { throw 'Pass the WoW _forever_ folder with -GameDirectory.' }
    if ($Mode -eq 'Start') { Start-RicoLootCompanion -GameDirectory $GameDirectory; exit 0 }
    $instanceLock = $null
    try {
        try { $instanceLock = [IO.File]::Open((Join-Path $stateRoot 'companion.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { Write-Output 'The RicoLoot companion is already running.'; exit 0 }
        if ([IO.File]::Exists($stopPath)) { [IO.File]::Delete($stopPath) }
        if ($Mode -eq 'Once') { Invoke-RicoLootCompanionPass -GameDirectory $GameDirectory -StateDirectory $stateRoot; exit 0 }
        $started = [DateTimeOffset]::UtcNow.ToString('o')
        $lastError = ''
        [IO.File]::WriteAllText((Join-Path $stateRoot 'companion-running.json'), (([ordered]@{ schema=1; processId=$PID; startedAt=$started } | ConvertTo-Json) + "`n"))
        while (-not [IO.File]::Exists($stopPath)) {
            try {
                Invoke-RicoLootCompanionPass -GameDirectory $GameDirectory -StateDirectory $stateRoot -Notify | Out-Null
                $lastError = ''
            } catch {
                # An offline mapped drive is recoverable. Do not pollute the log
                # every second with the same availability error.
                if ($lastError -ne $_.Exception.Message) {
                    $lastError = $_.Exception.Message
                    [IO.File]::AppendAllText((Join-Path $stateRoot 'companion.log'), ([DateTimeOffset]::UtcNow.ToString('o') + ' WAITING installation_or_state_unavailable' + [Environment]::NewLine))
                }
            }
            Start-Sleep -Seconds 1
        }
    } finally {
        if ($null -ne $instanceLock) {
            $instanceLock.Dispose()
            $runningPath = Join-Path $stateRoot 'companion-running.json'
            if ([IO.File]::Exists($runningPath)) { [IO.File]::Delete($runningPath) }
        }
    }
}
