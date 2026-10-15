# Local scheduler only. Loading this module never starts a timer or requests the network.
# Start-ManagerAutoRefresh is called from Loaded only by the real client launch mode.
function New-ManagerAutoRefreshState([int]$IntervalSeconds=300) {
    return @{IntervalSeconds=$IntervalSeconds;Started=$false;Closed=$false;Busy=$false;AutomaticBatch=$false
        NextDueUtc=$null;Timer=$null;Suspended=0;Servers=@{};UpdatingIds=@{};PreviousRecords=@{}}
}
function Get-ManagerAutoRefreshNow {
    if($script:managerAutoRefreshClock){return ([DateTime](& $script:managerAutoRefreshClock)).ToUniversalTime()}
    return [DateTime]::UtcNow
}
function Initialize-ManagerAutoRefresh {
    if($script:managerAutoRefresh -and $script:managerAutoRefresh.Timer){$script:managerAutoRefresh.Timer.Stop()}
    $seconds=if($script:managerAutoRefreshSeconds -in @(0,60,300)){[int]$script:managerAutoRefreshSeconds}else{300}
    $script:managerAutoRefresh=New-ManagerAutoRefreshState $seconds
    Update-ManagerAutoRefreshUi
}
function Get-ManagerAutoRefreshServer([string]$Id) {
    $s=$script:managerAutoRefresh
    if(-not $s.Servers.ContainsKey($Id)){$s.Servers[$Id]=@{Failures=0;RetryUtc=$null;AuthPaused=$false}}
    return $s.Servers[$Id]
}
function Set-ManagerAutoRefreshNextDue {
    $s=$script:managerAutoRefresh
    if(-not $s){return}
    $s.NextDueUtc=$null
    if(-not $s.Started -or $s.Closed -or $s.Busy -or $s.IntervalSeconds -eq 0){return}
    $base=(Get-ManagerAutoRefreshNow).AddSeconds($s.IntervalSeconds)
    $times=@(foreach($entry in @($script:entries)){
        $server=Get-ManagerAutoRefreshServer ([string]$entry.Id)
        if(-not $server.AuthPaused){if($server.RetryUtc -and $server.RetryUtc -gt $base){$server.RetryUtc}else{$base}}
    })
    if($times.Count){$s.NextDueUtc=@($times | Sort-Object)[0]}
}
function Reset-ManagerAutoRefreshServer([string]$Id) {
    if(-not $script:managerAutoRefresh){return}
    if($Id){$script:managerAutoRefresh.Servers.Remove($Id)}else{$script:managerAutoRefresh.Servers.Clear()}
    Set-ManagerAutoRefreshNextDue
    Update-ManagerAutoRefreshUi
}
function Get-ManagerAutoRefreshEligible([object[]]$Entries,$Now) {
    foreach($entry in @($Entries)){
        if(-not $entry){continue}
        $server=Get-ManagerAutoRefreshServer ([string]$entry.Id)
        if(-not $server.AuthPaused -and (-not $server.RetryUtc -or $Now -ge $server.RetryUtc)){$entry}
    }
}
function Notify-ManagerAutoRefreshBatchStarted([object[]]$Entries,[bool]$Automatic) {
    if(-not $script:managerAutoRefresh){return}
    $s=$script:managerAutoRefresh;$s.Busy=$true;$s.AutomaticBatch=$Automatic;$s.NextDueUtc=$null
    $s.UpdatingIds.Clear();$s.PreviousRecords.Clear()
    foreach($entry in @($Entries)){
        $id=[string]$entry.Id;$s.UpdatingIds[$id]=$true
        $old=$script:managerStatus[$id]
        if($Automatic -and $old -and $old.State -eq 'Done'){$s.PreviousRecords[$id]=$old}
    }
    Update-ManagerAutoRefreshUi
}
function Notify-ManagerAutoRefreshResult($Spec,$Record,[string]$Outcome) {
    if(-not $script:managerAutoRefresh){return}
    $s=$script:managerAutoRefresh;$id=[string]$Spec.Id;$s.UpdatingIds.Remove($id)
    if($Outcome -eq 'Cancelled'){return}
    $server=Get-ManagerAutoRefreshServer $id
    if($Record.AuthRejected){$server.AuthPaused=$true;$server.RetryUtc=$null;return}
    $failed=$Record.NetworkFailed -or $Outcome -in @('TimedOut','Failed') -or $Record.Http.State -eq 'Fail' -or $Record.Tunnel.State -eq 'Fail' -or $Record.Login.State -eq 'Fail'
    if($failed){
        $server.Failures=[Math]::Min(8,[int]$server.Failures+1)
        $base=[Math]::Max(60,[int]$s.IntervalSeconds)
        $seconds=[Math]::Min(1800,$base*[Math]::Pow(2,$server.Failures-1))
        $server.RetryUtc=(Get-ManagerAutoRefreshNow).AddSeconds($seconds)
    }else{$server.Failures=0;$server.RetryUtc=$null;$server.AuthPaused=$false}
}
function Notify-ManagerAutoRefreshBatchCompleted {
    if(-not $script:managerAutoRefresh){return}
    $s=$script:managerAutoRefresh;$s.Busy=$false;$s.UpdatingIds.Clear();$s.PreviousRecords.Clear()
    Set-ManagerAutoRefreshNextDue
    Update-ManagerAutoRefreshUi
}
function Test-ManagerStatusBatchBusy {
    $batch=$script:managerStatusBatch
    if(-not $batch){return $false}
    if(-not $batch.Closed){return (-not $batch.Completed -or ($batch.Draining -and $batch.Draining.Count -gt 0))}
    # A fault closes the generic polling timer. Wait for stopped pipelines before a new batch.
    foreach($job in @($batch.Running)+@($batch.Draining)){
        if($job.Handle -and -not $job.Handle.IsCompleted){return $true}
    }
    return $false
}
function Repair-ManagerAutoRefreshBatch {
    $s=$script:managerAutoRefresh;$batch=$script:managerStatusBatch
    if(-not $s -or -not $s.Busy -or -not $batch -or -not $batch.Closed -or (Test-ManagerStatusBatchBusy)){return}
    # Close-ManagerBackgroundBatch intentionally skips callbacks on a generic fault.
    # Complete failed UI records once after all underlying requests have ended.
    foreach($id in @($s.UpdatingIds.Keys)){Complete-ManagerStatusItem @{Id=$id;Password=$null;Username=$null} $null 'Failed'}
    foreach($job in @($batch.Running)+@($batch.Draining)){
        if($job.Item){$job.Item.Password=$null;$job.Item.Username=$null}
        if($job.PowerShell){try{[void]$job.PowerShell.EndInvoke($job.Handle)}catch{};try{$job.PowerShell.Dispose()}catch{}}
    }
    Notify-ManagerAutoRefreshBatchCompleted
    Set-ManagerFeedback '检测意外停止，已延长失败服务器的重试间隔。'
}
function Step-ManagerAutoRefresh {
    $s=$script:managerAutoRefresh
    if(-not $s -or -not $s.Started -or $s.Closed){return 'Stopped'}
    if($s.IntervalSeconds -eq 0){return 'Manual'}
    if($s.Suspended -gt 0){return 'Suspended'}
    Repair-ManagerAutoRefreshBatch
    if($s.Busy -or (Test-ManagerStatusBatchBusy)){return 'Busy'}
    $now=Get-ManagerAutoRefreshNow
    if($s.NextDueUtc -and $now -lt $s.NextDueUtc){Update-ManagerAutoRefreshUi;return 'NotDue'}
    $targets=@(Get-ManagerAutoRefreshEligible @($script:entries) $now)
    if(-not $targets.Count){
        $retries=@(foreach($entry in @($script:entries)){$server=Get-ManagerAutoRefreshServer ([string]$entry.Id);if(-not $server.AuthPaused -and $server.RetryUtc){$server.RetryUtc}})
        $s.NextDueUtc=if($retries.Count){@($retries | Sort-Object)[0]}else{$null}
        Update-ManagerAutoRefreshUi;return 'NoneEligible'
    }
    Start-ManagerStatusCheck $targets -Automatic
    return 'Started'
}
function Start-ManagerAutoRefresh {
    if(-not $script:managerAutoRefresh){Initialize-ManagerAutoRefresh}
    $s=$script:managerAutoRefresh
    if($s.Started -or $s.Closed -or -not $script:managerAutoRefreshEnabled){return}
    $s.Started=$true;$s.NextDueUtc=Get-ManagerAutoRefreshNow
    $timer=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
    $timer.Interval=[TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({param($sender,$eventArgs)
        try{[void](Step-ManagerAutoRefresh)}catch{
            $script:managerAutoRefresh.Busy=$false
            $script:managerAutoRefresh.NextDueUtc=(Get-ManagerAutoRefreshNow).AddSeconds([Math]::Max(60,$script:managerAutoRefresh.IntervalSeconds))
            Set-ManagerFeedback '自动刷新未完成，将在下一轮重试。';Update-ManagerAutoRefreshUi
        }
    })
    $s.Timer=$timer;$timer.Start()
    try{[void](Step-ManagerAutoRefresh)}catch{Set-ManagerFeedback '自动检测未能启动，可点击「批量检测」重试。'}
    Update-ManagerAutoRefreshUi
}
function Stop-ManagerAutoRefresh {
    if(-not $script:managerAutoRefresh){return}
    $s=$script:managerAutoRefresh;$s.Closed=$true;$s.Started=$false;$s.NextDueUtc=$null;$s.Busy=$false
    if($s.Timer){$s.Timer.Stop();$s.Timer=$null}
    $s.UpdatingIds.Clear();$s.PreviousRecords.Clear()
}
function Set-ManagerAutoRefreshMode([int]$Seconds,[switch]$Persist) {
    if($Seconds -notin @(0,60,300)){throw '刷新间隔仅支持手动、1 分钟或 5 分钟。'}
    if(-not $script:managerAutoRefresh){Initialize-ManagerAutoRefresh}
    $oldSeconds=$script:managerAutoRefreshSeconds
    $script:managerAutoRefreshSeconds=$Seconds
    if($Persist){
        try{Save-ManagerUiSettings}catch{$script:managerAutoRefreshSeconds=$oldSeconds;throw}
    }
    $s=$script:managerAutoRefresh;$s.IntervalSeconds=$Seconds
    Set-ManagerAutoRefreshNextDue
    Update-ManagerAutoRefreshUi
}
function Show-ManagerAutoRefreshMenu($Button) {
    $menu=[Windows.Controls.ContextMenu]::new()
    foreach($option in @(@(0,'手动刷新'),@(60,'每 1 分钟'),@(300,'每 5 分钟（推荐）'))){
        $item=[Windows.Controls.MenuItem]::new();$item.Header=$option[1];$item.Tag=[int]$option[0]
        $item.IsCheckable=$true;$item.IsChecked=$script:managerAutoRefresh.IntervalSeconds -eq [int]$option[0]
        $item.Add_Click({param($sender,$eventArgs)
            try{Set-ManagerAutoRefreshMode ([int]$sender.Tag) -Persist;Set-ManagerFeedback $(if($sender.Tag -eq 0){'已改为手动刷新。'}else{'自动刷新间隔已保存，下次启动继续使用。'})}
            catch{Set-ManagerFeedback '刷新间隔没能保存，已保留原设置。'}
        })
        [void]$menu.Items.Add($item)
    }
    $menu.PlacementTarget=$Button;$menu.Placement='Bottom';$menu.IsOpen=$true
}
function Update-ManagerAutoRefreshUi {
    $s=$script:managerAutoRefresh;$w=$script:window
    if(-not $s -or -not $w){return}
    $button=$w.FindName('AutoRefreshButton');$label=$w.FindName('AutoRefreshModeLabel');$status=$w.FindName('AutoRefreshStatus')
    if(-not $label -or -not $status -or -not $button){return}
    $label.Text=switch($s.IntervalSeconds){0{'手动刷新'}60{'自动 · 1 分钟'}default{'自动 · 5 分钟'}}
    $paused=@($s.Servers.Values | Where-Object {$_.AuthPaused}).Count
    $status.Text=if($s.Busy){'更新中…'}elseif($s.IntervalSeconds -eq 0){'自动刷新关闭'}elseif(-not $s.Started){'启动后自动检测'}elseif($s.NextDueUtc){'下次 '+$s.NextDueUtc.ToLocalTime().ToString('HH:mm:ss')}else{'等待手动检测'}
    $tip=if($s.IntervalSeconds -eq 0){'自动刷新已关闭。点击「刷新」或「批量检测」立即检测。'}else{'启动后自动检测一次；每轮完成后再计时。检测进行中不重复发起，休眠恢复后只刷新一次。'}
    if($paused){$tip+=[Environment]::NewLine+$paused+' 台账号认证失败，自动检测已暂停；修改账号或手动检测后恢复。'}
    $tip+=[Environment]::NewLine+'暂时不可达的服务器会逐台延长重试间隔，最长 30 分钟。'+[Environment]::NewLine+$status.Text
    $button.ToolTip=$tip;$status.ToolTip=$tip
}
