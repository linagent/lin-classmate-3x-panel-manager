# Client-only menu actions. Updates replace application files, never the data directory.
function Get-ManagerClientMenuActions {
    if(-not $script:managerClientExecutable){return @()}
    return @(
        @{Id='client.update';Label='更新客户端…'},
        @{Id='client.programFolder';Label='打开程序位置'},
        @{Id='client.dataFolder';Label='打开数据位置'}
    )
}
function Open-ManagerClientFolder([string]$Path) {
    if(-not [IO.Directory]::Exists($Path)){throw '这个目录暂不可用。'}
    Start-Process -FilePath explorer.exe -ArgumentList ('"'+$Path+'"')
}
function Show-ManagerClientUpdateHelp {
    $dialog=Read-ManagerXaml 'UpdateWindow.xaml'
    Add-ManagerTheme $dialog
    $dialog.Owner=$script:window
    $dialog.FindName('ProgramLocation').Text=$script:managerClientExecutable
    $dialog.FindName('ProgramLocation').ToolTip=$script:managerClientExecutable
    $dialog.FindName('DataLocation').Text=$script:workspace
    $dialog.FindName('DataLocation').ToolTip=$script:workspace
    $dialog.FindName('UpdateClose').Tag=$dialog
    $dialog.FindName('UpdateClose').Add_Click({param($sender,$eventArgs) $sender.Tag.Close()})
    $dialog.FindName('UpdateDone').Tag=$dialog
    $dialog.FindName('UpdateDone').Add_Click({param($sender,$eventArgs) $sender.Tag.Close()})
    $dialog.FindName('OpenProgramFolder').Tag=[IO.Path]::GetDirectoryName($script:managerClientExecutable)
    $dialog.FindName('OpenProgramFolder').Add_Click({param($sender,$eventArgs) Open-ManagerClientFolder $sender.Tag})
    [void]$dialog.ShowDialog()
}
function Invoke-ManagerClientMenuAction([string]$Id) {
    switch($Id){
        'client.update' {Show-ManagerClientUpdateHelp}
        'client.programFolder' {Open-ManagerClientFolder ([IO.Path]::GetDirectoryName($script:managerClientExecutable))}
        'client.dataFolder' {Open-ManagerClientFolder $script:workspace}
        default {throw '未找到这项客户端操作。'}
    }
}
