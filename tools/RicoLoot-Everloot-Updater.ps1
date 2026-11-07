#Requires -Version 5.1
<#
.SYNOPSIS
Downloads public Everloot JSON and builds RicoLoot's observed-data supplement.
.DESCRIPTION
No API key, game account, SavedVariables or executable remote code is used.
Updates a local RicoLootEverloot addon next to RicoLoot. The cache is separate
from the managed RicoLoot folder and retains the previous validated snapshot.
The derived data is CC BY-SA 4.0, attributed to Everloot contributors.
.EXAMPLE
.\RicoLoot-Everloot-Updater.ps1 -AddonDirectory 'C:\Games\World of Warcraft\_forever_\Interface\AddOns\RicoLoot'
.EXAMPLE
.\RicoLoot-Everloot-Updater.ps1 -OutputFile .\DataObserved.lua
#>
[CmdletBinding()]
param(
    [string]$AddonDirectory,
    [string]$OutputFile,
    [string]$RequestId = '',
    [switch]$FunctionsOnly
)

$script:RicoLootUpdaterRoot = $PSScriptRoot
$script:EverlootCredit = 'Data from Everloot (https://everloot.app), CC BY-SA 4.0.'
$script:EverlootFirstPage = 'https://everloot.app/api/rollups/drops?limit=500&offset=0'

function Test-EverlootProperty {
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

function Get-EverlootProperty {
    param($Object, [string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return ,$Object[$Name] }
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return ,$property.Value }
    return $null
}

function Assert-EverlootObject {
    param($Value, [string]$Label)
    if ($null -eq $Value -or ($Value -isnot [pscustomobject] -and $Value -isnot [System.Collections.IDictionary])) {
        throw "$Label must be a JSON object."
    }
}

function Get-EverlootNumber {
    param($Value, [string]$Label, [double]$Minimum = 0, [double]$Maximum = 2147483647, [switch]$Integer)
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [string]) { throw "$Label must be numeric." }
    $typeCode = [System.Type]::GetTypeCode($Value.GetType())
    if ($typeCode -notin @('SByte','Byte','Int16','UInt16','Int32','UInt32','Int64','UInt64','Single','Double','Decimal')) {
        throw "$Label must be numeric."
    }
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt $Minimum -or $number -gt $Maximum) {
        throw "$Label is outside its valid range."
    }
    if ($Integer -and $number -ne [math]::Floor($number)) { throw "$Label must be an integer." }
    return $number
}

function Get-EverlootTimestamp {
    param($Value, [string]$Label)
    # PowerShell 7.5+ can turn JSON ISO strings into DateTime automatically.
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) { $Value = [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc) }
        return [DateTimeOffset]$Value.ToUniversalTime()
    }
    if ($Value -isnot [string] -or $Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$') {
        throw "$Label must be an ISO UTC timestamp."
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { throw "$Label is invalid." }
    return $parsed.ToUniversalTime()
}

function ConvertFrom-EverlootJson {
    param([string]$Content)
    $options = @{ ErrorAction = 'Stop' }
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $options.DateKind = 'String' }
    return ConvertFrom-Json -InputObject $Content @options
}

function Resolve-EverlootPageUri {
    param([string]$Value)
    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or $uri.DnsSafeHost -cne 'everloot.app' -or $uri.Port -ne 443 -or
        $uri.AbsolutePath -cne '/api/rollups/drops' -or $uri.UserInfo -ne '' -or $uri.Fragment -ne '') {
        throw 'The feed supplied an unexpected page URL.'
    }
    $query = @{}
    foreach ($pair in $uri.Query.TrimStart('?').Split('&')) {
        $parts = $pair.Split('=')
        if ($parts.Length -ne 2 -or $parts[0] -notin @('limit','offset') -or $query.ContainsKey($parts[0]) -or $parts[1] -notmatch '^\d{1,9}$') {
            throw 'The feed supplied unexpected page parameters.'
        }
        $query[$parts[0]] = [int]$parts[1]
    }
    if (-not $query.ContainsKey('limit') -or -not $query.ContainsKey('offset') -or $query.limit -ne 500) {
        throw 'The feed supplied an unsupported page size.'
    }
    return [pscustomobject]@{ Uri = $uri.AbsoluteUri; Offset = $query.offset; Limit = $query.limit }
}

