param(
    [switch]$Verify,
    [switch]$RenderPreview,
    [string]$PreviewPath,
    [ValidateSet('Main','Settings','Transfer')][string]$PreviewView='Main',
    [switch]$LoadOnly,
    [string]$DataRoot,
    [string]$ClientExecutable
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1')
$script:workspace=if($DataRoot){[IO.Path]::GetFullPath($DataRoot)}else{Join-Path $env:LOCALAPPDATA '3XuiPanelManagerPublic\data'}
$cursor=$script:workspace
while($cursor){
    if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '公开版数据目录不能包含符号链接或目录联接。'}
    $cursor=[IO.Path]::GetDirectoryName($cursor)
}
$marker=Join-Path $script:workspace '.3xui-panel-manager-public.json'
if([IO.File]::Exists($marker)){
    if(((Get-Item -LiteralPath $marker -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-Item -LiteralPath $marker).Length -gt 4096){throw '公开版数据标识无效。'}
    $identity=[IO.File]::ReadAllText($marker) | ConvertFrom-Json
    if($identity.Product -cne '3XUI Panel Manager Public' -or $identity.SchemaVersion -ne 1){throw '数据目录不属于此公开版，已停止加载。'}
}else{
    if((Test-Path -LiteralPath $script:workspace) -and @(Get-ChildItem -LiteralPath $script:workspace -Force).Count){throw '公开版拒绝读取已有的非空数据目录，请使用新的空目录。'}
    [void][IO.Directory]::CreateDirectory($script:workspace)
    [IO.File]::WriteAllText($marker,'{"Product":"3XUI Panel Manager Public","SchemaVersion":1}',[Text.UTF8Encoding]::new($false))
}
$script:managerClientExecutable=$ClientExecutable
$script:configPath=Join-Path $workspace '统一管理\服务器列表.json'
foreach($path in @([IO.Path]::GetDirectoryName($script:configPath),$script:configPath)){
    if((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '公开版服务器清单不能包含符号链接或目录联接。'}
}
if(-not [IO.File]::Exists($script:configPath)){
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($script:configPath))
    [IO.File]::WriteAllText($script:configPath,'[]',[Text.UTF8Encoding]::new($true))
}
. (Join-Path $PSScriptRoot 'Panel-Manager.Core.ps1')
. (Join-Path $PSScriptRoot 'Account-Transfer.ps1')
. (Join-Path $PSScriptRoot 'Panel-Tunnel.ps1')
# Optional local metadata (到期日 / 客户分组 / 备注) in the 服务器元数据.json sidecar; read-only at load.
. (Join-Path $PSScriptRoot 'Panel-Metadata.ps1')
$parsedEntries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($configPath))
$script:entries=[object[]]@($parsedEntries | ForEach-Object {$_})
if($Verify){
    $entries | ForEach-Object {
        $a=Read-PanelAccount $_
        [pscustomobject]@{Name=$_.Name;Address=$_.Address;Url=$_.Url;AccountAvailable=[bool]$a.username;PasswordAvailable=[bool]$a.password;SecretFile=$_.SecretFile}
    } | ConvertTo-Json
    return
}
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
. (Join-Path $PSScriptRoot 'Panel-AutoRefresh.ps1')
$script:managerAutoRefreshEnabled=(-not $Verify -and -not $LoadOnly -and -not $RenderPreview)
. (Join-Path $PSScriptRoot 'Panel-Manager.Wpf.ps1')
# Explicit-click, read-only status check and its background-task layer (no check runs at load).
. (Join-Path $PSScriptRoot 'Panel-StatusCheck.ps1')
Register-BuiltinManagerActions
. (Join-Path $PSScriptRoot 'Panel-ClientActions.ps1')
$extensionPath=Join-Path $script:workspace '统一管理\程序\Manager-Extensions.ps1'
if([IO.File]::Exists($extensionPath)){. $extensionPath}else{. (Join-Path $PSScriptRoot 'Manager-Extensions.ps1')}
Initialize-ManagerWindow
Build-ManagerRows
if($LoadOnly){return}
if($RenderPreview){
    if(-not $PreviewPath){$PreviewPath=Join-Path $workspace '统一管理\资料\panel-manager-preview.png'}
    $target=switch($PreviewView){
        'Settings' {New-ManagerSettingsWindow $script:entries[0]}
        'Transfer' {New-ManagerTransferWindow $true}
        default {$script:window}
    }
    Export-ManagerPreview $target $PreviewPath
    $target.Close()
    if($target -ne $script:window){$script:window.Close()}
    return
}
try{[void]$script:window.ShowDialog()}finally{
    if(Get-Command Stop-ManagerAutoRefresh -ErrorAction SilentlyContinue){Stop-ManagerAutoRefresh}
    if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache}
    $script:entries=$null
    $script:cards=@()
    $script:window=$null
}
