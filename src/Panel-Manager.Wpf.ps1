# Presentation adapter. Storage/validation, transfer format and SSH remain independent.
$script:uiRoot=Join-Path $PSScriptRoot '界面'
# Optional metadata (到期日 / 客户分组 / 备注) lives in its own UI-independent module; the launcher loads it,
# this fallback keeps harnesses that dot-source the Wpf module directly working.
if(-not (Get-Command Import-ManagerMetadata -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'Panel-Metadata.ps1')}
if(-not (Get-Command Initialize-ManagerAutoRefresh -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'Panel-AutoRefresh.ps1')}
. (Join-Path $PSScriptRoot 'Panel-Lifecycle.ps1')
. (Join-Path $PSScriptRoot 'Panel-CardPresentation.ps1')
. (Join-Path $PSScriptRoot 'Panel-HomePackage.ps1')
. (Join-Path $PSScriptRoot 'Panel-Resources.ps1')
. (Join-Path $PSScriptRoot 'Panel-Purchases.ps1')
. (Join-Path $PSScriptRoot 'Panel-MonitorUi.ps1')
if($null -eq $script:managerListFilter){$script:managerListFilter=@{Kind='All';Value=$null}}
function Read-ManagerXaml([string]$Name) {
    $xml=[xml][IO.File]::ReadAllText((Join-Path $script:uiRoot $Name))
    $reader=[Xml.XmlNodeReader]::new($xml)
    try{return [Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Close()}
}
function Get-ManagerPaletteColors([bool]$Dark) {
    if($Dark){
        return @{
            CanvasBrush='#1E1B19';SidebarBrush='#1E1B19';SurfaceBrush='#2A2522';InkBrush='#F3EEE9';MutedBrush='#C4BBB3';FaintBrush='#9C948C';PlaceholderBrush='#7A736C'
            LineBrush='#3C3632';Line2Brush='#332E2B';WindowEdgeBrush='#4A433E';AccentBrush='#D0724E';AccentHoverBrush='#E08462';SuccessBrush='#5BB87A'
            SurfaceSoftBrush='#322C28';AccentSoftBrush='#3A2A24';AccentLineBrush='#5A4036';SuccessSoftBrush='#1E3326';SuccessLineBrush='#2C4A38';SuccessTextBrush='#8FCBAA'
            WarnBrush='#E08A6A';WarnSoftBrush='#3A2C28';InfoBrush='#9BB0CC';InfoSoftBrush='#2A313C';BadgeBrush='#332E2A';BadBrush='#E06A5C';BadSoftBrush='#3A2624';BadTextBrush='#F0B2A8'
            NeutralDotBrush='#8A827A';CautionBrush='#E0B15A';CautionSoftBrush='#3A3224';ExpiringBrush='#E09A4A';ExpiringDotBrush='#E09A4A';ExpiringSoftBrush='#3A3024'
            ExpiredBrush='#E06A5C';ExpiredSoftBrush='#3A2624';GroupBrush='#E08462';GroupSoftBrush='#3A2A24';GroupDotBrush='#D08A68';LineDotBrush='#8A827A';SidebarSelectedBrush='#3A2A24'
            HoverBrush='#3A342F';PressedBrush='#463F39';FieldDisabledBrush='#262220';CaptionGlyphBrush='#E6DFD8';CaptionHoverBrush='#3A342F';CaptionPressedBrush='#463F39'
            BadgeInkBrush='#C8BDB2';TrackBrush='#3A342F';DialogPaperBrush='#2A2522';NoteWellBrush='#322C28';FooterBrush='#241F1C';OnAccentBrush='#FFFFFF'
            FocusBrush='#D99A7C';FocusRingBrush='#33C9663F';SoftHoverBrush='#4A342C';ScrollThumbBrush='#5A524C';ScrollThumbHoverBrush='#6E655C';ChipHoverBrush='#3A342F';DashBrush='#5A524C'
            OfflineBackBrush='#2E2422';OfflineLineBrush='#6A403C';OfflineBadgeBrush='#3A2624';OfflineBadgeLineBrush='#5A3834';OfflineInkBrush='#E0A8A0'
            ExpiringLineBrush='#6A4E32';ExpiredLineBrush='#6A403C'
        }
    }
    return @{
        CanvasBrush='#FAF8F5';SidebarBrush='#FAF8F5';SurfaceBrush='#FFFFFF';InkBrush='#2B2724';MutedBrush='#6E6760';FaintBrush='#9C948B';PlaceholderBrush='#B8B0A7'
        LineBrush='#E8E4DE';Line2Brush='#F0ECE6';WindowEdgeBrush='#DCD7D0';AccentBrush='#C9663F';AccentHoverBrush='#B5552F';SuccessBrush='#3E9B5F'
        SurfaceSoftBrush='#F7F3EE';AccentSoftBrush='#F3E6DE';AccentLineBrush='#E2C3B2';SuccessSoftBrush='#E7F3EA';SuccessLineBrush='#D3E8D9';SuccessTextBrush='#2F7A4A'
        WarnBrush='#B5552F';WarnSoftBrush='#FBF3EE';InfoBrush='#4F6585';InfoSoftBrush='#E9EEF5';BadgeBrush='#F5F1EC';BadBrush='#C94A3B';BadSoftBrush='#FBEDEA';BadTextBrush='#A4554A'
        NeutralDotBrush='#BDB6AE';CautionBrush='#9A6A1C';CautionSoftBrush='#FCF0E2';ExpiringBrush='#C06A17';ExpiringDotBrush='#D9822B';ExpiringSoftBrush='#FCF0E2'
        ExpiredBrush='#C94A3B';ExpiredSoftBrush='#FBEDEA';GroupBrush='#B5552F';GroupSoftBrush='#F3E6DE';GroupDotBrush='#D08A68';LineDotBrush='#BDB6AE';SidebarSelectedBrush='#F3E6DE'
        HoverBrush='#F7F4F0';PressedBrush='#F0ECE6';FieldDisabledBrush='#F7F4F0';CaptionGlyphBrush='#3A3530';CaptionHoverBrush='#EFEBE6';CaptionPressedBrush='#E6E1DA'
        BadgeInkBrush='#7A6F64';TrackBrush='#F1EDE8';DialogPaperBrush='#FFFDFB';NoteWellBrush='#F7F3EE';FooterBrush='#FCFAF7';OnAccentBrush='#FFFFFF'
        FocusBrush='#D99A7C';FocusRingBrush='#21C9663F';SoftHoverBrush='#EEDACF';ScrollThumbBrush='#D9D2C9';ScrollThumbHoverBrush='#C2B8AC';ChipHoverBrush='#F3EFEA';DashBrush='#DCD5CC'
        OfflineBackBrush='#FFFBFA';OfflineLineBrush='#EFCFC8';OfflineBadgeBrush='#FBEDEA';OfflineBadgeLineBrush='#F3D8D2';OfflineInkBrush='#B5584B'
        ExpiringLineBrush='#EDD2B6';ExpiredLineBrush='#EFCFC8'
    }
}
function Set-ManagerPaletteOn($Dict,[bool]$Dark) {
    $colors=Get-ManagerPaletteColors $Dark
    foreach($key in @($colors.Keys)){$Dict[$key]=New-ManagerBrush $colors[$key]}
}
function Get-ManagerUiSettingsPath {
    return (Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($script:configPath))) '界面设置.json')
}
function Import-ManagerUiSettings {
    $script:managerDark=$false
    $script:managerAutoRefreshSeconds=300
    $path=Get-ManagerUiSettingsPath
    if(-not (Test-Path -LiteralPath $path)){return}
    try{
        $doc=Get-Content -Encoding UTF8 -Raw -LiteralPath $path | ConvertFrom-Json
        if($doc -isnot [pscustomobject]){throw 'Invalid settings document.'}
        if($doc.PSObject.Properties['Dark'] -and $doc.Dark -eq $true){$script:managerDark=$true}
        if($doc.PSObject.Properties['AutoRefreshSeconds'] -and $doc.AutoRefreshSeconds -is [ValueType] -and $doc.AutoRefreshSeconds -in @(0,60,300)){$script:managerAutoRefreshSeconds=[int]$doc.AutoRefreshSeconds}
    }catch{$script:managerDark=$false;$script:managerAutoRefreshSeconds=300}
}
function Save-ManagerUiSettings {
    $path=Get-ManagerUiSettingsPath
    # Merge the latest sidecar so a theme/mode save preserves unrelated future settings.
    $values=@{Version=1}
    if([IO.File]::Exists($path)){
        try{$doc=[IO.File]::ReadAllText($path) | ConvertFrom-Json;if($doc -isnot [pscustomobject]){throw 'Invalid settings document.'}}
        catch{throw '界面设置文件无法读取，已保留原文件。'}
        foreach($property in $doc.PSObject.Properties){$values[$property.Name]=$property.Value}
    }
    $values.Dark=[bool]$script:managerDark
    $values.AutoRefreshSeconds=if($script:managerAutoRefreshSeconds -in @(0,60,300)){[int]$script:managerAutoRefreshSeconds}else{300}
    $json=$values | ConvertTo-Json -Depth 100 -Compress
    $tmp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($tmp,$json,([Text.UTF8Encoding]::new($true)))
        if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
    }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Add-ManagerTheme($Target) {
    $dict=Read-ManagerXaml 'Theme.xaml'
    if($null -eq $script:managerDark){$script:managerDark=$false}
    Set-ManagerPaletteOn $dict ([bool]$script:managerDark)
    if($null -eq $script:managerThemeDicts){$script:managerThemeDicts=[Collections.ArrayList]::new()}
    [void]$script:managerThemeDicts.Add($dict)
    $Target.Resources.MergedDictionaries.Add($dict)
}
function Switch-ManagerTheme {
    $script:managerDark=-not [bool]$script:managerDark
    foreach($dict in @($script:managerThemeDicts)){if($dict){Set-ManagerPaletteOn $dict ([bool]$script:managerDark)}}
    foreach($row in @($script:cards)){if($row){Update-ManagerCardChrome $row}}
    $saved=$true
    try{Save-ManagerUiSettings}catch{$saved=$false;Set-ManagerFeedback '深色设置没能保存，本次切换只在这次运行里生效。'}
    $button=$script:window.FindName('ThemeButton')
    if($button){$button.ToolTip=if($script:managerDark){'浅色模式'}else{'深色模式'}}
    if($saved){Set-ManagerFeedback $(if($script:managerDark){'已切换为深色'}else{'已切换为浅色'})}
}
function Update-ManagerSortButton {
    $button=$script:window.FindName('SortButton');if(-not $button){return}
    $text=@($button.Content.Children | Where-Object {$_ -is [Windows.Controls.TextBlock]})[0]
    if($script:managerSortByGroup){$text.Text='按客户排序 · 开';$text.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'AccentBrush');$button.ToolTip='已按客户分组、再按名称。再点一次恢复列表原来的顺序。'}
    else{$text.Text='按客户排序';$text.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'MutedBrush');$button.ToolTip='按客户分组排序，再按名称。再点一次恢复列表顺序。'}
}
function Get-ManagerOrderedEntries {
    $list=@($script:entries)
    if(-not $script:managerSortByGroup){return $list}
    return @($list | Sort-Object @{Expression={$meta=Get-ManagerEntryMetadata $_;if([string]$meta.Group){0}else{1}}},@{Expression={[string](Get-ManagerEntryMetadata $_).Group}},@{Expression={$_.Name}})
}
function Initialize-ManagerWebView2 {
    # The standalone edition opens panels in the system default browser.
    return $false
}
function Wait-ManagerUiTask($Task,[int]$TimeoutMs) {
    if($Task.IsCompleted){if($Task.IsFaulted){throw $Task.Exception.GetBaseException()};return}
    $frame=[Windows.Threading.DispatcherFrame]::new()
    $timer=[Windows.Threading.DispatcherTimer]::new()
    $timer.Interval=[TimeSpan]::FromMilliseconds($TimeoutMs)
    $timer.Add_Tick({$frame.Continue=$false;$timer.Stop()})
    $null=$Task.ContinueWith({$frame.Continue=$false},[Threading.TaskScheduler]::FromCurrentSynchronizationContext())
    $timer.Start()
    try{[Windows.Threading.Dispatcher]::PushFrame($frame)}finally{$timer.Stop()}
    if(-not $Task.IsCompleted){throw '应用内窗口启动超时'}
    if($Task.IsFaulted){throw $Task.Exception.GetBaseException()}
}
function Get-ManagerPanelProfileDir($Uri) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Uri.Scheme+'|'+$Uri.Host+'|'+$Uri.Port))).Replace('-','').Substring(0,16).ToLower()}
    finally{$sha.Dispose()}
    $root=if($script:workspace){$script:workspace}else{[IO.Path]::GetTempPath()}
    $dir=Join-Path $root ('面板浏览器\'+$hash)
    [void][IO.Directory]::CreateDirectory($dir)
    return $dir
}
# In-app panel window. Accepts a certificate error only when the request host, port and scheme match this saved panel. Never logs the address.
function Show-ManagerPanelBrowser($Entry) {
    if(-not (Initialize-ManagerWebView2)){return $false}
    $uri=$null
    if(-not [Uri]::TryCreate([string]$Entry.Url,[UriKind]::Absolute,[ref]$uri) -or ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https') -or $uri.UserInfo){return $false}
    $window=[Windows.Window]::new()
    $window.Title=if([string]$Entry.Name){[string]$Entry.Name}else{'面板'}
    $window.Width=1100;$window.Height=760;$window.WindowStartupLocation='CenterScreen'
    Add-ManagerTheme $window
    $view=New-Object Microsoft.Web.WebView2.Wpf.WebView2
    $window.Content=$view
    if($script:window){try{$window.Owner=$script:window}catch{}}
    $window.Show()
    $state=@{Done=$false;Ok=$false}
    try{
        $folder=Get-ManagerPanelProfileDir $uri
        $envTask=[Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null,$folder)
        Wait-ManagerUiTask $envTask 20000
        $environment=$envTask.Result
        $rule=@{Scheme=$uri.Scheme;Host=$uri.Host;Port=[int]$uri.Port}
        # WebView2 refuses Ensure until a dispatcher loop is already running, so start it from that loop.
        [void]$view.Dispatcher.BeginInvoke([Action]{
            try{
                $task=$view.EnsureCoreWebView2Async($environment)
                [void]$task.ContinueWith([Action[System.Threading.Tasks.Task]]{
                    param($finished)
                    try{
                        if(-not $finished.IsFaulted -and $view.CoreWebView2){
                            $core=$view.CoreWebView2
                            if($null -eq $script:managerPanelCertRules){$script:managerPanelCertRules=@{}}
                            $script:managerPanelCertRules[$core.GetHashCode()]=$rule
                            $window.Tag=$core.GetHashCode()
                            $core.add_ServerCertificateErrorDetected({
                                param($sender,$eventArgs)
                                $saved=$script:managerPanelCertRules[$sender.GetHashCode()]
                                $match=$false
                                if($saved -and $eventArgs.RequestUri){
                                    $match=($eventArgs.RequestUri.Scheme -eq $saved.Scheme -and $eventArgs.RequestUri.Host -eq $saved.Host -and $eventArgs.RequestUri.Port -eq $saved.Port)
                                }
                                $eventArgs.Action=$(if($match){[Microsoft.Web.WebView2.Core.CoreWebView2ServerCertificateErrorAction]::AlwaysAllow}else{[Microsoft.Web.WebView2.Core.CoreWebView2ServerCertificateErrorAction]::Cancel})
                            })
                            $core.Navigate($uri.AbsoluteUri)
                            $state.Ok=$true
                        }
                    }catch{$state.Ok=$false}
                    $state.Done=$true
                },[System.Threading.Tasks.TaskScheduler]::FromCurrentSynchronizationContext())
            }catch{$state.Done=$true}
        },[Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $frame=[Windows.Threading.DispatcherFrame]::new()
        $poll=[Windows.Threading.DispatcherTimer]::new();$poll.Interval=[TimeSpan]::FromMilliseconds(40)
        $poll.Add_Tick({if($state.Done){$frame.Continue=$false}})
        $cap=[Windows.Threading.DispatcherTimer]::new();$cap.Interval=[TimeSpan]::FromSeconds(20)
        $cap.Add_Tick({$frame.Continue=$false})
        $poll.Start();$cap.Start()
        try{[Windows.Threading.Dispatcher]::PushFrame($frame)}finally{$poll.Stop();$cap.Stop()}
        if(-not $state.Ok){try{$window.Close()}catch{};return $false}
        $window.Add_Closed({param($sender,$eventArgs) if($script:managerPanelCertRules){$script:managerPanelCertRules.Remove($sender.Tag)}})
        return $true
    }catch{
        try{$window.Close()}catch{}
        return $false
    }
}
function Set-ManagerFeedback([string]$Text) {
    if($script:window){$feedback=$script:window.FindName('Feedback');$feedback.Text=$Text;$feedback.ToolTip=$Text}
}
function Show-ManagerMessage([string]$Text,[string]$Title) {
    [void][Windows.MessageBox]::Show($script:window,$Text,$Title,'OK','Information')
}
# vector icons (Theme.xaml geometry keys, copied from the mockup SVGs) for known built-in actions;
# extensions keep readable text buttons.
$script:managerActionIcons=@{
    'accounts.export'='IcoExport'
    'accounts.import'='IcoImport'
    'status.checkAll'='IcoPulse'
    'status.check'='IcoPulse'
    'resource.monitor'='IcoPulse'
    'server.settings'='IcoEdit'
    'server.folder'='IcoFolder'
}
# Short toolbar captions (full registered label stays in the tooltip / automation name) and display order.
$script:managerToolbarShortLabels=@{'accounts.import'='导入';'accounts.export'='导出'}
$script:managerToolbarOrder=@{'accounts.import'=1;'accounts.export'=2;'status.checkAll'=3}
$script:managerCardActionOrder=@{'panel.open'=0;'resource.monitor'=1;'server.folder'=2;'server.settings'=3}
# Short region code + caption from the existing Name prefix only; no lookup or network.
$script:managerRegionCodes=[ordered]@{
    '美国'=@('US','美国');'香港'=@('HK','中国香港');'日本'=@('JP','日本');'新加坡'=@('SG','新加坡');'韩国'=@('KR','韩国')
    '台湾'=@('TW','中国台湾');'澳门'=@('MO','中国澳门');'德国'=@('DE','德国');'英国'=@('UK','英国');'法国'=@('FR','法国')
    '荷兰'=@('NL','荷兰');'加拿大'=@('CA','加拿大');'澳大利亚'=@('AU','澳大利亚');'俄罗斯'=@('RU','俄罗斯');'印度'=@('IN','印度')
    '越南'=@('VN','越南');'泰国'=@('TH','泰国');'马来西亚'=@('MY','马来西亚');'菲律宾'=@('PH','菲律宾');'印尼'=@('ID','印尼')
    '土耳其'=@('TR','土耳其');'巴西'=@('BR','巴西');'中国'=@('CN','中国')
    '东京'=@('JP','日本 · 东京');'大阪'=@('JP','日本 · 大阪');'首尔'=@('KR','韩国 · 首尔');'洛杉矶'=@('US','美国 · 洛杉矶')
    '圣何塞'=@('US','美国 · 圣何塞');'硅谷'=@('US','美国 · 硅谷');'西雅图'=@('US','美国 · 西雅图');'纽约'=@('US','美国 · 纽约')
    '达拉斯'=@('US','美国 · 达拉斯');'芝加哥'=@('US','美国 · 芝加哥');'法兰克福'=@('DE','德国 · 法兰克福');'伦敦'=@('UK','英国 · 伦敦')
    '巴黎'=@('FR','法国 · 巴黎');'阿姆斯特丹'=@('NL','荷兰 · 阿姆斯特丹');'悉尼'=@('AU','澳大利亚 · 悉尼');'台北'=@('TW','中国台湾 · 台北')
}
function Get-ManagerRegionInfo($Entry) {
    $name=([string]$Entry.Name).Trim()
    foreach($key in $script:managerRegionCodes.Keys){if($name.StartsWith($key,[StringComparison]::Ordinal)){return $script:managerRegionCodes[$key]}}
    return $null
}
function Get-ManagerServerBadge($Entry) {
    $region=Get-ManagerRegionInfo $Entry
    if($region){return $region[0]}
    $name=([string]$Entry.Name).Trim()
    $letters=@([regex]::Matches($name,'[A-Za-z0-9]') | Select-Object -First 2 | ForEach-Object {$_.Value})
    if($letters.Count){return ($letters -join '').ToUpperInvariant()}
    foreach($ch in $name.ToCharArray()){if([char]::IsLetter($ch)){return [string]$ch}}
    return '·'
}
function Get-ManagerAccessKind($Entry) {
    if($Entry.Tunnel){return 'Tunnel'}
    $uri=$null
    if([Uri]::TryCreate([string]$Entry.Url,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https'){return 'Https'}
    return 'Http'
}
# Group colours: the mockup's avatar / tag palette, chosen by a stable hash of the group name.
$script:managerGroupPalette=@(
    @{Avatar='#D08A68';Soft='#F3E6DE';Ink='#B5552F'}
    @{Avatar='#7E93B0';Soft='#E9EEF5';Ink='#4F6585'}
    @{Avatar='#8FA08A';Soft='#EEF1EC';Ink='#5F6F57'}
    @{Avatar='#A38BB3';Soft='#F1ECF4';Ink='#6F5A80'}
    @{Avatar='#B9A58C';Soft='#F3EEE6';Ink='#7A6A55'}
    @{Avatar='#A9A39C';Soft='#F1EFEC';Ink='#6E6760'}
)
function Get-ManagerGroupPalette([string]$Name) {
    $sum=0;foreach($ch in ([string]$Name).ToCharArray()){$sum+=[int]$ch}
    return $script:managerGroupPalette[$sum % $script:managerGroupPalette.Count]
}
function Get-ManagerGroupInitial([string]$Name) {
    $text=([string]$Name).Trim()
    if(-not $text){return '?'}
    if([char]::IsHighSurrogate($text[0]) -and $text.Length -gt 1){return $text.Substring(0,2)}
    return ([string]$text[0]).ToUpperInvariant()
}
function New-ManagerBrush([string]$Hex) {
    $brush=[Windows.Media.SolidColorBrush]::new([Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $brush.Freeze()
    return $brush
}
function Set-ManagerBrush($Element,$Property,$Value) {
    # $Value is either a Theme resource key (contains no '#') or a hex colour.
    if(([string]$Value).StartsWith('#')){$Element.SetValue($Property,(New-ManagerBrush $Value))}
    else{$Element.SetResourceReference($Property,[string]$Value)}
}
function New-ManagerIcon([string]$Key,[string]$Stroke,[double]$Size,[double]$Scale) {
    $path=[Windows.Shapes.Path]::new()
    $path.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'Ico')
    $path.SetResourceReference([Windows.Shapes.Path]::DataProperty,$Key)
    if(-not $Size){$Size=16}
    $path.Width=$Size;$path.Height=$Size
    if($Stroke){Set-ManagerBrush $path ([Windows.Shapes.Shape]::StrokeProperty) $Stroke}
    if($Scale -and $Scale -ne 1){$path.LayoutTransform=[Windows.Media.ScaleTransform]::new($Scale,$Scale)}
    return $path
}
function Invoke-ManagerActionButtonClick($Sender) {
    try{
        $Sender.IsEnabled=$false
        Set-ManagerFeedback ('正在处理：'+$Sender.Tag.Label+'…')
        $script:window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
        Invoke-ManagerAction -Id $Sender.Tag.Action -Entry $Sender.Tag.Entry
    }catch{Set-ManagerFeedback '操作未完成，请查看提示。';Show-ManagerMessage $_.Exception.Message '操作未完成'}
    finally{$Sender.IsEnabled=$true}
}
function New-ManagerActionButton($Action,$Entry) {
    $button=[Windows.Controls.Button]::new()
    $label=[string]$Action.Label
    $id=[string]$Action.Id
    $icon=$script:managerActionIcons[$id]
    if($Action.Primary){
        $button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,$(if($null -ne $Entry){'EnterButton'}else{'PrimaryButton'}))
        if($id -eq 'panel.open'){
            # Mockup .enter: 「进入面板」 + arrow icon.
            $panel=[Windows.Controls.StackPanel]::new();$panel.Orientation='Horizontal'
            $text=[Windows.Controls.TextBlock]::new();$text.Text=($label -replace '\s*→\s*$','');$text.Foreground=[Windows.Media.Brushes]::White;$text.FontWeight=[Windows.FontWeights]::SemiBold
            $arrow=New-ManagerIcon 'IcoArrow' '#FFFFFF' 14 1;$arrow.StrokeThickness=1.6;$arrow.Margin=[Windows.Thickness]::new(6,0,0,0)
            [void]$panel.Children.Add($text);[void]$panel.Children.Add($arrow)
            $button.Content=$panel
        }else{$button.Content=$label}
    }elseif($null -ne $Entry -and $icon){
        $glyph=New-ManagerIcon $icon 'MutedBrush' 16 1;$glyph.StrokeThickness=1.4
        $button.Content=$glyph
        $button.ToolTip=$label
        $button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'IconButton')
    }elseif($null -eq $Entry -and $icon){
        $panel=[Windows.Controls.StackPanel]::new();$panel.Orientation='Horizontal'
        $glyph=New-ManagerIcon $icon 'InkBrush' 16 1
        $text=[Windows.Controls.TextBlock]::new();$text.Margin=[Windows.Thickness]::new(7,0,0,0)
        $short=$script:managerToolbarShortLabels[$id]
        $text.Text=if($short){$short}else{$label}
        [void]$panel.Children.Add($glyph);[void]$panel.Children.Add($text)
        $button.Content=$panel
        $button.ToolTip=$label
        $button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'ToolbarButton')
    }else{
        $button.Content=$label
        if($null -eq $Entry){$button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'ToolbarButton')}
    }
    [Windows.Automation.AutomationProperties]::SetName($button,$label)
    $button.Margin=[Windows.Thickness]::new(7,0,0,0)
    $button.Tag=@{Action=$Action.Id;Entry=$Entry;Label=$label}
    $button.Add_Click({param($sender,$eventArgs) Invoke-ManagerActionButtonClick $sender})
    return $button
}
function Get-ManagerOrderedActions([object[]]$Actions,$Order) {
    $index=0
    $keyed=foreach($action in @($Actions)){
        $rank=if($Order.ContainsKey([string]$action.Id)){[int]$Order[[string]$action.Id]}else{50}
        [pscustomobject]@{Rank=$rank;Index=$index;Action=$action};$index++
    }
    return @($keyed | Sort-Object Rank,Index | ForEach-Object {$_.Action})
}
# Card action row (mockup .c-foot): wide primary + 34px square icon buttons; any other (extension) action gets
# its own full-width row so nothing can overflow the card. A soft 「重新检测」 and a square 「进入面板」 icon are
# prepared (hidden) for the unreachable-card state.
function Add-ManagerCardActions($Card,$Entry) {
    $grid=$Card.FindName('ServerActions')
    $grid.Children.Clear();$grid.ColumnDefinitions.Clear();$grid.RowDefinitions.Clear()
    $first=[Windows.Controls.ColumnDefinition]::new();$first.Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $grid.ColumnDefinitions.Add($first)
    $top=[Windows.Controls.RowDefinition]::new();$top.Height=[Windows.GridLength]::Auto
    $grid.RowDefinitions.Add($top)
    $hasPrimary=$false;$column=1;$row=1
    $refs=@{Entry=$Entry;Primary=$null;Recheck=$null;OpenIcon=$null;CheckIcon=$null}
    foreach($action in @(Get-ManagerOrderedActions @(Get-ManagerActions -Placement Server | Where-Object {$_.Id -notin @('server.delete','status.check')}) $script:managerCardActionOrder)){
        $button=New-ManagerActionButton $action $Entry
        if($action.Primary -and -not $hasPrimary){
            $hasPrimary=$true
            $button.Margin=[Windows.Thickness]::new(0)
            [Windows.Controls.Grid]::SetColumn($button,0)
            if([string]$action.Id -eq 'panel.open'){$refs.Primary=$button}
        }elseif(-not $action.Primary -and $script:managerActionIcons.ContainsKey([string]$action.Id)){
            $definition=[Windows.Controls.ColumnDefinition]::new();$definition.Width=[Windows.GridLength]::Auto
            $grid.ColumnDefinitions.Add($definition)
            $button.Margin=[Windows.Thickness]::new(6,0,0,0)
            [Windows.Controls.Grid]::SetColumn($button,$column);$column++
            if([string]$action.Id -eq 'resource.monitor'){$refs.CheckIcon=$button}
        }else{
            $definition=[Windows.Controls.RowDefinition]::new();$definition.Height=[Windows.GridLength]::Auto
            $grid.RowDefinitions.Add($definition)
            $button.Margin=[Windows.Thickness]::new(0,8,0,0)
            [Windows.Controls.Grid]::SetRow($button,$row);[Windows.Controls.Grid]::SetColumnSpan($button,64);$row++
        }
        [void]$grid.Children.Add($button)
    }
    if($refs.Primary -and $refs.CheckIcon){
        $recheck=[Windows.Controls.Button]::new()
        $recheck.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'SoftButton')
        $panel=[Windows.Controls.StackPanel]::new();$panel.Orientation='Horizontal'
        $glyph=New-ManagerIcon 'IcoRefresh' 'AccentHoverBrush' 16 0.82;$glyph.StrokeThickness=1.6
        $text=[Windows.Controls.TextBlock]::new();$text.Text='重新检测';$text.FontWeight=[Windows.FontWeights]::SemiBold;$text.Margin=[Windows.Thickness]::new(6,0,0,0)
        $text.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'AccentHoverBrush')
        [void]$panel.Children.Add($glyph);[void]$panel.Children.Add($text)
        $recheck.Content=$panel;$recheck.ToolTip='重新只读检测这台服务器'
        [Windows.Automation.AutomationProperties]::SetName($recheck,'重新检测')
        $recheck.Tag=@{Action='status.check';Entry=$Entry;Label='重新检测'}
        $recheck.Add_Click({param($sender,$eventArgs) Invoke-ManagerActionButtonClick $sender})
        $recheck.Visibility='Collapsed'
        [Windows.Controls.Grid]::SetColumn($recheck,0)
        [void]$grid.Children.Add($recheck)
        $open=[Windows.Controls.Button]::new()
        $open.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'IconButton')
        $openGlyph=New-ManagerIcon 'IcoOpen' 'MutedBrush' 16 1;$openGlyph.StrokeThickness=1.4
        $open.Content=$openGlyph;$open.ToolTip=('仍要进入面板（'+($refs.Primary.Tag.Label -replace '\s*→\s*$','')+'）')
        [Windows.Automation.AutomationProperties]::SetName($open,'进入面板')
        $open.Tag=@{Action='panel.open';Entry=$Entry;Label=$refs.Primary.Tag.Label}
        $open.Add_Click({param($sender,$eventArgs) Invoke-ManagerActionButtonClick $sender})
        $open.Margin=$refs.CheckIcon.Margin;$open.Visibility='Collapsed'
        [Windows.Controls.Grid]::SetColumn($open,[Windows.Controls.Grid]::GetColumn($refs.CheckIcon))
        [void]$grid.Children.Add($open)
        $refs.Recheck=$recheck;$refs.OpenIcon=$open
    }
    $Card.Tag=$refs
}
function Register-BuiltinManagerActions {
    # Status checks only ever start from these explicit clicks (never on load, search or preview).
    Register-ManagerAction -Id 'status.checkAll' -Label '批量检测' -Placement Toolbar -Handler {param($entry) Start-ManagerStatusCheck @($script:entries)}
    Register-ManagerAction -Id 'accounts.export' -Label '导出跨电脑账号' -Placement Toolbar -Handler {param($entry) Export-PanelAccounts}
    Register-ManagerAction -Id 'accounts.import' -Label '导入跨电脑账号' -Placement Toolbar -Handler {param($entry) Import-PanelAccounts}
    Register-ManagerAction -Id 'panel.open' -Label '进入面板 →' -Placement Server -Primary -Handler {param($entry) Open-ManagedPanel $entry;Set-ManagerFeedback ('已交给默认浏览器打开 · '+$entry.Name)}
    Register-ManagerAction -Id 'status.check' -Label '检测状态' -Placement Server -Handler {param($entry) Start-ManagerStatusCheck @($entry)}
    Register-ManagerAction -Id 'resource.monitor' -Label '资源监控' -Placement Server -Handler {param($entry) Open-ManagerResourceDrawer $entry}
    Register-ManagerAction -Id 'server.settings' -Label '名称 / 设置' -Placement Server -Handler {param($entry) Show-PanelSettings $entry}
    Register-ManagerAction -Id 'server.folder' -Label '资料夹' -Placement Server -Handler {param($entry) Start-Process explorer.exe -ArgumentList ('"'+(Join-Path $script:workspace $entry.Folder)+'"');Set-ManagerFeedback ('已打开资料夹 · '+$entry.Name)}
    Register-ManagerAction -Id 'server.delete' -Label '删除服务器' -Placement Server -Handler {param($entry) Show-ManagerDeleteServer $entry}
}
# Mockup slots whose feature is not built yet: they look like the design, explain themselves and do nothing else.
$script:managerSoonButtons=[ordered]@{
    'LockNowButton'='立即锁定：即将支持。目前账号由 Windows 登录保护（DPAPI），无需单独锁定。'
    'NewGroupButton'='新建分组：在服务器卡片的「编辑」里填写客户分组即可（独立的新建分组即将支持）。'
    'NewGroupPlus'='新建分组：在服务器卡片的「编辑」里填写客户分组即可（独立的新建分组即将支持）。'
    'ListViewButton'='列表视图：即将支持。'
}
function Initialize-ManagerWindow {
    Import-ManagerUiSettings
    $script:window=Read-ManagerXaml 'MainWindow.xaml'
    Add-ManagerTheme $script:window
    $area=[Windows.SystemParameters]::WorkArea
    if($area.Width -gt 0){$script:window.Width=[Math]::Min(1280,[Math]::Max(760,$area.Width-40))}
    if($area.Height -gt 0){$script:window.Height=[Math]::Min(820,[Math]::Max(560,$area.Height-40))}
    $script:window.FindName('SidebarCount').Text=[string]$script:entries.Count
    foreach($action in @(Get-ManagerOrderedActions @(Get-ManagerActions -Placement Toolbar) $script:managerToolbarOrder)){
        $button=New-ManagerActionButton $action $null
        $button.Margin=[Windows.Thickness]::new(10,0,0,0)
        [void]$script:window.FindName('ToolbarActions').Children.Add($button)
    }
    $script:window.FindName('SearchBox').Add_TextChanged({Update-ManagerFilter})
    $script:window.Add_Deactivated({Reset-ManagerCredentials;Close-ManagerCardMenu})
    $script:window.Add_PreviewMouseDown({param($s,$e)
        if($script:managerCardMenu -and $script:managerCardMenu.IsOpen){
            $source=$e.OriginalSource;$trigger=$script:managerCardMenu.PlacementTarget;$onTrigger=$false
            while($source -is [Windows.Media.Visual]){if($source -eq $trigger){$onTrigger=$true;break};$source=[Windows.Media.VisualTreeHelper]::GetParent($source)}
            if(-not $onTrigger){Close-ManagerCardMenu}
        }
    })
    $script:window.Add_PreviewKeyDown({param($sender,$eventArgs)
        $control=([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -eq [Windows.Input.ModifierKeys]::Control
        if($eventArgs.Key -eq 'Escape'){Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse;Close-ManagerDrawer}
        if($control -and ($eventArgs.Key -eq [Windows.Input.Key]::K -or $eventArgs.Key -eq [Windows.Input.Key]::F)){
            $box=$script:window.FindName('SearchBox');[void]$box.Focus();$box.SelectAll();$eventArgs.Handled=$true
        }
    })
    $script:window.Add_SizeChanged({Update-ManagerResponsive})
    $script:window.Add_StateChanged({Update-ManagerWindowState})
    $script:window.FindName('ServerScroll').Add_SizeChanged({Update-ManagerCardColumns})
    # Custom caption buttons (WindowChrome keeps native drag / snap / double-click maximise / resize).
    $script:window.FindName('MinimizeButton').Add_Click({$script:window.WindowState='Minimized'})
    $script:window.FindName('MaximizeButton').Add_Click({$script:window.WindowState=if($script:window.WindowState -eq 'Maximized'){'Normal'}else{'Maximized'}})
    $script:window.FindName('CloseButton').Add_Click({$script:window.Close()})
    $script:window.FindName('TitleMenuButton').Add_Click({param($sender,$eventArgs)
        $menu=[Windows.Controls.ContextMenu]::new()
        foreach($action in @(Get-ManagerOrderedActions @(Get-ManagerActions -Placement Toolbar) $script:managerToolbarOrder)){
            $item=[Windows.Controls.MenuItem]::new();$item.Header=[string]$action.Label;$item.Tag=[string]$action.Id
            $item.Add_Click({param($s,$e) try{Invoke-ManagerAction -Id $s.Tag -Entry $null}catch{Set-ManagerFeedback '操作未完成，请查看提示。';Show-ManagerMessage $_.Exception.Message '操作未完成'}})
            [void]$menu.Items.Add($item)
        }
        if(Get-Command Get-ManagerClientMenuActions -ErrorAction SilentlyContinue){
            $clientActions=@(Get-ManagerClientMenuActions)
            if($clientActions.Count){[void]$menu.Items.Add([Windows.Controls.Separator]::new())}
            foreach($action in $clientActions){
                $item=[Windows.Controls.MenuItem]::new();$item.Header=[string]$action.Label;$item.Tag=[string]$action.Id
                $item.Add_Click({param($s,$e) try{Invoke-ManagerClientMenuAction -Id $s.Tag}catch{Set-ManagerFeedback '操作未完成，请查看提示。';Show-ManagerMessage $_.Exception.Message '操作未完成'}})
                [void]$menu.Items.Add($item)
            }
        }
        $menu.PlacementTarget=$sender;$menu.Placement='Bottom';$menu.IsOpen=$true
    })
    foreach($name in $script:managerSoonButtons.Keys){
        $button=$script:window.FindName($name)
        if($button){
            $button.Tag=$script:managerSoonButtons[$name];$button.ToolTip=$script:managerSoonButtons[$name]
            $button.IsEnabled=$false
            [Windows.Controls.ToolTipService]::SetShowOnDisabled($button,$true)
        }
    }
    $themeButton=$script:window.FindName('ThemeButton')
    if($themeButton){$themeButton.ToolTip=if($script:managerDark){'浅色模式'}else{'深色模式'};$themeButton.Add_Click({Switch-ManagerTheme})}
    $sortButton=$script:window.FindName('SortButton')
    if($sortButton){$sortButton.Add_Click({$script:managerSortByGroup=-not [bool]$script:managerSortByGroup;Update-ManagerSortButton;Build-ManagerRows;Set-ManagerFeedback $(if($script:managerSortByGroup){'已按客户分组、再按名称排列'}else{'已恢复列表原来的顺序'})})}
    Update-ManagerSortButton
    $script:window.FindName('AddServerButton').IsEnabled=$true
    $script:window.FindName('AddServerButton').ToolTip='添加服务器，账号在本机加密保存'
    $script:window.FindName('AddServerButton').Add_Click({Show-ManagerAddServer})
    $undo=$script:window.FindName('UndoDeleteButton');if($undo){$undo.Add_Click({Undo-ManagerDeleteServer})}
    $script:window.FindName('RefreshCheck').Add_Click({
        try{Invoke-ManagerAction -Id 'status.checkAll' -Entry $null}catch{Set-ManagerFeedback '操作未完成，请查看提示。';Show-ManagerMessage $_.Exception.Message '操作未完成'}
    })
    $script:window.FindName('CancelCheck').Add_Click({Stop-ManagerStatusCheck})
    $script:window.FindName('AutoRefreshButton').Add_Click({param($sender,$eventArgs) Show-ManagerAutoRefreshMenu $sender})
    Initialize-ManagerAutoRefresh
    $script:window.Add_Loaded({if($script:managerAutoRefreshEnabled){Start-ManagerAutoRefresh}})
    # Sidebar filters. Tag carries the filter so handlers need no closures.
    $w=$script:window
    foreach($pair in @(@('SidebarAll','All','SidebarAllLabel','SidebarCount'),@('SidebarOnline','Online','SidebarOnlineLabel','SidebarOnlineCount'),
        @('SidebarOffline','Offline','SidebarOfflineLabel','SidebarOfflineCount'),@('SidebarExpiring','Expiring','SidebarExpiringLabel','SidebarExpiringCount'),
        @('SidebarExpired','Expired','SidebarExpiredLabel','SidebarExpiredCount'),@('SidebarUnchecked','Unchecked','SidebarUncheckedLabel','SidebarUncheckedCount'))){
        $button=$w.FindName($pair[0])
        $button.Tag=@{Kind=$pair[1];Value=$null;LabelBlock=$w.FindName($pair[2]);CountBlock=$w.FindName($pair[3])}
        $button.Add_Click({param($sender,$eventArgs) Set-ManagerListFilter $sender.Tag.Kind $sender.Tag.Value})
    }
    $w.FindName('ClearFilter').Add_Click({Set-ManagerListFilter 'All' $null})
    Initialize-ManagerMonitorUi
    $script:window.Add_Closed({
        Stop-ManagerAutoRefresh
        if($script:managerStatusBatch){Close-ManagerBackgroundBatch $script:managerStatusBatch}
        if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache}
    })
}
# Maximised WindowChrome windows extend past the monitor by the frame width; pad the content back in.
function Update-ManagerWindowState {
    $w=$script:window;if(-not $w){return}
    $root=$w.FindName('RootGrid');$glyph=$w.FindName('MaximizeGlyph');$button=$w.FindName('MaximizeButton')
    if($w.WindowState -eq 'Maximized'){
        $frame=[Windows.SystemParameters]::WindowNonClientFrameThickness
        $pad=if($frame.Left -gt 0){$frame.Left}else{8}
        $root.Margin=[Windows.Thickness]::new($pad,$pad,$pad,$pad);$w.BorderThickness=[Windows.Thickness]::new(0)
        $glyph.SetResourceReference([Windows.Shapes.Path]::DataProperty,'IcoWinRestore');$button.ToolTip='还原'
    }else{
        $root.Margin=[Windows.Thickness]::new(0);$w.BorderThickness=[Windows.Thickness]::new(1)
        $glyph.SetResourceReference([Windows.Shapes.Path]::DataProperty,'IcoWinMax');$button.ToolTip='最大化'
    }
}
function Update-ManagerResponsive {
    $w=$script:window;if(-not $w){return}
    $width=$w.ActualWidth
    $w.FindName('SidebarColumn').Width=if($width -lt 930){[Windows.GridLength]::new(0)}else{[Windows.GridLength]::new(224)}
    $w.FindName('LocalSecurityPill').Visibility=if($width -lt 1160){'Collapsed'}else{'Visible'}
    $searchHost=$w.FindName('SearchBox').Parent
    $searchHost.Width=if($width -lt 1000){260}else{330}
    $compact=$width -lt 1180
    foreach($stat in @($w.FindName('SummaryStats').Children)){if([string]$stat.Tag -eq 'Stat'){$stat.Padding=if($compact){[Windows.Thickness]::new(14,0,14,0)}else{[Windows.Thickness]::new(22,0,22,0)}}}
    $w.FindName('SummaryNote').MaxWidth=if($compact){130}else{220}
    $w.FindName('ListHint').Visibility=if($width -lt 900){'Collapsed'}else{'Visible'}
    $w.FindName('AutoRefreshStatus').Visibility=if($width -lt 1180){'Collapsed'}else{'Visible'}
    $w.FindName('CompactPurchaseFilter').Visibility=if($width -lt 930){'Visible'}else{'Collapsed'}
    $w.FindName('DrawerFrame').Width=[Math]::Min(480,[Math]::Max(360,$width-24))
    Update-ManagerSummaryResponsive
}
function Update-ManagerSummaryResponsive {
    $w=$script:window;if(-not $w){return}
    # In the compact summary, reserve room for every numeric stat and the action buttons.
    # Put secondary login/time details in the refresh tooltip instead of overlapping the mean.
    $compact=$w.ActualWidth -gt 0 -and $w.ActualWidth -lt 1180
    $hideSecondary=$compact -or $w.FindName('CheckProgressPanel').Visibility -eq 'Visible'
    $hasResults=$w.FindName('SummaryOnlineBlock').Visibility -eq 'Visible'
    $w.FindName('SummaryLoginBlock').Visibility=if($hasResults -and -not $hideSecondary){'Visible'}else{'Collapsed'}
    $w.FindName('SummaryNote').Visibility=if($hideSecondary){'Collapsed'}else{'Visible'}
    foreach($name in 'CheckProgressText','CheckProgressBar'){$w.FindName($name).Visibility=if($compact){'Collapsed'}else{'Visible'}}
    $refresh=$w.FindName('RefreshCheck')
    $refresh.ToolTip='立即重新检测全部服务器（只读）；手动检测可恢复认证失败后的自动暂停。'+[Environment]::NewLine+$w.FindName('SummaryNote').Text
    if($hasResults){$refresh.ToolTip+=[Environment]::NewLine+'登录正常 '+$w.FindName('SummaryLogin').Text}
    $w.FindName('CancelCheck').ToolTip='取消检测（已发出的请求会在超时内自行结束）'+[Environment]::NewLine+$w.FindName('CheckProgressText').Text
}
# Responsive card grid; computed from the scroll viewer width (not content) to avoid scrollbar feedback loops.
function Update-ManagerCardColumns {
    $width=$script:window.FindName('ServerScroll').ActualWidth
    if($width -le 0){return}
    $columns=[Math]::Max(1,[Math]::Min(4,[int][Math]::Floor(($width-2)/400)))
    $grid=$script:window.FindName('ServerCards')
    if($grid.Columns -ne $columns){$grid.Columns=$columns}
}
function Test-ManagerRecordOnline($Record) {
    return [bool]($Record -and $Record.State -eq 'Done' -and ($Record.Http.State -eq 'Ok' -or $Record.Http.State -eq 'Warn'))
}
function Test-ManagerRecordOffline($Record) {
    return [bool]($Record -and $Record.State -eq 'Done' -and ($Record.Http.State -eq 'Fail' -or $Record.Tunnel.State -eq 'Fail'))
}
function Get-ManagerLatencyBrushKey($LatencyMs) {
    if($null -eq $LatencyMs -or ($LatencyMs -is [string] -and [string]::IsNullOrWhiteSpace($LatencyMs))){return 'PlaceholderBrush'}
    try{$value=[double]$LatencyMs}catch{return 'PlaceholderBrush'}
    if($value -lt 0 -or [double]::IsNaN($value) -or [double]::IsInfinity($value)){return 'PlaceholderBrush'}
    if($value -ge 300){return 'BadBrush'}
    if($value -gt 250){return 'ExpiringDotBrush'}
    return 'SuccessBrush'
}
# Summary: local configuration numbers always; online / offline / latency only after an explicit check.
function Update-ManagerSummary {
    $total=@($script:entries).Count
    $ready=@($script:cards | Where-Object {$_.StateKind -eq 'Ready'}).Count
    $https=@($script:cards | Where-Object {$_.Access -eq 'Https'}).Count
    $http=@($script:cards | Where-Object {$_.Access -eq 'Http'}).Count
    $tunnel=@($script:cards | Where-Object {$_.Access -eq 'Tunnel'}).Count
    $w=$script:window
    $w.FindName('SummaryTotal').Text=[string]$total
    $w.FindName('SummaryTotalBlock').ToolTip=('本机配置：账号可读 '+$ready+' · 账号待处理 '+(@($script:cards).Count-$ready)+' · HTTPS '+$https+' / HTTP '+$http+' · SSH 隧道 '+$tunnel)
    $expiring=@($script:cards | Where-Object {$_.Meta -and $_.Meta.ExpiryKind -eq 'Expiring'}).Count
    $expired=@($script:cards | Where-Object {$_.Meta -and $_.Meta.ExpiryKind -eq 'Expired'}).Count
    $w.FindName('SummaryExpiring').Text=[string]$expiring
    $w.FindName('SummaryExpiring').SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($expiring){'ExpiringDotBrush'}else{'InkBrush'}))
    $w.FindName('SummaryExpired').Text=('已到期 '+$expired)
    $w.FindName('SummaryExpired').Visibility=if($expired){'Visible'}else{'Collapsed'}
    $w.FindName('SidebarCount').Text=[string]$total
    $w.FindName('StatusSummary').Text=([string]$total+' 台服务器 · 数据仅保存在本地 · 已加密（Windows DPAPI）')
    # Online numbers appear only after an explicit check has produced results in this session.
    $records=@($script:cards | ForEach-Object {$script:managerStatus[[string]$_.Entry.Id]} | Where-Object {$_ -and $_.State -eq 'Done'})
    $checked=$records.Count -gt 0
    $w.FindName('SummaryUncheckedBlock').Visibility=if($checked){'Collapsed'}else{'Visible'}
    foreach($name in 'SummaryOnlineBlock','SummaryLoginBlock','SummaryProblemBlock'){$w.FindName($name).Visibility=if($checked){'Visible'}else{'Collapsed'}}
    $offlineBlock=$w.FindName('SummaryOffline')
    if($checked){
        $online=@($records | Where-Object {Test-ManagerRecordOnline $_}).Count
        $offline=@($records | Where-Object {Test-ManagerRecordOffline $_}).Count
        $w.FindName('SummaryOnline').Text=[string]$online
        $w.FindName('SummaryOnlineOf').Text=('/ '+$records.Count)
        $offlineBlock.Text=[string]$offline
        $offlineBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($offline){'BadBrush'}else{'InkBrush'}))
        $w.FindName('SummaryLogin').Text=[string]@($records | Where-Object {$_.Login.State -eq 'Ok'}).Count
        $w.FindName('SummaryProblem').Text=[string]@($records | Where-Object {$_.Problem}).Count
    }else{
        $offlineBlock.Text='—';$offlineBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'PlaceholderBrush')
    }
    Update-ManagerResourceSummary
    $note=$w.FindName('SummaryNote')
    if($checked -and $script:managerStatusLastRun){
        $run=$script:managerStatusLastRun
        $note.Text=if($run.Date -eq [DateTime]::Today){'上次检测 今天 '+$run.ToString('HH:mm')}else{'上次检测 '+$run.ToString('MM-dd HH:mm')}
    }elseif($checked){$note.Text='本次运行的检测结果'}
    else{$note.Text='尚未检测'}
    $note.ToolTip='检测结果只保留在本次运行，不写入任何文件。'
    Update-ManagerSidebarStatusCounts
    Update-ManagerAutoRefreshUi
    Update-ManagerSummaryResponsive
}
if($null -eq $script:managerStatus){$script:managerStatus=@{}}
# ---- Explicit status check: UI glue. Probe and background layer live in Panel-StatusCheck.ps1. ----
$script:managerChipStyles=@{
    Ok=@([string][char]0x2713,'SuccessSoftBrush','SuccessBrush')
    Fail=@([string][char]0x2715,'WarnSoftBrush','WarnBrush')
    Warn=@('!','CautionSoftBrush','CautionBrush')
    Skipped=@([string][char]0x2014,'SurfaceSoftBrush','MutedBrush')
    Checking=@([string][char]0x2026,'SurfaceSoftBrush','MutedBrush')
    Unknown=@([string][char]0x25CB,'SurfaceBrush','MutedBrush')
}
function Get-ManagerCardRow([string]$Id) {
    foreach($row in @($script:cards)){if([string]$row.Entry.Id -eq $Id){return $row}}
    return $null
}
function Set-ManagerStatusChip($Card,[string]$Layer,[string]$Kind,[string]$Label,[string]$Tip) {
    $style=$script:managerChipStyles[$Kind];if(-not $style){$Kind='Unknown';$style=$script:managerChipStyles.Unknown}
    $chip=$Card.FindName('Chip'+$Layer);$text=$Card.FindName('Chip'+$Layer+'Text')
    $text.Text=$style[0]+' '+$Label
    $chip.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,$style[1])
    $text.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$style[2])
    $chip.ToolTip=$Label+'：'+$Tip
    $chip.Tag=$Kind
}
function ConvertTo-ManagerStatusRecord($Result,[string]$Outcome) {
    $now=[DateTime]::Now
    if($Outcome -eq 'Cancelled'){return @{State='Cancelled';CheckedAt=$now}}
    if($Outcome -ne 'Completed' -or -not $Result){
        $text=if($Outcome -eq 'TimedOut'){'检测超时'}else{'检测出错'}
        return @{State='Done';CheckedAt=$now;HttpMs=$null;LatencyMs=$null;Traffic=$null;Xray=$null;Problem=$true
            Tunnel=@{State='Skipped';Text='未完成'};Http=@{State='Fail';Text=$text};Login=@{State='Skipped';Text='未完成'}}
    }
    $record=@{State='Done';CheckedAt=$now;HttpMs=$Result.HttpMs;LatencyMs=$Result.LatencyMs;LatencyKind=[string]$Result.LatencyKind;LatencySamples=@($Result.LatencySamples);Traffic=$Result.Traffic;Resources=$Result.Resources;Xray=$null;Problem=$false;Error=[string]$Result.Error;AuthRejected=[bool]$Result.AuthRejected;NetworkFailed=[bool]$Result.NetworkFailed}
    if($Result.Metrics){$record.Metrics=@{HttpRequests=[int]$Result.Metrics.HttpRequests;LoginRequests=[int]$Result.Metrics.LoginRequests;SessionReused=[bool]$Result.Metrics.SessionReused}}
    foreach($layer in 'Tunnel','Http','Login'){$record[$layer]=@{State=[string]$Result.$layer.State;Text=[string]$Result.$layer.Text}}
    if($Result.Xray){$record.Xray=@{State=[string]$Result.Xray.State;Version=[string]$Result.Xray.Version}}
    $record.Problem=[bool]($record.Error -or @('Tunnel','Http','Login' | Where-Object {$record[$_].State -in @('Fail','Warn')}).Count)
    return $record
}
function Update-ManagerCardStatus($Row) {
    $card=$Row.Control
    switch($Row.StateKind){
        'Ready' {Set-ManagerStatusChip $card 'Account' 'Ok' '账号' '本机账号可读（本机加密保存）'}
        'Missing' {Set-ManagerStatusChip $card 'Account' 'Fail' '账号' '未保存面板账号'}
        default {Set-ManagerStatusChip $card 'Account' 'Fail' '账号' '本机账号无法解密'}
    }
    $direct=$Row.Access -ne 'Tunnel'
    $record=$script:managerStatus[[string]$Row.Entry.Id]
    $detail=$card.FindName('CheckDetail')
    if(-not $record -or $record.State -eq 'Cancelled'){
        if($direct){Set-ManagerStatusChip $card 'Tunnel' 'Skipped' '隧道' '直连面板，不使用 SSH 隧道'}else{Set-ManagerStatusChip $card 'Tunnel' 'Unknown' '隧道' '未检测'}
        Set-ManagerStatusChip $card 'Http' 'Unknown' 'HTTP' '未检测'
        Set-ManagerStatusChip $card 'Login' 'Unknown' '登录' '未检测'
        $detail.Text=if($record){'已取消检测 · '+$record.CheckedAt.ToString('HH:mm')}else{'未检测 · 点击检测图标或「批量检测」'}
        $detail.ToolTip=$null
        Set-ManagerCardStatusView $Row $(if($record){'Cancelled'}else{'None'}) $record
        return
    }
    if($record.State -eq 'Checking'){
        if($direct){Set-ManagerStatusChip $card 'Tunnel' 'Skipped' '隧道' '直连面板，不使用 SSH 隧道'}else{Set-ManagerStatusChip $card 'Tunnel' 'Checking' '隧道' '检测中'}
        Set-ManagerStatusChip $card 'Http' 'Checking' 'HTTP' '检测中'
        Set-ManagerStatusChip $card 'Login' 'Checking' '登录' '检测中'
        $detail.Text='检测中…'
        $detail.ToolTip=$null
        Set-ManagerCardStatusView $Row 'Checking' $record
        return
    }
    Set-ManagerStatusChip $card 'Tunnel' $record.Tunnel.State '隧道' $record.Tunnel.Text
    Set-ManagerStatusChip $card 'Http' $record.Http.State 'HTTP' $record.Http.Text
    Set-ManagerStatusChip $card 'Login' $record.Login.State '登录' $record.Login.Text
    $parts=[Collections.ArrayList]::new()
    if($record.Error){[void]$parts.Add($record.Error)}
    if($record.Tunnel.State -eq 'Fail'){[void]$parts.Add($record.Tunnel.Text)}
    if($null -ne $record.LatencyMs){[void]$parts.Add('TCP '+$record.LatencyMs+'ms（'+@($record.LatencySamples).Count+' 次采样）')}
    if($null -ne $record.HttpMs){[void]$parts.Add('HTTP 响应 '+$record.HttpMs+'ms')}
    if($record.Http.State -eq 'Fail' -or $record.Http.State -eq 'Warn'){[void]$parts.Add($record.Http.Text)}
    if($record.Login.State -eq 'Ok'){[void]$parts.Add('登录正常')}
    elseif($record.Login.State -eq 'Fail' -or ($record.Login.State -eq 'Skipped' -and $record.Http.State -ne 'Fail' -and $record.Tunnel.State -ne 'Fail')){[void]$parts.Add($record.Login.Text)}
    if($record.Xray){
        $xray=switch($record.Xray.State){'running'{'Xray 运行中'}'stop'{'Xray 已停止'}'error'{'Xray 异常'}default{'Xray 状态未知'}}
        if($record.Xray.Version){$xray+=' v'+$record.Xray.Version}
        [void]$parts.Add($xray)
    }
    if($record.Traffic -and $record.Traffic.State -eq 'Ok'){[void]$parts.Add('累计流量 '+(Format-ManagerTrafficBytes $record.Traffic.TotalBytes))}
    [void]$parts.Add($record.CheckedAt.ToString('HH:mm')+' 检测')
    $detail.Text=$parts -join ' · '
    $detail.ToolTip=('本机账号：'+$card.FindName('ChipAccount').ToolTip+[Environment]::NewLine+'SSH 隧道：'+$record.Tunnel.Text+[Environment]::NewLine+'HTTP：'+$record.Http.Text+[Environment]::NewLine+'面板登录：'+$record.Login.Text)
    Set-ManagerCardStatusView $Row 'Done' $record
    if($script:managerAutoRefresh -and $script:managerAutoRefresh.UpdatingIds.ContainsKey([string]$Row.Entry.Id)){
        $card.FindName('StatusText').Text='更新中'
        $card.FindName('StatusTipTitle').Text='正在更新 · 显示上次检测结果'
        $detail.Text='更新中 · '+$record.CheckedAt.ToString('HH:mm:ss')+' 的检测结果'
    }
}
# mockup card status (dot + 「在线 42ms」 / 「离线」 / 「未检测」), unreachable-card styling,
# middle slot (alert line / account problem / traffic placeholder) and the offline action swap.
$script:managerStatusLook=@{
    Ok=@('SuccessBrush','#263E9B5F','MutedBrush')
    Warn=@('ExpiringDotBrush','#26D9822B','ExpiringBrush')
    Bad=@('BadBrush','#26C94A3B','BadBrush')
    Neutral=@('NeutralDotBrush','#26BDB6AE','FaintBrush')
}
function Format-ManagerTrafficBytes($Bytes) {
    if($null -eq $Bytes){return '—'}
    $value=[double]$Bytes
    if($value -lt 0 -or [double]::IsNaN($value) -or [double]::IsInfinity($value)){return '—'}
    $units=@('B','KiB','MiB','GiB','TiB','PiB');$index=0
    while($value -ge 1024 -and $index -lt $units.Count-1){$value/=1024;$index++}
    return $value.ToString($(if($index){'0.##'}else{'0'}),[Globalization.CultureInfo]::InvariantCulture)+' '+$units[$index]
}
function Update-ManagerCardTraffic($Card,[string]$Phase,$Record,$Metadata=$null) {
    $value=$Card.FindName('TrafficValue');$panel=$Card.FindName('TrafficPanel')
    $value.ToolTip=$null
    $hint=$Card.FindName('TrafficHint')
    $remaining=$Card.FindName('TrafficRemaining');$remaining.Text=''
    $remaining.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'FaintBrush')
    if(-not $Metadata -and $Card.Tag -and $Card.Tag.Entry){$Metadata=Get-ManagerEntryMetadata $Card.Tag.Entry}
    $quota=if($Metadata -and $Metadata.TotalTrafficBytes -gt 0){[double]$Metadata.TotalTrafficBytes}else{$null}
    $panel.Tag=@{HasQuota=($null -ne $quota);UsedBytes=$null;QuotaBytes=$quota;UsageRatio=$null;Percent=$null;Kind='Pending'}
    $Card.FindName('TrafficLabel').Text=if($quota){'流量用量'}else{'累计流量'}
    foreach($name in 'TrafficUploadFill','TrafficDownloadFill'){$Card.FindName($name).Visibility='Collapsed'}
    $Card.FindName('TrafficUploadColumn').Width=[Windows.GridLength]::new(0,[Windows.GridUnitType]::Star)
    $Card.FindName('TrafficDownloadColumn').Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star)
    $value.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'PlaceholderBrush')
    $hint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'FaintBrush')
    $hint.Text=if($quota){'已设置总量 · 检测后显示进度'}else{'点击设置总流量'}
    $panel.ToolTip='用量来自服务器网卡累计发送 + 接收，通常随重启归零；总流量可在铅笔编辑中设置。'
    if($Phase -eq 'Checking'){$value.Text='读取中…';return}
    if($Phase -ne 'Done'){$value.Text='待检测';return}
    $traffic=$Record.Traffic
    if($traffic -and $traffic.State -eq 'Ok' -and $null -ne $traffic.TotalBytes){
        $value.Text=Format-ManagerTrafficBytes $traffic.TotalBytes
        $value.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'MutedBrush')
        $used=[double]$traffic.TotalBytes;$panel.Tag.UsedBytes=$used
        $quotaDetail='尚未设置总流量，进度条留空。'
        if($quota){
            $unit=[string]$Metadata.TotalTrafficUnit
            $factor=switch($unit){'TB'{1e12}'GiB'{1073741824.0}'TiB'{1099511627776.0}default{$unit='GB';1e9}}
            $culture=[Globalization.CultureInfo]::InvariantCulture
            $usageRatio=$used/$quota;$percent=$usageRatio*100
            $usedText=($used/$factor).ToString('0.###',$culture)
            $quotaText=($quota/$factor).ToString('0.###',$culture)
            $percentText=$percent.ToString('0.#',$culture)+'%'
            $value.Text=$usedText+' / '+$quotaText+' '+$unit+' · '+$percentText
            $ratio=[Math]::Max([double]0,[Math]::Min([double]1,$usageRatio))
            $Card.FindName('TrafficUploadColumn').Width=[Windows.GridLength]::new($ratio,[Windows.GridUnitType]::Star)
            $Card.FindName('TrafficDownloadColumn').Width=[Windows.GridLength]::new(1-$ratio,[Windows.GridUnitType]::Star)
            if($used -gt 0){$Card.FindName('TrafficUploadFill').Visibility='Visible'}
            $kind=if($usageRatio -ge 1){'Exceeded'}elseif($usageRatio -ge 0.8){'Warning'}else{'Normal'}
            $color=switch($kind){'Exceeded'{'BadBrush'}'Warning'{'ExpiringDotBrush'}default{'AccentBrush'}}
            $Card.FindName('TrafficUploadFill').SetResourceReference([Windows.Controls.Border]::BackgroundProperty,$color)
            if($kind -ne 'Normal'){
                $value.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$color)
                $hint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$color)
                $remaining.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$color)
            }
            if($used -gt $quota){$hint.Text='已超出 '+(($used-$quota)/$factor).ToString('0.###',$culture)+' '+$unit+' · 点击调整'}
            elseif($used -eq $quota){$hint.Text='额度已用完 · 点击调整总量'}
            else{$hint.Text='剩余 '+(($quota-$used)/$factor).ToString('0.###',$culture)+' '+$unit+' · 点击调整总量'}
            $remaining.Text=if($used -gt $quota){' · 超出 '+(($used-$quota)/$factor).ToString('0.##',$culture)+$unit}else{' · 剩余 '+([Math]::Max([double]0,[double]($quota-$used))/$factor).ToString('0.##',$culture)+$unit}
            $panel.Tag.UsageRatio=$usageRatio;$panel.Tag.Percent=$percent;$panel.Tag.Kind=$kind
            $quotaDetail='已用 '+$usedText+' '+$unit+' / 总量 '+$quotaText+' '+$unit+' · '+$percentText
        }else{
            $panel.Tag.Kind='NoQuota';$hint.Text='未设置总量 · 点击设置'
        }
        $panel.ToolTip=('服务器网卡累计用量'+[Environment]::NewLine+'发送 ↑ '+(Format-ManagerTrafficBytes $traffic.UploadBytes)+' · 接收 ↓ '+(Format-ManagerTrafficBytes $traffic.DownloadBytes)+[Environment]::NewLine+$quotaDetail+[Environment]::NewLine+'来源：3X-UI netTraffic，按发送 + 接收计算，通常随重启归零。'+[Environment]::NewLine+'供应商可能采用不同计费口径；这里不会自动按月重置。'+[Environment]::NewLine+$Record.CheckedAt.ToString('HH:mm')+' 更新 · 总量可在铅笔编辑中设置')
        $value.ToolTip=$value.Text
    }else{
        $value.Text=if($Record.Login.State -ne 'Ok'){'登录后可读取'}else{'暂不可用'}
        if($traffic -and $traffic.Text){$panel.ToolTip=[string]$traffic.Text}
    }
}
function Set-ManagerCardStatusView($Row,[string]$Phase,$Record) {
    $card=$Row.Control
    $text='未检测';$look='Neutral';$ms=$null;$title='未检测 · 点「批量检测」或卡片上的检测图标后才会联网'
    $note=$null;$noteLook=$null
    $offline=Test-ManagerRecordOffline $Record
    switch($Phase){
        'Cancelled' {$text='已取消';$title='已取消检测'}
        'Checking' {$text='检测中…';$title='正在只读检测…'}
        'Done' {
            $title=('检测详情 · '+$Record.CheckedAt.ToString('HH:mm'))
            if($offline){
                $look='Bad'
                if($Record.Tunnel.State -eq 'Fail'){$text='隧道异常';$note=$Record.Tunnel.Text;$noteLook='Bad'}
                else{$text='离线';$note=($Record.Http.Text+' · '+$Record.CheckedAt.ToString('HH:mm')+' 检测');$noteLook='Bad'}
            }elseif(Test-ManagerRecordOnline $Record){
                $text='在线';$ms=$Record.LatencyMs
                $look=if($Record.Problem){'Warn'}else{'Ok'}
                if($Record.Login.State -eq 'Fail'){$note=$Record.Login.Text;$noteLook='Warn'}
                elseif($Record.Http.State -eq 'Warn'){$note=$Record.Http.Text;$noteLook='Warn'}
                elseif($Record.Error){$note=$Record.Error;$noteLook='Warn'}
            }else{
                $text='状态未知';$look='Warn'
                if($Record.Error){$note=$Record.Error;$noteLook='Warn'}
            }
        }
    }
    $style=$script:managerStatusLook[$look]
    Set-ManagerBrush $card.FindName('StatusDot') ([Windows.Shapes.Shape]::FillProperty) $style[0]
    Set-ManagerBrush $card.FindName('StatusRing') ([Windows.Shapes.Shape]::FillProperty) $style[1]
    $label=$card.FindName('StatusText');$label.Text=$text
    Set-ManagerBrush $label ([Windows.Controls.TextBlock]::ForegroundProperty) $style[2]
    $msBlock=$card.FindName('StatusMs')
    if($null -ne $ms){
        $msBlock.Text=([string]$ms+'ms');$msBlock.Visibility='Visible'
        Set-ManagerBrush $msBlock ([Windows.Controls.TextBlock]::ForegroundProperty) (Get-ManagerLatencyBrushKey $ms)
        $msBlock.ToolTip='本机直连服务器 TCP 建连延迟，多次采样中位数；HTTP 响应耗时另列在检测详情。'
    }else{$msBlock.Visibility='Collapsed';Set-ManagerBrush $msBlock ([Windows.Controls.TextBlock]::ForegroundProperty) 'PlaceholderBrush'}
    $card.FindName('StatusTipTitle').Text=$title
    Update-ManagerCardTraffic $card $Phase $Record $Row.Meta
    # Middle slot priority: check alert > account problem > read-only server traffic.
    $offNote=$card.FindName('OffNote')
    if($note){
        $offNote.Visibility='Visible'
        $card.FindName('OffNoteText').Text=$note;$offNote.ToolTip=$note
        if($noteLook -eq 'Bad'){
            Set-ManagerBrush $offNote ([Windows.Controls.Border]::BackgroundProperty) 'BadSoftBrush'
            Set-ManagerBrush $card.FindName('OffNoteText') ([Windows.Controls.TextBlock]::ForegroundProperty) 'BadTextBrush'
            Set-ManagerBrush $card.FindName('OffNoteIcon') ([Windows.Shapes.Shape]::StrokeProperty) 'BadTextBrush'
        }else{
            Set-ManagerBrush $offNote ([Windows.Controls.Border]::BackgroundProperty) 'ExpiringSoftBrush'
            Set-ManagerBrush $card.FindName('OffNoteText') ([Windows.Controls.TextBlock]::ForegroundProperty) 'ExpiringBrush'
            Set-ManagerBrush $card.FindName('OffNoteIcon') ([Windows.Shapes.Shape]::StrokeProperty) 'ExpiringBrush'
        }
    }else{$offNote.Visibility='Collapsed'}
    $accountProblem=-not $Row.HasAccount
    $card.FindName('AccountStatusFrame').Visibility=if($accountProblem -and -not $note){'Visible'}else{'Collapsed'}
    $trafficReady=$Record -and $Record.Traffic -and $Record.Traffic.State -eq 'Ok'
    $card.FindName('TrafficPanel').Visibility=if($accountProblem -or ($note -and -not $trafficReady)){'Collapsed'}else{'Visible'}
    # Unreachable direct panels: soft 「重新检测」 takes the wide slot, 「进入面板」 stays reachable as an icon.
    $refs=$card.Tag
    if($refs -is [hashtable] -and $refs.Recheck){
        $swap=$offline -and $Row.Access -ne 'Tunnel' -and $Record.Http.State -eq 'Fail'
        $refs.Primary.Visibility=if($swap){'Collapsed'}else{'Visible'}
        $refs.Recheck.Visibility=if($swap){'Visible'}else{'Collapsed'}
        $refs.CheckIcon.Visibility=if($swap){'Collapsed'}else{'Visible'}
        $refs.OpenIcon.Visibility=if($swap){'Visible'}else{'Collapsed'}
    }
    Update-ManagerCardChrome $Row
}
function Update-ManagerCardChrome($Row) {
    $card=$Row.Control
    $offline=Test-ManagerRecordOffline $script:managerStatus[[string]$Row.Entry.Id]
    $kind=if($Row.Meta){[string]$Row.Meta.ExpiryKind}else{'None'}
    $back=$card.FindName('CardBack');$frame=$card.FindName('CardFrame');$badge=$card.FindName('BadgeFrame');$code=$card.FindName('ServerBadge')
    if($offline){
        Set-ManagerBrush $back ([Windows.Controls.Border]::BackgroundProperty) 'OfflineBackBrush'
        Set-ManagerBrush $frame ([Windows.Controls.Border]::BorderBrushProperty) 'OfflineLineBrush'
        Set-ManagerBrush $badge ([Windows.Controls.Border]::BackgroundProperty) 'OfflineBadgeBrush'
        Set-ManagerBrush $badge ([Windows.Controls.Border]::BorderBrushProperty) 'OfflineBadgeLineBrush'
        Set-ManagerBrush $code ([Windows.Controls.TextBlock]::ForegroundProperty) 'OfflineInkBrush'
    }else{
        Set-ManagerBrush $back ([Windows.Controls.Border]::BackgroundProperty) 'SurfaceBrush'
        Set-ManagerBrush $frame ([Windows.Controls.Border]::BorderBrushProperty) $(switch($kind){'Expiring'{'ExpiringLineBrush'}'Expired'{'ExpiredLineBrush'}default{'LineBrush'}})
        Set-ManagerBrush $badge ([Windows.Controls.Border]::BackgroundProperty) 'BadgeBrush'
        Set-ManagerBrush $badge ([Windows.Controls.Border]::BorderBrushProperty) 'Line2Brush'
        Set-ManagerBrush $code ([Windows.Controls.TextBlock]::ForegroundProperty) 'BadgeInkBrush'
    }
}
function Update-ManagerCheckProgress($Batch) {
    $panel=$script:window.FindName('CheckProgressPanel')
    if(-not $Batch -or $Batch.Completed){$panel.Visibility='Collapsed';Update-ManagerSummaryResponsive;return}
    $panel.Visibility='Visible'
    $script:window.FindName('CheckProgressText').Text=('检测中 '+$Batch.Done+' / '+$Batch.Total)
    $bar=$script:window.FindName('CheckProgressBar');$bar.Maximum=[Math]::Max(1,$Batch.Total);$bar.Value=$Batch.Done
    Update-ManagerSummaryResponsive
}
function Start-ManagerStatusCheck {
    param([object[]]$Entries,[switch]$Automatic)
    Repair-ManagerAutoRefreshBatch
    if(Test-ManagerStatusBatchBusy){if(-not $Automatic){Set-ManagerFeedback '正在检测或结束上一轮请求，请稍后重试。'};return}
    $targets=@($Entries | Where-Object {$_})
    if($Automatic){$targets=@(Get-ManagerAutoRefreshEligible $targets (Get-ManagerAutoRefreshNow))}
    if(-not $targets.Count){return}
    $specs=[Collections.ArrayList]::new()
    foreach($entry in $targets){
        if(-not $Automatic){
            Reset-ManagerAutoRefreshServer ([string]$entry.Id)
            if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache -Id ([string]$entry.Id)}
        }
        $spec=New-ManagerStatusSpec $entry;$spec.Automatic=[bool]$Automatic
        [void]$specs.Add($spec)
    }
    Notify-ManagerAutoRefreshBatchStarted $targets ([bool]$Automatic)
    foreach($entry in $targets){
        $old=$script:managerStatus[[string]$entry.Id]
        if(-not $Automatic -or -not $old -or $old.State -ne 'Done'){$script:managerStatus[[string]$entry.Id]=@{State='Checking'}}
        $row=Get-ManagerCardRow ([string]$entry.Id);if($row){Update-ManagerCardStatus $row}
    }
    Set-ManagerFeedback ('正在只读检测 '+$specs.Count+' 台服务器…')
    try{
        $script:managerStatusBatch=Start-ManagerBackgroundBatch -Items $specs.ToArray() -WorkerScript (Get-ManagerProbeWorkerScript) `
            -Concurrency $script:managerStatusConcurrency -TimeoutSeconds $script:managerStatusHardTimeoutSeconds `
            -OnItemDone {param($spec,$result,$outcome) Complete-ManagerStatusItem $spec $result $outcome} `
            -OnProgress {param($batch) Update-ManagerCheckProgress $batch} `
            -OnComplete {param($batch) Complete-ManagerStatusCheck $batch}
    }catch{
        foreach($spec in $specs){Complete-ManagerStatusItem $spec $null 'Failed'}
        Notify-ManagerAutoRefreshBatchCompleted
        throw
    }
    Update-ManagerSummary
}
function Complete-ManagerStatusItem($Spec,$Result,[string]$Outcome) {
    $Spec.Password=$null;$Spec.Username=$null
    $record=ConvertTo-ManagerStatusRecord $Result $Outcome
    if($Outcome -eq 'Cancelled' -and $script:managerAutoRefresh -and $script:managerAutoRefresh.PreviousRecords.ContainsKey([string]$Spec.Id)){$record=$script:managerAutoRefresh.PreviousRecords[[string]$Spec.Id]}
    $script:managerStatus[[string]$Spec.Id]=$record
    if($Outcome -ne 'Cancelled'){Register-ManagerResourceResult -Id ([string]$Spec.Id) -ResultResources $record.Resources}
    Notify-ManagerAutoRefreshResult $Spec $record $Outcome
    $row=Get-ManagerCardRow ([string]$Spec.Id);if($row){Update-ManagerCardStatus $row}
    if($row){Update-ManagerCardResources $row}
    Update-ManagerResourceDrawer
    Update-ManagerSummary
}
function Complete-ManagerStatusCheck($Batch) {
    foreach($item in @($Batch.Queue)+@($Batch.Running)){if($item.Password){$item.Password=$null}}
    $script:managerStatusLastRun=[DateTime]::Now
    Update-ManagerCheckProgress $Batch
    Update-ManagerSummary
    Notify-ManagerAutoRefreshBatchCompleted
    if($Batch.Cancelled){Set-ManagerFeedback '已取消检测。';return}
    $records=@($script:cards | ForEach-Object {$script:managerStatus[[string]$_.Entry.Id]} | Where-Object {$_ -and $_.State -eq 'Done'})
    $online=@($records | Where-Object {$_.Http.State -eq 'Ok' -or $_.Http.State -eq 'Warn'}).Count
    $login=@($records | Where-Object {$_.Login.State -eq 'Ok'}).Count
    $problem=@($records | Where-Object {$_.Problem}).Count
    Set-ManagerFeedback ('检测完成 · HTTP 可达 '+$online+'/'+$records.Count+' · 登录正常 '+$login+' · 异常 '+$problem)
}
function Stop-ManagerStatusCheck {
    if($script:managerStatusBatch -and -not $script:managerStatusBatch.Completed){Stop-ManagerBackgroundBatch $script:managerStatusBatch}
}
# ---- Sidebar filters (group / ungrouped / expiring / expired / online / offline / unchecked) combined with search. ----
function Test-ManagerListFilter($Row,$Filter) {
    $meta=$Row.Meta
    switch([string]$Filter.Kind){
        'Provider' {$source=Get-ManagerEntryPurchase $Row.Entry;return [bool]($source -and $source.ProviderId -eq [string]$Filter.Value)}
        'PurchaseAccount' {$source=Get-ManagerEntryPurchase $Row.Entry;return [bool]($source -and $source.AccountId -eq [string]$Filter.Value)}
        'UnassignedPurchase' {return ($null -eq (Get-ManagerEntryPurchase $Row.Entry))}
        'Resources' {return (Test-ManagerResourceAttention ([string]$Row.Entry.Id))}
        'Group' {return [bool]($meta -and $meta.Group -ceq [string]$Filter.Value)}
        'Ungrouped' {return (-not ($meta -and $meta.Group))}
        'Expiring' {return [bool]($meta -and $meta.ExpiryKind -eq 'Expiring')}
        'Expired' {return [bool]($meta -and $meta.ExpiryKind -eq 'Expired')}
        'Online' {return (Test-ManagerRecordOnline $script:managerStatus[[string]$Row.Entry.Id])}
        'Offline' {return (Test-ManagerRecordOffline $script:managerStatus[[string]$Row.Entry.Id])}
        'Unchecked' {$record=$script:managerStatus[[string]$Row.Entry.Id];return (-not ($record -and $record.State -eq 'Done'))}
        default {return $true}
    }
}
function Get-ManagerListFilterTitle($Filter) {
    switch([string]$Filter.Kind){
        'Provider' {$p=@(Get-ManagerPurchaseProviders | Where-Object {$_.Id -eq $Filter.Value});return ('服务商 · '+[string]$p[0].Name)}
        'PurchaseAccount' {$a=@(Get-ManagerPurchaseAccounts | Where-Object {$_.Id -eq $Filter.Value});return ('购买账号 · '+[string]$a[0].Alias)}
        'UnassignedPurchase' {return '未设置购买来源'}
        'Resources' {return '资源需关注'}
        'Group' {return ('客户分组 · '+$Filter.Value)}
        'Ungrouped' {return '未分组'}
        'Expiring' {return '7 天内到期'}
        'Expired' {return '已到期'}
        'Online' {return '在线'}
        'Offline' {return '离线'}
        'Unchecked' {return '未检测'}
        default {return '全部服务器'}
    }
}
function Set-ManagerListFilter([string]$Kind,$Value) {
    Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse
    if(-not $Kind){$Kind='All'}
    $script:managerListFilter=@{Kind=$Kind;Value=$Value}
    Set-ManagerSidebarSelection
    Update-ManagerPurchaseSidebar
    Update-ManagerFilter
}
# Sidebar row (mockup .gi): letter avatar (group colour) or dashed 「?」 for 未分组, label, right-aligned count.
function New-ManagerSidebarItem([string]$Kind,$Value,[string]$Label,[int]$Count,[string]$DotBrush) {
    $button=[Windows.Controls.Button]::new()
    $button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'SidebarItem')
    $grid=[Windows.Controls.Grid]::new()
    foreach($width in @([Windows.GridLength]::Auto,[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star),[Windows.GridLength]::Auto)){
        $column=[Windows.Controls.ColumnDefinition]::new();$column.Width=$width;$grid.ColumnDefinitions.Add($column)
    }
    $avatar=[Windows.Controls.Grid]::new();$avatar.Width=20;$avatar.Height=20;$avatar.Margin=[Windows.Thickness]::new(0,0,9,0)
    $initial=[Windows.Controls.TextBlock]::new();$initial.FontSize=11;$initial.FontWeight=[Windows.FontWeights]::SemiBold;$initial.HorizontalAlignment='Center';$initial.VerticalAlignment='Center'
    if($Kind -eq 'Group'){
        $palette=Get-ManagerGroupPalette ([string]$Value)
        $fill=[Windows.Controls.Border]::new();$fill.CornerRadius=[Windows.CornerRadius]::new(6);$fill.Background=New-ManagerBrush $palette.Avatar
        [void]$avatar.Children.Add($fill)
        $initial.Text=Get-ManagerGroupInitial ([string]$Value);$initial.Foreground=[Windows.Media.Brushes]::White
    }else{
        $dash=[Windows.Shapes.Rectangle]::new();$dash.RadiusX=6;$dash.RadiusY=6;$dash.Stroke=New-ManagerBrush '#C9C1B7';$dash.StrokeThickness=1
        $dash.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@(2,2));$dash.Fill=[Windows.Media.Brushes]::White
        [void]$avatar.Children.Add($dash)
        $initial.Text='?';$initial.Foreground=New-ManagerBrush '#9C948B'
    }
    [void]$avatar.Children.Add($initial)
    $text=[Windows.Controls.TextBlock]::new();$text.Text=$Label;$text.TextTrimming='CharacterEllipsis';$text.SetResourceReference([Windows.Controls.TextBlock]::FontFamilyProperty,'NameFont');$text.SetValue([Windows.Media.TextOptions]::TextFormattingModeProperty,[Windows.Media.TextFormattingMode]::Ideal)
    [Windows.Controls.Grid]::SetColumn($text,1)
    $countBlock=[Windows.Controls.TextBlock]::new();$countBlock.Text=[string]$Count;$countBlock.FontSize=12;$countBlock.Margin=[Windows.Thickness]::new(6,0,0,0)
    [Windows.Controls.Grid]::SetColumn($countBlock,2)
    [void]$grid.Children.Add($avatar);[void]$grid.Children.Add($text);[void]$grid.Children.Add($countBlock)
    $button.Content=$grid
    $button.ToolTip=$Label
    [Windows.Automation.AutomationProperties]::SetName($button,$Label)
    $button.Tag=@{Kind=$Kind;Value=$Value;LabelBlock=$text;CountBlock=$countBlock}
    $button.Add_Click({param($sender,$eventArgs) Set-ManagerListFilter $sender.Tag.Kind $sender.Tag.Value})
    return $button
}
function Get-ManagerSidebarButtons {
    $w=$script:window
    return @($w.FindName('SidebarAll')) + @($w.FindName('SidebarGroups').Children) + @($w.FindName('SidebarStatus').Children)
}
function Set-ManagerSidebarSelection {
    $filter=$script:managerListFilter
    foreach($button in @(Get-ManagerSidebarButtons)){
        if(-not $button -or -not $button.Tag){continue}
        $selected=($button.Tag.Kind -eq $filter.Kind) -and ([string]$button.Tag.Value -ceq [string]$filter.Value)
        if($selected){$button.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'SidebarSelectedBrush')}else{$button.Background=[Windows.Media.Brushes]::Transparent}
        $label=$button.Tag.LabelBlock;$count=$button.Tag.CountBlock
        $label.FontWeight=if($selected){[Windows.FontWeights]::SemiBold}else{[Windows.FontWeights]::Normal}
        $label.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($selected){'AccentHoverBrush'}else{'InkBrush'}))
        $count.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($selected){'AccentHoverBrush'}else{'FaintBrush'}))
        $count.FontWeight=$label.FontWeight
    }
}
function Update-ManagerSidebar {
    $w=$script:window
    $panel=$w.FindName('SidebarGroups');$panel.Children.Clear()
    $groups=[ordered]@{}
    foreach($name in @(Get-ManagerMetadataGroups)){$groups[$name]=0}
    $ungrouped=0
    foreach($row in @($script:cards)){
        $group=if($row.Meta){[string]$row.Meta.Group}else{''}
        if($group -and $groups.Contains($group)){$groups[$group]++}else{$ungrouped++}
    }
    foreach($name in $groups.Keys){[void]$panel.Children.Add((New-ManagerSidebarItem 'Group' $name $name $groups[$name] 'GroupDotBrush'))}
    [void]$panel.Children.Add((New-ManagerSidebarItem 'Ungrouped' $null '未分组' $ungrouped 'LineDotBrush'))
    $w.FindName('SidebarGroupHint').Visibility=if($groups.Count){'Collapsed'}else{'Visible'}
    $w.FindName('SidebarExpiringCount').Text=[string]@($script:cards | Where-Object {$_.Meta -and $_.Meta.ExpiryKind -eq 'Expiring'}).Count
    $w.FindName('SidebarExpiredCount').Text=[string]@($script:cards | Where-Object {$_.Meta -and $_.Meta.ExpiryKind -eq 'Expired'}).Count
    # A group that no longer exists (renamed / cleared) falls back to the full list.
    if($script:managerListFilter.Kind -eq 'Group' -and -not $groups.Contains([string]$script:managerListFilter.Value)){$script:managerListFilter=@{Kind='All';Value=$null}}
    Update-ManagerSidebarStatusCounts
    Set-ManagerSidebarSelection
    Update-ManagerPurchaseSidebar
}
# 在线 / 离线 show 「—」 until an explicit check has results; 未检测 counts cards without a finished check.
function Update-ManagerSidebarStatusCounts {
    $w=$script:window;if(-not $w){return}
    $records=@($script:cards | ForEach-Object {$script:managerStatus[[string]$_.Entry.Id]})
    $done=@($records | Where-Object {$_ -and $_.State -eq 'Done'})
    $w.FindName('SidebarOnlineCount').Text=if($done.Count){[string]@($done | Where-Object {Test-ManagerRecordOnline $_}).Count}else{'—'}
    $w.FindName('SidebarOfflineCount').Text=if($done.Count){[string]@($done | Where-Object {Test-ManagerRecordOffline $_}).Count}else{'—'}
    $w.FindName('SidebarUncheckedCount').Text=[string](@($script:cards).Count-$done.Count)
    if(@('Online','Offline','Unchecked') -contains [string]$script:managerListFilter.Kind -and @($script:cards).Count){Update-ManagerFilter}
}
function Update-ManagerFilter {
    Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse
    $query=$script:window.FindName('SearchBox').Text.Trim()
    $script:window.FindName('SearchHint').Visibility=if($query){'Collapsed'}else{'Visible'}
    $filter=$script:managerListFilter
    $filtered=$filter.Kind -ne 'All'
    $shown=0
    foreach($row in $script:cards){
        $text=$row.Entry.Name+' '+$row.Entry.Address
        if($row.Meta){$text+=' '+$row.Meta.Group+' '+$row.Meta.Note}
        $source=Get-ManagerEntryPurchase $row.Entry;if($source){$text+=' '+$source.ProviderName+' '+$source.AccountAlias+' '+$source.Hint}
        $match=((-not $query) -or ($text.IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)) -and (Test-ManagerListFilter $row $filter)
        $row.Control.Visibility=if($match){'Visible'}else{'Collapsed'}
        if($match){$shown++}else{$row.Control.FindName('ShowPassword').IsChecked=$false}
    }
    $script:window.FindName('ResultCount').Text=if($query -or $filtered){"$shown / $($script:entries.Count) 台"}else{"$shown 台"}
    $script:window.FindName('ListTitle').Text=Get-ManagerListFilterTitle $filter
    $script:window.FindName('ClearFilter').Visibility=if($filtered){'Visible'}else{'Collapsed'}
    $script:window.FindName('EmptyState').Text=if($filtered){'当前筛选下没有匹配的服务器。'}else{'没有找到匹配的服务器。'}
    $script:window.FindName('EmptyState').Visibility=if($shown -eq 0){'Visible'}else{'Collapsed'}
}
# Card metadata: group tag (palette colour), corner ribbon (orange ≤ 7 days, red when past), 到期 row (always shown,
# 「未设置」 when empty) and a one-line note with the full text in its tooltip.
function Set-ManagerCardMetadata($Card,$Meta) {
    $groupFrame=$Card.FindName('GroupFrame')
    if($Meta.Group){
        $palette=Get-ManagerGroupPalette $Meta.Group
        $groupFrame.Visibility='Visible';$groupFrame.Background=New-ManagerBrush $palette.Soft
        $groupLabel=$Card.FindName('GroupLabel');$groupLabel.Text=$Meta.Group;$groupLabel.Foreground=New-ManagerBrush $palette.Ink
        $groupFrame.ToolTip=('客户分组：'+$Meta.Group)
    }else{$groupFrame.Visibility='Collapsed'}
    $badgeFrame=$Card.FindName('ExpiryFrame');$badge=$Card.FindName('ExpiryBadge');$line=$Card.FindName('ExpiryText')
    $badgeFrame.Tag=$Meta.ExpiryKind
    $badgeFrame.Visibility='Collapsed'
    $Card.FindName('ExpiryRow').Height=[Windows.GridLength]::new(20)
    foreach($name in 'ExpiryCaption','ExpiryText'){$Card.FindName($name).Visibility='Visible'}
    $lineBrush='InkBrush';$bold=$false
    switch($Meta.ExpiryKind){
        'Ok' {$line.Text=($Meta.Expiry+' · 剩 '+$Meta.DaysLeft+' 天')}
        'Expiring' {
            $badge.Text=if($Meta.DaysLeft -eq 0){'今天到期'}else{[string]$Meta.DaysLeft+' 天后到期'}
            $badgeFrame.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'ExpiringDotBrush')
            $badgeFrame.Visibility='Visible'
            $line.Text=if($Meta.DaysLeft -eq 0){$Meta.Expiry+' · 今天到期'}else{$Meta.Expiry+' · 剩 '+$Meta.DaysLeft+' 天'}
            $lineBrush='ExpiringBrush';$bold=$true
        }
        'Expired' {
            $badge.Text='已到期'
            $badgeFrame.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'BadBrush')
            $badgeFrame.Visibility='Visible'
            $line.Text=($Meta.Expiry+' · 已过期 '+(-$Meta.DaysLeft)+' 天')
            $lineBrush='ExpiredBrush';$bold=$true
        }
        'Invalid' {$line.Text='到期日格式无效，请在「编辑」中修改';$lineBrush='WarnBrush'}
        default {$line.Text='未设置';$lineBrush='PlaceholderBrush'}
    }
    $line.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$lineBrush)
    $line.FontWeight=if($bold){[Windows.FontWeights]::SemiBold}else{[Windows.FontWeights]::Normal}
    $line.ToolTip=if($Meta.ExpiryKind -ne 'None'){'到期日（仅本机提醒，不会联网或弹出通知）：'+$Meta.Expiry}else{'未设置到期日 · 可在「编辑」里填写'}
    # The ribbon sits in the top-right corner, so the status moves down a little (as in the mockup).
    $Card.FindName('StatusPill').Margin=[Windows.Thickness]::new(0,0,5,0)
    $Card.FindName('BadgeFrame').Parent.Margin=if($badgeFrame.Visibility -eq 'Visible'){[Windows.Thickness]::new(0,10,0,0)}else{[Windows.Thickness]::new(0)}
    $note=$Card.FindName('NoteText')
    $hasNote=[bool]$Meta.Note
    $Card.FindName('NoteRow').Height=if($hasNote){[Windows.GridLength]::new(19)}else{[Windows.GridLength]::new(0)}
    foreach($name in 'NoteCaption','NoteText'){$Card.FindName($name).Visibility=if($hasNote){'Visible'}else{'Collapsed'}}
    if($hasNote){
        $note.Text=(($Meta.Note -split "`n" | Where-Object {$_.Trim()}) -join ' / ')
        $tip=[Windows.Controls.TextBlock]::new();$tip.Text=$Meta.Note;$tip.TextWrapping='Wrap';$tip.MaxWidth=320
        $note.ToolTip=$tip
    }else{$note.Text='';$note.ToolTip=$null}
}
function Copy-ManagerAccountValue($Sender,[string]$Field) {
    $account=Read-PanelAccount $Sender.Tag.Entry
    $value=[string]$account.$Field
    if($value){
        [Windows.Clipboard]::SetText($value)
        $label=if($Field -eq 'username'){'账号'}else{'密码'}
        Set-ManagerFeedback ($label+'已复制 · '+$Sender.Tag.Entry.Name)
    }else{Set-ManagerFeedback '请先在「名称 / 设置」中补充账号。'}
    $account=$null;$value=$null
}
# 面板 row: port plus a masked path hint only (the hidden panel path itself is never shown on the card).
function Set-ManagerPanelText($Card,$Entry,[string]$Access) {
    $block=$Card.FindName('PanelText');$block.Inlines.Clear()
    $uri=$null
    if(-not [Uri]::TryCreate([string]$Entry.Url,[UriKind]::Absolute,[ref]$uri)){
        $run=[Windows.Documents.Run]::new('—');$run.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty,'PlaceholderBrush');$block.Inlines.Add($run)
        $block.ToolTip='面板地址无效，请在「编辑」中修改';return
    }
    $hasPath=$uri.AbsolutePath -and $uri.AbsolutePath -ne '/'
    $parts=@()
    if($Access -eq 'Tunnel'){$parts+=,@('本机 ','FaintBrush')}
    $parts+=,@(':','FaintBrush')
    $parts+=,@([string]$uri.Port,'InkBrush')
    $parts+=,@($(if($hasPath){' /••••/'}else{' /'}),'FaintBrush')
    foreach($part in $parts){
        $run=[Windows.Documents.Run]::new($part[0]);$run.SetResourceReference([Windows.Documents.TextElement]::ForegroundProperty,$part[1]);$block.Inlines.Add($run)
    }
    $block.ToolTip=if($Access -eq 'Tunnel'){'经固定 SSH 隧道访问本机端口；面板路径已隐藏，进入面板时自动使用。'}else{'面板端口；面板路径已隐藏，进入面板时自动使用。'}
}
function Build-ManagerRows {
    Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse
    $container=$script:window.FindName('ServerCards')
    $offset=$script:window.FindName('ServerScroll').VerticalOffset
    $container.Children.Clear()
    $script:cards=@()
    [void](Import-ManagerMetadata)
    foreach($entry in @(Get-ManagerOrderedEntries)){
        $state=Get-ManagerAccountState -Entry $entry
        $meta=Get-ManagerEntryMetadata $entry
        $access=Get-ManagerAccessKind $entry
        $card=Read-ManagerXaml 'ServerCard.xaml'
        $location=Get-ManagerEntryLocation $entry
        $card.FindName('ServerBadge').Text=$location.CountryName
        $card.FindName('ServerFlag').Content=New-ManagerCountryFlag $location.CountryCode
        $card.FindName('ServerName').Text=$entry.Name
        $card.FindName('ServerName').ToolTip=$entry.Name
        $card.FindName('ServerAddress').Text=$entry.Address
        $card.FindName('ServerAddress').ToolTip=$entry.Address
        $card.FindName('RegionLabel').Text=$location.DisplayName+'·'
        $connection=$card.FindName('ConnectionLabel')
        if($access -eq 'Tunnel'){$connection.Text='SSH加密隧道';$connection.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'InfoBrush')}
        elseif($access -eq 'Https'){$connection.Text='HTTPS面板'}
        else{$connection.Text='HTTP面板';$connection.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'WarnBrush');$card.FindName('ConnectionFrame').ToolTip='明文 HTTP：状态检测不会发送密码'}
        Set-ManagerPanelText $card $entry $access
        $card.FindName('UsernameBox').Text=if($state.HasAccount){'••••••'}else{'—'}
        $card.FindName('PasswordDisplay').Text=if($state.HasAccount){'••••••'}else{'—'}
        $card.FindName('AccountStatus').Text=$state.StateText
        $context=@{Entry=$entry;Card=$card}
        $copyUser=$card.FindName('CopyUsername');$copyUser.Tag=$context
        $copyUser.Add_Click({param($sender,$args) try{Copy-ManagerAccountValue $sender 'username'}catch{Show-ManagerMessage '账号暂时无法读取，请重新导入加密账号。' '无法复制'}})
        $copyPassword=$card.FindName('CopyPassword');$copyPassword.Tag=$context
        $copyPassword.Add_Click({param($sender,$args) try{Copy-ManagerAccountValue $sender 'password'}catch{Show-ManagerMessage '账号暂时无法读取，请重新导入加密账号。' '无法复制'}})
        $userToggle=$card.FindName('ShowUsername');$userToggle.Tag=$context
        $userToggle.Add_Checked({param($sender,$args) try{$a=Read-PanelAccount $sender.Tag.Entry;$sender.Tag.Card.FindName('UsernameBox').Text=[string]$a.username;$a=$null}catch{$sender.IsChecked=$false;Show-ManagerMessage '账号暂时无法读取，请重新导入加密账号。' '无法显示'}})
        $userToggle.Add_Unchecked({param($sender,$args) $sender.Tag.Card.FindName('UsernameBox').Text='••••••'})
        $userToggle.IsEnabled=$state.HasAccount
        $toggle=$card.FindName('ShowPassword');$toggle.Tag=$context
        $toggle.Add_Checked({param($sender,$args)
            try{$account=Read-PanelAccount $sender.Tag.Entry;$sender.Tag.Card.FindName('PasswordDisplay').Text=[string]$account.password;$account=$null}
            catch{$sender.IsChecked=$false;Show-ManagerMessage '密码暂时无法读取，请重新导入加密账号。' '无法显示'}
        })
        $toggle.Add_Unchecked({param($sender,$args) $sender.Tag.Card.FindName('PasswordDisplay').Text='••••••'})
        $toggle.IsEnabled=$state.HasAccount
        $copyUser.IsEnabled=$state.HasAccount;$copyPassword.IsEnabled=$state.HasAccount
        Set-ManagerCardMetadata $card $meta
        Add-ManagerCardActions $card $entry
        $card.Tag.HasAccount=[bool]$state.HasAccount
        $more=$card.FindName('MoreButton');$more.Tag=$context;$more.Add_Click({param($s,$e) Show-ManagerCardMenu $s})
        [void]$container.Children.Add($card)
        $script:cards+=@{Entry=$entry;Control=$card;Access=$access;StateKind=[string]$state.StateKind;Meta=$meta;HasAccount=[bool]$state.HasAccount}
        Initialize-ManagerCardMonitoring $script:cards[$script:cards.Count-1]
        Update-ManagerCardStatus $script:cards[$script:cards.Count-1]
        $state=$null
    }
    Update-ManagerSidebar
    Update-ManagerSummary
    Update-ManagerFilter
    $script:window.FindName('ServerScroll').ScrollToVerticalOffset($offset)
}
function New-ManagerSettingsWindow($Entry) {
    $dialog=Read-ManagerXaml 'SettingsWindow.xaml';Add-ManagerTheme $dialog
    $state=Get-ManagerAccountState -Entry $Entry
    $dialog.FindName('SettingsAddress').Text=('保存后可在卡片上一键进入 3x-ui 面板 · '+$Entry.Address)
    $dialog.FindName('NameBox').Text=$Entry.Name
    $dialog.FindName('UrlBox').Text=$Entry.Url
    $dialog.FindName('AccountBox').Text=[string]$state.Account.username
    $dialog.FindName('SecretBox').Password=[string]$state.Account.password
    if($Entry.Tunnel){$dialog.FindName('SettingsHelp').Text='此面板使用 SSH 加密隧道。保留当前本机地址和端口，只修改后面的面板路径。账号密码在本机用 Windows DPAPI 加密保存。'}
    Initialize-ManagerMetadataFields $dialog $Entry
    $location=Get-ManagerEntryLocation $Entry
    $dialog.FindName('CountryBox').Text=$location.CountryName;$dialog.FindName('CityBox').Text=$location.City
    Initialize-ManagerDialogChrome $dialog $Entry
    $area=[Windows.SystemParameters]::WorkArea
    if($area.Height -gt 0){$dialog.FindName('SettingsScroll').MaxHeight=[Math]::Max(300,$area.Height-260)}
    $dialog.FindName('SaveSettings').Tag=@{Dialog=$dialog;Entry=$Entry}
    $dialog.FindName('SaveSettings').Add_Click({param($sender,$args)
        $d=$sender.Tag.Dialog
        try{
            if($d.FindName('SecretReveal').IsChecked){$d.FindName('SecretBox').Password=$d.FindName('SecretPlain').Text}
            $locationValues=ConvertTo-ManagerLocationInput -Country $d.FindName('CountryBox').Text -City $d.FindName('CityBox').Text
            $snapshot=Get-ManagerMetadataSnapshot
            [void](Save-ManagerLocationMetadata -Entry $sender.Tag.Entry -Country $locationValues.Country -City $locationValues.City)
            try{
            $saved=Save-ManagerServerEdit -Entry $sender.Tag.Entry -Name $d.FindName('NameBox').Text -Url $d.FindName('UrlBox').Text -Username $d.FindName('AccountBox').Text -Password $d.FindName('SecretBox').Password `
                -Expiry $d.FindName('ExpiryBox').Text -Group $d.FindName('GroupBox').Text -Note $d.FindName('NoteBox').Text `
                -TotalTrafficValue $d.FindName('TotalTrafficBox').Text -TotalTrafficUnit ([string]$d.FindName('TotalTrafficUnit').SelectedItem.Content)
            }catch{Restore-ManagerMetadataSnapshot $snapshot;throw}
            $d.Tag=@{ConnectionChanged=[bool]$saved.ConnectionChanged}
            $d.DialogResult=$true
        }catch{$d.FindName('SettingsError').Text=$_.Exception.Message}
    })
    return $dialog
}
function Get-ManagerUrlKindText([string]$Url) {
    $uri=$null
    if(-not [Uri]::TryCreate(([string]$Url).Trim(),[UriKind]::Absolute,[ref]$uri) -or ($uri.Scheme -ne 'http' -and $uri.Scheme -ne 'https')){return ''}
    if($uri.Scheme -eq 'http' -and $uri.Host -eq '127.0.0.1'){return '本机隧道地址'}
    if($uri.Scheme -eq 'https'){return 'HTTPS 面板'}
    return 'HTTP · 明文'
}
# Dialog chrome: close / drag, URL kind hint, placeholders, group avatar, password eye, 测试连接.
function Initialize-ManagerDialogChrome($Dialog,$Entry) {
    $close=$Dialog.FindName('CloseDialog');$close.Tag=$Dialog
    $close.Add_Click({param($sender,$eventArgs) try{$sender.Tag.DialogResult=$false}catch{$sender.Tag.Close()}})
    $header=$Dialog.FindName('DialogHeader');$header.Tag=$Dialog
    $header.Add_MouseLeftButtonDown({param($sender,$eventArgs) if($eventArgs.ButtonState -eq 'Pressed'){try{$sender.Tag.DragMove()}catch{}}})
    $url=$Dialog.FindName('UrlBox');$url.Tag=$Dialog.FindName('UrlKind')
    $url.Add_TextChanged({param($sender,$eventArgs) $sender.Tag.Text=Get-ManagerUrlKindText $sender.Text})
    $url.Tag.Text=Get-ManagerUrlKindText $url.Text
    $expiry=$Dialog.FindName('ExpiryBox');$expiry.Tag=$Dialog.FindName('ExpiryPlaceholder')
    $expiry.Add_TextChanged({param($sender,$eventArgs) $sender.Tag.Visibility=if($sender.Text){'Collapsed'}else{'Visible'}})
    $expiry.Tag.Visibility=if($expiry.Text){'Collapsed'}else{'Visible'}
    $group=$Dialog.FindName('GroupBox');$group.Tag=@{Placeholder=$Dialog.FindName('GroupPlaceholder');Avatar=$Dialog.FindName('GroupAvatar');Initial=$Dialog.FindName('GroupAvatarText')}
    $group.Add_TextChanged({param($sender,$eventArgs) Update-ManagerDialogGroupAvatar $sender})
    Update-ManagerDialogGroupAvatar $group
    $reveal=$Dialog.FindName('SecretReveal');$reveal.Tag=@{Secret=$Dialog.FindName('SecretBox');Plain=$Dialog.FindName('SecretPlain')}
    $reveal.Add_Checked({param($sender,$eventArgs) $t=$sender.Tag;$t.Plain.Text=$t.Secret.Password;$t.Plain.Visibility='Visible';$t.Secret.Visibility='Collapsed'})
    $reveal.Add_Unchecked({param($sender,$eventArgs) $t=$sender.Tag;$t.Secret.Password=$t.Plain.Text;$t.Plain.Clear();$t.Plain.Visibility='Collapsed';$t.Secret.Visibility='Visible'})
    $test=$Dialog.FindName('TestConnection');$test.Tag=@{Dialog=$Dialog;Entry=$Entry}
    $test.Add_Click({param($sender,$eventArgs) Start-ManagerDialogTest $sender.Tag.Dialog $sender.Tag.Entry})
    # Show the result of a check already made in this session (nothing is started here).
    Show-ManagerTestResult $Dialog $script:managerStatus[[string]$Entry.Id]
}
function Update-ManagerDialogGroupAvatar($Box) {
    $t=$Box.Tag;$value=([string]$Box.Text).Trim()
    $t.Placeholder.Visibility=if($Box.Text){'Collapsed'}else{'Visible'}
    if($value){$t.Avatar.Visibility='Visible';$t.Avatar.Background=New-ManagerBrush (Get-ManagerGroupPalette $value).Avatar;$t.Initial.Text=Get-ManagerGroupInitial $value}
    else{$t.Avatar.Visibility='Collapsed'}
}
# 测试连接 = the existing explicit, read-only status check for this saved server (no other network path).
function Start-ManagerDialogTest($Dialog,$Entry) {
    if($script:managerStatusBatch -and -not $script:managerStatusBatch.Completed){Show-ManagerTestResult $Dialog @{State='Busy'};return}
    $changed=$false
    try{
        $saved=Read-PanelAccount $Entry
        $plain=$Dialog.FindName('SecretPlain');$secret=if($Dialog.FindName('SecretReveal').IsChecked){$plain.Text}else{$Dialog.FindName('SecretBox').Password}
        $changed=($Dialog.FindName('UrlBox').Text.Trim() -ne [string]$Entry.Url) -or ($Dialog.FindName('AccountBox').Text -cne [string]$saved.username) -or ($secret -cne [string]$saved.password)
    }catch{$changed=$true}
    finally{$saved=$null;$secret=$null}
    if($changed){Show-ManagerTestResult $Dialog @{State='Unsaved'};return}
    Start-ManagerStatusCheck @($Entry)
    Show-ManagerTestResult $Dialog $script:managerStatus[[string]$Entry.Id]
    if($script:managerDialogTestTimer){$script:managerDialogTestTimer.Stop()}
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(300)
    $timer.Tag=@{Dialog=$Dialog;Id=[string]$Entry.Id}
    $timer.Add_Tick({param($sender,$eventArgs)
        $record=$script:managerStatus[$sender.Tag.Id]
        $running=$script:managerStatusBatch -and -not $script:managerStatusBatch.Completed
        if(-not $record -or $record.State -ne 'Checking' -or -not $running){$sender.Stop();Show-ManagerTestResult $sender.Tag.Dialog $record}
    })
    $script:managerDialogTestTimer=$timer
    $timer.Start()
}
function Show-ManagerTestResult($Dialog,$Record) {
    $box=$Dialog.FindName('TestResult');$text=$Dialog.FindName('TestResultText');$icon=$Dialog.FindName('TestResultIcon')
    if(-not $Record){$box.Visibility='Collapsed';return}
    $look='Neutral';$main='';$extra='';$glyph='IcoPulse';$tip=$null
    switch([string]$Record.State){
        'Busy' {$main='正在检测其他服务器，请稍候'}
        'Unsaved' {$look='Warn';$glyph='IcoWarn';$main='请先保存修改';$extra=' · 测试使用已保存的设置'}
        'Checking' {$main='检测中…'}
        'Cancelled' {$main='已取消检测'}
        'Done' {
            $tip=('SSH 隧道：'+$Record.Tunnel.Text+[Environment]::NewLine+'HTTP：'+$Record.Http.Text+[Environment]::NewLine+'面板登录：'+$Record.Login.Text+[Environment]::NewLine+$Record.CheckedAt.ToString('HH:mm')+' 检测')
            $ms=if($null -ne $Record.LatencyMs){' TCP '+$Record.LatencyMs+'ms'}else{''}
            if(Test-ManagerRecordOffline $Record){$look='Bad';$glyph='IcoWarn';$main='连接失败';$extra=(' · '+$(if($Record.Tunnel.State -eq 'Fail'){$Record.Tunnel.Text}else{$Record.Http.Text}))}
            elseif((Test-ManagerRecordOnline $Record) -and $Record.Login.State -eq 'Ok'){$look='Ok';$glyph='IcoCheck';$main='连接成功';$extra=($ms+' · 登录正常')}
            elseif((Test-ManagerRecordOnline $Record) -and $Record.Login.State -eq 'Fail'){$look='Warn';$glyph='IcoWarn';$main='可达';$extra=($ms+' · '+$Record.Login.Text)}
            elseif(Test-ManagerRecordOnline $Record){$look='Ok';$glyph='IcoCheck';$main='可达';$extra=($ms+' · '+$Record.Login.Text)}
            else{$look='Warn';$glyph='IcoWarn';$main='状态未知';$extra=$(if($Record.Error){' · '+$Record.Error}else{''})}
        }
        default {$box.Visibility='Collapsed';return}
    }
    $palette=switch($look){
        'Ok' {@('SuccessSoftBrush','SuccessLineBrush','SuccessTextBrush','#6E9C7D')}
        'Bad' {@('BadSoftBrush','#F3D8D2','BadTextBrush','#B9786E')}
        'Warn' {@('ExpiringSoftBrush','#F0DCC4','ExpiringBrush','#B98A5C')}
        default {@('SurfaceSoftBrush','LineBrush','MutedBrush','FaintBrush')}
    }
    Set-ManagerBrush $box ([Windows.Controls.Border]::BackgroundProperty) $palette[0]
    Set-ManagerBrush $box ([Windows.Controls.Border]::BorderBrushProperty) $palette[1]
    Set-ManagerBrush $icon ([Windows.Shapes.Shape]::StrokeProperty) $palette[2]
    $icon.SetResourceReference([Windows.Shapes.Path]::DataProperty,$glyph)
    $text.Inlines.Clear()
    $bold=[Windows.Documents.Run]::new($main);$bold.FontWeight=[Windows.FontWeights]::SemiBold
    Set-ManagerBrush $bold ([Windows.Documents.TextElement]::ForegroundProperty) $palette[2]
    $text.Inlines.Add($bold)
    if($extra){$rest=[Windows.Documents.Run]::new($extra);Set-ManagerBrush $rest ([Windows.Documents.TextElement]::ForegroundProperty) $palette[3];$text.Inlines.Add($rest)}
    $box.ToolTip=if($tip){$tip}else{$main+$extra}
    $box.Visibility='Visible'
}
# 到期日: validated yyyy-MM-dd text + calendar popup + quick +1 月 / +1 年 / 清除.
# 客户分组: free text + dropdown of existing groups. 备注: multi-line with a live counter.
function Initialize-ManagerMetadataFields($Dialog,$Entry) {
    [void](Import-ManagerMetadata)
    $store=Get-ManagerMetadataStore
    $meta=Get-ManagerEntryMetadata $Entry
    $expiry=$Dialog.FindName('ExpiryBox');$group=$Dialog.FindName('GroupBox');$note=$Dialog.FindName('NoteBox')
    $expiry.Text=$meta.Expiry;$group.Text=$meta.Group;$note.Text=$meta.Note
    $quotaBox=$Dialog.FindName('TotalTrafficBox');$quotaBox.Text=$meta.TotalTrafficValue
    $units=$Dialog.FindName('TotalTrafficUnit')
    foreach($item in $units.Items){if([string]$item.Content -eq $meta.TotalTrafficUnit){$units.SelectedItem=$item;break}}
    $quotaBox.Tag=$Dialog.FindName('TotalTrafficPlaceholder')
    $quotaBox.Add_TextChanged({param($sender,$eventArgs) $sender.Tag.Visibility=if($sender.Text){'Collapsed'}else{'Visible'}})
    $quotaBox.Tag.Visibility=if($quotaBox.Text){'Collapsed'}else{'Visible'}
    $clearQuota=$Dialog.FindName('TotalTrafficClear');$clearQuota.Tag=$quotaBox
    $clearQuota.Add_Click({param($sender,$eventArgs) $sender.Tag.Clear()})
    $counter=$Dialog.FindName('NoteCounter')
    $note.Tag=@{Counter=$counter}
    $note.Add_TextChanged({param($sender,$eventArgs)
        $length=(([string]$sender.Text) -replace "`r`n","`n").Trim().Length
        $sender.Tag.Counter.Text=([string]$length+' / '+$script:managerNoteMaxLength)
        $sender.Tag.Counter.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($length -gt $script:managerNoteMaxLength){'WarnBrush'}else{'MutedBrush'}))
    })
    $counter.Text=([string]$meta.Note.Length+' / '+$script:managerNoteMaxLength)
    foreach($pair in @(@('ExpiryAddMonth','Month'),@('ExpiryAddYear','Year'),@('ExpiryClear','Clear'))){
        $button=$Dialog.FindName($pair[0]);$button.Tag=@{Box=$expiry;Mode=$pair[1]}
        $button.Add_Click({param($sender,$eventArgs)
            $box=$sender.Tag.Box
            if($sender.Tag.Mode -eq 'Clear'){$box.Text='';return}
            $date=[DateTime]::MinValue
            $base=if([DateTime]::TryParseExact($box.Text.Trim(),'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){$date}else{Get-ManagerToday}
            $box.Text=if($sender.Tag.Mode -eq 'Year'){$base.AddYears(1).ToString('yyyy-MM-dd')}else{$base.AddMonths(1).ToString('yyyy-MM-dd')}
        })
    }
    $popup=$Dialog.FindName('ExpiryPopup');$calendar=$Dialog.FindName('ExpiryCalendar')
    $calendar.Tag=@{Box=$expiry;Popup=$popup}
    $calendar.Add_SelectedDatesChanged({param($sender,$eventArgs)
        if($sender.SelectedDate){$sender.Tag.Box.Text=([DateTime]$sender.SelectedDate).ToString('yyyy-MM-dd');$sender.Tag.Popup.IsOpen=$false}
    })
    $pick=$Dialog.FindName('ExpiryPick');$pick.Tag=@{Box=$expiry;Popup=$popup;Calendar=$calendar}
    $pick.Add_Click({param($sender,$eventArgs)
        $date=[DateTime]::MinValue
        $cal=$sender.Tag.Calendar
        if([DateTime]::TryParseExact($sender.Tag.Box.Text.Trim(),'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){$cal.DisplayDate=$date}else{$cal.DisplayDate=Get-ManagerToday}
        $sender.Tag.Popup.IsOpen=$true
    })
    $groupPick=$Dialog.FindName('GroupPick');$groupPick.Tag=@{Box=$group}
    $groupPick.Add_Click({param($sender,$eventArgs)
        $menu=[Windows.Controls.ContextMenu]::new()
        $existing=@(Get-ManagerMetadataGroups)
        foreach($name in $existing){
            $item=[Windows.Controls.MenuItem]::new();$item.Header=$name;$item.Tag=@{Box=$sender.Tag.Box;Value=$name}
            $item.Add_Click({param($s,$e) $s.Tag.Box.Text=$s.Tag.Value})
            [void]$menu.Items.Add($item)
        }
        if(-not $existing.Count){$item=[Windows.Controls.MenuItem]::new();$item.Header='暂无已有分组，直接输入即可';$item.IsEnabled=$false;[void]$menu.Items.Add($item)}
        [void]$menu.Items.Add([Windows.Controls.Separator]::new())
        $clear=[Windows.Controls.MenuItem]::new();$clear.Header='不分组（清空）';$clear.Tag=@{Box=$sender.Tag.Box;Value=''}
        $clear.Add_Click({param($s,$e) $s.Tag.Box.Text=$s.Tag.Value})
        [void]$menu.Items.Add($clear)
        $menu.PlacementTarget=$sender.Tag.Box;$menu.Placement='Bottom';$menu.IsOpen=$true
    })
    if($store.Error -or $store.ReadOnly){
        foreach($name in 'ExpiryBox','GroupBox','NoteBox','ExpiryAddMonth','ExpiryAddYear','ExpiryClear','ExpiryPick','GroupPick','TotalTrafficBox','TotalTrafficUnit','TotalTrafficClear'){$Dialog.FindName($name).IsEnabled=$false}
        $warning=$Dialog.FindName('MetadataUnavailable')
        $warning.Text=if($store.Error){'服务器元数据文件无法读取，到期日 / 分组 / 备注 / 总流量暂不能修改；其他设置可正常保存。'}else{'服务器元数据文件由更新版本创建，本版本只读显示。'}
        $warning.Visibility='Visible'
    }
}
function Show-PanelSettings($Entry) {
    $dialog=New-ManagerSettingsWindow $Entry;$dialog.Owner=$script:window
    if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended++}
    try{
        if($dialog.ShowDialog()) {
            if($dialog.Tag -and $dialog.Tag.ConnectionChanged){
                $script:managerStatus.Remove([string]$Entry.Id)
                Reset-ManagerAutoRefreshServer ([string]$Entry.Id)
                if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache -Id ([string]$Entry.Id)}
            }
            Build-ManagerRows;Set-ManagerFeedback ('设置已保存 · '+$Entry.Name)
        }
        else{Set-ManagerFeedback '已取消设置。'}
    }finally{
        if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended=[Math]::Max(0,$script:managerAutoRefresh.Suspended-1)}
        if($script:managerDialogTestTimer){$script:managerDialogTestTimer.Stop();$script:managerDialogTestTimer=$null}
        $dialog.FindName('SecretBox').Clear();$plain=$dialog.FindName('SecretPlain');if($plain){$plain.Clear()}
        $dialog.Close()
    }
}
function New-ManagerAddWindow {
    $dialog=Read-ManagerXaml 'AddWindow.xaml';Add-ManagerTheme $dialog
    $placeholder=[pscustomobject]@{Id='';Name='';Address='';Url='';Tunnel=$null}
    Initialize-ManagerMetadataFields $dialog $placeholder
    Initialize-ManagerDialogChrome $dialog $placeholder
    $dialog.FindName('SettingsAddress').Text='填写完整面板地址和账号，保存后即可使用'
    $dialog.FindName('SettingsHelp').Text='账号仅在本机用 Windows DPAPI 加密保存。先添加，再用卡片检测连接；新增面板支持 HTTP / HTTPS。'
    $area=[Windows.SystemParameters]::WorkArea
    if($area.Height -gt 0){$dialog.FindName('SettingsScroll').MaxHeight=[Math]::Max(300,$area.Height-260)}
    $dialog.FindName('SaveSettings').Tag=$dialog
    $dialog.FindName('SaveSettings').Add_Click({param($s,$e)
        $d=$s.Tag
        try{
            $password=if($d.FindName('SecretReveal').IsChecked){$d.FindName('SecretPlain').Text}else{$d.FindName('SecretBox').Password}
            $entry=Add-ManagerServer -Name $d.FindName('NameBox').Text -Url $d.FindName('UrlBox').Text -Username $d.FindName('AccountBox').Text -Password $password `
                -Country $d.FindName('CountryBox').Text -City $d.FindName('CityBox').Text -Expiry $d.FindName('ExpiryBox').Text -Group $d.FindName('GroupBox').Text -Note $d.FindName('NoteBox').Text `
                -TotalTrafficValue $d.FindName('TotalTrafficBox').Text -TotalTrafficUnit ([string]$d.FindName('TotalTrafficUnit').SelectedItem.Content)
            $d.Tag=@{Entry=$entry};$d.DialogResult=$true
        }catch{$d.FindName('SettingsError').Text=$_.Exception.Message}finally{$password=$null}
    })
    return $dialog
}
function Show-ManagerAddServer {
    Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse
    $dialog=New-ManagerAddWindow;$dialog.Owner=$script:window
    if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended++}
    try{
        if($dialog.ShowDialog()){
            Set-ManagerListFilter 'All' $null;$script:window.FindName('SearchBox').Clear()
            Build-ManagerRows;Set-ManagerFeedback ('已添加 · '+$dialog.Tag.Entry.Name+' · 点击检测验证连接')
        }
    }finally{
        if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended=[Math]::Max(0,$script:managerAutoRefresh.Suspended-1)}
        $dialog.FindName('SecretBox').Clear();$dialog.FindName('SecretPlain').Clear();$dialog.Close()
    }
}
function New-ManagerDeleteWindow($Entry) {
    $dialog=Read-ManagerXaml 'DeleteWindow.xaml';Add-ManagerTheme $dialog
    $dialog.FindName('DeleteName').Text=$Entry.Name
    $dialog.FindName('DeleteAddress').Text=$Entry.Address
    $dialog.FindName('DeleteSummary').Text='删除此条管理记录。勾选清理时，专属资料和加密账号会送入 Windows 回收站。其他服务器、共用文件及历史备份保留。'
    $homeCopyPlan=Get-ManagerHomeRemovalPlan -Entry $Entry
    $homeAvailable=$homeCopyPlan.Exists -and $homeCopyPlan.Registered -and $homeCopyPlan.CanRemove
    $dialog.FindName('DeleteHomeCopy').IsEnabled=[bool]$homeAvailable
    $dialog.FindName('DeleteHomeCopy').IsChecked=[bool]$homeAvailable
    $dialog.FindName('DeleteLocalFiles').IsChecked=$true
    $dialog.FindName('ConfirmDelete').Tag=@{Dialog=$dialog;Entry=$Entry}
    $dialog.FindName('ConfirmDelete').Add_Click({param($s,$e)
        $d=$s.Tag.Dialog;$entry=$s.Tag.Entry
        try{
            # Validate both scopes before touching either copy.
            $local=[bool]$d.FindName('DeleteLocalFiles').IsChecked;$homeCopy=[bool]$d.FindName('DeleteHomeCopy').IsChecked
            [void](Get-ManagerServerRemovalPlan -Entry $entry -DeleteLocalFiles:$local)
            if($homeCopy){$homePlan=Get-ManagerHomeRemovalPlan -Entry $entry;if(-not $homePlan.CanRemove){throw $homePlan.BlockedReason}}
            if($script:managerStatusBatch -and -not $script:managerStatusBatch.Completed){Stop-ManagerStatusCheck}
            $homeResult=$null
            if($homeCopy){$homeResult=Remove-ManagerHomeServer -Entry $entry -DeleteLocalFiles:$local}
            try{$result=Remove-ManagerServer -Entry $entry -DeleteLocalFiles:$local}
            catch{if($homeResult -and $homeResult.UndoState){Restore-ManagerHomeRemoval $homeResult.UndoState};throw}
            $script:managerStatus.Remove([string]$entry.Id)
            Reset-ManagerAutoRefreshServer ([string]$entry.Id)
            if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache -Id ([string]$entry.Id)}
            $script:managerDeleteUndo=if(-not $homeCopy){$result.UndoToken}else{$null}
            $d.Tag=@{Name=$entry.Name;Recycled=$result.LocalFilesRecycled;Reason=$d.FindName('DeleteReason').Text}
            $d.DialogResult=$true
        }catch{$d.FindName('DeleteError').Text=$_.Exception.Message}
    })
    foreach($name in 'DialogClose','CancelDelete'){$b=$dialog.FindName($name);$b.Tag=$dialog;$b.Add_Click({param($s,$e) $s.Tag.DialogResult=$false})}
    $dialog.FindName('DialogHeader').Tag=$dialog
    $dialog.FindName('DialogHeader').Add_MouseLeftButtonDown({param($s,$e) if($e.ButtonState -eq 'Pressed'){try{$s.Tag.DragMove()}catch{}}})
    return $dialog
}
function Show-ManagerDeleteServer($Entry) {
    Close-ManagerCardMenu;Reset-ManagerCredentials -Collapse
    $dialog=New-ManagerDeleteWindow $Entry;$dialog.Owner=$script:window
    if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended++}
    try{
        if($dialog.ShowDialog()){
            Build-ManagerRows
            $undo=$script:window.FindName('UndoDeleteButton');if($undo){$undo.Visibility=if($script:managerDeleteUndo){'Visible'}else{'Collapsed'}}
            Set-ManagerFeedback ('已删除 · '+$dialog.Tag.Name+$(if($dialog.Tag.Recycled){' · 专属资料已送入回收站'}else{' · 本地资料保留'}))
        }
    }finally{
        if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended=[Math]::Max(0,$script:managerAutoRefresh.Suspended-1)}
        $dialog.Close()
    }
}
function Undo-ManagerDeleteServer {
    if(-not $script:managerDeleteUndo){return}
    try{
        [void](Undo-ManagerServerRemoval -Token $script:managerDeleteUndo);$script:managerDeleteUndo=$null
        Build-ManagerRows;$script:window.FindName('UndoDeleteButton').Visibility='Collapsed'
        Set-ManagerFeedback '已撤销最近一次管理记录删除。'
    }catch{Show-ManagerMessage $_.Exception.Message '撤销未完成'}
}
function New-ManagerTransferWindow([bool]$Confirm) {
    $dialog=Read-ManagerXaml 'TransferWindow.xaml';Add-ManagerTheme $dialog
    $dialog.FindName('TransferTitle').Text=if($Confirm){'带到另一台电脑。'}else{'把账号导入这里。'}
    $dialog.FindName('TransferHelp').Text=if($Confirm){'设置至少 10 个字符的迁移密码。请记住它，在另一台电脑导入时需要。'}else{'输入导出时设置的迁移密码。导入后，账号会在这台电脑重新加密保存。'}
    if(-not $Confirm){$dialog.FindName('ConfirmGroup').Visibility='Collapsed';$dialog.Height=350}
    $dialog.FindName('ConfirmTransfer').Tag=@{Dialog=$dialog;Confirm=$Confirm}
    $dialog.FindName('ConfirmTransfer').Add_Click({param($sender,$args)
        $d=$sender.Tag.Dialog;$password=$d.FindName('TransferPassword').Password
        if(-not $password){$d.FindName('TransferError').Text='请输入迁移密码。';return}
        if($sender.Tag.Confirm -and ($password.Length -lt 10 -or $password -cne $d.FindName('ConfirmPassword').Password)){
            $d.FindName('TransferError').Text='密码至少 10 个字符，两次填写需一致。';return
        }
        $d.DialogResult=$true
    })
    return $dialog
}
# WPF adapters override only the legacy module's three UI entry points.
function Get-TransferPassword([bool]$Confirm) {
    $dialog=New-ManagerTransferWindow $Confirm;$dialog.Owner=$script:window
    try{if($dialog.ShowDialog()){return $dialog.FindName('TransferPassword').Password};return $null}
    finally{$dialog.FindName('TransferPassword').Clear();$dialog.FindName('ConfirmPassword').Clear();$dialog.Close()}
}
function Select-ManagerTransferFile {
    param([ValidateSet('Export','Import')][string]$Mode)
    $dialog=if($Mode -eq 'Export'){[Microsoft.Win32.SaveFileDialog]::new()}else{[Microsoft.Win32.OpenFileDialog]::new()}
    $dialog.Filter='加密账号文件 (*.vpsaccounts)|*.vpsaccounts'
    if($Mode -eq 'Export'){$dialog.FileName='面板账号-加密迁移.vpsaccounts'}
    if($dialog.ShowDialog($script:window)){return $dialog.FileName}
    return $null
}
function Export-PanelAccounts {
    try{
        $accounts=@(Get-PanelTransferAccounts)
        if(-not $accounts.Count){throw '目前没有可导出的面板账号。'}
        $password=Get-TransferPassword $true
        if(-not $password){Set-ManagerFeedback '已取消导出。';return}
        $path=Select-ManagerTransferFile -Mode Export
        if(-not $path){Set-ManagerFeedback '已取消导出。';return}
        $payload=@{Version=1;Accounts=$accounts} | ConvertTo-Json -Depth 12 -Compress
        Write-AtomicText $path (Protect-TransferText $payload $password) ([Text.UTF8Encoding]::new($false))
        Set-ManagerFeedback ('已加密导出 '+$accounts.Count+' 台服务器账号。')
        Show-ManagerMessage '加密导出完成。把文件带到另一台电脑，在管理窗口点击「导入跨电脑账号」。文件包含面板账号、自定义名称和专用面板隧道密钥，请妥善保管文件与迁移密码。' '导出完成'
    }catch{Set-ManagerFeedback '导出未完成。';Show-ManagerMessage $_.Exception.Message '导出失败'}
    finally{$accounts=$null;$password=$null;$payload=$null}
}
function Import-PanelAccounts {
    if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended++}
    try{
        $path=Select-ManagerTransferFile -Mode Import
        if(-not $path){Set-ManagerFeedback '已取消导入。';return}
        $password=Get-TransferPassword $false
        if(-not $password){Set-ManagerFeedback '已取消导入。';return}
        if((Get-Item -LiteralPath $path).Length -gt 1048576){throw '迁移文件过大。'}
        $payload=Unprotect-TransferText ([IO.File]::ReadAllText($path)) $password | ConvertFrom-Json
        if($payload.Version -ne 1){throw '不支持的账号内容。'}
        $planned=@(New-PanelImportPlan $payload.Accounts)
        Save-PanelImportPlan $planned
        Reset-ManagerAutoRefreshServer
        if(Get-Command Reset-ManagerProbeSessionCache -ErrorAction SilentlyContinue){Reset-ManagerProbeSessionCache}
        $script:managerStatus.Clear()
        Build-ManagerRows
        Set-ManagerFeedback ('已导入 '+$planned.Count+' 台面板账号，并在本机重新加密保存。')
        Show-ManagerMessage ('已导入 '+$planned.Count+' 台面板账号，并在这台电脑重新加密保存。') '导入完成'
    }catch{Set-ManagerFeedback '导入未完成。';Show-ManagerMessage $_.Exception.Message '导入失败'}
    finally{if($script:managerAutoRefresh){$script:managerAutoRefresh.Suspended=[Math]::Max(0,$script:managerAutoRefresh.Suspended-1)};$password=$null;$payload=$null;$planned=$null}
}
function Export-ManagerPreview($Target,[string]$Path) {
    $Target.Show()
    $Target.UpdateLayout()
    $Target.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Render)
    $visual=$Target.Content
    $margin=$visual.Margin
    $width=[int][Math]::Ceiling($visual.ActualWidth+$margin.Left+$margin.Right)
    $height=[int][Math]::Ceiling($visual.ActualHeight+$margin.Top+$margin.Bottom)
    $drawing=[Windows.Media.DrawingVisual]::new()
    $context=$drawing.RenderOpen()
    try{
        $context.DrawRectangle($Target.Background,$null,[Windows.Rect]::new(0,0,$width,$height))
        $brush=[Windows.Media.VisualBrush]::new($visual)
        $brush.ViewboxUnits=[Windows.Media.BrushMappingMode]::Absolute
        $brush.Viewbox=[Windows.Rect]::new(0,0,$visual.ActualWidth,$visual.ActualHeight)
        $context.DrawRectangle($brush,$null,[Windows.Rect]::new($margin.Left,$margin.Top,$visual.ActualWidth,$visual.ActualHeight))
    }finally{$context.Close()}
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($drawing)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)))
    $stream=[IO.File]::Create($Path)
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
}
