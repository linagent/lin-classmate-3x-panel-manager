# Local purchasing attribution. This sidecar contains provider names and account aliases only.
# It never writes the server inventory, metadata, panel credentials or remote configuration.
# Loading is read-only; a missing file means every server is unassigned.
$script:managerPurchasesFileName='购买来源.json'
$script:managerPurchasesVersion=1

function Get-ManagerPurchasesPath {
    return (Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:configPath))) $script:managerPurchasesFileName)
}
function Get-ManagerPurchasesFingerprint([byte[]]$Bytes,[bool]$Exists) {
    if(-not $Exists){return '<missing>'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','')}finally{$sha.Dispose()}
}
function Get-ManagerPurchasesFileFingerprint([string]$Path) {
    if(-not [IO.File]::Exists($Path)){return '<missing>'}
    return (Get-ManagerPurchasesFingerprint -Bytes ([IO.File]::ReadAllBytes($Path)) -Exists $true)
}
function Get-ManagerPurchaseText($Record,[string]$Name) {
    if($null -eq $Record){return ''}
    $property=$Record.PSObject.Properties[$Name]
    if($null -eq $property -or $null -eq $property.Value){return ''}
    return ([string]$property.Value).Trim()
}
function ConvertTo-ManagerPurchaseText {
    param([AllowEmptyString()][AllowNull()][string]$Value,[string]$Label,[int]$MaxLength,[switch]$AllowEmpty)
    $text=([string]$Value).Trim()
    if(-not $text -and -not $AllowEmpty){throw ('请填写'+$Label+'。')}
    if($text -match '\p{Cc}'){throw ($Label+'不能包含换行或控制字符。')}
    if($text.Length -gt $MaxLength){throw ($Label+'最多 '+$MaxLength+' 个字符。')}
    return $text
}
function Assert-ManagerPurchaseDocument($Doc) {
    if($Doc -isnot [pscustomobject]){throw '购买来源文件的根节点应为对象。'}
    $version=$Doc.PSObject.Properties['Version']
    if(-not $version -or $version.Value -isnot [ValueType] -or ([string]$version.Value) -notmatch '^\d+$' -or [decimal]$version.Value -lt 1){throw '购买来源文件的版本无效。'}
    $index=@{Providers=@{};Accounts=@{};ServerLinks=@{}}
    foreach($collection in 'Providers','Accounts','ServerLinks'){
        $property=$Doc.PSObject.Properties[$collection]
        if(-not $property -or $property.Value -isnot [Array]){throw ('购买来源文件缺少有效的 '+$collection+' 数组。')}
        foreach($record in @($property.Value)){
            if($record -isnot [pscustomobject]){throw ('购买来源文件的 '+$collection+' 记录无效。')}
            $idProperty=$record.PSObject.Properties['Id']
            if(-not $idProperty -or $idProperty.Value -isnot [string]){throw '购买来源文件包含无效的标识。'}
            $id=ConvertTo-ManagerPurchaseText -Value $idProperty.Value -Label '标识' -MaxLength 128
            if($id -cne $idProperty.Value -or $index[$collection].ContainsKey($id)){throw '购买来源文件包含重复或无效的标识。'}
            $index[$collection][$id]=$record
        }
    }
    $providerNames=@{}
    foreach($record in @($Doc.Providers)){
        if($record.PSObject.Properties['Name'].Value -isnot [string]){throw '购买来源文件包含无效的服务商名称。'}
        $name=ConvertTo-ManagerPurchaseText -Value $record.Name -Label '服务商名称' -MaxLength 64
        if($name -cne $record.Name -or $providerNames.ContainsKey($name)){throw '购买来源文件包含重复或无效的服务商名称。'}
        $providerNames[$name]=$true
    }
    $aliases=@{}
    foreach($record in @($Doc.Accounts)){
        if($record.PSObject.Properties['ProviderId'].Value -isnot [string] -or -not $index.Providers.ContainsKey([string]$record.ProviderId)){throw '购买账号引用的服务商不存在。'}
        if($record.PSObject.Properties['Alias'].Value -isnot [string]){throw '购买来源文件包含无效的购买账号别名。'}
        $alias=ConvertTo-ManagerPurchaseText -Value $record.Alias -Label '购买账号别名' -MaxLength 64
        $key=[string]$record.ProviderId+[char]0+$alias
        if($alias -cne $record.Alias -or $aliases.ContainsKey($key)){throw '同一服务商下存在重复或无效的购买账号别名。'}
        $aliases[$key]=$true
        if($record.PSObject.Properties['Hint']){
            if($null -ne $record.Hint -and $record.Hint -isnot [string]){throw '购买账号提示无效。'}
            [void](ConvertTo-ManagerPurchaseText -Value $record.Hint -Label '账号提示' -MaxLength 160 -AllowEmpty)
        }
    }
    foreach($record in @($Doc.ServerLinks)){
        if($record.PSObject.Properties['AccountId'].Value -isnot [string]){throw '服务器购买来源的账号标识无效。'}
        if($record.AccountId -and -not $index.Accounts.ContainsKey([string]$record.AccountId)){throw '服务器购买来源引用的账号不存在。'}
    }
    return $index
}
function Import-ManagerPurchases {
    $path=Get-ManagerPurchasesPath
    $store=@{Path=$path;Exists=$false;Fingerprint='<missing>';Doc=$null;Providers=@{};Accounts=@{};ServerLinks=@{};Error=$null;ReadOnly=$false}
    try{
        if([IO.File]::Exists($path)){
            $store.Exists=$true
            $bytes=[IO.File]::ReadAllBytes($path)
            $store.Fingerprint=Get-ManagerPurchasesFingerprint -Bytes $bytes -Exists $true
            if($bytes.Length -gt 4194304){throw '购买来源文件过大。'}
            $text=([Text.UTF8Encoding]::new($false,$true)).GetString($bytes).TrimStart([char]0xFEFF)
            if(-not $text.Trim()){throw '购买来源文件为空。'}
            $doc=ConvertFrom-Json -InputObject $text -ErrorAction Stop
            $index=Assert-ManagerPurchaseDocument $doc
            $store.Doc=$doc;$store.Providers=$index.Providers;$store.Accounts=$index.Accounts;$store.ServerLinks=$index.ServerLinks
            $store.ReadOnly=([decimal]$doc.Version -gt $script:managerPurchasesVersion)
        }
    }catch{
        $store.Error='购买来源文件无法读取。为避免覆盖，暂时不能保存；请先修复该文件或重新导入有效文件。'
        $store.Doc=$null;$store.Providers=@{};$store.Accounts=@{};$store.ServerLinks=@{};$store.ReadOnly=$true
    }
    $script:managerPurchases=$store
    return $store
}
function Get-ManagerPurchasesStore {
    if(-not $script:managerPurchases -or $script:managerPurchases.Path -ne (Get-ManagerPurchasesPath)){return (Import-ManagerPurchases)}
    return $script:managerPurchases
}
function Get-ManagerPurchaseProviders {
    $store=Get-ManagerPurchasesStore
    foreach($provider in @($store.Doc.Providers | Sort-Object Name)){
        if($null -ne $provider){[pscustomobject]@{Id=[string]$provider.Id;Name=[string]$provider.Name}}
    }
}
function Get-ManagerPurchaseAccounts {
    param([AllowEmptyString()][string]$ProviderId='')
    $store=Get-ManagerPurchasesStore
    foreach($account in @($store.Doc.Accounts | Sort-Object Alias)){
        if($null -ne $account -and (-not $ProviderId -or [string]$account.ProviderId -eq $ProviderId)){
            [pscustomobject]@{Id=[string]$account.Id;ProviderId=[string]$account.ProviderId;Alias=[string]$account.Alias;Hint=(Get-ManagerPurchaseText $account 'Hint')}
        }
    }
}
function Get-ManagerEntryPurchase {
    param([Parameter(Mandatory=$true)]$Entry)
    $store=Get-ManagerPurchasesStore
    $link=$store.ServerLinks[[string]$Entry.Id]
    if(-not $link -or -not $link.AccountId){return $null}
    $account=$store.Accounts[[string]$link.AccountId]
    if(-not $account){return $null}
    $provider=$store.Providers[[string]$account.ProviderId]
    if(-not $provider){return $null}
    return [pscustomobject]@{ProviderId=[string]$provider.Id;ProviderName=[string]$provider.Name;AccountId=[string]$account.Id;AccountAlias=[string]$account.Alias;Hint=(Get-ManagerPurchaseText $account 'Hint')}
}
function New-ManagerPurchasesWorkingDocument($Store) {
    if($Store.Error){throw $Store.Error}
    if($Store.ReadOnly){throw '购买来源文件由更新版本的程序创建，本版本不会改写它。'}
    if($Store.Doc){return (ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Store.Doc -Depth 100) -ErrorAction Stop)}
    return [pscustomobject]@{Version=$script:managerPurchasesVersion;Providers=@();Accounts=@();ServerLinks=@()}
}
function Write-ManagerPurchasesDocument($Store,$Doc) {
    $ErrorActionPreference='Stop'
    [void](Assert-ManagerPurchaseDocument $Doc)
    $json=ConvertTo-Json -InputObject $Doc -Depth 100
    # A per-path named mutex serializes this module's writers across client processes.
    # The on-disk fingerprint also detects external edits since the view was loaded.
    $pathBytes=[Text.Encoding]::UTF8.GetBytes($Store.Path.ToUpperInvariant())
    $mutexName='Local\Public3XuiPurchases_'+(Get-ManagerPurchasesFingerprint -Bytes $pathBytes -Exists $true)
    $mutex=[Threading.Mutex]::new($false,$mutexName);$locked=$false;$tmp=$null
    try{
        try{$locked=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw '另一个客户端正在保存购买来源，请稍后重试。'}
        if((Get-ManagerPurchasesFileFingerprint $Store.Path) -cne $Store.Fingerprint){throw '购买来源已被其他窗口或程序修改，本次未覆盖。请刷新后重新编辑。'}
        $tmp=$Store.Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
        $encoding=[Text.UTF8Encoding]::new($true)
        $preamble=$encoding.GetPreamble();$payload=$encoding.GetBytes($json)
        $stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($preamble,0,$preamble.Length);$stream.Write($payload,0,$payload.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if((Get-ManagerPurchasesFileFingerprint $Store.Path) -cne $Store.Fingerprint){throw '购买来源已被其他程序修改，本次未覆盖。请刷新后重新编辑。'}
        if($Store.Exists){[IO.File]::Replace($tmp,$Store.Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Store.Path)}
        $tmp=$null
        [void](Import-ManagerPurchases)
    }catch [IO.IOException]{
        throw '购买来源未能保存。请检查文件是否被其他程序占用、磁盘是否可写，然后重试；本次没有覆盖原文件。'
    }catch [UnauthorizedAccessException]{
        throw '购买来源未能保存。请检查文件和文件夹的写入权限，然后重试；本次没有覆盖原文件。'
    }finally{
        if($tmp -and [IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
        if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()
    }
}
function Find-ManagerPurchaseProvider($Doc,[string]$Id,[string]$Name) {
    foreach($item in @($Doc.Providers)){
        if(($Id -and [string]$item.Id -eq $Id) -or (-not $Id -and [string]$item.Name -eq $Name)){return $item}
    }
    return $null
}
function Find-ManagerPurchaseAccount($Doc,[string]$Id,[string]$ProviderId,[string]$Alias) {
    foreach($item in @($Doc.Accounts)){
        if(($Id -and [string]$item.Id -eq $Id) -or (-not $Id -and [string]$item.ProviderId -eq $ProviderId -and [string]$item.Alias -eq $Alias)){return $item}
    }
    return $null
}
function Save-ManagerPurchaseProvider {
    param([AllowEmptyString()][string]$Id='',[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name)
    $name=ConvertTo-ManagerPurchaseText -Value $Name -Label '服务商名称' -MaxLength 64
    $store=Get-ManagerPurchasesStore;$doc=New-ManagerPurchasesWorkingDocument $store
    $record=Find-ManagerPurchaseProvider $doc $Id $name
    if($Id -and -not $record){throw '该服务商已不存在，请刷新后重新选择。'}
    if($record -and -not $Id){return [pscustomobject]@{Id=[string]$record.Id;Name=[string]$record.Name}}
    $duplicate=Find-ManagerPurchaseProvider $doc '' $name
    if($duplicate -and $record -and [string]$duplicate.Id -ne [string]$record.Id){throw '已存在同名服务商，请使用已有服务商或换一个名称。'}
    if(-not $record){$record=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');Name=$name};$doc.Providers=@($doc.Providers)+@($record)}
    elseif([string]$record.Name -ceq $name){return [pscustomobject]@{Id=[string]$record.Id;Name=[string]$record.Name}}
    else{$record.Name=$name}
    Write-ManagerPurchasesDocument $store $doc
    return [pscustomobject]@{Id=[string]$record.Id;Name=[string]$record.Name}
}
function Save-ManagerPurchaseAccount {
    param([AllowEmptyString()][string]$Id='',[Parameter(Mandatory=$true)][string]$ProviderId,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Alias,[AllowEmptyString()][AllowNull()][string]$Hint='')
    $alias=ConvertTo-ManagerPurchaseText -Value $Alias -Label '购买账号别名' -MaxLength 64
    $hintValue=ConvertTo-ManagerPurchaseText -Value $Hint -Label '账号提示' -MaxLength 160 -AllowEmpty
    $store=Get-ManagerPurchasesStore;$doc=New-ManagerPurchasesWorkingDocument $store
    if(-not (Find-ManagerPurchaseProvider $doc $ProviderId '')){throw '请先选择有效的服务商。'}
    $record=Find-ManagerPurchaseAccount $doc $Id $ProviderId $alias
    if($Id -and -not $record){throw '该购买账号已不存在，请刷新后重新选择。'}
    if($record -and -not $Id){return [pscustomobject]@{Id=[string]$record.Id;ProviderId=[string]$record.ProviderId;Alias=[string]$record.Alias;Hint=(Get-ManagerPurchaseText $record 'Hint')}}
    $duplicate=Find-ManagerPurchaseAccount $doc '' $ProviderId $alias
    if($duplicate -and $record -and [string]$duplicate.Id -ne [string]$record.Id){throw '该服务商下已存在同名购买账号，请使用已有账号或换一个别名。'}
    if(-not $record){$record=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');ProviderId=$ProviderId;Alias=$alias};$doc.Accounts=@($doc.Accounts)+@($record)}
    elseif([string]$record.ProviderId -ceq $ProviderId -and [string]$record.Alias -ceq $alias -and (Get-ManagerPurchaseText $record 'Hint') -ceq $hintValue){return [pscustomobject]@{Id=[string]$record.Id;ProviderId=[string]$record.ProviderId;Alias=[string]$record.Alias;Hint=$hintValue}}
    $record.ProviderId=$ProviderId;$record.Alias=$alias
    if($hintValue){$record | Add-Member -MemberType NoteProperty -Name Hint -Value $hintValue -Force}
    elseif($record.PSObject.Properties['Hint']){$record.PSObject.Properties.Remove('Hint')}
    Write-ManagerPurchasesDocument $store $doc
    return [pscustomobject]@{Id=[string]$record.Id;ProviderId=[string]$record.ProviderId;Alias=[string]$record.Alias;Hint=$hintValue}
}
function Set-ManagerPurchaseDocumentLink($Doc,[string]$Id,[string]$AccountId) {
    $link=$null;foreach($item in @($Doc.ServerLinks)){if([string]$item.Id -eq $Id){$link=$item;break}}
    if($AccountId){
        if($link){$link.AccountId=$AccountId}else{$Doc.ServerLinks=@($Doc.ServerLinks)+@([pscustomobject]@{Id=$Id;AccountId=$AccountId})}
    }elseif($link){
        # Retain unknown per-link fields while removing only the known association.
        if(@($link.PSObject.Properties | Where-Object {$_.Name -notin @('Id','AccountId')}).Count){$link.AccountId=''}
        else{$Doc.ServerLinks=@($Doc.ServerLinks | Where-Object {[string]$_.Id -ne $Id})}
    }
}
function Save-ManagerPurchaseAssignment {
    param([Parameter(Mandatory=$true)]$Entry,[AllowEmptyString()][string]$ProviderId='',[AllowEmptyString()][string]$ProviderName='',[AllowEmptyString()][string]$AccountId='',[AllowEmptyString()][string]$AccountAlias='',[AllowEmptyString()][AllowNull()][string]$Hint='')
    $id=ConvertTo-ManagerPurchaseText -Value ([string]$Entry.Id) -Label '服务器标识' -MaxLength 128
    $store=Get-ManagerPurchasesStore;$doc=New-ManagerPurchasesWorkingDocument $store
    $account=$null
    if($AccountId){
        $account=Find-ManagerPurchaseAccount $doc $AccountId '' ''
        if(-not $account){throw '该购买账号已不存在，请刷新后重新选择。'}
        if($ProviderId -and [string]$account.ProviderId -ne $ProviderId){throw '购买账号与服务商不匹配，请重新选择。'}
    }elseif($ProviderId -or $ProviderName -or $AccountAlias -or $Hint){
        $alias=ConvertTo-ManagerPurchaseText -Value $AccountAlias -Label '购买账号别名' -MaxLength 64
        $hintValue=ConvertTo-ManagerPurchaseText -Value $Hint -Label '账号提示' -MaxLength 160 -AllowEmpty
        if($ProviderId){
            $provider=Find-ManagerPurchaseProvider $doc $ProviderId ''
            if(-not $provider){throw '该服务商已不存在，请刷新后重新选择。'}
        }else{
            $name=ConvertTo-ManagerPurchaseText -Value $ProviderName -Label '服务商名称' -MaxLength 64
            $provider=Find-ManagerPurchaseProvider $doc '' $name
            if(-not $provider){$provider=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');Name=$name};$doc.Providers=@($doc.Providers)+@($provider)}
        }
        $account=Find-ManagerPurchaseAccount $doc '' ([string]$provider.Id) $alias
        if(-not $account){
            $account=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');ProviderId=[string]$provider.Id;Alias=$alias}
            if($hintValue){$account | Add-Member -MemberType NoteProperty -Name Hint -Value $hintValue}
            $doc.Accounts=@($doc.Accounts)+@($account)
        }
    }
    $accountValue=if($account){[string]$account.Id}else{''}
    Set-ManagerPurchaseDocumentLink $doc $id $accountValue
    $before=if($store.Doc){ConvertTo-Json -InputObject $store.Doc -Depth 100 -Compress}else{''}
    $after=ConvertTo-Json -InputObject $doc -Depth 100 -Compress
    if(($store.Doc -and $before -cne $after) -or (-not $store.Doc -and $accountValue)){Write-ManagerPurchasesDocument $store $doc}
    return (Get-ManagerEntryPurchase -Entry $Entry)
}
function Set-ManagerEntryPurchase {
    param([Parameter(Mandatory=$true)]$Entry,[AllowEmptyString()][AllowNull()][string]$AccountId='')
    return (Save-ManagerPurchaseAssignment -Entry $Entry -AccountId $AccountId)
}
function Remove-ManagerPurchaseProvider {
    param([Parameter(Mandatory=$true)][string]$Id)
    $store=Get-ManagerPurchasesStore;$doc=New-ManagerPurchasesWorkingDocument $store
    if(-not (Find-ManagerPurchaseProvider $doc $Id '')){return $false}
    if(@($doc.Accounts | Where-Object {[string]$_.ProviderId -eq $Id}).Count){throw '该服务商下还有购买账号，请先处理或删除这些账号。'}
    $doc.Providers=@($doc.Providers | Where-Object {[string]$_.Id -ne $Id})
    Write-ManagerPurchasesDocument $store $doc
    return $true
}
function Remove-ManagerPurchaseAccount {
    param([Parameter(Mandatory=$true)][string]$Id,[AllowEmptyCollection()][AllowNull()][string[]]$ActiveServerIds)
    $store=Get-ManagerPurchasesStore;$doc=New-ManagerPurchasesWorkingDocument $store
    if(-not (Find-ManagerPurchaseAccount $doc $Id '' '')){return $false}
    $links=@($doc.ServerLinks | Where-Object {[string]$_.AccountId -eq $Id})
    if($PSBoundParameters.ContainsKey('ActiveServerIds')){
        $active=@{}
        foreach($serverId in @($ActiveServerIds)){
            $checkedId=ConvertTo-ManagerPurchaseText -Value $serverId -Label '服务器标识' -MaxLength 128
            $active[$checkedId]=$true
        }
        if(@($links | Where-Object {$active.ContainsKey([string]$_.Id)}).Count){throw '该购买账号仍有关联的服务器，请先更换或解除这些服务器的购买来源。'}
        # Explicit inventory-scoped deletion may remove this account's retired-server links.
        # Other accounts' historical associations and their unknown fields remain intact.
        $doc.ServerLinks=@($doc.ServerLinks | Where-Object {[string]$_.AccountId -ne $Id})
    }elseif($links.Count){throw '该购买账号仍有关联的服务器，请先更换或解除这些服务器的购买来源。'}
    $doc.Accounts=@($doc.Accounts | Where-Object {[string]$_.Id -ne $Id})
    Write-ManagerPurchasesDocument $store $doc
    return $true
}
