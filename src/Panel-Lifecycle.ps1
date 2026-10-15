# Local server lifecycle only. No server-side actions, network requests or backup folders.
# The manager supplies Core/Metadata, $script:workspace, $script:configPath and $script:entries.
function ConvertTo-ManagerLocationInput {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Country='',[AllowEmptyString()][AllowNull()][string]$City='')
    $countryValue=([string]$Country).Trim();$cityValue=([string]$City).Trim()
    if($countryValue -match '\p{Cc}' -or $cityValue -match '\p{Cc}'){throw '国家地区和城市不能包含换行或控制字符。'}
    if($countryValue.Length -gt 30 -or $cityValue.Length -gt 40){throw '国家地区最多 30 个字符，城市最多 40 个字符。'}
    $aliases=@{'美国'='US';'美利坚合众国'='US';'US'='US';'USA'='US';'香港'='HK';'中国香港'='HK';'HK'='HK';'英国'='GB';'UK'='GB';'GB'='GB';'日本'='JP';'JP'='JP';'新加坡'='SG';'SG'='SG';'中国'='CN';'CN'='CN';'台湾'='TW';'中国台湾'='TW';'TW'='TW';'德国'='DE';'DE'='DE';'加拿大'='CA';'CA'='CA';'澳大利亚'='AU';'AU'='AU';'韩国'='KR';'KR'='KR';'法国'='FR';'FR'='FR';'荷兰'='NL';'NL'='NL'}
    if($aliases.ContainsKey($countryValue)){$countryValue=$aliases[$countryValue]}
    elseif($countryValue -match '^[a-zA-Z]{2}$'){$countryValue=$countryValue.ToUpperInvariant()}
    return @{Country=$countryValue;City=$cityValue}
}
function Get-ManagerEntryLocation {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry)
    $store=Get-ManagerMetadataStore;$record=$store.ById[[string]$Entry.Id]
    $country=Get-ManagerMetadataText $record 'Country';$city=Get-ManagerMetadataText $record 'City'
    $name=[string]$Entry.Name
    if(-not $country){
        $legacy=@(@('香港','HK'),@('台湾','TW'),@('美国','US'),@('英国','GB'),@('日本','JP'),@('新加坡','SG'),@('加拿大','CA'),@('德国','DE'),@('澳大利亚','AU'),@('韩国','KR'),@('法国','FR'),@('荷兰','NL'),@('中国','CN'))
        foreach($pair in $legacy){if($name.Contains($pair[0])){$country=$pair[1];break}}
    }
    if(-not $city){foreach($value in '洛杉矶','西雅图','加州','圣何塞','纽约','达拉斯','芝加哥','伦敦','东京','大阪','法兰克福','阿姆斯特丹'){if($name.Contains($value)){$city=$value;break}}}
    $location=ConvertTo-ManagerLocationInput -Country $country -City $city
    $names=@{US='美国';HK='香港';GB='英国';JP='日本';SG='新加坡';CN='中国';TW='台湾';DE='德国';CA='加拿大';AU='澳大利亚';KR='韩国';FR='法国';NL='荷兰'}
    $label=if($names.ContainsKey($location.Country)){$names[$location.Country]}elseif($location.Country){$location.Country}else{'地区未设'}
    return [pscustomobject]@{Country=$location.Country;CountryCode=$location.Country;CountryName=$label;City=$location.City;DisplayName=if($location.City){$label+'-'+$location.City}else{$label}}
}
function Get-ManagerLifecycleMetadataDocument {
    $store=Import-ManagerMetadata
    if($store.Error){throw '服务器元数据文件无法读取。为避免覆盖，未更改服务器资料。'}
    if($store.ReadOnly){throw '服务器元数据由更新版本创建，本版本不会改写它。'}
    $doc=if($store.Doc){ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $store.Doc -Depth 30)}else{[pscustomobject]@{Version=1;Servers=@()}}
    if(-not $doc.PSObject.Properties['Version']){$doc | Add-Member NoteProperty Version 1}
    return $doc
}
function Save-ManagerLocationMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry,[AllowEmptyString()][AllowNull()][string]$Country='',[AllowEmptyString()][AllowNull()][string]$City='')
    $ErrorActionPreference='Stop';$values=ConvertTo-ManagerLocationInput -Country $Country -City $City
    $doc=Get-ManagerLifecycleMetadataDocument;$records=[Collections.ArrayList]::new();$record=$null
    foreach($item in @($doc.Servers)){if($item){[void]$records.Add($item);if([string]$item.Id -ceq [string]$Entry.Id){$record=$item}}}
    if(-not $record){if(-not ($values.Country -or $values.City)){return $false};$record=[pscustomobject]@{Id=[string]$Entry.Id};[void]$records.Add($record)}
    $changed=$false
    foreach($field in 'Country','City'){
        $current=Get-ManagerMetadataText $record $field
        if($current -cne $values[$field]){$changed=$true}
        if($values[$field]){$record | Add-Member NoteProperty $field ([string]$values[$field]) -Force}
        elseif($record.PSObject.Properties[$field]){$record.PSObject.Properties.Remove($field)}
    }
    if(-not $changed){return $false}
    if(-not @($record.PSObject.Properties | Where-Object {$_.Name -ne 'Id'}).Count){[void]$records.Remove($record)}
    $doc | Add-Member NoteProperty Servers ([object[]]$records.ToArray()) -Force
    Write-ManagerAtomicText -Path (Get-ManagerMetadataPath) -Text (ConvertTo-Json -InputObject $doc -Depth 30) -Encoding ([Text.UTF8Encoding]::new($true))
    [void](Import-ManagerMetadata);return $true
}
function Get-ManagerLifecycleFileSnapshot([string]$Path) {
    return @{Path=$Path;Exists=[IO.File]::Exists($Path);Bytes=if([IO.File]::Exists($Path)){[IO.File]::ReadAllBytes($Path)}else{$null}}
}
function Restore-ManagerLifecycleFileSnapshot($Snapshot) {
    if($Snapshot.Exists){
        $tmp=$Snapshot.Path+'.tmp'
        try{[IO.File]::WriteAllBytes($tmp,$Snapshot.Bytes);if([IO.File]::Exists($Snapshot.Path)){[IO.File]::Replace($tmp,$Snapshot.Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Snapshot.Path)}}finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
    }elseif([IO.File]::Exists($Snapshot.Path)){[IO.File]::Delete($Snapshot.Path)}
}
function Get-ManagerLifecycleFileStamp([string]$Path) {
    if(-not [IO.File]::Exists($Path)){return '<absent>'}
    $sha=[Security.Cryptography.SHA256]::Create();try{return [Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($Path)))}finally{$sha.Dispose()}
}
function Get-ManagerLifecycleCurrentEntries {
    $current=@($script:entries | Where-Object {$null -ne $_})
    $onDisk=@(if([IO.File]::Exists($script:configPath)){(ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($script:configPath,[Text.Encoding]::UTF8))) | Where-Object {$null -ne $_}})
    $memoryJson=ConvertTo-Json -InputObject ([object[]]$current) -Depth 30 -Compress
    $diskJson=ConvertTo-Json -InputObject ([object[]]$onDisk) -Depth 30 -Compress
    if($memoryJson -cne $diskJson){throw '服务器列表已被其他窗口修改，请关闭后重新打开客户端再操作。'}
    return [object[]]$current
}
function Assert-ManagerLifecyclePlainDirectory([string]$Path) {
    if(-not [IO.Directory]::Exists($Path)){if([IO.File]::Exists($Path)){throw '待清理的资料路径指向文件，拒绝清理。'};return}
    # Inspect each directory before descending; never enumerate a junction target.
    $pending=[Collections.Generic.Queue[string]]::new();$pending.Enqueue($Path)
    while($pending.Count -gt 0){
        $currentPath=$pending.Dequeue();$currentItem=Get-Item -LiteralPath $currentPath -Force
        if(($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw '资料目录含符号链接或目录联接，拒绝清理。'}
        foreach($child in @(Get-ChildItem -LiteralPath $currentPath -Force)){
            if(($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw '资料目录含符号链接或目录联接，拒绝清理。'}
            if($child.PSIsContainer){$pending.Enqueue($child.FullName)}
        }
    }
}
function Get-ManagerLifecyclePanelOrigin([string]$Url) {
    $uri=$null
    if(-not [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo){throw '服务器面板地址无效，无法确定缓存范围。'}
    return ($uri.Scheme+'|'+$uri.Host+'|'+$uri.Port)
}
function Get-ManagerLifecycleBrowserCachePlan {
    param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Entries)
    $origin=Get-ManagerLifecyclePanelOrigin ([string]$Entry.Url);$sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($origin))).Replace('-','').Substring(0,16).ToLowerInvariant()}finally{$sha.Dispose()}
    $root=[IO.Path]::GetFullPath([string]$script:workspace).TrimEnd('\','/')
    $parent=[IO.Path]::GetFullPath((Join-Path $root '面板浏览器'));$path=[IO.Path]::GetFullPath((Join-Path $parent $hash))
    if([IO.Path]::GetDirectoryName($parent) -cne $root -or [IO.Path]::GetDirectoryName($path) -cne $parent -or [IO.Path]::GetFileName($path) -notmatch '^[a-f0-9]{16}$'){throw '浏览器缓存目录超出本地工作区，拒绝清理。'}
    $shared=$false
    foreach($other in $Entries){
        if([string]$other.Id -ceq [string]$Entry.Id){continue}
        if((Get-ManagerLifecyclePanelOrigin ([string]$other.Url)) -ceq $origin){$shared=$true;break}
    }
    $exists=[IO.Directory]::Exists($path);$fileCount=0;$bytes=[Int64]0
    if(-not $shared){
        if([IO.Directory]::Exists($parent)){
            $item=Get-Item -LiteralPath $parent -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw '浏览器缓存目录含符号链接或目录联接，拒绝清理。'}
        }elseif([IO.File]::Exists($parent)){throw '浏览器缓存目录指向文件，拒绝清理。'}
        Assert-ManagerLifecyclePlainDirectory $path
        if($exists){foreach($file in @(Get-ChildItem -LiteralPath $path -Force -Recurse -File)){$fileCount++;$bytes+=$file.Length}}
    }
    return [pscustomobject]@{Path=$path;Exists=$exists;Shared=$shared;ShouldRecycle=($exists -and -not $shared);FileCount=$fileCount;Bytes=$bytes}
}
function Assert-ManagerLifecycleTunnelInactive($Entry,[string]$FolderPath) {
    if(-not $Entry.Tunnel -or -not (Get-Command Test-PanelTunnelProcess -ErrorAction SilentlyContinue)){return}
    $candidatePids=[Collections.Generic.HashSet[int]]::new();$statePath=Join-Path $FolderPath '凭据\隧道运行\process.json'
    if([IO.File]::Exists($statePath)){
        try{$state=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($statePath));if([int]$state.ProcessId -gt 0){[void]$candidatePids.Add([int]$state.ProcessId)}}catch{}
    }
    if($Entry.Tunnel.LocalPort -and (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)){
        foreach($listener in @(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort ([int]$Entry.Tunnel.LocalPort) -State Listen -ErrorAction SilentlyContinue)){if([int]$listener.OwningProcess -gt 0){[void]$candidatePids.Add([int]$listener.OwningProcess)}}
    }
    foreach($pidValue in $candidatePids){if(Test-PanelTunnelProcess $Entry $pidValue){throw '这台服务器的 SSH 隧道仍在使用，请先关闭对应隧道连接再清理本地资料；也可以取消勾选「清理本地资料」。'}}
}
function Resolve-ManagerLifecycleOwnedDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry,[Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Entries)
    $root=[IO.Path]::GetFullPath([string]$script:workspace).TrimEnd('\','/')
    $folder=([string]$Entry.Folder).Trim()
    if(-not $folder -or [IO.Path]::IsPathRooted($folder) -or $folder -match '[\\/]' -or $folder -in @('.','..','统一管理','面板浏览器','.git','.agents','.codex','.aws')){throw '此条目的本地资料目录不是独立服务器目录，拒绝清理。'}
    $path=[IO.Path]::GetFullPath((Join-Path $root $folder))
    if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetDirectoryName($path) -ne $root){throw '本地目录超出工作区，拒绝清理。'}
    $secret=([string]$Entry.SecretFile).Trim()
    if(-not $secret -or [IO.Path]::IsPathRooted($secret)){throw '账号文件不属于这台服务器的独立目录，拒绝清理。'}
    $secretPath=[IO.Path]::GetFullPath((Join-Path $root $secret))
    if(-not $secretPath.StartsWith($path+'\',[StringComparison]::OrdinalIgnoreCase)){throw '账号文件不属于这台服务器的独立目录，拒绝清理。'}
    foreach($other in $Entries){
        if([string]$other.Id -ceq [string]$Entry.Id){continue}
        foreach($value in @($other.Folder,$other.SecretFile,$other.Tunnel.KeyFile,$other.Tunnel.KnownHostsFile)){
            if(-not $value){continue};$otherPath=[IO.Path]::GetFullPath((Join-Path $root ([string]$value)))
            if([string]::Equals($otherPath,$path,[StringComparison]::OrdinalIgnoreCase) -or $otherPath.StartsWith($path+'\',[StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith($otherPath+'\',[StringComparison]::OrdinalIgnoreCase)){throw '此目录被其他服务器共用，拒绝清理。'}
        }
    }
    Assert-ManagerLifecyclePlainDirectory $path
    return $path
}
function Get-ManagerServerRemovalPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry,[switch]$DeleteLocalFiles)
    $ErrorActionPreference='Stop';$all=@(Get-ManagerLifecycleCurrentEntries)
    $matches=@($all | Where-Object {[string]$_.Id -ceq [string]$Entry.Id})
    if($matches.Count -ne 1){throw '服务器条目不存在或 ID 重复，拒绝删除。'}
    if((ConvertTo-Json -InputObject $matches[0] -Depth 30 -Compress) -cne (ConvertTo-Json -InputObject $Entry -Depth 30 -Compress)){throw '这台服务器的资料已经变化，请重新打开删除窗口。'}
    [void](Get-ManagerLifecycleMetadataDocument)
    $folderPath=$null;$fileCount=0;$byteCount=[Int64]0;$cache=$null
    if($DeleteLocalFiles){
        $folderPath=Resolve-ManagerLifecycleOwnedDirectory -Entry $Entry -Entries $all;Assert-ManagerLifecycleTunnelInactive -Entry $Entry -FolderPath $folderPath
        if([IO.Directory]::Exists($folderPath)){foreach($file in @(Get-ChildItem -LiteralPath $folderPath -Force -Recurse -File)){$fileCount++;$byteCount+=$file.Length}}
        $cache=Get-ManagerLifecycleBrowserCachePlan -Entry $Entry -Entries $all
    }
    return [pscustomobject]@{Id=[string]$Entry.Id;Name=[string]$Entry.Name;Entry=$matches[0];DeleteLocalFiles=[bool]$DeleteLocalFiles;FolderPath=$folderPath;FolderExists=[bool]($folderPath -and [IO.Directory]::Exists($folderPath));FileCount=$fileCount;Bytes=$byteCount;BrowserCachePath=if($cache){$cache.Path}else{$null};BrowserCacheExists=[bool]($cache -and $cache.Exists);BrowserCacheShared=[bool]($cache -and $cache.Shared);RecycleBrowserCache=[bool]($cache -and $cache.ShouldRecycle);BrowserCacheFileCount=if($cache){$cache.FileCount}else{0};BrowserCacheBytes=if($cache){$cache.Bytes}else{0};OtherServerCount=$all.Count-1;CanUndoListOnly=(-not $DeleteLocalFiles);ServerSideAction=$false}
}
function Invoke-ManagerRecycleDirectory([string]$Path) {
    if($script:managerRecycleDirectoryOverride){& $script:managerRecycleDirectoryOverride $Path;return}
    Add-Type -AssemblyName Microsoft.VisualBasic
    # A local user's Recycle Bin preserves recoverability; no permanent-delete fallback.
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin,[Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException)
}
function Remove-ManagerServer {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry,[switch]$DeleteLocalFiles)
    $ErrorActionPreference='Stop';$plan=Get-ManagerServerRemovalPlan -Entry $Entry -DeleteLocalFiles:$DeleteLocalFiles
    $beforeEntries=[object[]]@(Get-ManagerLifecycleCurrentEntries);$configSnapshot=Get-ManagerLifecycleFileSnapshot $script:configPath;$metaSnapshot=Get-ManagerLifecycleFileSnapshot (Get-ManagerMetadataPath)
    $remaining=[object[]]@($beforeEntries | Where-Object {[string]$_.Id -cne [string]$Entry.Id})
    $doc=Get-ManagerLifecycleMetadataDocument;$hadRecord=[bool]@($doc.Servers | Where-Object {[string]$_.Id -ceq [string]$Entry.Id}).Count
    $doc | Add-Member NoteProperty Servers ([object[]]@($doc.Servers | Where-Object {[string]$_.Id -cne [string]$Entry.Id})) -Force
    $cacheRecycled=$false
    try{
        Write-ManagerAtomicText -Path $script:configPath -Text (ConvertTo-Json -InputObject $remaining -Depth 30) -Encoding ([Text.UTF8Encoding]::new($true))
        if($hadRecord){Write-ManagerAtomicText -Path (Get-ManagerMetadataPath) -Text (ConvertTo-Json -InputObject $doc -Depth 30) -Encoding ([Text.UTF8Encoding]::new($true))}
        # Cache is recreatable; clean it before touching the irreplaceable local account directory.
        if($plan.RecycleBrowserCache){Invoke-ManagerRecycleDirectory $plan.BrowserCachePath;$cacheRecycled=$true}
        if($plan.FolderExists){Invoke-ManagerRecycleDirectory $plan.FolderPath}
    }catch{
        $original=$_
        try{Restore-ManagerLifecycleFileSnapshot $configSnapshot;Restore-ManagerLifecycleFileSnapshot $metaSnapshot;$script:entries=$beforeEntries;[void](Import-ManagerMetadata)}catch{throw '删除失败且本地列表恢复未完成，请保留当前文件并检查本地资料。'}
        if($cacheRecycled){throw ('本地资料清理未完成，服务器列表和元数据已恢复；浏览器缓存已送入 Windows 回收站，下次打开面板会重新生成。原因：'+$original.Exception.Message)}
        throw $original
    }
    $script:entries=$remaining;[void](Import-ManagerMetadata)
    $undo=$null
    if(-not $DeleteLocalFiles){$undo=[pscustomobject]@{ConfigSnapshot=$configSnapshot;MetadataSnapshot=$metaSnapshot;Entries=$beforeEntries;ConfigStamp=(Get-ManagerLifecycleFileStamp $script:configPath);MetadataStamp=(Get-ManagerLifecycleFileStamp (Get-ManagerMetadataPath));Used=$false}}
    $script:managerLifecycleUndo=$undo
    return [pscustomobject]@{Removed=$true;Id=$plan.Id;Name=$plan.Name;LocalFilesRecycled=[bool]($plan.FolderExists -or $cacheRecycled);BrowserCacheRecycled=$cacheRecycled;BrowserCacheRetainedForOtherServer=$plan.BrowserCacheShared;FileCount=$plan.FileCount;BrowserCacheFileCount=$plan.BrowserCacheFileCount;RemainingCount=$remaining.Count;UndoToken=$undo;ServerSideAction=$false}
}
function Undo-ManagerServerRemoval {
    [CmdletBinding()]
    param($Token=$script:managerLifecycleUndo)
    $ErrorActionPreference='Stop'
    if(-not $Token -or $Token.Used){throw '当前没有可撤销的列表删除；已清理的资料请从 Windows 回收站恢复。'}
    if($Token.ConfigSnapshot.Path -cne $script:configPath -or $Token.MetadataSnapshot.Path -cne (Get-ManagerMetadataPath)){throw '数据目录已经变化，无法撤销。'}
    if((Get-ManagerLifecycleFileStamp $script:configPath) -cne $Token.ConfigStamp -or (Get-ManagerLifecycleFileStamp (Get-ManagerMetadataPath)) -cne $Token.MetadataStamp){throw '删除后资料已经改变，为避免覆盖，不能撤销这次删除。'}
    $currentConfig=Get-ManagerLifecycleFileSnapshot $script:configPath;$currentMeta=Get-ManagerLifecycleFileSnapshot (Get-ManagerMetadataPath)
    try{Restore-ManagerLifecycleFileSnapshot $Token.ConfigSnapshot;Restore-ManagerLifecycleFileSnapshot $Token.MetadataSnapshot}catch{$original=$_;Restore-ManagerLifecycleFileSnapshot $currentConfig;Restore-ManagerLifecycleFileSnapshot $currentMeta;throw $original}
    $script:entries=$Token.Entries;[void](Import-ManagerMetadata);$Token.Used=$true;$script:managerLifecycleUndo=$null;return $true
}
function Add-ManagerServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Url,
        [AllowEmptyString()][string]$Username='',[AllowEmptyString()][string]$Password='',[AllowEmptyString()][string]$Address='',
        [AllowEmptyString()][string]$Country='',[AllowEmptyString()][string]$City='',[AllowEmptyString()][string]$Expiry='',
        [AllowEmptyString()][string]$Group='',[AllowEmptyString()][string]$Note='',[AllowEmptyString()][string]$TotalTrafficValue='',[AllowEmptyString()][string]$TotalTrafficUnit='GB'
    )
    $ErrorActionPreference='Stop';$newName=$Name.Trim();$newUrl=$Url.Trim();$newUser=$Username.Trim();$uri=$null
    if(-not $newName -or $newName.Length -gt 100 -or $newName -match '\p{Cc}'){throw '服务器名称需要 1 到 100 个字符，不能包含换行或控制字符。'}
    if(-not [Uri]::TryCreate($newUrl,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Fragment){throw '请填写完整的 http:// 或 https:// 面板地址，不要包含账号密码或 # 片段。'}
    if(($newUser -and -not $Password) -or ($Password -and -not $newUser)){throw '账号和密码需要同时填写，或同时留空。'}
    $location=ConvertTo-ManagerLocationInput -Country $Country -City $City
    $metadata=ConvertTo-ManagerMetadataInput -Expiry $Expiry -Group $Group -Note $Note -TotalTrafficValue $TotalTrafficValue -TotalTrafficUnit $TotalTrafficUnit
    [void](Get-ManagerLifecycleMetadataDocument);$beforeEntries=[object[]]@(Get-ManagerLifecycleCurrentEntries)
    if(@($beforeEntries | Where-Object {[string]$_.Url -ceq $newUrl}).Count){throw '这个面板地址已存在，请编辑已有服务器。'}
    $addressValue=$Address.Trim();if($addressValue -match '\p{Cc}' -or $addressValue.Length -gt 255){throw '服务器地址不能包含换行或控制字符，且不能超过 255 个字符。'}
    if(-not $addressValue){$addressValue=$uri.Host}
    $id='server-'+[Guid]::NewGuid().ToString('N');$folder='服务器-'+$id.Substring(7,12)
    $entry=[pscustomobject]@{Id=$id;Name=$newName;Address=$addressValue;Url=$newUrl;SecretFile=($folder+'/凭据/panel.dpapi');Folder=$folder}
    $folderPath=Resolve-ManagerLifecycleOwnedDirectory -Entry $entry -Entries $beforeEntries
    if([IO.Directory]::Exists($folderPath) -or [IO.File]::Exists($folderPath)){throw '新服务器目录发生冲突，请重试。'}
    $configSnapshot=Get-ManagerLifecycleFileSnapshot $script:configPath;$metaSnapshot=Get-ManagerLifecycleFileSnapshot (Get-ManagerMetadataPath);$created=$false
    try{
        [void][IO.Directory]::CreateDirectory((Join-Path $folderPath '凭据'));$created=$true
        [void][IO.Directory]::CreateDirectory((Join-Path $folderPath '资料'))
        $account=[pscustomobject]@{username=$newUser;password=$Password};$json=ConvertTo-Json -InputObject $account -Compress
        $encrypted=ConvertFrom-SecureString (ConvertTo-SecureString $json -AsPlainText -Force)
        Write-ManagerAtomicText -Path (Join-Path $script:workspace $entry.SecretFile) -Text $encrypted -Encoding ([Text.Encoding]::ASCII)
        Write-ManagerAtomicText -Path (Join-Path $folderPath '服务器信息.json') -Text (ConvertTo-Json -InputObject ([pscustomobject]@{Id=$id;Name=$newName;Address=$addressValue;Url=$newUrl}) -Depth 5) -Encoding ([Text.UTF8Encoding]::new($true))
        Write-ManagerAtomicText -Path (Join-Path $folderPath '服务器说明.md') -Text ('# '+$newName+"`r`n`r`n此目录由本地客户端创建。面板账号使用当前 Windows 用户的 DPAPI 加密保存。`r`n") -Encoding ([Text.UTF8Encoding]::new($true))
        Write-ManagerAtomicText -Path (Join-Path $folderPath '打开3x-ui面板.url') -Text ("[InternetShortcut]`r`nURL="+$newUrl+"`r`n") -Encoding ([Text.Encoding]::UTF8)
        $script:entries=[object[]]@($beforeEntries)+@($entry)
        Write-ManagerAtomicText -Path $script:configPath -Text (ConvertTo-Json -InputObject ([object[]]$script:entries) -Depth 30) -Encoding ([Text.UTF8Encoding]::new($true))
        [void](Save-ManagerMetadata -Id $id -Values $metadata)
        [void](Save-ManagerLocationMetadata -Entry $entry -Country $location.Country -City $location.City)
        $script:managerLifecycleUndo=$null
        return $entry
    }catch{
        $original=$_
        Restore-ManagerLifecycleFileSnapshot $configSnapshot;Restore-ManagerLifecycleFileSnapshot $metaSnapshot;$script:entries=$beforeEntries;[void](Import-ManagerMetadata)
        # Only the newly generated directory can be rolled back; no existing server is involved.
        if($created -and [IO.Directory]::Exists($folderPath)){[void](Resolve-ManagerLifecycleOwnedDirectory -Entry $entry -Entries $beforeEntries);Remove-Item -LiteralPath $folderPath -Recurse -Force}
        throw $original
    }finally{$account=$null;$json=$null;$encrypted=$null}
}
