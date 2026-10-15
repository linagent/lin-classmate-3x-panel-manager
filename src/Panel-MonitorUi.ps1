# Resource and purchasing UI integration. All purchasing writes use the independent local store.
. (Join-Path $PSScriptRoot 'Panel-ResourceUi.ps1')

function Initialize-ManagerMonitorUi {
    if($null -eq $script:managerResourceCache){$script:managerResourceCache=@{}}
    if($null -eq $script:managerResourceHistory){$script:managerResourceHistory=@{}}
    if(-not $script:managerSidebarView){$script:managerSidebarView='Customers'}
    [void](Import-ManagerPurchases)
    $w=$script:window
    $w.FindName('DrawerBackdrop').Add_Click({Close-ManagerDrawer})
    $w.FindName('CustomerViewButton').Add_Click({$script:managerSidebarView='Customers';Update-ManagerPurchaseSidebar;Set-ManagerListFilter 'All' $null})
    $w.FindName('ProviderViewButton').Add_Click({$script:managerSidebarView='Providers';Update-ManagerPurchaseSidebar;Set-ManagerListFilter 'All' $null})
    $w.FindName('ManagePurchasesButton').Add_Click({Show-ManagerPurchaseManageWindow})
    $w.FindName('CompactPurchaseFilter').Add_Click({param($sender,$eventArgs) Show-ManagerCompactPurchaseFilter $sender})
    $w.FindName('ResourceAttentionButton').Add_Click({Close-ManagerDrawer;Set-ManagerListFilter 'Resources' $null})
    # Local presentation clock only: mark old samples stale even while manual refresh is selected.
    if($script:managerResourceDisplayTimer){$script:managerResourceDisplayTimer.Stop()}
    $timer=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
    $timer.Interval=[TimeSpan]::FromSeconds(30)
    $timer.Add_Tick({
        foreach($row in @($script:cards)){Update-ManagerCardResources -Row $row}
        Update-ManagerResourceSummary;Update-ManagerResourceDrawer
        if($script:managerListFilter.Kind -eq 'Resources'){Update-ManagerFilter}
    })
    $script:managerResourceDisplayTimer=$timer
    $w.Add_Loaded({if($script:managerAutoRefreshEnabled -and $script:managerResourceDisplayTimer){$script:managerResourceDisplayTimer.Start()}})
    $w.Add_Closed({if($script:managerResourceDisplayTimer){$script:managerResourceDisplayTimer.Stop();$script:managerResourceDisplayTimer=$null}})
}
function Set-ManagerDrawer {
    param($View,$Entry,[string]$Mode)
    Close-ManagerCardMenu
    Reset-ManagerCredentials
    $w=$script:window
    if(-not $script:managerDrawer){$script:managerDrawerFocus=[Windows.Input.Keyboard]::FocusedElement}
    $script:managerDrawer=@{View=$View;Entry=$Entry;Mode=$Mode;RangeMinutes=30}
    $w.FindName('DrawerContent').Content=$View
    $w.FindName('DrawerFrame').Width=[Math]::Min(480,[Math]::Max(360,$w.ActualWidth-24))
    $w.FindName('MonitorOverlay').Visibility='Visible'
    $w.FindName('ManagerBody').IsEnabled=$false
    $w.FindName('DrawerBackdrop').IsEnabled=$true
    [void]$View.FindName('CloseDrawer').Focus()
}
function Close-ManagerDrawer {
    if(-not $script:window){return}
    $script:window.FindName('MonitorOverlay').Visibility='Collapsed'
    $script:window.FindName('DrawerContent').Content=$null
    $script:window.FindName('ManagerBody').IsEnabled=$true
    $script:managerDrawer=$null
    if($script:managerDrawerFocus){try{[void]$script:managerDrawerFocus.Focus()}catch{};$script:managerDrawerFocus=$null}
}
function Get-ManagerPurchaseRows([string]$Kind,[string]$Id) {
    foreach($row in @($script:cards)){
        $source=Get-ManagerEntryPurchase -Entry $row.Entry
        if($source -and (($Kind -eq 'Provider' -and $source.ProviderId -eq $Id) -or ($Kind -eq 'PurchaseAccount' -and $source.AccountId -eq $Id))){$row}
    }
}
function Update-ManagerPurchaseSidebar {
    $w=$script:window;if(-not $w){return}
    $providers=$script:managerSidebarView -eq 'Providers'
    $w.FindName('SidebarCaption').Text=if($providers){'购买来源'}else{'客户分组'}
    $w.FindName('SidebarGroups').Visibility=if($providers){'Collapsed'}else{'Visible'}
    $w.FindName('SidebarPurchases').Visibility=if($providers){'Visible'}else{'Collapsed'}
    $w.FindName('SidebarGroupHint').Visibility=if($providers -or @(Get-ManagerMetadataGroups).Count){'Collapsed'}else{'Visible'}
    foreach($name in 'CustomerViewButton','ProviderViewButton'){
        $selected=($providers -and $name -eq 'ProviderViewButton') -or (-not $providers -and $name -eq 'CustomerViewButton')
        $w.FindName($name).SetResourceReference([Windows.Controls.Control]::BackgroundProperty,$(if($selected){'SidebarSelectedBrush'}else{'SurfaceBrush'}))
    }
    $panel=$w.FindName('SidebarPurchases');$panel.Children.Clear()
    $script:managerPurchaseSidebarButtons=@()
    foreach($provider in @(Get-ManagerPurchaseProviders)){
        $count=@(Get-ManagerPurchaseRows 'Provider' $provider.Id).Count
        $button=New-ManagerSidebarItem 'Provider' $provider.Id $provider.Name $count 'InfoBrush'
        # Replace the ungrouped placeholder with the provider's initial.
        $button.Content.Children[0].Children[1].Text=$provider.Name.Substring(0,1)
        [void]$panel.Children.Add($button);$script:managerPurchaseSidebarButtons+=,$button
        foreach($account in @(Get-ManagerPurchaseAccounts -ProviderId $provider.Id)){
            $count=@(Get-ManagerPurchaseRows 'PurchaseAccount' $account.Id).Count
            $button=New-ManagerSidebarItem 'PurchaseAccount' $account.Id $account.Alias $count 'InfoBrush'
            $button.Margin=[Windows.Thickness]::new(16,0,0,0)
            $button.Content.Children[0].Children[1].Text='账'
            [void]$panel.Children.Add($button);$script:managerPurchaseSidebarButtons+=,$button
        }
    }
    $unassigned=@($script:cards | Where-Object {-not (Get-ManagerEntryPurchase -Entry $_.Entry)}).Count
    $button=New-ManagerSidebarItem 'UnassignedPurchase' $null '未设置来源' $unassigned 'FaintBrush'
    [void]$panel.Children.Add($button);$script:managerPurchaseSidebarButtons+=,$button
    foreach($b in $script:managerPurchaseSidebarButtons){
        $selected=$script:managerListFilter.Kind -eq $b.Tag.Kind -and [string]$script:managerListFilter.Value -eq [string]$b.Tag.Value
        $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,$(if($selected){'SidebarSelectedBrush'}else{'SurfaceBrush'}))
        $b.Tag.LabelBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($selected){'AccentHoverBrush'}else{'InkBrush'}))
    }
}
function Show-ManagerCompactPurchaseFilter($Button) {
    Close-ManagerCardMenu
    $menu=[Windows.Controls.ContextMenu]::new();$menu.StaysOpen=$false;Add-ManagerTheme $menu
    foreach($provider in @(Get-ManagerPurchaseProviders)){
        $item=[Windows.Controls.MenuItem]::new();$item.Header=$provider.Name;$item.Tag=@{Kind='Provider';Id=$provider.Id}
        $item.Add_Click({param($sender,$eventArgs) if($eventArgs.OriginalSource -eq $sender){Set-ManagerListFilter $sender.Tag.Kind $sender.Tag.Id;$eventArgs.Handled=$true}})
        $all=[Windows.Controls.MenuItem]::new();$all.Header='此服务商全部服务器';$all.Tag=$provider.Id
        $all.Add_Click({param($sender,$eventArgs) $eventArgs.Handled=$true;Set-ManagerListFilter 'Provider' $sender.Tag});[void]$item.Items.Add($all)
        foreach($account in @(Get-ManagerPurchaseAccounts -ProviderId $provider.Id)){
            $child=[Windows.Controls.MenuItem]::new();$child.Header=$account.Alias;$child.Tag=$account.Id
            $child.Add_Click({param($sender,$eventArgs) $eventArgs.Handled=$true;Set-ManagerListFilter 'PurchaseAccount' $sender.Tag})
            [void]$item.Items.Add($child)
        }
        [void]$menu.Items.Add($item)
    }
    $item=[Windows.Controls.MenuItem]::new();$item.Header='未设置购买来源';$item.Add_Click({Set-ManagerListFilter 'UnassignedPurchase' $null});[void]$menu.Items.Add($item)
    $item=[Windows.Controls.MenuItem]::new();$item.Header='管理服务商与账号';$item.Add_Click({Show-ManagerPurchaseManageWindow});[void]$menu.Items.Add($item)
    $menu.PlacementTarget=$Button;$menu.Placement='Bottom';$script:managerCardMenu=$menu;$menu.IsOpen=$true
}
function Update-ManagerCardPurchase($Row) {
    $card=$Row.Control;$source=Get-ManagerEntryPurchase -Entry $Row.Entry
    $card.FindName('ProviderName').Text=if($source){$source.ProviderName}else{'未设置 · 点击设置'}
    $card.FindName('ProviderName').ToolTip=if($source){$source.ProviderName}else{'设置服务商与购买账号'}
    $card.FindName('PurchaseSeparator').Visibility=if($source){'Visible'}else{'Collapsed'}
    $card.FindName('PurchaseAlias').Text=if($source){if($card.FindName('ShowPurchaseAccount').IsChecked){$source.AccountAlias}else{'••••••'}}else{'—'}
    $card.FindName('ShowPurchaseAccount').IsEnabled=[bool]$source
    $card.FindName('ShowPurchaseAccount').Visibility=if($source){'Visible'}else{'Collapsed'}
}
function Initialize-ManagerCardMonitoring($Row) {
    $card=$Row.Control
    $card.FindName('ResourceOverview').Tag=$Row.Entry
    $card.FindName('ResourceOverview').Add_Click({param($sender,$eventArgs) Open-ManagerResourceDrawer -Entry $sender.Tag})
    $card.FindName('PurchaseSourceButton').Tag=$Row.Entry
    $card.FindName('PurchaseSourceButton').Add_Click({param($sender,$eventArgs) Open-ManagerPurchaseDrawer -Entry $sender.Tag})
    $eye=$card.FindName('ShowPurchaseAccount');$eye.Tag=$Row
    $eye.Add_Checked({param($sender,$eventArgs) Update-ManagerCardPurchase $sender.Tag})
    $eye.Add_Unchecked({param($sender,$eventArgs) Update-ManagerCardPurchase $sender.Tag})
    Update-ManagerCardPurchase $Row
    Update-ManagerCardResources -Row $Row
}
function Update-ManagerPurchasesUi {
    foreach($row in @($script:cards)){Update-ManagerCardPurchase $row}
    Update-ManagerPurchaseSidebar
    if($script:managerListFilter.Kind -in @('Provider','PurchaseAccount')){
        $exists=if($script:managerListFilter.Kind -eq 'Provider'){@(Get-ManagerPurchaseProviders | Where-Object {$_.Id -eq $script:managerListFilter.Value}).Count}else{@(Get-ManagerPurchaseAccounts | Where-Object {$_.Id -eq $script:managerListFilter.Value}).Count}
        if(-not $exists){$script:managerListFilter=@{Kind='All';Value=$null}}
    }
    Update-ManagerFilter
}
function Set-ManagerPurchaseUiError {
    param($View,[ValidateSet('PurchaseError','PurchaseManageError')][string]$Target='PurchaseError')
    $message='购买来源操作未完成，请关闭此面板后重试。'
    if($View){
        $errorBox=$View.FindName($Target)
        if($errorBox){
            $errorBox.Text=$message
            if($Target -eq 'PurchaseError'){
                $View.FindName('PurchaseDetails').Visibility='Collapsed'
                $View.FindName('PurchaseEditor').Visibility='Visible'
                $View.FindName('SavePurchaseSource').IsEnabled=$false
            }
            return
        }
    }
    Set-ManagerFeedback $message
}
function Open-ManagerPurchaseDrawer {
    param($Entry)
    $view=$null
    try{
    [void](Import-ManagerPurchases)
    $view=Read-ManagerXaml 'PurchaseWindow.xaml'
    $view.Tag=@{Entry=$Entry;View=$view;Editing=$false;Updating=$false}
    Set-ManagerDrawer -View $view -Entry $Entry -Mode 'Purchases'
    foreach($name in 'CloseDrawer','EditPurchaseSource','CancelPurchaseEdit','SavePurchaseSource','ClearPurchaseSource','FilterPurchaseAccount','ManageSourceAccounts'){$view.FindName($name).Tag=$view.Tag}
    $view.FindName('CloseDrawer').Add_Click({Close-ManagerDrawer})
    $view.FindName('EditPurchaseSource').Add_Click({param($sender,$eventArgs) try{Start-ManagerPurchaseEditor $sender.Tag}catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}})
    $view.FindName('CancelPurchaseEdit').Add_Click({param($sender,$eventArgs) try{Update-ManagerPurchaseDetails $sender.Tag}catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}})
    $view.FindName('SavePurchaseSource').Add_Click({param($sender,$eventArgs) try{Save-ManagerPurchaseEditor $sender.Tag}catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}})
    $view.FindName('ClearPurchaseSource').Add_Click({param($sender,$eventArgs) try{Save-ManagerPurchaseEditor $sender.Tag -Clear}catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}})
    $view.FindName('FilterPurchaseAccount').Add_Click({param($sender,$eventArgs)
        try{
        $source=Get-ManagerEntryPurchase -Entry $sender.Tag.Entry
        if($source){Close-ManagerDrawer;Set-ManagerListFilter 'PurchaseAccount' $source.AccountId}
        }catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}
    })
    $view.FindName('ManageSourceAccounts').Add_Click({Show-ManagerPurchaseManageWindow})
    $provider=$view.FindName('ProviderBox');$provider.Tag=$view.Tag
    $provider.Add_SelectionChanged({param($sender,$eventArgs) try{Update-ManagerPurchaseEditorAccounts $sender.Tag}catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}})
    $account=$view.FindName('PurchaseAccountBox');$account.Tag=$view.Tag
    $account.Add_SelectionChanged({param($sender,$eventArgs)
        try{
        if(-not $sender.Tag.Updating){
            $hint=$sender.Tag.View.FindName('PurchaseHintBox');$hint.IsReadOnly=[bool]$sender.SelectedItem
            $hint.ToolTip=if($sender.SelectedItem){'已有账号的提示可在“管理服务商与购买账号”统一修改。'}else{'新账号提示，可选'}
            $hint.Text=if($sender.SelectedItem){[string]$sender.SelectedItem.Hint}else{''}
        }
        }catch{Set-ManagerPurchaseUiError -View $sender.Tag.View}
    })
    Update-ManagerPurchaseDetails $view.Tag
    }catch{Set-ManagerPurchaseUiError -View $view}
}
function Update-ManagerPurchaseDetails($Context) {
    $view=$Context.View;$Context.Editing=$false
    $source=Get-ManagerEntryPurchase -Entry $Context.Entry
    $view.FindName('PurchaseDetails').Visibility='Visible';$view.FindName('PurchaseEditor').Visibility='Collapsed'
    $view.FindName('SourceServerName').Text=$Context.Entry.Name
    $view.FindName('SourceName').Text=if($source){$source.ProviderName}else{'未设置服务商'}
    $view.FindName('SourceAlias').Text=if($source){$source.AccountAlias}else{'未设置购买账号'}
    $view.FindName('SourceHint').Text=if($source -and $source.Hint){'账号提示 · '+$source.Hint}else{'购买账号只保存别名与提示，不保存服务商密码。'}
    $rows=@(if($source){Get-ManagerPurchaseRows 'PurchaseAccount' $source.AccountId})
    $view.FindName('SourceCount').Text='此购买账号 · '+$rows.Count+' 台服务器'
    $meta=Get-ManagerEntryMetadata $Context.Entry
    $view.FindName('SourceCustomer').Text='客户归属 · '+$(if($meta.Group){$meta.Group}else{'未分组'})
    $view.FindName('FilterPurchaseAccount').IsEnabled=[bool]$source
    $panel=$view.FindName('SourceServers');$panel.Children.Clear()
    foreach($row in $rows){
        $button=[Windows.Controls.Button]::new();$button.Content=$row.Entry.Name;$button.Tag=$row.Entry
        $button.SetResourceReference([Windows.FrameworkElement]::StyleProperty,'MiniLinkButton');$button.HorizontalContentAlignment='Left'
        $button.Margin=[Windows.Thickness]::new(0,3,0,0)
        $button.Add_Click({param($sender,$eventArgs) Open-ManagerResourceDrawer -Entry $sender.Tag})
        [void]$panel.Children.Add($button)
    }
}
function Update-ManagerPurchaseEditorAccounts($Context) {
    if($Context.Updating){return}
    $view=$Context.View;$provider=$view.FindName('ProviderBox');$box=$view.FindName('PurchaseAccountBox')
    $Context.Updating=$true
    try{
        $box.ItemsSource=$null;$box.Text=''
        # Wrap the whole conditional: its branch output otherwise unwraps a single account.
        # SelectedItem already reflects SelectionChanged; SelectedValue may still be the old value.
        $selectedProviderId=if($provider.SelectedItem){[string]$provider.SelectedItem.Id}else{''}
        $accountItems=@(if($selectedProviderId){Get-ManagerPurchaseAccounts -ProviderId $selectedProviderId})
        $box.ItemsSource=$accountItems
        $view.FindName('PurchaseHintBox').Text='';$view.FindName('PurchaseHintBox').IsReadOnly=$false;$view.FindName('PurchaseHintBox').ToolTip='新账号提示，可选'
    }catch{Set-ManagerPurchaseUiError -View $view}finally{$Context.Updating=$false}
}
function Start-ManagerPurchaseEditor($Context) {
    $view=$Context.View;$Context.Editing=$true;$Context.Updating=$true
    try{
        [void](Import-ManagerPurchases)
        $source=Get-ManagerEntryPurchase -Entry $Context.Entry
        $provider=$view.FindName('ProviderBox');$provider.ItemsSource=@(Get-ManagerPurchaseProviders);$provider.SelectedIndex=-1;$provider.Text=''
        if($source){$provider.SelectedValue=$source.ProviderId}
        $box=$view.FindName('PurchaseAccountBox')
        $accountItems=@(if($provider.SelectedValue){Get-ManagerPurchaseAccounts -ProviderId ([string]$provider.SelectedValue)})
        $box.ItemsSource=$accountItems;$box.SelectedIndex=-1;$box.Text=''
        if($source){$box.SelectedValue=$source.AccountId}
        $view.FindName('PurchaseHintBox').Text=if($source){$source.Hint}else{''}
        $view.FindName('PurchaseHintBox').IsReadOnly=[bool]$source
        $view.FindName('PurchaseHintBox').ToolTip=if($source){'已有账号的提示可在“管理服务商与购买账号”统一修改。'}else{'新账号提示，可选'}
        $store=Get-ManagerPurchasesStore;$Context.Fingerprint=$store.Fingerprint;$view.FindName('PurchaseError').Text=if($store.Error){$store.Error}elseif($store.ReadOnly){'购买来源由较新版本创建，当前只读。'}else{''}
        $view.FindName('SavePurchaseSource').IsEnabled=-not $store.ReadOnly
        $view.FindName('ClearPurchaseSource').IsEnabled=-not $store.ReadOnly -and [bool]$source
        $view.FindName('PurchaseDetails').Visibility='Collapsed';$view.FindName('PurchaseEditor').Visibility='Visible'
        [void]$view.FindName('ProviderBox').Focus()
    }catch{
        Set-ManagerPurchaseUiError -View $view
    }finally{$Context.Updating=$false}
}
function Save-ManagerPurchaseEditor {
    param($Context,[switch]$Clear)
    $view=$Context.View
    try{
        Assert-ManagerPurchaseEditVersion $Context.Fingerprint
        if($Clear){[void](Set-ManagerEntryPurchase -Entry $Context.Entry -AccountId '')}
        else{
            $provider=$view.FindName('ProviderBox');$account=$view.FindName('PurchaseAccountBox')
            $providerText=$provider.Text.Trim();$accountText=$account.Text.Trim()
            if(-not $providerText -or -not $accountText){throw '请填写服务商名称和购买账号别名。'}
            $providerId=if($provider.SelectedItem -and $provider.SelectedItem.Name -eq $providerText){[string]$provider.SelectedValue}else{''}
            $accountId=if($providerId -and $account.SelectedItem -and $account.SelectedItem.ProviderId -eq $providerId -and $account.SelectedItem.Alias -eq $accountText){[string]$account.SelectedValue}else{''}
            [void](Save-ManagerPurchaseAssignment -Entry $Context.Entry -ProviderId $providerId -ProviderName $providerText -AccountId $accountId -AccountAlias $accountText -Hint $view.FindName('PurchaseHintBox').Text)
        }
        Update-ManagerPurchasesUi;Update-ManagerPurchaseDetails $Context
        Set-ManagerFeedback '购买来源已保存到本地。'
    }catch{$view.FindName('PurchaseError').Text=$_.Exception.Message}
}
function Assert-ManagerPurchaseEditVersion([string]$Fingerprint) {
    $store=Get-ManagerPurchasesStore
    if($store.Fingerprint -cne $Fingerprint -or (Get-ManagerPurchasesFileFingerprint $store.Path) -cne $Fingerprint){throw '购买来源已被其他窗口或程序修改，本次未覆盖。请取消后重新编辑。'}
}
function Update-ManagerPurchaseManageLists($Dialog,[string]$ProviderId,[string]$AccountId) {
    $Dialog.Tag.Updating=$true
    try{
        $p=$Dialog.FindName('ProviderList');$p.ItemsSource=$null;$p.ItemsSource=@(Get-ManagerPurchaseProviders)
        if($ProviderId){$p.SelectedValue=$ProviderId}else{$p.SelectedIndex=-1}
        $a=$Dialog.FindName('AccountList');$a.ItemsSource=$null
        $accountItems=@(if($ProviderId){Get-ManagerPurchaseAccounts -ProviderId $ProviderId})
        $a.ItemsSource=$accountItems
        if($AccountId){$a.SelectedValue=$AccountId}else{$a.SelectedIndex=-1}
        $Dialog.FindName('ProviderNameBox').Text=if($p.SelectedItem){$p.SelectedItem.Name}else{''}
        $Dialog.FindName('AccountAliasBox').Text=if($a.SelectedItem){$a.SelectedItem.Alias}else{''}
        $Dialog.FindName('AccountHintBox').Text=if($a.SelectedItem){$a.SelectedItem.Hint}else{''}
    }catch{Set-ManagerPurchaseUiError -View $Dialog -Target 'PurchaseManageError'}finally{$Dialog.Tag.Updating=$false}
}
function Invoke-ManagerPurchaseManageAction($Dialog,[string]$Action) {
    if($Dialog.Tag.Updating){return}
    $p=$Dialog.FindName('ProviderList');$a=$Dialog.FindName('AccountList');$purchaseProviderId=[string]$p.SelectedValue;$aid=[string]$a.SelectedValue
    $Dialog.FindName('PurchaseManageError').Text=''
    try{
        if($Action -notin @('NewProvider','NewPurchaseAccount')){Assert-ManagerPurchaseEditVersion $Dialog.Tag.Fingerprint}
        switch($Action){
            'NewProvider' {Update-ManagerPurchaseManageLists $Dialog '' '';[void]$Dialog.FindName('ProviderNameBox').Focus();return}
            'NewPurchaseAccount' {$a.SelectedIndex=-1;$Dialog.FindName('AccountAliasBox').Text='';$Dialog.FindName('AccountHintBox').Text='';[void]$Dialog.FindName('AccountAliasBox').Focus();return}
            'SaveProvider' {$saved=Save-ManagerPurchaseProvider -Id $purchaseProviderId -Name $Dialog.FindName('ProviderNameBox').Text;$purchaseProviderId=$saved.Id}
            'SavePurchaseAccount' {if(-not $purchaseProviderId){throw '请先选择或保存服务商。'};$saved=Save-ManagerPurchaseAccount -Id $aid -ProviderId $purchaseProviderId -Alias $Dialog.FindName('AccountAliasBox').Text -Hint $Dialog.FindName('AccountHintBox').Text;$aid=$saved.Id}
            'DeleteProvider' {if(-not $purchaseProviderId){throw '请选择服务商。'};Remove-ManagerPurchaseProvider -Id $purchaseProviderId;$purchaseProviderId='';$aid=''}
            'DeletePurchaseAccount' {if(-not $aid){throw '请选择购买账号。'};[void](Remove-ManagerPurchaseAccount -Id $aid -ActiveServerIds @($script:entries | ForEach-Object {[string]$_.Id}));$aid=''}
        }
        $Dialog.Tag.Fingerprint=(Get-ManagerPurchasesStore).Fingerprint
        Update-ManagerPurchaseManageLists $Dialog $purchaseProviderId $aid;Update-ManagerPurchasesUi
        if($script:managerDrawer -and $script:managerDrawer.Mode -eq 'Purchases' -and -not $script:managerDrawer.View.Tag.Editing){Update-ManagerPurchaseDetails $script:managerDrawer.View.Tag}
    }catch{$Dialog.FindName('PurchaseManageError').Text=$_.Exception.Message}
}
function New-ManagerPurchaseManageWindow {
    [void](Import-ManagerPurchases)
    $dialog=Read-ManagerXaml 'PurchaseManageWindow.xaml';Add-ManagerTheme $dialog
    $dialog.Owner=$script:window;$dialog.Tag=@{Updating=$false;Fingerprint=(Get-ManagerPurchasesStore).Fingerprint}
    foreach($name in 'NewProvider','SaveProvider','DeleteProvider','NewPurchaseAccount','SavePurchaseAccount','DeletePurchaseAccount'){
        $button=$dialog.FindName($name);$button.Tag=@{Dialog=$dialog;Action=$name}
        $button.Add_Click({param($sender,$eventArgs) try{Invoke-ManagerPurchaseManageAction $sender.Tag.Dialog $sender.Tag.Action}catch{Set-ManagerPurchaseUiError -View $sender.Tag.Dialog -Target 'PurchaseManageError'}})
    }
    $p=$dialog.FindName('ProviderList');$p.Tag=$dialog
    $p.Add_SelectionChanged({param($sender,$eventArgs)
        $d=$sender.Tag;if($d.Tag.Updating){return}
        $d.Tag.Updating=$true
        try{
        $d.FindName('ProviderNameBox').Text=if($sender.SelectedItem){$sender.SelectedItem.Name}else{''}
        $a=$d.FindName('AccountList')
        $selectedProviderId=if($sender.SelectedItem){[string]$sender.SelectedItem.Id}else{''}
        $accountItems=@(if($selectedProviderId){Get-ManagerPurchaseAccounts -ProviderId $selectedProviderId})
        $a.ItemsSource=$accountItems
        $a.SelectedIndex=-1;$d.FindName('AccountAliasBox').Text='';$d.FindName('AccountHintBox').Text=''
        }catch{Set-ManagerPurchaseUiError -View $d -Target 'PurchaseManageError'}finally{$d.Tag.Updating=$false}
    })
    $a=$dialog.FindName('AccountList');$a.Tag=$dialog
    $a.Add_SelectionChanged({param($sender,$eventArgs)
        $d=$sender.Tag;if($d.Tag.Updating){return}
        try{
        $d.FindName('AccountAliasBox').Text=if($sender.SelectedItem){$sender.SelectedItem.Alias}else{''}
        $d.FindName('AccountHintBox').Text=if($sender.SelectedItem){$sender.SelectedItem.Hint}else{''}
        }catch{Set-ManagerPurchaseUiError -View $d -Target 'PurchaseManageError'}
    })
    $dialog.FindName('ClosePurchaseManage').Add_Click({param($sender,$eventArgs) [Windows.Window]::GetWindow($sender).Close()})
    Update-ManagerPurchaseManageLists $dialog '' ''
    $store=Get-ManagerPurchasesStore
    if($store.ReadOnly){$dialog.FindName('PurchaseManageError').Text=if($store.Error){$store.Error}else{'购买来源由较新版本创建，当前只读。'};foreach($name in 'SaveProvider','DeleteProvider','SavePurchaseAccount','DeletePurchaseAccount'){$dialog.FindName($name).IsEnabled=$false}}
    return $dialog
}
function Show-ManagerPurchaseManageWindow {
    $dialog=$null
    try{$dialog=New-ManagerPurchaseManageWindow;[void]$dialog.ShowDialog()}catch{Set-ManagerPurchaseUiError -View $dialog -Target 'PurchaseManageError'}
}