function Invoke-EverlootRequest {
    param([string]$Uri)
    $null = Resolve-EverlootPageUri $Uri
    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        # Refuse redirects rather than following a JSON endpoint to another host.
        $response = Invoke-WebRequest -Uri $Uri -Method Get -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 0 `
            -Headers @{ Accept = 'application/json'; 'User-Agent' = 'RicoLoot-Everloot-Updater/1.0 (daily public data sync)' } -ErrorAction Stop
        if ([int]$response.StatusCode -ne 200) { throw 'Everloot did not return HTTP 200.' }
        $contentType = [string]$response.Headers['Content-Type']
        if ($contentType -notmatch '^application/json(?:\s*;|$)') { throw 'Everloot did not return JSON.' }
        if ($response.Content.Length -gt 8MB) { throw 'Everloot page exceeds the maximum response size.' }
        return ConvertFrom-EverlootJson $response.Content
    } finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function ConvertFrom-EverlootPages {
    param([Parameter(Mandatory=$true)][object[]]$Pages, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    if ($Pages.Count -lt 1 -or $Pages.Count -gt 24) { throw 'A complete snapshot must contain between 1 and 24 pages.' }
    $mobs, $items = @{}, @{}
    $expectedOffset, $expectedTotal, $expectedRates, $expectedZeros = 0, $null, $null, $null
    $dataAsOf, $dataTime = $null, $null
    $seenRows, $seenZeroRows = 0, 0
    for ($pageIndex = 0; $pageIndex -lt $Pages.Count; $pageIndex++) {
        $page = $Pages[$pageIndex]
        if ($page -is [string]) { $page = ConvertFrom-EverlootJson $page }
        Assert-EverlootObject $page 'Page'
        if ((Get-EverlootProperty $page 'unreachable') -isnot [bool] -or (Get-EverlootProperty $page 'unreachable')) {
            throw 'Everloot reports that its data store is unreachable.'
        }
        $attribution = Get-EverlootProperty $page 'attribution'
        Assert-EverlootObject $attribution 'Attribution'
        if ((Get-EverlootProperty $attribution 'licence') -cne 'CC BY-SA 4.0' -or
            (Get-EverlootProperty $attribution 'licenceUrl') -cne 'https://creativecommons.org/licenses/by-sa/4.0/' -or
            (Get-EverlootProperty $attribution 'credit') -cne $script:EverlootCredit) {
            throw 'Everloot attribution or data licence changed; the previous snapshot is retained.'
        }
        $stamp = Get-EverlootProperty $page 'dataAsOf'
        $timestamp = Get-EverlootTimestamp $stamp 'dataAsOf'
        if ($stamp -isnot [string]) { $stamp = $timestamp.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture) }
        $stats = Get-EverlootProperty $page 'stats'
        Assert-EverlootObject $stats 'Source statistics'
        if ((Get-EverlootProperty $stats 'unreachable') -isnot [bool] -or (Get-EverlootProperty $stats 'unreachable')) {
            throw 'Everloot source statistics report that the data store is unreachable.'
        }
        if ((Get-EverlootTimestamp (Get-EverlootProperty $stats 'dataAsOf') 'statistics dataAsOf') -ne $timestamp) {
            throw 'Everloot source statistics disagree with the snapshot timestamp.'
        }
        $generated = Get-EverlootTimestamp (Get-EverlootProperty $page 'generatedAt') 'generatedAt'
        if ($generated -gt $Now.AddMinutes(10) -or $generated -lt $Now.AddDays(-2) -or
            $timestamp -gt $Now.AddMinutes(10) -or $timestamp -gt $generated) {
            throw 'The response is stale or has inconsistent timestamps.'
        }
        if ($null -eq $dataAsOf) { $dataAsOf, $dataTime = $stamp, $timestamp }
        elseif ($stamp -cne $dataAsOf) { throw 'The source changed during pagination; retry on the next run.' }
        $offset = [int](Get-EverlootNumber (Get-EverlootProperty $page 'offset') 'offset' -Integer)
        $limit = [int](Get-EverlootNumber (Get-EverlootProperty $page 'limit') 'limit' -Minimum 1 -Maximum 500 -Integer)
        $total = [int](Get-EverlootNumber (Get-EverlootProperty $page 'total') 'total' -Integer)
        $totalRates = [int](Get-EverlootNumber (Get-EverlootProperty $page 'totalRates') 'totalRates' -Integer)
        $totalZeros = [int](Get-EverlootNumber (Get-EverlootProperty $page 'totalMeasuredZeros') 'totalMeasuredZeros' -Integer)
        if ($limit -ne 500 -or $offset -ne $expectedOffset -or $total -ne ($totalRates + $totalZeros)) {
            throw 'The source paging counters are inconsistent.'
        }
        if ($pageIndex -eq 0) { $expectedTotal, $expectedRates, $expectedZeros = $total, $totalRates, $totalZeros }
        elseif ($total -ne $expectedTotal -or $totalRates -ne $expectedRates -or $totalZeros -ne $expectedZeros) {
            throw 'The source paging totals changed during download.'
        }
        $rates, $zeros = (Get-EverlootProperty $page 'rates'), (Get-EverlootProperty $page 'measuredZeros')
        if ($rates -isnot [Array] -or $zeros -isnot [Array] -or ($rates.Count + $zeros.Count) -gt $limit) {
            throw 'The source rows do not match the documented page shape.'
        }
        $seenRows += $rates.Count
        $seenZeroRows += $zeros.Count
        foreach ($row in $rates) {
            Assert-EverlootObject $row 'Rate row'
            if ((Get-EverlootProperty $row 'public') -isnot [bool]) { throw 'A rate row is missing its privacy status.' }
            if (-not (Get-EverlootProperty $row 'public')) { continue }
            $hasNpc = (Test-EverlootProperty $row 'sourceNpcId') -and $null -ne (Get-EverlootProperty $row 'sourceNpcId')
            $hasObject = (Test-EverlootProperty $row 'sourceObjectId') -and $null -ne (Get-EverlootProperty $row 'sourceObjectId')
            if ($hasNpc -and $hasObject) { throw 'A rate row has conflicting creature and object sources.' }
            if ($hasObject) { continue }
            if (-not $hasNpc) { throw 'A public rate row has no recognised source.' }
            $reporters = [int](Get-EverlootNumber (Get-EverlootProperty $row 'reporters') 'reporters' -Integer)
            if ($reporters -lt 3) { continue }
            $npc = [int](Get-EverlootNumber (Get-EverlootProperty $row 'sourceNpcId') 'sourceNpcId' -Minimum 1 -Integer)
            $item = [int](Get-EverlootNumber (Get-EverlootProperty $row 'itemId') 'itemId' -Minimum 1 -Integer)
            $windows = [int](Get-EverlootNumber (Get-EverlootProperty $row 'kills') 'loot windows' -Minimum 1 -Integer)
            $drops = [int](Get-EverlootNumber (Get-EverlootProperty $row 'drops') 'drops' -Integer)
            $rate = Get-EverlootNumber (Get-EverlootProperty $row 'rate') 'rate' -Maximum 1
            if ($drops -gt $windows -or [math]::Abs($rate - ($drops / [double]$windows)) -gt 0.000000001) {
                throw 'A source rate does not agree with its observed counts.'
            }
            if ($drops -eq 0) { continue }
            $name = Get-EverlootProperty $row 'sourceName'
            if ($null -ne $name -and $name -isnot [string]) { throw 'A creature name has an unexpected type.' }
            $name = ConvertTo-EverlootDisplayName $name
            if (-not $mobs.ContainsKey($npc)) {
                $mobs[$npc] = [pscustomobject]@{ Id = $npc; Name = $name; Rows = @{}; Windows = $windows; Reporters = $reporters }
            }
            $mob = $mobs[$npc]
            if ($mob.Windows -ne $windows -or $mob.Reporters -ne $reporters -or
                ($mob.Name -ne '' -and $name -ne '' -and $mob.Name -cne $name)) {
                throw 'A creature has conflicting aggregate counts or names.'
            }
            if ($mob.Name -eq '' -and $name -ne '') { $mob.Name = $name }
            if ($mob.Rows.ContainsKey($item)) {
                $old = $mob.Rows[$item]
                if ($old.Drops -ne $drops -or $old.Windows -ne $windows -or $old.Reporters -ne $reporters) {
                    throw 'A source/item pair has conflicting duplicate aggregates.'
                }
                continue
            }
            $mob.Rows[$item] = [pscustomobject]@{ ItemId = $item; Drops = $drops; Windows = $windows; Reporters = $reporters }
            $items[$item] = $true
        }
        if (-not (Test-EverlootProperty $page 'next')) { throw 'The source omitted its pagination status.' }
        $next = Get-EverlootProperty $page 'next'
        $expectedOffset = $offset + $rates.Count + $zeros.Count
        if ($null -eq $next) {
            if ($pageIndex -ne ($Pages.Count - 1) -or $expectedOffset -ne $total) { throw 'The source snapshot is incomplete.' }
        } else {
            if ($next -isnot [string] -or $pageIndex -eq ($Pages.Count - 1) -or $expectedOffset -ge $total) {
                throw 'The source snapshot is incomplete or has extra pagination.'
            }
            $nextPage = Resolve-EverlootPageUri $next
            if ($nextPage.Offset -ne $expectedOffset) { throw 'The source next-page offset is inconsistent.' }
        }
    }
    if ($seenRows -ne $expectedRates -or $seenZeroRows -ne $expectedZeros) { throw 'Downloaded row totals do not match the source.' }
    if ($mobs.Count -eq 0) { throw 'No public creature drops were returned; the previous snapshot is retained.' }
    $dropCount = 0
    foreach ($mob in $mobs.Values) { $dropCount += $mob.Rows.Count }
    return [pscustomobject]@{ DataAsOf = $dataAsOf; UtcTimestamp = $dataTime; Mobs = $mobs; Items = $items;
        NpcCount = $mobs.Count; ItemCount = $items.Count; DropCount = $dropCount }
}

function Get-EverlootSnapshot {
    param([scriptblock]$FetchPage = { param($url) Invoke-EverlootRequest -Uri $url }, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
    $pages = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    $url = $script:EverlootFirstPage
    while ($null -ne $url) {
        if ($pages.Count -ge 24) { throw 'The complete feed exceeds the anonymous daily request budget (24 pages).' }
        $validated = Resolve-EverlootPageUri $url
        if ($seen.ContainsKey($validated.Offset)) { throw 'The source repeated a page offset.' }
        $seen[$validated.Offset] = $true
        $page = & $FetchPage $validated.Uri
        if ($page -is [string]) { $page = ConvertFrom-EverlootJson $page }
        Assert-EverlootObject $page 'Downloaded page'
        $pages.Add($page)
        if (-not (Test-EverlootProperty $page 'next')) { throw 'The source omitted its pagination status.' }
        $url = Get-EverlootProperty $page 'next'
        if ($null -ne $url -and $url -isnot [string]) { throw 'The source next page is not a URL.' }
        # One request per second; never retry an error or consume the API's quota in a loop.
        if ($null -ne $url) { Start-Sleep -Milliseconds 1100 }
    }
    return ConvertFrom-EverlootPages -Pages ($pages.ToArray()) -Now $Now
}

function ConvertTo-EverlootDisplayName {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $name = $Value -replace '\|[cC][0-9a-fA-F]{8}', '' -replace '\|[rR]', ''
    $name = $name -replace '\|[TtAaHh].*?\|[tTaAhH]', ''
    $name = $name -replace '[\x00-\x1f\x7f-\x9f]', '' -replace '\|', ''
    $name = ($name -replace '\s+', ' ').Trim()
    if ($name.Length -gt 160) { $name = $name.Substring(0, 160) }
    return $name
}

function ConvertTo-EverlootLuaString {
    param([string]$Value)
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int]$character
        if ($code -eq 34) { $null = $builder.Append('\"') }
        elseif ($code -eq 92) { $null = $builder.Append('\\') }
        elseif ($code -lt 32 -or $code -eq 127) { $null = $builder.Append(('\{0:000}' -f $code)) }
        else { $null = $builder.Append($character) }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Get-EverlootObjectKeys {
    param($Object)
    if ($Object -is [System.Collections.IDictionary]) { return @($Object.Keys) }
    if ($null -ne $Object) { return @($Object.PSObject.Properties.Name) }
    return @()
}

function Get-EverlootIdentity {
    param([Parameter(Mandatory=$true)]$Snapshot)
    $npcIds, $itemIds = @{}, @{}
    $pairs = [ordered]@{}
    foreach ($npc in ($Snapshot.Mobs.Keys | Sort-Object { [int]$_ })) {
        $mob = $Snapshot.Mobs[$npc]
        $npcIds[[int]$npc] = $true
        foreach ($item in ($mob.Rows.Keys | Sort-Object { [int]$_ })) {
            $row = $mob.Rows[$item]
            $itemIds[[int]$item] = $true
            $pairs[([string]$npc + ':' + [string]$item)] = [ordered]@{
                drops = [int]$row.Drops; windows = [int]$row.Windows; reporters = [int]$row.Reporters
            }
        }
    }
    return [pscustomobject]@{
        dataAsOf = $Snapshot.DataAsOf
        npcIds = @($npcIds.Keys | Sort-Object { [int]$_ })
        itemIds = @($itemIds.Keys | Sort-Object { [int]$_ })
        dropKeys = @($pairs.Keys)
        pairs = $pairs
    }
}

function Assert-EverlootIdentity {
    param($Identity)
    Assert-EverlootObject $Identity 'Snapshot identifiers'
    $null = Get-EverlootTimestamp (Get-EverlootProperty $Identity 'dataAsOf') 'identifier dataAsOf'
    $pairs = Get-EverlootProperty $Identity 'pairs'
    Assert-EverlootObject $pairs 'Snapshot pairs'
    $keys = @(Get-EverlootObjectKeys $pairs)
    if ($keys.Count -lt 1 -or $keys.Count -gt 12000) { throw 'Saved snapshot identifiers have an invalid pair count.' }
    $npcs, $items, $seenKeys = @{}, @{}, @{}
    foreach ($key in $keys) {
        if ($key -isnot [string] -or $key -notmatch '^([1-9]\d{0,9}):([1-9]\d{0,9})$') { throw 'A saved source/item key is invalid.' }
        $npc = [int](Get-EverlootNumber ([double]$Matches[1]) 'saved source ID' -Minimum 1 -Integer)
        $item = [int](Get-EverlootNumber ([double]$Matches[2]) 'saved item ID' -Minimum 1 -Integer)
        $pair = Get-EverlootProperty $pairs $key
        Assert-EverlootObject $pair 'Saved pair counts'
        $windows = Get-EverlootNumber (Get-EverlootProperty $pair 'windows') 'saved window count' -Minimum 1 -Integer
        $drops = Get-EverlootNumber (Get-EverlootProperty $pair 'drops') 'saved drop count' -Minimum 1 -Integer
        $null = Get-EverlootNumber (Get-EverlootProperty $pair 'reporters') 'saved reporters' -Minimum 3 -Integer
        if ($drops -gt $windows) { throw 'Saved drop counts exceed their observation denominator.' }
        $npcs[$npc], $items[$item], $seenKeys[$key] = $true, $true, $true
    }
    foreach ($descriptor in @(
        @{Name='npcIds'; Set=$npcs; Numeric=$true},
        @{Name='itemIds'; Set=$items; Numeric=$true},
        @{Name='dropKeys'; Set=$seenKeys; Numeric=$false}
    )) {
        $values = Get-EverlootProperty $Identity $descriptor.Name
        if ($values -isnot [Array] -or $values.Count -ne $descriptor.Set.Count) { throw 'Saved identifier lists do not match the snapshot pairs.' }
        $seen = @{}
        foreach ($value in $values) {
            if ($descriptor.Numeric) { $value = [int](Get-EverlootNumber $value 'saved identifier' -Minimum 1 -Integer) }
            elseif ($value -isnot [string]) { throw 'A saved pair identifier has the wrong type.' }
            if ($seen.ContainsKey($value) -or -not $descriptor.Set.ContainsKey($value)) { throw 'Saved identifier lists are inconsistent.' }
            $seen[$value] = $true
        }
    }
}

function Compare-EverlootIdentity {
    param($Previous, [Parameter(Mandatory=$true)]$Current)
    Assert-EverlootIdentity $Current
    $addedItems, $addedNpcs, $addedDrops = @(), @(), @()
    $removedItems, $removedNpcs, $removedDrops, $updatedDrops = @(), @(), @(), @()
    $previousStamp = ''
    if ($null -ne $Previous) {
        Assert-EverlootIdentity $Previous
        $oldStamp = Get-EverlootProperty $Previous 'dataAsOf'
        if ($oldStamp -is [string]) { $previousStamp = $oldStamp }
        else { $previousStamp = (Get-EverlootTimestamp $oldStamp 'previous dataAsOf').ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture) }
        $oldPairs, $newPairs = (Get-EverlootProperty $Previous 'pairs'), (Get-EverlootProperty $Current 'pairs')
        foreach ($field in @('itemIds', 'npcIds', 'dropKeys')) {
            $oldSet, $newSet = @{}, @{}
            foreach ($value in (Get-EverlootProperty $Previous $field)) { $oldSet[[string]$value] = $true }
            foreach ($value in (Get-EverlootProperty $Current $field)) { $newSet[[string]$value] = $true }
            $added, $removed = @(), @()
            foreach ($value in (Get-EverlootProperty $Current $field)) { if (-not $oldSet.ContainsKey([string]$value)) { $added += $value } }
            foreach ($value in (Get-EverlootProperty $Previous $field)) { if (-not $newSet.ContainsKey([string]$value)) { $removed += $value } }
            if ($field -eq 'itemIds') { $addedItems, $removedItems = @($added), @($removed) }
            elseif ($field -eq 'npcIds') { $addedNpcs, $removedNpcs = @($added), @($removed) }
            else { $addedDrops, $removedDrops = @($added), @($removed) }
        }
        foreach ($key in (Get-EverlootProperty $Current 'dropKeys')) {
            if (-not (Test-EverlootProperty $oldPairs $key)) { continue }
            $old, $new = (Get-EverlootProperty $oldPairs $key), (Get-EverlootProperty $newPairs $key)
            if ((Get-EverlootProperty $old 'drops') -ne (Get-EverlootProperty $new 'drops') -or
                (Get-EverlootProperty $old 'windows') -ne (Get-EverlootProperty $new 'windows') -or
                (Get-EverlootProperty $old 'reporters') -ne (Get-EverlootProperty $new 'reporters')) { $updatedDrops += $key }
        }
    }
    $hasChanges = ($addedItems.Count + $addedNpcs.Count + $addedDrops.Count + $removedItems.Count +
        $removedNpcs.Count + $removedDrops.Count + $updatedDrops.Count) -gt 0
    return [pscustomobject][ordered]@{
        previousDataAsOf=$previousStamp; baselineEstablished=($null -ne $Previous)
        addedItems=$addedItems.Count; addedNpcs=$addedNpcs.Count; addedDrops=$addedDrops.Count
        removedItems=$removedItems.Count; removedNpcs=$removedNpcs.Count; removedDrops=$removedDrops.Count; updatedDrops=$updatedDrops.Count
        newItemIds=@($addedItems); newNpcIds=@($addedNpcs); newDropKeys=@($addedDrops)
        removedItemIds=@($removedItems); removedNpcIds=@($removedNpcs); removedDropKeys=@($removedDrops); updatedDropKeys=@($updatedDrops)
        checkedAt=''; comparisonAt=''; latestCheckChanged=[bool]$hasChanges
    }
}

function Read-RicoLootGeneratedSnapshot {
    param([Parameter(Mandatory=$true)][string]$Path)
    # Read only the updater's numeric generated format. Never execute or evaluate Lua.
    if (-not [IO.File]::Exists($Path) -or (Get-Item -LiteralPath $Path).Length -gt 8MB) { return $null }
    try {
        $lines = [IO.File]::ReadAllLines($Path, (New-Object Text.UTF8Encoding($false, $true)))
        if ($lines -notcontains '-- Generated from validated public JSON by RicoLoot-Everloot-Updater.ps1.') { return $null }
        $metadata = @($lines | Where-Object { $_ -match '^D\.remoteSnapshot = ' })
        if ($metadata.Count -ne 1 -or $metadata[0] -notmatch '^D\.remoteSnapshot = \{ provider="Everloot", dataAsOf="(?<date>[0-9T:.Z-]+)", npcCount=(?<npcs>\d+), itemCount=(?<items>\d+), dropCount=(?<drops>\d+) \}$') { return $null }
        $stamp, $npcCount, $itemCount, $dropCount = $Matches.date, [int]$Matches.npcs, [int]$Matches.items, [int]$Matches.drops
        $timestamp = Get-EverlootTimestamp $stamp 'generated dataAsOf'
        $mobs, $items = @{}, @{}
        foreach ($line in $lines) {
            if (-not $line.StartsWith('add(')) { continue }
            if ($line -notmatch '^add\((?<npc>[1-9]\d{0,9}), "(?:[^"\\\x00-\x1f]|\\(?:["\\]|[0-9]{3}))*", "(?<packed>(?:[1-9]\d{0,9}\|\|\|\|[1-9]\d{0,9}\|[1-9]\d{0,9}\|\|;)+)", (?<windows>[1-9]\d{0,9}), (?<reporters>[1-9]\d{0,9})\)$') { return $null }
            $npc, $packed, $windows, $reporters = [int]$Matches.npc, $Matches.packed, [int]$Matches.windows, [int]$Matches.reporters
            if ($mobs.ContainsKey($npc) -or $reporters -lt 3) { return $null }
            $rows = @{}
            foreach ($raw in $packed.TrimEnd(';').Split(';')) {
                $parts = $raw.Split('|')
                $item, $drops, $rowWindows = [int]$parts[0], [int]$parts[4], [int]$parts[5]
                if ($drops -gt $rowWindows -or $rowWindows -ne $windows -or $rows.ContainsKey($item)) { return $null }
                $rows[$item] = [pscustomobject]@{ ItemId=$item; Drops=$drops; Windows=$rowWindows; Reporters=$reporters }
                $items[$item] = $true
            }
            $mobs[$npc] = [pscustomobject]@{ Id=$npc; Name=''; Rows=$rows; Windows=$windows; Reporters=$reporters }
        }
        $snapshot = [pscustomobject]@{ DataAsOf=$stamp; UtcTimestamp=$timestamp; Mobs=$mobs; Items=$items }
        $identity = Get-EverlootIdentity $snapshot
        Assert-EverlootIdentity $identity
        if ($identity.npcIds.Count -ne $npcCount -or $identity.itemIds.Count -ne $itemCount -or $identity.dropKeys.Count -ne $dropCount) { return $null }
        return $identity
    } catch { return $null }
}

function ConvertTo-EverlootChangesLua {
    param($Changes)
    Assert-EverlootChanges $Changes
    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($field in @('previousDataAsOf','checkedAt','comparisonAt')) { $values.Add($field + '=' + (ConvertTo-EverlootLuaString ([string](Get-EverlootProperty $Changes $field)))) }
    $values.Add('baselineEstablished=' + ([string][bool](Get-EverlootProperty $Changes 'baselineEstablished')).ToLowerInvariant())
    $values.Add('latestCheckChanged=' + ([string][bool](Get-EverlootProperty $Changes 'latestCheckChanged')).ToLowerInvariant())
    foreach ($field in @('addedItems','addedNpcs','addedDrops','removedItems','removedNpcs','removedDrops','updatedDrops')) {
        $values.Add($field + '=' + [string][int](Get-EverlootProperty $Changes $field))
    }
    foreach ($field in @('newItemIds','newNpcIds','removedItemIds','removedNpcIds')) {
        $values.Add($field + '={' + ((Get-EverlootProperty $Changes $field) -join ',') + '}')
    }
    foreach ($field in @('newDropKeys','removedDropKeys','updatedDropKeys')) {
        $quoted = @((Get-EverlootProperty $Changes $field) | ForEach-Object { ConvertTo-EverlootLuaString $_ })
        $values.Add($field + '={' + ($quoted -join ',') + '}')
    }
    return 'D.remoteSnapshot.changes = { ' + ($values -join ', ') + ' }'
}

function Assert-EverlootChanges {
    param($Changes)
    Assert-EverlootObject $Changes 'Snapshot changes'
    if ((Get-EverlootProperty $Changes 'baselineEstablished') -isnot [bool]) { throw 'The saved comparison baseline status is invalid.' }
    if ((Get-EverlootProperty $Changes 'latestCheckChanged') -isnot [bool]) { throw 'The latest comparison status is invalid.' }
    foreach ($field in @('previousDataAsOf','checkedAt','comparisonAt')) {
        $value = Get-EverlootProperty $Changes $field
        if ($value -isnot [string]) { throw 'A saved comparison timestamp has the wrong type.' }
        if ($value -ne '') { $null = Get-EverlootTimestamp $value ('comparison ' + $field) }
    }
    foreach ($descriptor in @(
        @{Count='addedItems'; List='newItemIds'; Numeric=$true}, @{Count='addedNpcs'; List='newNpcIds'; Numeric=$true},
        @{Count='addedDrops'; List='newDropKeys'; Numeric=$false}, @{Count='removedItems'; List='removedItemIds'; Numeric=$true},
        @{Count='removedNpcs'; List='removedNpcIds'; Numeric=$true}, @{Count='removedDrops'; List='removedDropKeys'; Numeric=$false},
        @{Count='updatedDrops'; List='updatedDropKeys'; Numeric=$false}
    )) {
        $count = [int](Get-EverlootNumber (Get-EverlootProperty $Changes $descriptor.Count) 'comparison count' -Maximum 12000 -Integer)
        $values = Get-EverlootProperty $Changes $descriptor.List
        if ($values -isnot [Array] -or $values.Count -ne $count) { throw 'Saved comparison counts and identifiers disagree.' }
        $seen = @{}
        foreach ($value in $values) {
            if ($descriptor.Numeric) { $null = Get-EverlootNumber $value 'comparison identifier' -Minimum 1 -Integer }
            elseif ($value -isnot [string] -or $value -notmatch '^[1-9]\d{0,9}:[1-9]\d{0,9}$') { throw 'A saved comparison pair key is invalid.' }
            if ($seen.ContainsKey([string]$value)) { throw 'A saved comparison contains repeated identifiers.' }
            $seen[[string]$value] = $true
        }
    }
}

function Assert-RicoLootRequestId {
    param([string]$RequestId = '')
    if (-not [string]::IsNullOrEmpty($RequestId) -and $RequestId -notmatch '^RICOLOOT-SYNC-1:[1-9]\d{8,11}:[A-Za-z0-9_-]{8,64}$') {
        throw 'The in-game database request identifier is invalid.'
    }
}

function ConvertTo-RicoLootLua {
    param([Parameter(Mandatory=$true)]$Snapshot, $Changes, [string]$CompletedRequestId = '', [string]$LastCheckedUtc = '', [switch]$ForCacheAddon)
    $date = $Snapshot.UtcTimestamp.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $stamp = ConvertTo-EverlootLuaString $Snapshot.DataAsOf
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(
        '-- Derived observation data: Everloot contributors, CC BY-SA 4.0.',
        '-- Data from Everloot (https://everloot.app), CC BY-SA 4.0.',
        '-- https://creativecommons.org/licenses/by-sa/4.0/',
        '-- Generated from validated public JSON by RicoLoot-Everloot-Updater.ps1.',
        '-- Rates describe opened source loot windows, not every kill. No method or location is inferred.',
        'local _, R = ...', 'local D = R.Data',
        'assert(D and D.schema == 1, "RicoLoot: Data.lua must load before DataObserved.lua")',
        ('D.remoteSnapshot = { provider="Everloot", dataAsOf=' + $stamp + ', npcCount=' + $Snapshot.NpcCount + ', itemCount=' + $Snapshot.ItemCount + ', dropCount=' + $Snapshot.DropCount + ' }'),
        'D.sources.everloot_observed = {',
        '  name="Everloot - Forever observations", url="https://everloot.app/database/drops",',
        ('  license="CC BY-SA 4.0", revision=' + $stamp + ', date="' + $date + '",'),
        '  note="Data from Everloot (https://everloot.app), CC BY-SA 4.0. Rate = windows containing an item / observed source loot windows; not every kill. Reporters count installations for the source, not confirmations for each item.",',
        '}',
        'local function add(id, name, packed, windows, reporters)',
        '  local mob = D.mobs[id]',
        '  if not mob then mob = { id=id, name=name ~= "" and name or ("NPC " .. id), zones={}, tables={} }; D.mobs[id] = mob end',
        '  mob.tables = mob.tables or {}',
        '  mob.tables[#mob.tables + 1] = {',
        '    key="everloot_observed:" .. id, label="Public observed drops", method="observed",',
        '    source="everloot_observed", provenance="forever_observed", rateKind="observed", complete=false,',
        ('    sampleSize=windows, sourceReporters=reporters, date="' + $date + '",'),
        '    url="https://everloot.app/database/npcs/" .. id, packed=packed,',
        '    note="Observed in " .. windows .. " source loot windows from " .. reporters .. " reporting installations. Installations are counted for the source, not as confirmations of every item. Small samples can change substantially. Creature levels are combined; loot method and Forever locations are not inferred. Unlisted items may still drop. Data from Everloot (https://everloot.app), CC BY-SA 4.0.",',
        '  }', 'end'
    )) { $lines.Add($line) }
    if ($null -eq $Changes) { $Changes = Get-EverlootProperty $Snapshot 'Changes' }
    if ($null -eq $Changes) { $Changes = Compare-EverlootIdentity -Previous $null -Current (Get-EverlootIdentity $Snapshot) }
    $lines.Insert(9, (ConvertTo-EverlootChangesLua $Changes))
    if ($CompletedRequestId -ne '') {
        Assert-RicoLootRequestId $CompletedRequestId
        $lines.Insert(10, ('D.remoteSnapshot.completedRequestId = ' + (ConvertTo-EverlootLuaString $CompletedRequestId)))
    }
    if ($LastCheckedUtc -ne '') {
        $null = Get-EverlootTimestamp $LastCheckedUtc 'last checked timestamp'
        $lines.Insert(10, ('D.remoteSnapshot.lastCheckedUtc = ' + (ConvertTo-EverlootLuaString $LastCheckedUtc)))
    }
    foreach ($id in ($Snapshot.Mobs.Keys | Sort-Object { [int]$_ })) {
        $mob = $Snapshot.Mobs[$id]
        $packed = New-Object Text.StringBuilder
        foreach ($itemId in ($mob.Rows.Keys | Sort-Object { [int]$_ })) {
            $row = $mob.Rows[$itemId]
            # Percent stays blank: Core:GetChance derives it from validated integer counts.
            $null = $packed.Append(('{0}||||{1}|{2}||;' -f $row.ItemId, $row.Drops, $row.Windows))
        }
        $lines.Add(('add({0}, {1}, {2}, {3}, {4})' -f $id, (ConvertTo-EverlootLuaString $mob.Name),
            (ConvertTo-EverlootLuaString $packed.ToString()), $mob.Windows, $mob.Reporters))
    }
    $ids = (($Snapshot.Items.Keys | Sort-Object { [int]$_ }) -join ',')
    $lines.Add(('for _, id in ipairs({' + $ids + '}) do'))
    $lines.Add('  if not D.items[id] then D.items[id] = { id=id, name="Item " .. id } end')
    $lines.Add('end')
    if ($ForCacheAddon) {
        $entry = $lines.IndexOf('local _, R = ...')
        $lines[$entry] = "local _, Cache = ...`nfunction Cache.ApplyObserved(R)"
        $lines.Add('end')
    }
    return ($lines -join "`n") + "`n"
}

