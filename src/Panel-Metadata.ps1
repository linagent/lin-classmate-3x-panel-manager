# Optional per-server metadata: 到期日 (Expiry), 客户分组 (Group), 备注 (Note).
# Storage: a plain, non-secret sidecar next to the server list, 统一管理\服务器元数据.json, keyed by server Id.
#   - 服务器列表.json, the DPAPI account files and the version-1 .vpsaccounts transfer format are never touched.
#   - Old app versions do not know the sidecar and simply ignore it.
#   - Unknown top-level fields, unknown per-server fields and records for Ids not in the list are preserved on save.
#   - The file is only created when the user actually saves a non-empty value; loading never writes.
# No network, no background task, no notification: expiry reminders are visual only.
$script:managerMetadataFileName='服务器元数据.json'
$script:managerMetadataVersion=1
$script:managerGroupMaxLength=20
$script:managerNoteMaxLength=200
$script:managerExpiringDays=7
$script:managerReservedGroups=@('全部','全部服务器','未分组','即将到期','已到期')

function Get-ManagerMetadataPath {
    # Derived from the active server list so test fixtures are isolated automatically.
    return (Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:configPath))) $script:managerMetadataFileName)
}
function Get-ManagerToday {
    if($script:managerTodayOverride){return ([DateTime]$script:managerTodayOverride).Date}
    return [DateTime]::Today
}
function Import-ManagerMetadata {
    $path=Get-ManagerMetadataPath
    $store=@{Path=$path;Exists=$false;Doc=$null;ById=@{};Error=$null;ReadOnly=$false}
    try{
        if([IO.File]::Exists($path)){
            $store.Exists=$true
            $text=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
            if($text.Trim()){
                $doc=ConvertFrom-Json -InputObject $text
                if($doc -isnot [pscustomobject]){throw 'Metadata root must be an object.'}
                $versionProperty=$doc.PSObject.Properties['Version']
                if($versionProperty -and $null -ne $versionProperty.Value -and [int]$versionProperty.Value -gt $script:managerMetadataVersion){$store.ReadOnly=$true}
                foreach($record in @($doc.Servers)){
                    if($record -is [pscustomobject] -and $record.Id -and -not $store.ById.ContainsKey([string]$record.Id)){$store.ById[[string]$record.Id]=$record}
                }
                $store.Doc=$doc
            }
        }
    }catch{
        $store.Error='服务器元数据文件无法读取'
        $store.ById=@{};$store.Doc=$null
    }
    $script:managerMetadata=$store
    return $store
}
function Get-ManagerMetadataStore {
    if(-not $script:managerMetadata -or $script:managerMetadata.Path -ne (Get-ManagerMetadataPath)){return (Import-ManagerMetadata)}
    return $script:managerMetadata
}
function Get-ManagerMetadataText($Record,[string]$Name) {
    if($null -eq $Record){return ''}
    $property=$Record.PSObject.Properties[$Name]
    if($null -eq $property -or $null -eq $property.Value){return ''}
    return ([string]$property.Value).Trim()
}
# Quotas are byte counts, with the user's value and unit retained for the settings dialog.
# Decimal units match common provider quotas; binary units match 3X-UI's GiB display.
function ConvertTo-ManagerTrafficQuotaInput {
    param([AllowEmptyString()][AllowNull()][string]$TotalTrafficValue='',[AllowEmptyString()][AllowNull()][string]$TotalTrafficUnit='GB')
    $value=([string]$TotalTrafficValue).Trim()
    if(-not $value){return @{TotalTrafficBytes=$null;TrafficQuotaValue='';TrafficQuotaUnit=''}}
    if($value -notmatch '^[0-9]+(?:\.[0-9]{1,3})?$'){throw '总流量请输入大于 0 的数字，最多 3 位小数；不设置请留空。'}
    $unit=([string]$TotalTrafficUnit).Trim()
    $factor=switch($unit){
        'GB' {$unit='GB';[decimal]1000000000;break}
        'TB' {$unit='TB';[decimal]1000000000000;break}
        'GiB' {$unit='GiB';[decimal]1073741824;break}
        'TiB' {$unit='TiB';[decimal]1099511627776;break}
        default {throw '总流量单位应为 GB、TB、GiB 或 TiB。'}
    }
    $number=[decimal]0
    if(-not [decimal]::TryParse($value,[Globalization.NumberStyles]::AllowDecimalPoint,[Globalization.CultureInfo]::InvariantCulture,[ref]$number) -or $number -le 0){throw '总流量应大于 0，且不能超过支持范围。'}
    $maxBytes=[decimal][UInt64]::MaxValue
    if($number -gt ($maxBytes/$factor)){throw '总流量过大，已超过支持范围。'}
    $bytes=[decimal]::Round(($number*$factor),0,[MidpointRounding]::AwayFromZero)
    if($bytes -le 0 -or $bytes -gt $maxBytes){throw '总流量应大于 0，且不能超过支持范围。'}
    return @{TotalTrafficBytes=[UInt64]$bytes;TrafficQuotaValue=$number.ToString('0.###',[Globalization.CultureInfo]::InvariantCulture);TrafficQuotaUnit=$unit}
}
# Normalized, display-ready view of one server's metadata (no secrets involved).
function Get-ManagerEntryMetadata($Entry) {
    $store=Get-ManagerMetadataStore
    $record=$store.ById[[string]$Entry.Id]
    $expiryText=Get-ManagerMetadataText $record 'Expiry'
    $result=[pscustomobject]@{
        Expiry=$expiryText;Group=(Get-ManagerMetadataText $record 'Group');Note=(Get-ManagerMetadataText $record 'Note')
        ExpiryDate=$null;DaysLeft=$null;ExpiryKind='None'
        TotalTrafficBytes=$null;TotalTrafficValue='';TotalTrafficUnit='GB';TrafficQuotaValue='';TrafficQuotaUnit=''
    }
    if($expiryText){
        $date=[DateTime]::MinValue
        if($expiryText -match '^\d{4}-\d{2}-\d{2}$' -and [DateTime]::TryParseExact($expiryText,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){
            $result.ExpiryDate=$date.Date
            $result.DaysLeft=[int][Math]::Round(($date.Date-(Get-ManagerToday)).TotalDays)
            $result.ExpiryKind=if($result.DaysLeft -lt 0){'Expired'}elseif($result.DaysLeft -le $script:managerExpiringDays){'Expiring'}else{'Ok'}
        }else{$result.ExpiryKind='Invalid'}
    }
    $bytesText=Get-ManagerMetadataText $record 'TotalTrafficBytes'
    $quotaBytes=[UInt64]0
    if($bytesText -match '^[0-9]+$' -and [UInt64]::TryParse($bytesText,[Globalization.NumberStyles]::None,[Globalization.CultureInfo]::InvariantCulture,[ref]$quotaBytes) -and $quotaBytes -gt 0){
        $result.TotalTrafficBytes=$quotaBytes
        $result.TotalTrafficValue=([decimal]$quotaBytes/[decimal]1000000000).ToString('0.###',[Globalization.CultureInfo]::InvariantCulture)
        try{
            $quota=ConvertTo-ManagerTrafficQuotaInput -TotalTrafficValue (Get-ManagerMetadataText $record 'TrafficQuotaValue') -TotalTrafficUnit (Get-ManagerMetadataText $record 'TrafficQuotaUnit')
            if($quota.TotalTrafficBytes -eq $quotaBytes){
                $result.TotalTrafficValue=$quota.TrafficQuotaValue;$result.TotalTrafficUnit=$quota.TrafficQuotaUnit
                $result.TrafficQuotaValue=$quota.TrafficQuotaValue;$result.TrafficQuotaUnit=$quota.TrafficQuotaUnit
            }
        }catch{
            # A malformed optional display value cannot prevent the server card from loading.
        }
    }
    return $result
}
# Validation with user-facing Chinese messages. Empty means "not set".
function ConvertTo-ManagerMetadataInput {
    param(
        [AllowEmptyString()][AllowNull()][string]$Expiry,[AllowEmptyString()][AllowNull()][string]$Group,[AllowEmptyString()][AllowNull()][string]$Note,
        [AllowEmptyString()][AllowNull()][string]$TotalTrafficValue='',[AllowEmptyString()][AllowNull()][string]$TotalTrafficUnit='GB'
    )
    $expiryValue=([string]$Expiry).Trim()
    if($expiryValue){
        if($expiryValue -notmatch '^\d{4}-\d{2}-\d{2}$'){throw '到期日格式应为 yyyy-MM-dd，例如 2026-12-31；不设置请留空。'}
        $date=[DateTime]::MinValue
        if(-not [DateTime]::TryParseExact($expiryValue,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw '到期日不是有效日期，请检查月份和日期。'}
        if($date.Year -lt 2000 -or $date.Year -gt 2099){throw '到期日年份应在 2000 到 2099 之间。'}
    }
    $groupValue=([string]$Group).Trim()
    if($groupValue -match '\p{Cc}'){throw '客户分组不能包含换行或控制字符。'}
    if($groupValue.Length -gt $script:managerGroupMaxLength){throw ('客户分组最多 '+$script:managerGroupMaxLength+' 个字符（当前 '+$groupValue.Length+' 个）。')}
    if($groupValue -and $script:managerReservedGroups -contains $groupValue){throw ('「'+$groupValue+'」是侧栏保留名称，请换一个客户分组名称。')}
    $noteValue=(([string]$Note) -replace "`r`n","`n" -replace "`r","`n").Trim()
    if($noteValue -match '[\p{Cc}-[\n\t]]'){throw '备注包含不支持的控制字符。'}
    if($noteValue.Length -gt $script:managerNoteMaxLength){throw ('备注最多 '+$script:managerNoteMaxLength+' 个字符（当前 '+$noteValue.Length+' 个）。')}
    $quota=ConvertTo-ManagerTrafficQuotaInput -TotalTrafficValue $TotalTrafficValue -TotalTrafficUnit $TotalTrafficUnit
    return @{Expiry=$expiryValue;Group=$groupValue;Note=$noteValue;TotalTrafficBytes=$quota.TotalTrafficBytes;TrafficQuotaValue=$quota.TrafficQuotaValue;TrafficQuotaUnit=$quota.TrafficQuotaUnit}
}
function Get-ManagerMetadataGroups {
    $store=Get-ManagerMetadataStore
    $ids=@{};foreach($entry in @($script:entries)){if($entry){$ids[[string]$entry.Id]=$true}}
    $groups=[Collections.Generic.SortedSet[string]]::new([StringComparer]::Create([Globalization.CultureInfo]::GetCultureInfo('zh-CN'),$false))
    foreach($id in $store.ById.Keys){
        if(-not $ids.ContainsKey($id)){continue}
        $group=Get-ManagerMetadataText $store.ById[$id] 'Group'
        if($group){[void]$groups.Add($group)}
    }
    return @($groups)
}
function Get-ManagerMetadataSnapshot {
    $path=Get-ManagerMetadataPath
    $exists=[IO.File]::Exists($path)
    return @{Path=$path;Exists=$exists;Bytes=if($exists){[IO.File]::ReadAllBytes($path)}else{$null}}
}
function Restore-ManagerMetadataSnapshot($Snapshot) {
    $tmp=$Snapshot.Path+'.tmp'
    try{
        if($Snapshot.Exists){
            [IO.File]::WriteAllBytes($tmp,$Snapshot.Bytes)
            if([IO.File]::Exists($Snapshot.Path)){[IO.File]::Replace($tmp,$Snapshot.Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Snapshot.Path)}
        }elseif([IO.File]::Exists($Snapshot.Path)){[IO.File]::Delete($Snapshot.Path)}
    }finally{
        if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
        [void](Import-ManagerMetadata)
    }
}
# Transactional: builds the new document on a deep copy, writes temp file + replace (Write-ManagerAtomicText).
# On any failure the original file and the in-memory store stay unchanged.
function Save-ManagerMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Id,[Parameter(Mandatory=$true)][hashtable]$Values)
    $ErrorActionPreference='Stop'
    $store=Import-ManagerMetadata
    if($store.Error){throw '服务器元数据文件（统一管理\服务器元数据.json）无法读取。为避免覆盖，本次未保存到期日、分组、备注和总流量；请先修复该文件。'}
    if($store.ReadOnly){throw '服务器元数据文件由更新版本的程序创建，本版本不会改写它。'}
    $doc=if($store.Doc){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $store.Doc -Depth 30)}else{[pscustomobject]@{Version=$script:managerMetadataVersion;Servers=@()}}
    if(-not $doc.PSObject.Properties['Version']){$doc | Add-Member -MemberType NoteProperty -Name Version -Value $script:managerMetadataVersion}
    $servers=[Collections.ArrayList]::new()
    foreach($item in @($doc.Servers)){if($null -ne $item){[void]$servers.Add($item)}}
    $record=$null
    foreach($item in $servers){if($item -is [pscustomobject] -and [string]$item.Id -eq $Id){$record=$item;break}}
    $hasValue=[bool]($Values.Expiry -or $Values.Group -or $Values.Note -or $Values.TotalTrafficBytes)
    if(-not $record){
        if(-not $hasValue){return $false}
        $record=[pscustomobject]@{Id=$Id};[void]$servers.Add($record)
    }
    foreach($field in 'Expiry','Group','Note'){
        if($Values[$field]){$record | Add-Member -MemberType NoteProperty -Name $field -Value ([string]$Values[$field]) -Force}
        elseif($record.PSObject.Properties[$field]){$record.PSObject.Properties.Remove($field)}
    }
    if($Values.ContainsKey('TotalTrafficBytes')){
        if($null -ne $Values.TotalTrafficBytes -and [decimal]$Values.TotalTrafficBytes -gt 0){
            $record | Add-Member -MemberType NoteProperty -Name TotalTrafficBytes -Value ([UInt64]$Values.TotalTrafficBytes) -Force
            foreach($field in 'TrafficQuotaValue','TrafficQuotaUnit'){
                if($Values[$field]){$record | Add-Member -MemberType NoteProperty -Name $field -Value ([string]$Values[$field]) -Force}
                elseif($record.PSObject.Properties[$field]){$record.PSObject.Properties.Remove($field)}
            }
        }else{
            foreach($field in 'TotalTrafficBytes','TrafficQuotaValue','TrafficQuotaUnit'){
                if($record.PSObject.Properties[$field]){$record.PSObject.Properties.Remove($field)}
            }
        }
    }
    if(-not @($record.PSObject.Properties | Where-Object {$_.Name -ne 'Id'}).Count){[void]$servers.Remove($record)}
    $doc | Add-Member -MemberType NoteProperty -Name Servers -Value ([object[]]$servers.ToArray()) -Force
    $json=ConvertTo-Json -InputObject $doc -Depth 30
    Write-ManagerAtomicText -Path $store.Path -Text $json -Encoding ([Text.UTF8Encoding]::new($true))
    [void](Import-ManagerMetadata)
    return $true
}
# One edit-dialog save: validate all fields first, then write only changed metadata and settings.
# If the settings part fails, the metadata file is restored byte-for-byte.
function Save-ManagerServerEdit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Entry,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Url,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Username,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Password,
        [AllowEmptyString()][string]$Expiry='',
        [AllowEmptyString()][string]$Group='',
        [AllowEmptyString()][string]$Note='',
        [AllowEmptyString()][AllowNull()][string]$TotalTrafficValue='',
        [AllowEmptyString()][AllowNull()][string]$TotalTrafficUnit='GB'
    )
    $ErrorActionPreference='Stop'
    $values=ConvertTo-ManagerMetadataInput -Expiry $Expiry -Group $Group -Note $Note -TotalTrafficValue $TotalTrafficValue -TotalTrafficUnit $TotalTrafficUnit
    # Use the same validation as Save-PanelSettings before deciding whether that writer is needed.
    # Metadata-only saves must not rewrite the server list or re-encrypt an unchanged account.
    $newName=$Name.Trim();$newUrl=$Url.Trim();$newUsername=$Username.Trim();$uri=$null
    if(-not $newName){throw '请填写自定义名称。'}
    if(-not [Uri]::TryCreate($newUrl,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo){throw '请填写完整的 http:// 或 https:// 面板地址（不要在地址里填写密码）。'}
    if($Entry.Tunnel -and ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Entry.Tunnel.LocalPort)){throw ('此面板通过 SSH 隧道访问，请保留 http://127.0.0.1:'+$Entry.Tunnel.LocalPort+'，仅修改后面的面板路径。')}
    if(($newUsername -and -not $Password) -or ($Password -and -not $newUsername)){throw '账号和密码需要同时填写，或同时留空。'}
    try{
        $account=Read-PanelAccount $Entry
        if($null -eq $account -or $account -isnot [pscustomobject]){throw 'Invalid account object.'}
        $settingsChanged=($newName -cne [string]$Entry.Name) -or ($newUrl -cne [string]$Entry.Url) -or ($newUsername -cne [string]$account.username) -or ($Password -cne [string]$account.password)
    }catch{
        throw '本机账号不可读取。请先从原电脑导出账号并在本机导入，再修改设置。'
    }finally{$account=$null}
    [void](Import-ManagerMetadata)
    $current=Get-ManagerEntryMetadata $Entry
    if(-not $PSBoundParameters.ContainsKey('TotalTrafficValue')){
        $values.TotalTrafficBytes=$current.TotalTrafficBytes;$values.TrafficQuotaValue=$current.TrafficQuotaValue;$values.TrafficQuotaUnit=$current.TrafficQuotaUnit
    }
    $changed=($values.Expiry -cne $current.Expiry) -or ($values.Group -cne $current.Group) -or ($values.Note -cne $current.Note)
    $changed=$changed -or ($values.TotalTrafficBytes -ne $current.TotalTrafficBytes) -or ($values.TrafficQuotaValue -cne $current.TrafficQuotaValue) -or ($values.TrafficQuotaUnit -cne $current.TrafficQuotaUnit)
    $snapshot=$null
    if($changed){
        $snapshot=Get-ManagerMetadataSnapshot
        [void](Save-ManagerMetadata -Id ([string]$Entry.Id) -Values $values)
    }
    try{
        if($settingsChanged){Save-PanelSettings -Entry $Entry -Name $Name -Url $Url -Username $Username -Password $Password | Out-Null}
    }catch{
        $settingsError=$_
        if($snapshot){
            try{Restore-ManagerMetadataSnapshot $snapshot}
            catch{throw '设置保存失败，且到期日 / 分组 / 备注 / 总流量恢复未完成。请检查 统一管理\服务器元数据.json。'}
        }
        throw $settingsError
    }
    return @{ConnectionChanged=[bool]$settingsChanged;MetadataChanged=[bool]$changed}
}
