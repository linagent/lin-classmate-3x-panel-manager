# UI-independent account persistence and action extension points.
# The launcher supplies $script:workspace, $script:configPath and $script:entries.
function Read-PanelAccount($entry) {
    $path=Join-Path $script:workspace $entry.SecretFile
    if(-not (Test-Path -LiteralPath $path)){return [pscustomobject]@{username='';password=''}}
    $secure=ConvertTo-SecureString (Get-Content -LiteralPath $path -Raw).Trim()
    return ([PSCredential]::new('local',$secure).GetNetworkCredential().Password | ConvertFrom-Json)
}
function Save-ManagerConfig {
    $tmp=$script:configPath+'.tmp'
    ConvertTo-Json -InputObject ([object[]]@($script:entries)) -Depth 30 | Set-Content -LiteralPath $tmp -Encoding utf8
    # PS 5.1 needs NullString.Value to pass an actual null backup file name.
    if([IO.File]::Exists($script:configPath)){[IO.File]::Replace($tmp,$script:configPath,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$script:configPath)}
}

function Write-ManagerAtomicText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory=$true)][Text.Encoding]$Encoding
    )
    $tmp=$Path+'.tmp'
    try {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllText($tmp,$Text,$Encoding)
        if([IO.File]::Exists($Path)){[IO.File]::Replace($tmp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
    } finally {
        if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}
    }
}

function Save-PanelSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Entry,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Url,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Username,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Password
    )
    $ErrorActionPreference='Stop'
    $newName=$Name.Trim();$newUrl=$Url.Trim();$newUsername=$Username.Trim();$uri=$null
    if(-not $newName){throw '请填写自定义名称。'}
    if(-not [Uri]::TryCreate($newUrl,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo){throw '请填写完整的 http:// 或 https:// 面板地址（不要在地址里填写密码）。'}
    if($Entry.Tunnel -and ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Entry.Tunnel.LocalPort)){throw ('此面板通过 SSH 隧道访问，请保留 http://127.0.0.1:'+$Entry.Tunnel.LocalPort+'，仅修改后面的面板路径。')}
    if(($newUsername -and -not $Password) -or ($Password -and -not $newUsername)){throw '账号和密码需要同时填写，或同时留空。'}

    # Read before writing; an unreadable account must not lose its extra fields.
    try {
        $account=Read-PanelAccount $Entry
        if($null -eq $account -or $account -isnot [pscustomobject]){throw 'Invalid account object.'}
    } catch {
        throw '本机账号不可读取。请先从原电脑导出账号并在本机导入，再修改设置。'
    }
    $account | Add-Member -MemberType NoteProperty -Name username -Value $newUsername -Force
    $account | Add-Member -MemberType NoteProperty -Name password -Value $Password -Force
    $json=$account | ConvertTo-Json -Depth 8 -Compress
    $encrypted=ConvertFrom-SecureString (ConvertTo-SecureString $json -AsPlainText -Force)

    $path=Join-Path $script:workspace $Entry.SecretFile
    $hadSecret=[IO.File]::Exists($path)
    $oldEncrypted=if($hadSecret){[IO.File]::ReadAllText($path)}else{$null}
    $oldName=$Entry.Name;$oldUrl=$Entry.Url;$secretWritten=$false
    try {
        Write-ManagerAtomicText -Path $path -Text $encrypted -Encoding ([Text.Encoding]::ASCII)
        $secretWritten=$true
        $Entry.Name=$newName;$Entry.Url=$newUrl
        Save-ManagerConfig
    } catch {
        $saveError=$_
        $Entry.Name=$oldName;$Entry.Url=$oldUrl
        try {
            if($secretWritten){
                if($hadSecret){Write-ManagerAtomicText -Path $path -Text $oldEncrypted -Encoding ([Text.Encoding]::ASCII)}elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}
            }
        } catch {
            throw '设置保存失败，原账号恢复未完成。请保留本机文件并从跨电脑账号文件重新导入。'
        } finally {
            $configTmp=$script:configPath+'.tmp'
            if([IO.File]::Exists($configTmp)){[IO.File]::Delete($configTmp)}
        }
        throw $saveError
    } finally {
        $account=$null;$json=$null;$encrypted=$null;$oldEncrypted=$null
    }
}

function Get-ManagerAccountState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Entry)
    $ErrorActionPreference='Stop'
    $hasSecret=$false
    try {
        $hasSecret=[IO.File]::Exists((Join-Path $script:workspace $Entry.SecretFile))
        $account=Read-PanelAccount $Entry
        if($null -eq $account -or $account -isnot [pscustomobject]){throw 'Invalid account object.'}
        $hasAccount=[bool]($account.username -and $account.password)
        $text=if($hasAccount){'账号已加密保存'}else{'账号待补充 · 点击「名称 / 设置」填写'}
        if($Entry.Tunnel -and $hasAccount){$text='账号已加密保存 · 自动 SSH 加密隧道'}
        return [pscustomobject]@{
            Account=$account
            StateText=$text
            HasAccount=$hasAccount
            HasSecret=$hasSecret
            Error=$false
            NeedsImport=$false
            StateKind=if($hasAccount){'Ready'}else{'Missing'}
        }
    } catch {
        return [pscustomobject]@{
            Account=[pscustomobject]@{username='';password=''}
            StateText='账号不可读取 · 请导入跨电脑账号'
            HasAccount=$false
            HasSecret=$hasSecret
            Error=$true
            NeedsImport=$true
            StateKind='Unavailable'
        }
    }
}

# Ordered registration lets a later module add buttons without changing the view.
$script:managerActions=[ordered]@{}
function Register-ManagerAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Id,
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Label,
        [Parameter(Mandatory=$true)][ValidateSet('Toolbar','Server')][string]$Placement,
        [Parameter(Mandatory=$true)][scriptblock]$Handler,
        [switch]$Primary
    )
    if($script:managerActions.Contains($Id)){throw ('操作 ID 已注册：'+$Id)}
    $script:managerActions.Add($Id,[pscustomobject]@{Id=$Id;Label=$Label;Placement=$Placement;Handler=$Handler;Primary=[bool]$Primary})
}
function Get-ManagerActions {
    [CmdletBinding()]
    param([ValidateSet('Toolbar','Server')][string]$Placement)
    foreach($action in $script:managerActions.Values){
        if(-not $Placement -or $action.Placement -eq $Placement){$action}
    }
}
function Invoke-ManagerAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Id,
        $Entry
    )
    if(-not $script:managerActions.Contains($Id)){throw ('未知操作 ID：'+$Id)}
    $action=$script:managerActions[$Id]
    & $action.Handler $Entry
}