function Write-AtomicUtf8 {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $directory = [IO.Path]::GetDirectoryName($fullPath)
    if (-not [IO.Directory]::Exists($directory)) { throw 'The destination directory does not exist.' }
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    $bytes = $encoding.GetBytes($Content)
    if ([IO.File]::Exists($fullPath)) {
        $current = [IO.File]::ReadAllBytes($fullPath)
        if ($current.Length -eq $bytes.Length) {
            $same = $true
            for ($index = 0; $index -lt $bytes.Length; $index++) { if ($bytes[$index] -ne $current[$index]) { $same = $false; break } }
            if ($same) { return $false }
        }
    }
    $temporary = Join-Path $directory ('.ricoloot-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        if ([IO.File]::Exists($fullPath)) { [IO.File]::Replace($temporary, $fullPath, $fullPath + '.previous', $true) }
        else { [IO.File]::Move($temporary, $fullPath) }
        return $true
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Get-RicoLootEverlootCache {
    param([string]$AddonDirectory)

    if ([string]::IsNullOrWhiteSpace($AddonDirectory)) { throw 'Pass the path to the installed RicoLoot folder with -AddonDirectory.' }
    $addon = [IO.Path]::GetFullPath($AddonDirectory).TrimEnd('\', '/')
    if ([IO.Path]::GetFileName($addon) -ine 'RicoLoot' -or
        -not [IO.File]::Exists((Join-Path $addon 'RicoLoot.toc')) -or
        -not [IO.File]::Exists((Join-Path $addon 'Data.lua'))) {
        throw 'AddonDirectory must point to the installed RicoLoot folder.'
    }
    $addons = [IO.Path]::GetDirectoryName($addon)
    $cache = [IO.Path]::GetFullPath((Join-Path $addons 'RicoLootEverloot'))
    $files = [ordered]@{
        'RicoLootEverloot.toc' = (@(
            '## Interface: 16001', '## Interface-Camelot: 16001', '## Title: RicoLoot Everloot Cache',
            '## Notes: Locally generated Everloot observations for RicoLoot.', '## Version: 1',
            '## X-RicoLoot-LocalCache: 1', 'Cache.lua', 'DataObserved.lua', 'DataSyncStatus.lua'
        ) -join "`n") + "`n"
        'Cache.lua' = "local _, Cache = ...`n_G.RicoLootEverloot = Cache`n"
        'DataObserved.lua' = "-- Populated after a successful Everloot download.`n"
        'DataSyncStatus.lua' = "-- Populated by the local RicoLoot companion.`n"
    }

    if (-not [IO.Directory]::Exists($cache)) {
        # Publish the new folder only after its complete TOC and files exist.
        $temporary = [IO.Path]::GetFullPath($cache + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
        if ([IO.Path]::GetDirectoryName($temporary) -ine $addons -or [IO.Path]::GetDirectoryName($cache) -ine $addons) {
            throw 'The Everloot cache must be created beside RicoLoot.'
        }
        $null = [IO.Directory]::CreateDirectory($temporary)
        try {
            foreach ($name in $files.Keys) {
                [IO.File]::WriteAllText((Join-Path $temporary $name), $files[$name], (New-Object Text.UTF8Encoding($false)))
            }
            try { [IO.Directory]::Move($temporary, $cache) }
            catch [IO.IOException] { if (-not [IO.Directory]::Exists($cache)) { throw } }
        } finally {
            if ([IO.Directory]::Exists($temporary)) {
                foreach ($name in $files.Keys) { [IO.File]::Delete((Join-Path $temporary $name)) }
                [IO.Directory]::Delete($temporary)
            }
        }
    }
    if (([IO.File]::GetAttributes($cache) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The Everloot cache folder cannot be a redirect or link.'
    }
    foreach ($name in $files.Keys) {
        $path = Join-Path $cache $name
        if (-not [IO.File]::Exists($path) -or ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The existing Everloot cache folder does not match the expected layout.'
        }
    }
    foreach ($name in @('RicoLootEverloot.toc', 'Cache.lua')) {
        $text = [IO.File]::ReadAllText((Join-Path $cache $name)).Replace("`r`n", "`n")
        if ($text -cne $files[$name]) { throw 'The existing Everloot cache folder is not managed by these tools.' }
    }
    return $cache
}

function Invoke-RicoLootUpdate {
    [CmdletBinding()]
    param(
        [string]$AddonDirectory,
        [string]$OutputFile,
        [string]$StateDirectory = (Join-Path $script:RicoLootUpdaterRoot 'updater-state'),
        [scriptblock]$FetchPage = { param($url) Invoke-EverlootRequest -Uri $url },
        [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
        [string]$RequestId = ''
    )
    Assert-RicoLootRequestId $RequestId
    $installed = [string]::IsNullOrWhiteSpace($OutputFile)
    if ($installed) {
        $cache = Get-RicoLootEverlootCache -AddonDirectory $AddonDirectory
        $OutputFile = Join-Path $cache 'DataObserved.lua'
        $StateDirectory = $cache
    }
    $target = [IO.Path]::GetFullPath($OutputFile)
    if ([IO.Path]::GetExtension($target) -ine '.lua') { throw 'The database output must be a .lua file.' }
    if (-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($target))) { throw 'The database output directory does not exist.' }
    $stateRoot = [IO.Path]::GetFullPath($StateDirectory)
    $null = [IO.Directory]::CreateDirectory($stateRoot)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $targetKey = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($target.ToLowerInvariant())))).Replace('-', '').Substring(0, 16).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $statePath = Join-Path $stateRoot ('everloot-' + $targetKey + '.json')
    $lockPath = Join-Path $stateRoot ('everloot-' + $targetKey + '.lock')
    $logPath = Join-Path $stateRoot 'updater.log'
    $lock = $null
    try {
        try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw 'Another updater run is already using this output.' }
        $previous = $null
        if ([IO.File]::Exists($statePath)) {
            $previous = ConvertFrom-EverlootJson ([IO.File]::ReadAllText($statePath))
            Assert-EverlootObject $previous 'Saved updater state'
            if ($previous.outputFile -cne $target) { throw 'Saved updater state belongs to a different output.' }
            $null = Get-EverlootTimestamp $previous.dataAsOf 'saved dataAsOf'
        }
        $previousIdentity, $previousChanges, $completedRequest = $null, $null, ''
        if ($null -ne $previous -and (Get-EverlootProperty $previous 'schema') -eq 2) {
            $previousIdentity = Get-EverlootProperty $previous 'identity'
            Assert-EverlootIdentity $previousIdentity
            if ((Get-EverlootTimestamp (Get-EverlootProperty $previousIdentity 'dataAsOf') 'previous identity timestamp') -ne
                (Get-EverlootTimestamp $previous.dataAsOf 'saved dataAsOf')) { throw 'Saved snapshot timestamps disagree.' }
            $previousChanges = Get-EverlootProperty $previous 'changes'
            Assert-EverlootChanges $previousChanges
            $completedRequest = [string](Get-EverlootProperty $previous 'completedRequestId')
            Assert-RicoLootRequestId $completedRequest
        } elseif ($null -eq $previous -or (Get-EverlootProperty $previous 'schema') -eq 1) {
            # Migration from the original count-only state uses the installed
            # generated numeric records, never executable Lua evaluation.
            $previousIdentity = Read-RicoLootGeneratedSnapshot -Path $target
            if ($installed -and $null -eq $previousIdentity) {
                $previousIdentity = Read-RicoLootGeneratedSnapshot -Path (Join-Path $AddonDirectory 'DataObserved.lua')
            }
        } else { throw 'Saved updater state has an unsupported schema.' }
        if ($RequestId -ne '' -and $RequestId -ceq $completedRequest -and [IO.File]::Exists($target) -and
            [IO.File]::ReadAllText($target).Contains(('D.remoteSnapshot.completedRequestId = ' + (ConvertTo-EverlootLuaString $RequestId)))) {
            return [pscustomobject]@{ Changed=$false; DataChanged=$false; MatchedExistingRequest=$true; OutputFile=$target;
                DataAsOf=$previous.dataAsOf; NpcCount=$previous.npcCount; ItemCount=$previous.itemCount; DropCount=$previous.dropCount;
                StateFile=$statePath; CompletedRequestId=$completedRequest; Changes=$previousChanges }
        }
        $snapshot = Get-EverlootSnapshot -FetchPage $FetchPage -Now $Now
        if ($installed -and $null -ne $previous -and $snapshot.UtcTimestamp -lt (Get-EverlootTimestamp $previous.dataAsOf 'saved dataAsOf')) {
            throw 'Everloot returned an older snapshot; the current database is retained.'
        }
        if ($installed -and $null -ne $previousIdentity -and $snapshot.UtcTimestamp -lt
            (Get-EverlootTimestamp (Get-EverlootProperty $previousIdentity 'dataAsOf') 'previous source timestamp')) {
            throw 'Everloot returned an older snapshot than the installed database; the current database is retained.'
        }
        $identity = Get-EverlootIdentity $snapshot
        $changes = Compare-EverlootIdentity -Previous $previousIdentity -Current $identity
        $meaningfulChange = ($changes.addedItems + $changes.addedNpcs + $changes.addedDrops + $changes.removedItems +
            $changes.removedNpcs + $changes.removedDrops + $changes.updatedDrops) -gt 0
        $checkStamp = $Now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
        if (-not $meaningfulChange -and $null -ne $previousChanges) {
            # An unchanged check keeps the last useful before/after comparison.
            $changes = ConvertFrom-EverlootJson ($previousChanges | ConvertTo-Json -Depth 8)
        } else { $changes.comparisonAt = $checkStamp }
        $changes.checkedAt = $checkStamp
        $changes.latestCheckChanged = [bool]$meaningfulChange
        if ($RequestId -ne '') { $completedRequest = $RequestId }
        $content = ConvertTo-RicoLootLua -Snapshot $snapshot -Changes $changes -CompletedRequestId $completedRequest -LastCheckedUtc $checkStamp -ForCacheAddon:$installed
        $changed = Write-AtomicUtf8 -Path $target -Content $content
        $state = [ordered]@{ schema=2; provider='Everloot'; dataAsOf=$snapshot.DataAsOf; outputFile=$target;
            npcCount=$snapshot.NpcCount; itemCount=$snapshot.ItemCount; dropCount=$snapshot.DropCount;
            lastSuccessUtc=$checkStamp; lastCheckedUtc=$checkStamp; completedRequestId=$completedRequest; identity=$identity; changes=$changes }
        $null = Write-AtomicUtf8 -Path $statePath -Content (($state | ConvertTo-Json -Depth 10) + "`n")
        $message = '{0} SUCCESS changed={1} dataChanged={2} npcs={3} drops={4} newItems={5} dataAsOf={6}' -f $Now.ToString('o'), $changed,
            $meaningfulChange, $snapshot.NpcCount, $snapshot.DropCount, $changes.addedItems, $snapshot.DataAsOf
        [IO.File]::AppendAllText($logPath, $message + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{ Changed=$changed; DataChanged=$meaningfulChange; MatchedExistingRequest=$false; OutputFile=$target;
            DataAsOf=$snapshot.DataAsOf; NpcCount=$snapshot.NpcCount; ItemCount=$snapshot.ItemCount; DropCount=$snapshot.DropCount;
            StateFile=$statePath; CompletedRequestId=$completedRequest; Changes=$changes }
    } catch {
        try {
            $message = '{0} FAILED {1}' -f $Now.ToString('o'), ($_.Exception.Message -replace '[\r\n]', ' ')
            [IO.File]::AppendAllText($logPath, $message + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
        } catch { }
        throw
    } finally { if ($null -ne $lock) { $lock.Dispose() } }
}

if (-not $FunctionsOnly) {
    $ErrorActionPreference = 'Stop'
    try {
        $result = Invoke-RicoLootUpdate -AddonDirectory $AddonDirectory -OutputFile $OutputFile -RequestId $RequestId
        $result | Format-List Changed, DataChanged, DataAsOf, NpcCount, ItemCount, DropCount, OutputFile
        if ($result.MatchedExistingRequest) { Write-Output 'This in-game request was already completed; no additional API request was made.' }
        elseif (-not $result.Changes.baselineEstablished) { Write-Output 'Database downloaded and comparison baseline stored. Restart WoW if you just created the cache addon. For subsequent checks, use /reload.' }
        elseif ($result.DataChanged) { Write-Output 'Database observations updated. Use /reload in WoW to load them.' }
        else { Write-Output 'Database checked. No observation data changed; /reload loads the latest check status.' }
    } catch {
        Write-Error ('RicoLoot update failed; the last validated database is retained. ' + $_.Exception.Message)
        exit 1
    }
}
