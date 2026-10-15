# Pure, read-only normalization of the 3x-ui status response already fetched by Panel-StatusCheck.
# No networking, persistence or historical interpolation belongs in this module.
# Official status fields are shared by v2.6.8 and v3.x; missing/invalid fields stay null.
# netIO is the panel's bytes/second sample; netTraffic is host-interface cumulative bytes.
# netTraffic may reset after a restart/interface change and is not a billing-month counter.
# appStats.uptime is Xray uptime, not panel uptime; appStats.threads counts Go goroutines.
$script:managerResourceFunctions=@'
function Get-ManagerResourceMember($Value,[string]$Name) {
    if($null -eq $Value){return $null}
    if($Value -is [Collections.IDictionary]){
        if($Value.Contains($Name)){return $Value[$Name]}
        return $null
    }
    $property=$Value.PSObject.Properties[$Name]
    if($property){return $property.Value}
    return $null
}
function ConvertTo-ManagerResourceNumber($Value,[double]$Maximum=[double]::MaxValue) {
    if($null -eq $Value -or $Value -is [bool] -or $Value -is [Array] -or $Value -is [Collections.IDictionary]){return $null}
    $number=[double]0
    if(-not [double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){return $null}
    if([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt $Maximum){return $null}
    return $number
}
function ConvertTo-ManagerResourceCounter($Value,[decimal]$Maximum=[decimal][uint64]::MaxValue) {
    if($null -eq $Value -or $Value -is [bool] -or $Value -is [Array] -or $Value -is [Collections.IDictionary]){return $null}
    $number=[decimal]0
    if(-not [decimal]::TryParse([string]$Value,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)){return $null}
    if($number -lt 0 -or $number -gt $Maximum){return $null}
    return $number
}
function ConvertTo-ManagerResourceUsage($Value) {
    $used=ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $Value 'current')
    $total=ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $Value 'total')
    $percent=$null
    if($null -ne $used -and $null -ne $total){
        if($used -gt $total){$used=$null}
        elseif($total -gt 0){$percent=[double](100*$used/$total)}
        # Explicit 0/0 is useful (e.g. no configured swap), but has no meaningful percentage.
    }
    return @{UsedBytes=$used;TotalBytes=$total;Percent=$percent}
}
function ConvertTo-ManagerResourceVersion($Value) {
    if($Value -isnot [string] -or $Value -notmatch '^[0-9A-Za-z][0-9A-Za-z.\-+_]{0,47}$'){return $null}
    return [string]$Value
}
function ConvertTo-ManagerResourceSnapshot {
    param($StatusObject,[DateTime]$SampledAtUtc=[DateTime]::UtcNow)
    $mem=ConvertTo-ManagerResourceUsage (Get-ManagerResourceMember $StatusObject 'mem')
    $swap=ConvertTo-ManagerResourceUsage (Get-ManagerResourceMember $StatusObject 'swap')
    $disk=ConvertTo-ManagerResourceUsage (Get-ManagerResourceMember $StatusObject 'disk')
    $netIO=Get-ManagerResourceMember $StatusObject 'netIO'
    $traffic=Get-ManagerResourceMember $StatusObject 'netTraffic'
    $app=Get-ManagerResourceMember $StatusObject 'appStats'
    $xray=Get-ManagerResourceMember $StatusObject 'xray'
    $xrayState=Get-ManagerResourceMember $xray 'state'
    if($xrayState -is [string] -and $xrayState.ToLowerInvariant() -in @('running','stop','error')){$xrayState=$xrayState.ToLowerInvariant()}else{$xrayState=$null}
    $loads=Get-ManagerResourceMember $StatusObject 'loads'
    $r=@{
        State='Unavailable';SampledAtUtc=$null;Source='3x-ui/status'
        CpuPercent=(ConvertTo-ManagerResourceNumber (Get-ManagerResourceMember $StatusObject 'cpu') 100)
        CpuCores=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $StatusObject 'cpuCores') ([int]::MaxValue))
        CpuLogicalProcessors=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $StatusObject 'logicalPro') ([int]::MaxValue))
        CpuSpeedMHz=(ConvertTo-ManagerResourceNumber (Get-ManagerResourceMember $StatusObject 'cpuSpeedMhz'))
        MemoryUsedBytes=$mem.UsedBytes;MemoryTotalBytes=$mem.TotalBytes;MemoryPercent=$mem.Percent
        SwapUsedBytes=$swap.UsedBytes;SwapTotalBytes=$swap.TotalBytes;SwapPercent=$swap.Percent
        DiskUsedBytes=$disk.UsedBytes;DiskTotalBytes=$disk.TotalBytes;DiskPercent=$disk.Percent
        UploadBytesPerSecond=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $netIO 'up'))
        DownloadBytesPerSecond=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $netIO 'down'))
        NetworkUploadBytes=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $traffic 'sent'))
        NetworkDownloadBytes=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $traffic 'recv'))
        NetworkTotalBytes=$null
        TcpConnections=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $StatusObject 'tcpCount') ([int]::MaxValue))
        UdpConnections=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $StatusObject 'udpCount') ([int]::MaxValue))
        ConnectionCount=$null
        OsUptimeSeconds=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $StatusObject 'uptime'))
        XrayUptimeSeconds=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $app 'uptime'))
        XrayState=$xrayState;XrayVersion=(ConvertTo-ManagerResourceVersion (Get-ManagerResourceMember $xray 'version'))
        PanelMemoryBytes=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $app 'mem'))
        PanelThreads=(ConvertTo-ManagerResourceCounter (Get-ManagerResourceMember $app 'threads') ([uint32]::MaxValue))
        PanelVersion=(ConvertTo-ManagerResourceVersion (Get-ManagerResourceMember $StatusObject 'panelVersion'))
        Load1=$null;Load5=$null;Load15=$null
    }
    if($loads -is [Array] -or $loads -is [Collections.IList]){
        if($loads.Count -gt 0){$r.Load1=ConvertTo-ManagerResourceNumber $loads[0]}
        if($loads.Count -gt 1){$r.Load5=ConvertTo-ManagerResourceNumber $loads[1]}
        if($loads.Count -gt 2){$r.Load15=ConvertTo-ManagerResourceNumber $loads[2]}
    }
    # Exact decimal arithmetic preserves even uint64 byte counters and their combined total.
    if($null -ne $r.NetworkUploadBytes -and $null -ne $r.NetworkDownloadBytes){$r.NetworkTotalBytes=$r.NetworkUploadBytes+$r.NetworkDownloadBytes}
    if($null -ne $r.TcpConnections -and $null -ne $r.UdpConnections){$r.ConnectionCount=$r.TcpConnections+$r.UdpConnections}
    $metrics=@($r.Keys | Where-Object {$_ -notin @('State','SampledAtUtc','Source') -and $null -ne $r[$_]})
    if($metrics.Count){$r.State='Ok';$r.SampledAtUtc=$SampledAtUtc.ToUniversalTime()}
    return $r
}
'@
. ([scriptblock]::Create($script:managerResourceFunctions))
function Get-ManagerResourceFunctionSource {return $script:managerResourceFunctions}
