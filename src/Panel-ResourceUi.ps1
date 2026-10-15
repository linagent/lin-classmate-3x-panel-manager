# Resource presentation and process-only history. Opens cached data without network activity.
if($null -eq $script:managerResourceCache){$script:managerResourceCache=@{}}
if($null -eq $script:managerResourceHistory){$script:managerResourceHistory=@{}}
function Get-ManagerResourceNow {return [DateTime]::UtcNow}
function Get-ManagerResourceId($Entry) {if($Entry -is [string]){return $Entry};return [string]$Entry.Id}
function Get-ManagerResourceRecord($Entry) {
    $id=Get-ManagerResourceId $Entry
    if($script:managerResourceCache.ContainsKey($id)){return $script:managerResourceCache[$id]}
    return $null
}
function Test-ManagerResourceStale($Record) {
    if(-not $Record -or -not $Record.Snapshot -or $Record.Stale){return $true}
    $interval=300
    if($script:managerAutoRefreshSeconds -in @(60,300)){$interval=[int]$script:managerAutoRefreshSeconds}
    try{$age=((Get-ManagerResourceNow)-[DateTime]$Record.Snapshot.SampledAtUtc).TotalSeconds}catch{return $true}
    return ($age -lt -60 -or $age -gt [Math]::Max(120,2*$interval+30))
}
function Test-ManagerResourceAttention($Entry) {
    $record=Get-ManagerResourceRecord $Entry
    if(Test-ManagerResourceStale $record){return $false}
    $s=$record.Snapshot
    return [bool](($null -ne $s.CpuPercent -and $s.CpuPercent -ge 80) -or ($null -ne $s.MemoryPercent -and $s.MemoryPercent -ge 80) -or ($null -ne $s.DiskPercent -and $s.DiskPercent -ge 85))
}
function Register-ManagerResourceResult {
    param([Parameter(Mandatory=$true)][string]$Id,$ResultResources)
    $now=Get-ManagerResourceNow
    $old=Get-ManagerResourceRecord $Id
    $sampleTime=$null
    try{if($ResultResources -and $ResultResources.State -eq 'Ok' -and $ResultResources.SampledAtUtc){$sampleTime=([DateTime]$ResultResources.SampledAtUtc).ToUniversalTime()}}catch{}
    if($sampleTime -and $sampleTime -le $now.AddMinutes(1)){
        # The probe returns a fresh immutable-by-convention whitelist snapshot; it contains no credentials.
        $script:managerResourceCache[$Id]=@{Snapshot=$ResultResources;LastAttempt=$now;LastError=$null;Stale=$false}
        if(-not $script:managerResourceHistory.ContainsKey($Id)){$script:managerResourceHistory[$Id]=[Collections.ArrayList]::new()}
        $history=$script:managerResourceHistory[$Id]
        $duplicate=@($history | Where-Object {([DateTime]$_.SampledAtUtc).Ticks -eq $sampleTime.Ticks}).Count -gt 0
        if(-not $duplicate){[void]$history.Add($ResultResources)}
        $cutoff=$now.AddHours(-6)
        for($i=$history.Count-1;$i -ge 0;$i--){if(([DateTime]$history[$i].SampledAtUtc) -lt $cutoff){$history.RemoveAt($i)}}
        if($history.Count -gt 2048){$history.RemoveRange(0,$history.Count-2048)}
    }else{
        $errorText='资源读取失败，请重新检测'
        $status=if($script:managerStatus){$script:managerStatus[$Id]}else{$null}
        if($status -and $status.Login -and $status.Login.State -in @('Fail','Skipped')){$errorText=[string]$status.Login.Text}
        elseif($status -and $status.Http -and $status.Http.State -in @('Fail','Warn')){$errorText=[string]$status.Http.Text}
        if(-not $errorText){$errorText='资源暂不可用，请重新检测'}
        $script:managerResourceCache[$Id]=@{Snapshot=if($old){$old.Snapshot}else{$null};LastAttempt=$now;LastError=$errorText;Stale=$true}
    }
}
function Format-ManagerResourcePercent($Value) {if($null -eq $Value){return '—'};return ([double]$Value).ToString('0.#',[Globalization.CultureInfo]::InvariantCulture)+'%'}
function Format-ManagerResourceNumber($Value,[string]$Format='0.##') {if($null -eq $Value){return '—'};return ([double]$Value).ToString($Format,[Globalization.CultureInfo]::InvariantCulture)}
function Format-ManagerResourceBytes($Value,[switch]$Rate) {
    if($null -eq $Value){return '—'}
    $v=[double]$Value;$units=if($Rate){@('B/s','KiB/s','MiB/s','GiB/s','TiB/s','PiB/s')}else{@('B','KiB','MiB','GiB','TiB','PiB')};$i=0
    while($v -ge 1024 -and $i -lt $units.Count-1){$v/=1024;$i++}
    return $v.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)+' '+$units[$i]
}
function Format-ManagerResourceDuration($Value) {
    if($null -eq $Value){return '—'}
    $seconds=[decimal]$Value;$days=[Math]::Floor($seconds/86400);$hours=[Math]::Floor(($seconds%86400)/3600);$minutes=[Math]::Floor(($seconds%3600)/60)
    if($days -gt 0){return "$days 天 $hours 小时"}
    if($hours -gt 0){return "$hours 小时 $minutes 分钟"}
    if($minutes -gt 0){return "$minutes 分钟"}
    return ([Math]::Floor($seconds)).ToString()+' 秒'
}
function Get-ManagerResourceBrushKey($Value,[double]$Attention=80,[bool]$Stale=$false) {
    if($null -eq $Value -or $Stale){return 'FaintBrush'}
    if($Value -ge 95){return 'BadBrush'}
    if($Value -ge $Attention){return 'ExpiringDotBrush'}
    return 'SuccessBrush'
}
function Set-ManagerResourceMetric($View,[string]$ValueName,[string]$MeterName,$Value,[double]$Attention,[bool]$Stale) {
    $text=$View.FindName($ValueName);$meter=$View.FindName($MeterName)
    $key=Get-ManagerResourceBrushKey $Value $Attention $Stale
    if($text){$text.Text=(Format-ManagerResourcePercent $Value);$text.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$key)}
    if($meter){$meter.Value=if($null -ne $Value){[Math]::Max(0,[Math]::Min(100,[double]$Value))}else{0};$meter.SetResourceReference([Windows.Controls.Control]::ForegroundProperty,$key);$meter.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'TrackBrush');$meter.Opacity=if($Stale){0.45}else{1}}
}
function Update-ManagerCardResources {
    param($Row)
    if(-not $Row -or -not $Row.Control){return}
    $card=$Row.Control;$record=Get-ManagerResourceRecord $Row.Entry;$s=if($record){$record.Snapshot}else{$null};$stale=Test-ManagerResourceStale $record
    Set-ManagerResourceMetric $card 'CpuValue' 'CpuMeter' $s.CpuPercent 80 $stale
    Set-ManagerResourceMetric $card 'MemoryValue' 'MemoryMeter' $s.MemoryPercent 80 $stale
    Set-ManagerResourceMetric $card 'DiskValue' 'DiskMeter' $s.DiskPercent 85 $stale
    $overview=$card.FindName('ResourceOverview')
    if($overview){
        $message=if(-not $s){'资源尚未读取 · 点击查看监控，或执行批量检测'}elseif($stale){'数据待更新 · 上次采样 '+([DateTime]$s.SampledAtUtc).ToLocalTime().ToString('HH:mm:ss')}else{'采样 '+([DateTime]$s.SampledAtUtc).ToLocalTime().ToString('HH:mm:ss')+' · 点击查看完整资源监控'}
        if($record.LastError){$message+=' · '+$record.LastError}
        $overview.ToolTip=$message
        foreach($name in 'CpuValue','MemoryValue','DiskValue'){$element=$card.FindName($name);if($element){$element.ToolTip=$message}}
    }
}
function Update-ManagerResourceSummary {
    if(-not $script:window){return}
    $number=$script:window.FindName('SummaryResourceCount');$note=$script:window.FindName('SummaryResourceNote');$button=$script:window.FindName('ResourceAttentionButton')
    if(-not $number -or -not $note){return}
    $attention=0;$unknown=0;$total=0
    foreach($entry in @($script:entries)){
        if(-not $entry){continue};$total++
        $record=Get-ManagerResourceRecord $entry
        if(Test-ManagerResourceStale $record){$unknown++;continue}
        if(Test-ManagerResourceAttention $entry){$attention++;continue}
        $s=$record.Snapshot
        if($null -eq $s.CpuPercent -or $null -eq $s.MemoryPercent -or $null -eq $s.DiskPercent){$unknown++}
    }
    if($unknown -gt 0 -and $attention -eq 0){$number.Text='—';$note.Text=if($script:managerResourceCache.Count){"$unknown 台待更新"}else{'待检测'};$key='PlaceholderBrush'}
    else{$number.Text=[string]$attention;$note.Text=if($unknown -gt 0){"· $unknown 台待更新"}elseif($total -eq 0){'暂无服务器'}else{'台'};$key=if($attention){'ExpiringDotBrush'}else{'SuccessBrush'}}
    $number.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$key)
    if($button){$button.IsEnabled=($attention -gt 0);$button.ToolTip="CPU 或内存 ≥80%，磁盘 ≥85%。每台服务器只计一次。当前 $attention 台需关注，$unknown 台数据待更新。"}
}
function Open-ManagerResourceDrawer {
    param($Entry)
    if(-not $Entry){return}
    $view=Read-ManagerXaml 'ResourceDrawer.xaml'
    Set-ManagerDrawer -View $view -Entry $Entry -Mode 'Resources'
    $view.FindName('CloseDrawer').Add_Click({Close-ManagerDrawer})
    $refresh=$view.FindName('RefreshResource');$refresh.Tag=$Entry
    $refresh.Add_Click({param($sender,$eventArgs) Start-ManagerStatusCheck -Entries @($sender.Tag);Update-ManagerResourceDrawer})
    $source=$view.FindName('MonitorSource');$source.Tag=$Entry
    $source.Add_Click({param($sender,$eventArgs) Open-ManagerPurchaseDrawer -Entry $sender.Tag})
    foreach($minutes in @(5,30,360)){
        $range=$view.FindName('Range'+$minutes);$range.Tag=@{View=$view;Minutes=$minutes}
        $range.Add_Click({param($sender,$eventArgs) if($script:managerDrawer -and $script:managerDrawer.Mode -eq 'Resources' -and $script:managerDrawer.View -eq $sender.Tag.View){$script:managerDrawer.RangeMinutes=[int]$sender.Tag.Minutes;Update-ManagerResourceDrawer}})
    }
    $chart=$view.FindName('NetworkChart')
    $chart.Add_SizeChanged({Update-ManagerResourceChart})
    $chart.Add_MouseMove({param($sender,$eventArgs) Update-ManagerResourceChartHover $sender ($eventArgs.GetPosition($sender).X)})
    $chart.Add_MouseLeave({param($sender,$eventArgs) if($script:managerDrawer -and $script:managerDrawer.Mode -eq 'Resources'){$script:managerDrawer.View.FindName('NetworkChartHover').Text=Get-ManagerResourceHistoryCaption;Remove-ManagerResourceChartCursor $sender}})
    Update-ManagerResourceDrawer
}
function Get-ManagerResourceHistoryCaption {
    if(-not $script:managerDrawer -or $script:managerDrawer.Mode -ne 'Resources'){return ''}
    $view=$script:managerDrawer.View;$chart=$view.FindName('NetworkChart');$data=$chart.Tag
    if(-not $data -or $data.Samples.Count -eq 0){return '客户端采样 · 当前时间范围尚无真实历史'}
    $count=$data.Samples.Count;$first=([DateTime]$data.Samples[0].SampledAtUtc).ToLocalTime().ToString('HH:mm:ss');$last=([DateTime]$data.Samples[$count-1].SampledAtUtc).ToLocalTime().ToString('HH:mm:ss')
    return "客户端采样 · $count 个点 · $first 至 $last"
}
function Update-ManagerResourceDrawer {
    if(-not $script:managerDrawer -or $script:managerDrawer.Mode -ne 'Resources'){return}
    $view=$script:managerDrawer.View;$entry=$script:managerDrawer.Entry
    if(-not $view -or -not $entry){return}
    $record=Get-ManagerResourceRecord $entry;$s=if($record){$record.Snapshot}else{$null};$stale=Test-ManagerResourceStale $record
    $view.FindName('MonitorServerName').Text=[string]$entry.Name
    $location=Get-ManagerEntryLocation $entry;$access=Get-ManagerAccessKind $entry
    $connection=switch($access){'Tunnel'{'SSH加密隧道'}'Https'{'HTTPS面板'}default{'HTTP面板'}}
    $view.FindName('MonitorLocation').Text=$location.DisplayName+' · '+$connection
    $purchase=$null;try{$purchase=Get-ManagerEntryPurchase $entry}catch{}
    $view.FindName('MonitorSource').Content=if($purchase){'服务商：'+$purchase.ProviderName}else{'服务商未设置 · 点击设置'}
    $view.FindName('MonitorSampleTime').Text=if($s){'采样 '+([DateTime]$s.SampledAtUtc).ToLocalTime().ToString('MM-dd HH:mm:ss')+$(if($stale){' · 待更新'}else{' · 已读取'})}else{'尚未采样 · 点击刷新采样'}
    $warning=$view.FindName('MonitorWarning');$warningText=$view.FindName('MonitorWarningText')
    if($stale -and $s){$warning.Visibility='Visible';$warningText.Text=if($record.LastError){$record.LastError+'。保留上次成功采样，数值已淡化。'}else{'数据已过期。保留上次成功采样，点击刷新获取最新状态。'}}
    elseif(-not $s -and $record -and $record.LastError){$warning.Visibility='Visible';$warningText.Text=$record.LastError}
    else{$warning.Visibility='Collapsed';$warningText.Text=''}
    Set-ManagerResourceMetric $view 'MonitorCpu' 'MonitorCpuMeter' $s.CpuPercent 80 $stale
    Set-ManagerResourceMetric $view 'MonitorMemory' 'MonitorMemoryMeter' $s.MemoryPercent 80 $stale
    Set-ManagerResourceMetric $view 'MonitorDisk' 'MonitorDiskMeter' $s.DiskPercent 85 $stale
    Set-ManagerResourceMetric $view 'MonitorSwap' 'MonitorSwapMeter' $s.SwapPercent 80 $stale
    $view.FindName('MonitorCpuInfo').Text=if($s -and ($null -ne $s.CpuCores -or $null -ne $s.CpuLogicalProcessors -or $null -ne $s.CpuSpeedMHz)){(Format-ManagerResourceNumber $s.CpuCores '0')+' 核 / '+(Format-ManagerResourceNumber $s.CpuLogicalProcessors '0')+' 线程 · '+$(if($null -ne $s.CpuSpeedMHz){(Format-ManagerResourceNumber ($s.CpuSpeedMHz/1000))+' GHz'}else{'—'})}else{'核心信息未返回'}
    foreach($metric in @(@('Memory','MemoryUsedBytes','MemoryTotalBytes'),@('Disk','DiskUsedBytes','DiskTotalBytes'),@('Swap','SwapUsedBytes','SwapTotalBytes'))){$used=if($s){$s[$metric[1]]}else{$null};$total=if($s){$s[$metric[2]]}else{$null};$view.FindName('Monitor'+$metric[0]+'Info').Text=(Format-ManagerResourceBytes $used)+' / '+(Format-ManagerResourceBytes $total)}
    if($s -and $null -ne $s.SwapTotalBytes -and $s.SwapTotalBytes -eq 0){$view.FindName('MonitorSwap').Text='未配置';$view.FindName('MonitorSwap').FontSize=19;$view.FindName('MonitorSwapInfo').Text='交换空间总量为 0'}else{$view.FindName('MonitorSwap').FontSize=26}
    $view.FindName('MonitorUpload').Text='↑ '+(Format-ManagerResourceBytes $s.UploadBytesPerSecond -Rate)
    $view.FindName('MonitorDownload').Text='↓ '+(Format-ManagerResourceBytes $s.DownloadBytesPerSecond -Rate)
    $view.FindName('MonitorConnections').Text=Format-ManagerResourceNumber $s.ConnectionCount '0'
    $view.FindName('MonitorTcp').Text='TCP '+(Format-ManagerResourceNumber $s.TcpConnections '0')
    $view.FindName('MonitorUdp').Text='UDP '+(Format-ManagerResourceNumber $s.UdpConnections '0')
    $view.FindName('MonitorOsUptime').Text=Format-ManagerResourceDuration $s.OsUptimeSeconds
    $xrayLabel=switch($s.XrayState){'running'{'运行中'}'stop'{'已停止'}'error'{'异常'}default{'—'}}
    $view.FindName('MonitorXray').Text=$xrayLabel+$(if($s.XrayVersion){' · '+$s.XrayVersion}else{''})
    $view.FindName('MonitorXrayUptime').Text=Format-ManagerResourceDuration $s.XrayUptimeSeconds
    $view.FindName('MonitorPanel').Text=(Format-ManagerResourceBytes $s.PanelMemoryBytes)+' / '+(Format-ManagerResourceNumber $s.PanelThreads '0')+' 协程'
    $view.FindName('MonitorLoad').Text=(Format-ManagerResourceNumber $s.Load1)+' / '+(Format-ManagerResourceNumber $s.Load5)+' / '+(Format-ManagerResourceNumber $s.Load15)
    $status=if($script:managerStatus){$script:managerStatus[(Get-ManagerResourceId $entry)]}else{$null};$latency=$status.LatencyMs
    $view.FindName('MonitorLatency').Text=if($null -ne $latency){[string]$latency+' ms'}else{'—'}
    $view.FindName('MonitorLatency').SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,(Get-ManagerLatencyBrushKey $latency))
    $view.FindName('MonitorSent').Text='已发送 '+(Format-ManagerResourceBytes $s.NetworkUploadBytes)
    $view.FindName('MonitorReceived').Text='已接收 '+(Format-ManagerResourceBytes $s.NetworkDownloadBytes)
    # A retained old rate is useful history, but must not look like a live current rate.
    $view.FindName('MonitorUpload').SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($stale){'FaintBrush'}else{'AccentBrush'}))
    $view.FindName('MonitorDownload').SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($stale){'FaintBrush'}else{'InfoBrush'}))
    foreach($name in 'MonitorConnections','MonitorTcp','MonitorUdp','MonitorOsUptime','MonitorXrayUptime','MonitorPanel','MonitorLoad','MonitorSent','MonitorReceived'){$view.FindName($name).SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($stale){'FaintBrush'}else{'InkBrush'}))}
    $view.FindName('MonitorXray').SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,$(if($stale -or -not $s.XrayState){'FaintBrush'}elseif($s.XrayState -eq 'running'){'SuccessBrush'}elseif($s.XrayState -eq 'error'){'BadBrush'}else{'MutedBrush'}))
    $view.FindName('RefreshResource').IsEnabled=(-not $script:managerStatusBatch -or $script:managerStatusBatch.Completed)
    $minutes=[int]$script:managerDrawer.RangeMinutes
    foreach($n in @(5,30,360)){$view.FindName('Range'+$n).SetResourceReference([Windows.Controls.Control]::ForegroundProperty,$(if($n -eq $minutes){'AccentBrush'}else{'MutedBrush'}))}
    Update-ManagerResourceChart
}
function Add-ManagerResourceChartText($Canvas,[string]$Text,[double]$X,[double]$Y,[double]$Width=50,[string]$Align='Right') {
    $label=[Windows.Controls.TextBlock]::new();$label.Text=$Text;$label.FontSize=11;$label.Width=$Width;$label.TextAlignment=$Align;$label.IsHitTestVisible=$false
    $label.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty,'FaintBrush');[Windows.Controls.Canvas]::SetLeft($label,$X);[Windows.Controls.Canvas]::SetTop($label,$Y);[void]$Canvas.Children.Add($label)
}
function Remove-ManagerResourceChartCursor($Canvas) {
    $remove=@($Canvas.Children | Where-Object {$_.Tag -eq 'ResourceChartCursor'})
    foreach($item in $remove){[void]$Canvas.Children.Remove($item)}
}
function Update-ManagerResourceChart {
    if(-not $script:managerDrawer -or $script:managerDrawer.Mode -ne 'Resources'){return}
    $view=$script:managerDrawer.View;$canvas=$view.FindName('NetworkChart');if(-not $canvas){return}
    $canvas.Children.Clear();$width=$canvas.ActualWidth;$height=$canvas.ActualHeight
    if($width -lt 100 -or $height -lt 70){return}
    $now=Get-ManagerResourceNow;$minutes=[int]$script:managerDrawer.RangeMinutes;if($minutes -notin @(5,30,360)){$minutes=30}
    $start=$now.AddMinutes(-$minutes);$id=Get-ManagerResourceId $script:managerDrawer.Entry
    $samples=@($script:managerResourceHistory[$id] | Where-Object {$_ -and ([DateTime]$_.SampledAtUtc) -ge $start -and ([DateTime]$_.SampledAtUtc) -le $now -and ($null -ne $_.UploadBytesPerSecond -or $null -ne $_.DownloadBytesPerSecond)} | Sort-Object SampledAtUtc)
    $left=57.0;$top=24.0;$plotWidth=[Math]::Max(20,$width-$left-8);$plotHeight=[Math]::Max(20,$height-54)
    $maximum=1.0;foreach($sample in $samples){foreach($field in 'UploadBytesPerSecond','DownloadBytesPerSecond'){if($null -ne $sample[$field]){$maximum=[Math]::Max($maximum,[double]$sample[$field])}}}
    $magnitude=[Math]::Pow(10,[Math]::Floor([Math]::Log10($maximum)));$axisMaximum=[Math]::Ceiling($maximum/$magnitude)*$magnitude
    $divisor=1.0;$unit='B/s';foreach($pair in @(@(1073741824.0,'GiB/s'),@(1048576.0,'MiB/s'),@(1024.0,'KiB/s'))){if($axisMaximum -ge $pair[0]){$divisor=$pair[0];$unit=$pair[1];break}}
    for($tick=0;$tick -le 4;$tick++){
        $y=$top+$plotHeight*$tick/4;$line=[Windows.Shapes.Line]::new();$line.X1=$left;$line.X2=$left+$plotWidth;$line.Y1=$y;$line.Y2=$y;$line.StrokeThickness=0.75;$line.IsHitTestVisible=$false;$line.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty,'LineBrush');[void]$canvas.Children.Add($line)
        Add-ManagerResourceChartText $canvas ((($axisMaximum*(4-$tick)/4/$divisor).ToString('0.#',[Globalization.CultureInfo]::InvariantCulture))) 0 ($y-7) 49
    }
    Add-ManagerResourceChartText $canvas $unit 0 0 49
    Add-ManagerResourceChartText $canvas $start.ToLocalTime().ToString('HH:mm') $left ($top+$plotHeight+9) 45 'Left'
    Add-ManagerResourceChartText $canvas $start.AddMinutes($minutes/2).ToLocalTime().ToString('HH:mm') ($left+$plotWidth/2-22) ($top+$plotHeight+9) 45 'Center'
    Add-ManagerResourceChartText $canvas $now.ToLocalTime().ToString('HH:mm') ($left+$plotWidth-45) ($top+$plotHeight+9) 45 'Right'
    $positions=[Collections.ArrayList]::new()
    foreach($sample in $samples){[void]$positions.Add(@{X=$left+$plotWidth*(([DateTime]$sample.SampledAtUtc-$start).TotalSeconds/($minutes*60));Sample=$sample})}
    foreach($spec in @(@('UploadBytesPerSecond','AccentBrush'),@('DownloadBytesPerSecond','InfoBrush'))){
        $segment=[Windows.Shapes.Polyline]::new();$segment.StrokeThickness=1.75;$segment.IsHitTestVisible=$false;$segment.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty,$spec[1]);$previous=$null
        foreach($position in $positions){
            $value=$position.Sample[$spec[0]]
            $gap=($previous -and (([DateTime]$position.Sample.SampledAtUtc)-[DateTime]$previous).TotalSeconds -gt 630)
            if($null -eq $value -or $gap){if($segment.Points.Count -gt 1){[void]$canvas.Children.Add($segment)};$segment=[Windows.Shapes.Polyline]::new();$segment.StrokeThickness=1.75;$segment.IsHitTestVisible=$false;$segment.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty,$spec[1])}
            if($null -ne $value){$y=$top+$plotHeight*(1-[double]$value/$axisMaximum);$segment.Points.Add([Windows.Point]::new($position.X,$y));$dot=[Windows.Shapes.Ellipse]::new();$dot.Width=4;$dot.Height=4;$dot.IsHitTestVisible=$false;$dot.SetResourceReference([Windows.Shapes.Shape]::FillProperty,$spec[1]);[Windows.Controls.Canvas]::SetLeft($dot,$position.X-2);[Windows.Controls.Canvas]::SetTop($dot,$y-2);[void]$canvas.Children.Add($dot)}
            $previous=$position.Sample.SampledAtUtc
        }
        if($segment.Points.Count -gt 1){[void]$canvas.Children.Add($segment)}
    }
    $canvas.Tag=@{Samples=$samples;Positions=$positions;Left=$left;Top=$top;PlotWidth=$plotWidth;PlotHeight=$plotHeight;Start=$start;End=$now;Maximum=$axisMaximum}
    $empty=$view.FindName('NetworkChartEmpty');$empty.Visibility=if($samples.Count -lt 2){'Visible'}else{'Collapsed'};$empty.Text=if($samples.Count -eq 1){'已收到 1 个真实采样 · 等待下一次刷新'}else{'当前时间范围尚无真实采样'}
    $view.FindName('NetworkChartHover').Text=Get-ManagerResourceHistoryCaption
}
function Update-ManagerResourceChartHover($Canvas,[double]$X) {
    if(-not $script:managerDrawer -or $script:managerDrawer.Mode -ne 'Resources' -or -not $Canvas.Tag -or $Canvas.Tag.Positions.Count -eq 0){return}
    $data=$Canvas.Tag;$nearest=$null;$distance=[double]::MaxValue
    foreach($position in $data.Positions){$d=[Math]::Abs($X-$position.X);if($d -lt $distance){$nearest=$position;$distance=$d}}
    if(-not $nearest){return}
    Remove-ManagerResourceChartCursor $Canvas
    $cursor=[Windows.Shapes.Line]::new();$cursor.Tag='ResourceChartCursor';$cursor.X1=$nearest.X;$cursor.X2=$nearest.X;$cursor.Y1=$data.Top;$cursor.Y2=$data.Top+$data.PlotHeight;$cursor.StrokeThickness=1;$cursor.StrokeDashArray=[Windows.Media.DoubleCollection]::new();$cursor.StrokeDashArray.Add(3);$cursor.StrokeDashArray.Add(3);$cursor.IsHitTestVisible=$false;$cursor.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty,'MutedBrush');[void]$Canvas.Children.Add($cursor)
    $sample=$nearest.Sample;$script:managerDrawer.View.FindName('NetworkChartHover').Text=([DateTime]$sample.SampledAtUtc).ToLocalTime().ToString('MM-dd HH:mm:ss')+' · ↑ '+(Format-ManagerResourceBytes $sample.UploadBytesPerSecond -Rate)+' · ↓ '+(Format-ManagerResourceBytes $sample.DownloadBytesPerSecond -Rate)
}
