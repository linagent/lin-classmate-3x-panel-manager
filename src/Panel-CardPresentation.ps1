# Local, deterministic vector flags: no emoji font dependency or network lookup.
function New-ManagerCountryFlag([string]$Code) {
    $canvas=[Windows.Controls.Canvas]::new();$canvas.Width=30;$canvas.Height=20;$canvas.ClipToBounds=$true
    function Add-FlagRect($X,$Y,$W,$H,$Color) {
        $shape=[Windows.Shapes.Rectangle]::new();$shape.Width=$W;$shape.Height=$H;$shape.Fill=New-ManagerBrush $Color
        [Windows.Controls.Canvas]::SetLeft($shape,$X);[Windows.Controls.Canvas]::SetTop($shape,$Y);[void]$canvas.Children.Add($shape)
    }
    function Add-FlagEllipse($X,$Y,$W,$H,$Color) {
        $shape=[Windows.Shapes.Ellipse]::new();$shape.Width=$W;$shape.Height=$H;$shape.Fill=New-ManagerBrush $Color
        [Windows.Controls.Canvas]::SetLeft($shape,$X);[Windows.Controls.Canvas]::SetTop($shape,$Y);[void]$canvas.Children.Add($shape)
    }
    function Add-FlagStar($X,$Y,$R,$Color) {
        $star=[Windows.Shapes.Polygon]::new();$star.Fill=New-ManagerBrush $Color
        for($i=0;$i -lt 10;$i++){$angle=(-90+$i*36)*[Math]::PI/180;$radius=if($i%2){$R*0.382}else{$R};$star.Points.Add([Windows.Point]::new($X+[Math]::Cos($angle)*$radius,$Y+[Math]::Sin($angle)*$radius))}
        [void]$canvas.Children.Add($star)
    }
    switch($Code.ToUpperInvariant()) {
        'US' {
            Add-FlagRect 0 0 30 20 '#FFFFFF'
            for($i=0;$i -lt 13;$i+=2){Add-FlagRect 0 ($i*20/13) 30 (20/13) '#B22234'}
            Add-FlagRect 0 0 12.3 (20*7/13) '#3C3B6E'
            for($r=0;$r -lt 9;$r++){ $n=if($r%2){5}else{6};for($c=0;$c -lt $n;$c++){Add-FlagStar (1.03+$c*2.05+($r%2)*1.025) (0.6+$r*1.18) 0.51 '#FFFFFF'}}
        }
        {$_ -in 'UK','GB'} {
            Add-FlagRect 0 0 30 20 '#012169'
            foreach($spec in @(@('M0,0 L30,20',5,'#FFFFFF'),@('M0,20 L30,0',5,'#FFFFFF'),@('M0,0 L30,20',2,'#C8102E'),@('M0,20 L30,0',2,'#C8102E'))){$p=[Windows.Shapes.Path]::new();$p.Data=[Windows.Media.Geometry]::Parse($spec[0]);$p.Stroke=New-ManagerBrush $spec[2];$p.StrokeThickness=$spec[1];[void]$canvas.Children.Add($p)}
            Add-FlagRect 0 7 30 6 '#FFFFFF';Add-FlagRect 12 0 6 20 '#FFFFFF';Add-FlagRect 0 8.5 30 3 '#C8102E';Add-FlagRect 13.5 0 3 20 '#C8102E'
        }
        'AU' {
            Add-FlagRect 0 0 30 20 '#012169'
            $union=New-ManagerCountryFlag 'GB';$union.RenderTransform=[Windows.Media.ScaleTransform]::new(0.5,0.5);[void]$canvas.Children.Add($union)
            Add-FlagStar 7.5 15 2.1 '#FFFFFF'
            foreach($p in @(@(23,4),@(19,9),@(27,9),@(24,16))){Add-FlagStar $p[0] $p[1] 1.4 '#FFFFFF'}
            Add-FlagStar 25.5 11.5 0.8 '#FFFFFF'
        }
        'HK' {
            Add-FlagRect 0 0 30 20 '#DE2910'
            for($i=0;$i -lt 5;$i++){$p=[Windows.Shapes.Path]::new();$p.Data=[Windows.Media.Geometry]::Parse('M15,10 C10,8 12,3 16,4 C14,6 18,7 15,10 Z');$p.Fill=[Windows.Media.Brushes]::White;$p.RenderTransform=[Windows.Media.RotateTransform]::new($i*72,15,10);[void]$canvas.Children.Add($p)}
        }
        'JP' {Add-FlagRect 0 0 30 20 '#FFFFFF';Add-FlagEllipse 9 4 12 12 '#BC002D'}
        'DE' {Add-FlagRect 0 0 30 7 '#171717';Add-FlagRect 0 7 30 6 '#DD0000';Add-FlagRect 0 13 30 7 '#FFCE00'}
        'FR' {Add-FlagRect 0 0 10 20 '#002395';Add-FlagRect 10 0 10 20 '#FFFFFF';Add-FlagRect 20 0 10 20 '#ED2939'}
        'NL' {Add-FlagRect 0 0 30 7 '#AE1C28';Add-FlagRect 0 7 30 6 '#FFFFFF';Add-FlagRect 0 13 30 7 '#21468B'}
        'RU' {Add-FlagRect 0 0 30 7 '#FFFFFF';Add-FlagRect 0 7 30 6 '#0039A6';Add-FlagRect 0 13 30 7 '#D52B1E'}
        'ID' {Add-FlagRect 0 0 30 10 '#CE1126';Add-FlagRect 0 10 30 10 '#FFFFFF'}
        'CN' {Add-FlagRect 0 0 30 20 '#DE2910';Add-FlagStar 5 5 3 '#FFDE00';foreach($p in @(@(10,2),@(12,4),@(12,7),@(10,9))){Add-FlagStar $p[0] $p[1] 1 '#FFDE00'}}
        'CA' {Add-FlagRect 0 0 30 20 '#FFFFFF';Add-FlagRect 0 0 7 20 '#D80621';Add-FlagRect 23 0 7 20 '#D80621';$p=[Windows.Shapes.Path]::new();$p.Fill=New-ManagerBrush '#D80621';$p.Data=[Windows.Media.Geometry]::Parse('M15,3 L17,7 L19,5 L19,9 L22,8 L20,13 L16,14 L16,18 L14,18 L14,14 L10,13 L8,8 L11,9 L11,5 L13,7 Z');[void]$canvas.Children.Add($p)}
        default {
            # Unknown flags use a neutral globe and the explicit Chinese country label.
            $canvas.Background=New-ManagerBrush '#ECE8E2'
            $globe=[Windows.Shapes.Path]::new();$globe.Data=[Windows.Media.Geometry]::Parse('M23,10 A8,8 0 1 1 7,10 A8,8 0 1 1 23,10 M7,10 L23,10 M15,2 C10,6 10,14 15,18 M15,2 C20,6 20,14 15,18');$globe.Stroke=New-ManagerBrush '#8B8076';$globe.StrokeThickness=0.9;[void]$canvas.Children.Add($globe)
        }
    }
    return $canvas
}
function Reset-ManagerCardCredentials($Card,[switch]$Collapse) {
    if(-not $Card){return}
    # -Collapse remains accepted by old callers; the approved credential row stays visible.
    # Reset the eyes first, then overwrite both values so Unchecked handlers cannot leave text exposed.
    foreach($name in 'ShowUsername','ShowPassword','ShowPurchaseAccount'){
        $toggle=$Card.FindName($name);if($toggle){$toggle.IsChecked=$false}
    }
    $mask=if($Card.Tag -and $Card.Tag.HasAccount){'••••••'}else{'—'}
    foreach($name in 'UsernameBox','PasswordDisplay'){
        $value=$Card.FindName($name);if($value){$value.Text=$mask}
    }
    $panel=$Card.FindName('CredentialsPanel');if($panel){$panel.Visibility='Visible'}
    $purchase=$null
    if($Card.Tag -and $Card.Tag.Entry -and (Get-Command Get-ManagerEntryPurchase -ErrorAction SilentlyContinue)){
        $purchase=Get-ManagerEntryPurchase -Entry $Card.Tag.Entry
    }
    $alias=$Card.FindName('PurchaseAlias');if($alias){$alias.Text=if($purchase){'••••••'}else{'—'}}
}
function Reset-ManagerCredentials([switch]$Collapse) {
    foreach($row in @($script:cards)){if($row.Control){Reset-ManagerCardCredentials $row.Control -Collapse:$Collapse}}
}
function Close-ManagerCardMenu {
    if($script:managerCardMenu){$script:managerCardMenu.IsOpen=$false;$script:managerCardMenu=$null}
}
function Show-ManagerCardMenu($Button) {
    if($script:managerCardMenu -and $script:managerCardMenu.IsOpen -and $script:managerCardMenu.PlacementTarget -eq $Button){Close-ManagerCardMenu;return}
    Close-ManagerCardMenu
    $menu=[Windows.Controls.ContextMenu]::new();Add-ManagerTheme $menu
    $menu.StaysOpen=$false;$menu.Placement='Bottom';$menu.PlacementTarget=$Button;$menu.HorizontalOffset=-120
    # WPF consumes the first outside click while a ContextMenu owns mouse capture.
    # Resolve another card trigger during that captured click and open it after close.
    $outside=[Windows.Input.MouseButtonEventHandler]{param($s,$e)
        if($e.ChangedButton -ne [Windows.Input.MouseButton]::Left -or -not $script:window){return}
        $point=[Windows.Input.Mouse]::GetPosition($script:window)
        $hit=$script:window.InputHitTest($point)
        while($hit -is [Windows.Media.Visual] -and $hit -isnot [Windows.Controls.Button]){$hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)}
        if($hit -is [Windows.Controls.Button] -and $hit.Name -eq 'MoreButton' -and $hit -ne $s.PlacementTarget){
            $script:managerPendingCardMenu=$hit;$s.IsOpen=$false
            [void]$script:window.Dispatcher.BeginInvoke([Action]{
                $next=$script:managerPendingCardMenu;$script:managerPendingCardMenu=$null
                if($next -and $script:window.IsActive){Show-ManagerCardMenu $next}
            },[Windows.Threading.DispatcherPriority]::Input)
        }
    }
    $menu.AddHandler([Windows.Input.Mouse]::PreviewMouseDownOutsideCapturedElementEvent,$outside,$true)
    $specs=@()
    if(Get-Command Open-ManagerResourceDrawer -ErrorAction SilentlyContinue){$specs+=,@('resource.monitor','资源监控','IcoActivity')}
    if(Get-Command Open-ManagerPurchaseDrawer -ErrorAction SilentlyContinue){$specs+=,@('purchase.source','购买来源','IcoFolder')}
    $specs+=@(@('server.settings','编辑服务器','IcoEdit'),@('server.folder','打开本地资料','IcoFolder'),@('server.delete','删除服务器','IcoTrash'))
    foreach($spec in $specs){
        if($spec[0] -eq 'server.delete'){[void]$menu.Items.Add([Windows.Controls.Separator]::new())}
        $item=[Windows.Controls.MenuItem]::new();$item.Header=$spec[1];$item.Tag=@{Action=$spec[0];Entry=$Button.Tag.Entry}
        $item.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,$(if($spec[0] -eq 'server.delete'){'BadBrush'}else{'InkBrush'}))
        $item.Add_Click({param($s,$e)
            Close-ManagerCardMenu
            try{
                switch([string]$s.Tag.Action){
                    'resource.monitor' {Open-ManagerResourceDrawer $s.Tag.Entry;break}
                    'purchase.source' {Open-ManagerPurchaseDrawer $s.Tag.Entry;break}
                    default {Invoke-ManagerAction -Id $s.Tag.Action -Entry $s.Tag.Entry}
                }
            }catch{Show-ManagerMessage $_.Exception.Message '操作未完成'}
        })
        [void]$menu.Items.Add($item)
    }
    $menu.Add_PreviewKeyDown({param($s,$e) if($e.Key -eq 'Escape'){$target=$s.PlacementTarget;$s.IsOpen=$false;[void]$target.Focus();$e.Handled=$true}})
    $script:managerCardMenu=$menu;$menu.IsOpen=$true
}
