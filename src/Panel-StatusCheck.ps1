# Explicit-click panel status check plus a small background-task layer.
# Nothing in this file runs a check at load time; the caller controls manual or automatic checks.
# Results stay in memory ($script:managerStatus). Nothing is written to 服务器列表.json, logs or reports.
# A configured local SSH forward may be established, as when opening the panel.
# Remote operations are limited to authentication and read-only status; no server settings are changed.
. (Join-Path $PSScriptRoot 'Panel-Resources.ps1')

$script:managerStatus=@{}
$script:managerStatusBatch=$null
$script:managerStatusLastRun=$null
$script:managerStatusTimeoutMs=8000            # per-server network budget inside the worker
$script:managerStatusHardTimeoutSeconds=45     # includes optional local tunnel setup, then the network budget
$script:managerStatusConcurrency=4
$script:managerProbeSessionCache=[hashtable]::Synchronized(@{}) # Cookies and tokens never leave this process.

function Reset-ManagerProbeSessionCache {
    param([string]$Id)
    # Invalidate without waiting on network workers. An old worker cannot publish a session after reset.
    [Threading.Monitor]::Enter($script:managerProbeSessionCache.SyncRoot)
    try{
        $keys=if($PSBoundParameters.ContainsKey('Id')){@($Id)}else{@($script:managerProbeSessionCache.Keys)}
        foreach($key in $keys){
            if($script:managerProbeSessionCache.ContainsKey($key)){
                $state=$script:managerProbeSessionCache[$key]
                $state.Invalidated=$true;$state.Authenticated=$false;$state.Cookies=$null;$state.Token=$null;$state.Referer=$null;$state.Endpoint=$null
                $script:managerProbeSessionCache.Remove($key)
            }
        }
    }finally{[Threading.Monitor]::Exit($script:managerProbeSessionCache.SyncRoot)}
}
function Get-ManagerProbeSessionFingerprint($Spec) {
    # JSON arrays avoid delimiter collisions. Only the hash is kept in the cache.
    $bytes=$null;$digest=$null;$hash=[Security.Cryptography.SHA256]::Create();$text=$null
    try{
        $route=if($Spec.TunnelEntry){$Spec.TunnelEntry.Tunnel}else{$null}
        $text=@([string]$Spec.Id,[string]$Spec.Url,[string]$Spec.Username,[string]$Spec.Password,[string]$route.Host,[string]$route.Port,[string]$route.User,[string]$route.LocalPort,[string]$route.RemotePort) | ConvertTo-Json -Compress
        $bytes=[Text.Encoding]::UTF8.GetBytes($text);$digest=$hash.ComputeHash($bytes)
        return ([BitConverter]::ToString($digest).Replace('-','').ToLowerInvariant())
    }finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)};if($digest){[Array]::Clear($digest,0,$digest.Length)};$text=$null;$hash.Dispose()}
}
function Get-ManagerProbeSessionState($Spec) {
    $fingerprint=Get-ManagerProbeSessionFingerprint $Spec
    [Threading.Monitor]::Enter($script:managerProbeSessionCache.SyncRoot)
    try{
        $state=$script:managerProbeSessionCache[$Spec.Id]
        if(-not $state -or $state.Invalidated -or $state.Fingerprint -ne $fingerprint){
            if($state){$state.Invalidated=$true;$state.Authenticated=$false;$state.Cookies=$null;$state.Token=$null}
            $state=[hashtable]::Synchronized(@{Fingerprint=$fingerprint;Cookies=$null;Token=$null;Referer=$null;Endpoint=$null;Authenticated=$false;Invalidated=$false;SyncLock=[object]::new()})
            $script:managerProbeSessionCache[$Spec.Id]=$state
        }
        $Spec.SessionFingerprint=$fingerprint
        return $state
    }finally{[Threading.Monitor]::Exit($script:managerProbeSessionCache.SyncRoot)}
}

# ---------------------------------------------------------------------------------------------
# Long-task layer (generic): RunspacePool workers, a DispatcherTimer on the UI thread polls for
# finished/timed-out jobs and invokes the callbacks there (marshal-back to the WPF dispatcher).
# Workers never touch WPF objects; callbacks never block on unfinished work.
# ---------------------------------------------------------------------------------------------
function Start-ManagerBackgroundBatch {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Items,
        [Parameter(Mandatory=$true)][string]$WorkerScript,
        [int]$Concurrency=4,
        [int]$TimeoutSeconds=20,
        [scriptblock]$OnItemDone,
        [scriptblock]$OnProgress,
        [scriptblock]$OnComplete
    )
    $size=[Math]::Max(1,[Math]::Min($Concurrency,$Items.Count))
    $pool=[runspacefactory]::CreateRunspacePool($size,$size)
    $batch=[pscustomobject]@{
        Pool=$pool;OpenHandle=$null;Queue=[Collections.Queue]::new()
        Running=[Collections.ArrayList]::new();Draining=[Collections.ArrayList]::new()
        Total=$Items.Count;Done=0;Concurrency=$size;TimeoutSeconds=$TimeoutSeconds;WorkerScript=$WorkerScript
        OnItemDone=$OnItemDone;OnProgress=$OnProgress;OnComplete=$OnComplete
        Cancelled=$false;Completed=$false;Closed=$false;Fault=$null;CallbackErrors=0;Timer=$null
    }
    foreach($item in $Items){$batch.Queue.Enqueue($item)}
    # Opening runspaces can take a moment; do it asynchronously so the click returns at once.
    $batch.OpenHandle=$pool.BeginOpen($null,$null)
    $timer=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
    $timer.Interval=[TimeSpan]::FromMilliseconds(100)
    $timer.Tag=$batch
    $timer.Add_Tick({param($sender,$eventArgs) Step-ManagerBackgroundBatch $sender.Tag})
    $batch.Timer=$timer
    $timer.Start()
    if($OnProgress){try{& $OnProgress $batch}catch{$batch.CallbackErrors++}}
    return $batch
}
function Complete-ManagerBatchItem($Batch,$Item,$Result,[string]$Outcome) {
    $Batch.Done++
    if($Batch.OnItemDone){try{& $Batch.OnItemDone $Item $Result $Outcome}catch{$Batch.CallbackErrors++}}
    if($Batch.OnProgress){try{& $Batch.OnProgress $Batch}catch{$Batch.CallbackErrors++}}
}
function Stop-ManagerBatchJob($Batch,$Job) {
    # BeginStop never blocks the UI thread; the job is disposed once its pipeline has really ended.
    try{[void]$Job.PowerShell.BeginStop($null,$null)}catch{}
    [void]$Batch.Draining.Add($Job)
}
function Step-ManagerBackgroundBatch($Batch) {
    if($Batch.Closed){return}
    try{
        if($Batch.OpenHandle){
            if(-not $Batch.OpenHandle.IsCompleted){return}
            try{$Batch.Pool.EndOpen($Batch.OpenHandle)}catch{$Batch.Fault='后台检测无法启动。'}
            $Batch.OpenHandle=$null
            if($Batch.Fault){while($Batch.Queue.Count){Complete-ManagerBatchItem $Batch $Batch.Queue.Dequeue() $null 'Failed'}}
        }
        foreach($job in @($Batch.Running)){
            if($job.Handle.IsCompleted){
                [void]$Batch.Running.Remove($job)
                $result=$null;$outcome='Completed'
                try{
                    $output=$job.PowerShell.EndInvoke($job.Handle)
                    if($output.Count){$result=$output[$output.Count-1]}else{$outcome='Failed'}
                }catch{$outcome='Failed'}
                try{$job.PowerShell.Dispose()}catch{}
                Complete-ManagerBatchItem $Batch $job.Item $result $outcome
            }elseif(([DateTime]::UtcNow-$job.Started).TotalSeconds -gt $Batch.TimeoutSeconds){
                [void]$Batch.Running.Remove($job)
                Stop-ManagerBatchJob $Batch $job
                Complete-ManagerBatchItem $Batch $job.Item $null 'TimedOut'
            }
        }
        foreach($job in @($Batch.Draining)){
            if($job.Handle.IsCompleted){
                try{[void]$job.PowerShell.EndInvoke($job.Handle)}catch{}
                try{$job.PowerShell.Dispose()}catch{}
                [void]$Batch.Draining.Remove($job)
            }
        }
        while(-not $Batch.Cancelled -and -not $Batch.Fault -and -not $Batch.OpenHandle -and $Batch.Queue.Count -and $Batch.Running.Count -lt $Batch.Concurrency){
            $item=$Batch.Queue.Dequeue()
            $ps=[powershell]::Create()
            $ps.RunspacePool=$Batch.Pool
            [void]$ps.AddScript($Batch.WorkerScript).AddArgument($item)
            [void]$Batch.Running.Add([pscustomobject]@{Item=$item;PowerShell=$ps;Handle=$ps.BeginInvoke();Started=[DateTime]::UtcNow})
        }
        if(-not $Batch.Completed -and $Batch.Running.Count -eq 0 -and $Batch.Queue.Count -eq 0){
            $Batch.Completed=$true
            if($Batch.OnComplete){try{& $Batch.OnComplete $Batch}catch{$Batch.CallbackErrors++}}
        }
        if($Batch.Completed -and $Batch.Draining.Count -eq 0 -and -not $Batch.OpenHandle){
            $Batch.Timer.Stop();$Batch.Closed=$true
            try{$Batch.Pool.Close()}catch{}
            try{$Batch.Pool.Dispose()}catch{}
        }
    }catch{
        # Never let a tick exception reach the dispatcher; stop polling and release the pool.
        $Batch.Fault='后台检测意外停止。'
        Close-ManagerBackgroundBatch $Batch
    }
}
function Stop-ManagerBackgroundBatch($Batch) {
    if(-not $Batch -or $Batch.Completed){return}
    $Batch.Cancelled=$true
    foreach($job in @($Batch.Running)){
        [void]$Batch.Running.Remove($job)
        Stop-ManagerBatchJob $Batch $job
        Complete-ManagerBatchItem $Batch $job.Item $null 'Cancelled'
    }
    while($Batch.Queue.Count){Complete-ManagerBatchItem $Batch $Batch.Queue.Dequeue() $null 'Cancelled'}
    Step-ManagerBackgroundBatch $Batch
}
function Close-ManagerBackgroundBatch($Batch) {
    # Non-blocking shutdown used when the window closes or the batch faults.
    if(-not $Batch -or $Batch.Closed){return}
    $Batch.OnItemDone=$null;$Batch.OnProgress=$null;$Batch.OnComplete=$null
    $Batch.Cancelled=$true;$Batch.Completed=$true;$Batch.Closed=$true
    try{$Batch.Timer.Stop()}catch{}
    foreach($job in @($Batch.Running)+@($Batch.Draining)){try{[void]$job.PowerShell.BeginStop($null,$null)}catch{}}
    $Batch.Queue.Clear()
    try{[void]$Batch.Pool.BeginClose($null,$null)}catch{}
}

# ---------------------------------------------------------------------------------------------
# Status-check specifics (UI thread side): endpoints and per-server job description.
# ---------------------------------------------------------------------------------------------
function Get-ManagerPanelEndpoints([Uri]$Uri) {
    # 3x-ui serves pages under <webBasePath>/panel/... and login at <webBasePath>/login.
    $path=$Uri.AbsolutePath
    $match=[regex]::Match($path,'^(.*?)/panel(?:/.*)?$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $base=if($match.Success){$match.Groups[1].Value}else{$path.TrimEnd('/')}
    $root=$Uri.GetLeftPart([UriPartial]::Authority)+$base
    return [pscustomobject]@{
        LoginPage=$root+'/'
        Login=$root+'/login'
        Csrf=$root+'/csrf-token'
        Status=@(@{Method='GET';Uri=$root+'/panel/api/server/status'},@{Method='POST';Uri=$root+'/server/status'})
    }
}
function New-ManagerStatusSpec($Entry) {
    $spec=@{
        Id=[string]$Entry.Id;Kind='Direct';Url=[string]$Entry.Url;UrlValid=$false;Host=$null;Port=0
        LoginUri=$null;LoginPageUri=$null;CsrfUri=$null;StatusUris=@();PlainHttpRemote=$false;Username=$null;Password=$null
        LatencyHost=$null;LatencyPort=0;LatencyKind='TcpConnect'
        TimeoutMs=$script:managerStatusTimeoutMs;Workspace=$script:workspace
        TunnelEntry=$null;TunnelStateFile=$null;TunnelFunction=$null;TunnelFunctions=$null
        Automatic=$false;SessionState=$null;SessionFingerprint=$null
    }
    $uri=$null
    if([Uri]::TryCreate($spec.Url,[UriKind]::Absolute,[ref]$uri) -and ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https') -and -not $uri.UserInfo){
        $spec.UrlValid=$true;$spec.Host=$uri.DnsSafeHost;$spec.Port=$uri.Port
        $spec.LatencyHost=$spec.Host;$spec.LatencyPort=$spec.Port
        $endpoints=Get-ManagerPanelEndpoints $uri
        $spec.LoginUri=$endpoints.Login;$spec.LoginPageUri=$endpoints.LoginPage;$spec.CsrfUri=$endpoints.Csrf;$spec.StatusUris=$endpoints.Status
        $spec.PlainHttpRemote=($uri.Scheme -eq 'http' -and -not $Entry.Tunnel)
    }
    if($Entry.Tunnel){
        $spec.Kind='Tunnel'
        # Same rule as Open-ManagedPanel: a tunnel panel is only reachable through its fixed local port.
        if(-not ($spec.UrlValid -and $uri.Scheme -eq 'http' -and $uri.Host -eq '127.0.0.1' -and $uri.Port -eq [int]$Entry.Tunnel.LocalPort)){$spec.UrlValid=$false}
        $spec.TunnelEntry=[pscustomobject]@{Id=[string]$Entry.Id;Folder=[string]$Entry.Folder;Tunnel=$Entry.Tunnel}
        # Measure the remote SSH connection, never the sub-millisecond loopback forwarding port.
        $spec.LatencyHost=[string]$Entry.Tunnel.Host;$spec.LatencyPort=[int]$Entry.Tunnel.Port;$spec.LatencyKind='SshTcpConnect'
        $spec.TunnelStateFile=Join-Path $script:workspace ([string]$Entry.Folder+'\凭据\隧道运行\process.json')
        $tunnelCheck=Get-Command Test-PanelTunnelProcess -CommandType Function -ErrorAction SilentlyContinue
        if($tunnelCheck){$spec.TunnelFunction=$tunnelCheck.ScriptBlock.ToString()}
        if(Get-Command Get-PanelTunnelFunctionSource -CommandType Function -ErrorAction SilentlyContinue){$spec.TunnelFunctions=Get-PanelTunnelFunctionSource}
    }
    # Credentials only live in this in-memory spec; the worker and the completion callback clear them.
    $state=Get-ManagerAccountState -Entry $Entry
    if($state.HasAccount){$spec.Username=[string]$state.Account.username;$spec.Password=[string]$state.Account.password}
    $state=$null
    $spec.SessionState=Get-ManagerProbeSessionState $spec
    return $spec
}

# ---------------------------------------------------------------------------------------------
# Worker (runs inside a pool runspace; has no access to app functions or WPF).
# ---------------------------------------------------------------------------------------------
$script:managerProbeTlsSource=@'
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
namespace PanelManagerProbe {
    public sealed class TlsCapture {
        public bool AllowUntrusted;
        public bool Called;
        public SslPolicyErrors Errors = SslPolicyErrors.None;
        public RemoteCertificateValidationCallback Callback { get { return new RemoteCertificateValidationCallback(this.Validate); } }
        private bool Validate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors errors) {
            Called = true; Errors = errors;
            return errors == SslPolicyErrors.None || AllowUntrusted;
        }
    }
}
'@
$script:managerProbeFunctions=@'
function Get-ProbeInnerException($Exception) {
    $ex=$Exception
    while($ex -and ($ex -is [Management.Automation.MethodInvocationException] -or $ex -is [Management.Automation.RuntimeException] -or $ex -is [AggregateException]) -and $ex.InnerException){$ex=$ex.InnerException}
    return $ex
}
function Convert-ProbeError($Exception) {
    # Fixed Chinese messages only: never pass raw exception text (it may contain host or path).
    $ex=Get-ProbeInnerException $Exception
    if($ex -is [Net.WebException]){
        switch([string]$ex.Status){
            'Timeout' {return @{Kind='Timeout';Text='连接超时'}}
            'TrustFailure' {return @{Kind='Trust';Text='证书不受信任'}}
            'SecureChannelFailure' {return @{Kind='Tls';Text='TLS 握手失败'}}
            'NameResolutionFailure' {return @{Kind='Dns';Text='无法解析地址'}}
            'ConnectFailure' {
                $inner=Get-ProbeInnerException $ex.InnerException
                if($inner -is [Net.Sockets.SocketException]){return (Convert-ProbeError $inner)}
                return @{Kind='Connect';Text='无法连接'}
            }
            'ReceiveFailure' {return @{Kind='Closed';Text='连接被中断'}}
            'ConnectionClosed' {return @{Kind='Closed';Text='连接被中断'}}
            'KeepAliveFailure' {return @{Kind='Closed';Text='连接被中断'}}
            default {return @{Kind='Network';Text='网络错误'}}
        }
    }
    if($ex -is [Net.Sockets.SocketException]){
        switch([string]$ex.SocketErrorCode){
            'ConnectionRefused' {return @{Kind='Refused';Text='拒绝连接'}}
            'TimedOut' {return @{Kind='Timeout';Text='连接超时'}}
            'HostNotFound' {return @{Kind='Dns';Text='无法解析地址'}}
            'NoData' {return @{Kind='Dns';Text='无法解析地址'}}
            'NetworkUnreachable' {return @{Kind='Unreachable';Text='网络不可达'}}
            'HostUnreachable' {return @{Kind='Unreachable';Text='网络不可达'}}
            default {return @{Kind='Connect';Text='无法连接'}}
        }
    }
    if($ex -is [TimeoutException]){return @{Kind='Timeout';Text='连接超时'}}
    if($ex -is [IO.IOException]){return @{Kind='Closed';Text='连接被中断'}}
    return @{Kind='Other';Text='网络错误'}
}
function Enable-ProbeTls([string]$Source) {
    if(-not ('PanelManagerProbe.TlsCapture' -as [type])){
        $mutex=[Threading.Mutex]::new($false,'Local\PanelManagerProbeTls-'+$PID)
        $owned=$false
        try{
            try{$owned=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$owned=$true}
            if(-not ('PanelManagerProbe.TlsCapture' -as [type])){Add-Type -TypeDefinition $Source}
        }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
    }
    # Old .NET defaults lack TLS 1.2; only add it when the process is not on SystemDefault (0).
    $protocols=[Net.ServicePointManager]::SecurityProtocol
    if([int]$protocols -ne 0 -and -not ($protocols -band [Net.SecurityProtocolType]::Tls12)){
        [Net.ServicePointManager]::SecurityProtocol=$protocols -bor [Net.SecurityProtocolType]::Tls12
    }
}
function Get-ProbeRemaining([int]$Cap) {
    $left=[int]($script:probeDeadline-[DateTime]::UtcNow).TotalMilliseconds
    return [Math]::Min($Cap,$left)
}
function Test-ProbeTcp([string]$HostName,[int]$Port,[int]$TimeoutMs) {
    if($TimeoutMs -le 0){return @{Ok=$false;Kind='Timeout';Text='连接超时'}}
    $client=[Net.Sockets.TcpClient]::new()
    $watch=[Diagnostics.Stopwatch]::StartNew();$waitHandle=$null
    try{
        $async=$client.BeginConnect($HostName,$Port,$null,$null)
        $waitHandle=$async.AsyncWaitHandle
        if(-not $waitHandle.WaitOne($TimeoutMs)){return @{Ok=$false;Kind='Timeout';Text='连接超时'}}
        $client.EndConnect($async)
        return @{Ok=$true;Ms=$watch.Elapsed.TotalMilliseconds}
    }catch{
        $e=Convert-ProbeError $_.Exception
        return @{Ok=$false;Kind=$e.Kind;Text=$e.Text}
    }finally{$watch.Stop();$client.Close();if($waitHandle){$waitHandle.Close()}}
}
function Measure-ProbeLatency([string]$HostName,[int]$Port) {
    $samples=[Collections.ArrayList]::new();$first=$null
    for($i=0;$i -lt 3;$i++){
        $cap=if($i -eq 0){3000}else{1200}
        $left=Get-ProbeRemaining $cap
        if($left -le 0){break}
        $tcp=Test-ProbeTcp $HostName $Port $left
        if($i -eq 0){$first=$tcp}
        if($tcp.Ok){[void]$samples.Add([double]$tcp.Ms)}elseif($i -eq 0){break}
    }
    $median=$null
    if($samples.Count){
        $ordered=@($samples | Sort-Object)
        $middle=[int][Math]::Floor($ordered.Count/2)
        $value=if($ordered.Count%2){$ordered[$middle]}else{($ordered[$middle-1]+$ordered[$middle])/2}
        $median=[int][Math]::Round($value)
    }
    return @{Ms=$median;Samples=@($samples);First=$first}
}
function Invoke-ProbeRequest([string]$Method,[string]$Uri,[string]$Body,[int]$TimeoutMs,$Cookies,[bool]$AllowUntrusted,[bool]$ReadBody,[string]$ContentType,[string]$Referer,[string]$CsrfToken) {
    if($TimeoutMs -le 0){return @{Ok=$false;Kind='Timeout';Text='连接超时'}}
    if($script:probeMetrics){$script:probeMetrics.HttpRequests++;if($Method -eq 'POST' -and $Uri -eq $script:probeLoginUri){$script:probeMetrics.LoginRequests++}}
    $tls=[PanelManagerProbe.TlsCapture]::new();$tls.AllowUntrusted=$AllowUntrusted
    $request=[Net.WebRequest]::Create($Uri)
    $request.Method=$Method;$request.Timeout=$TimeoutMs;$request.ReadWriteTimeout=$TimeoutMs
    $request.AllowAutoRedirect=$false;$request.KeepAlive=$false
    $request.Proxy=$null   # direct connection from this PC, same path as the TCP check
    $request.UserAgent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36'
    if($Referer){$request.Referer=$Referer}
    if($Method -eq 'POST'){$request.Headers['Origin']=([Uri]$Uri).GetLeftPart([UriPartial]::Authority)}
    if($CsrfToken){$request.Headers['X-CSRF-Token']=$CsrfToken}
    $request.Headers['X-Requested-With']='XMLHttpRequest'
    $request.Accept='application/json, text/html;q=0.9, */*;q=0.5'
    $request.ServerCertificateValidationCallback=$tls.Callback
    $request.ServicePoint.Expect100Continue=$false
    if($Cookies){$request.CookieContainer=$Cookies}
    $response=$null;$bytes=$null
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        if($Method -eq 'POST'){
            $bytes=[Text.Encoding]::UTF8.GetBytes([string]$Body)
            if(-not $ContentType){$ContentType='application/x-www-form-urlencoded; charset=UTF-8'}
            $request.ContentType=$ContentType
            $request.ContentLength=$bytes.Length
            $stream=$request.GetRequestStream()
            try{$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Close()}
        }
        try{$response=$request.GetResponse()}
        catch{
            $inner=Get-ProbeInnerException $_.Exception
            if($inner -is [Net.WebException] -and $inner.Response){$response=$inner.Response}else{throw $inner}
        }
        $ms=[int]$watch.ElapsedMilliseconds
        $text=$null
        if($ReadBody){
            $reader=[IO.StreamReader]::new($response.GetResponseStream(),[Text.Encoding]::UTF8)
            # A login page may include embedded assets before its meta token. Bound the body without truncating at 64 KiB.
            try{$buffer=New-Object char[] 1048576;$count=$reader.ReadBlock($buffer,0,$buffer.Length);$text=[string]::new($buffer,0,$count)}finally{$reader.Dispose()}
        }
        return @{Ok=$true;Status=[int]$response.StatusCode;Ms=$ms;Body=$text;Location=[string]$response.Headers['Location'];Uri=$Uri}
    }catch{
        $e=Convert-ProbeError $_.Exception
        if(-not $AllowUntrusted -and $tls.Called -and [string]$tls.Errors -ne 'None'){$e=@{Kind='Trust';Text='证书不受信任'}}
        return @{Ok=$false;Kind=$e.Kind;Text=$e.Text}
    }finally{
        if($response){$response.Close()}
        if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}
    }
}
function Invoke-ProbeGet([string]$Uri,$Cookies,[bool]$AllowUntrusted) {
    # Never follow a page redirect to another origin or forward credentials in a redirected POST.
    $origin=([Uri]$Uri).GetLeftPart([UriPartial]::Authority)
    $current=$Uri;$totalMs=0
    for($i=0;$i -lt 4;$i++){
        $get=Invoke-ProbeRequest 'GET' $current $null (Get-ProbeRemaining 4000) $Cookies $AllowUntrusted $true $null $current $null
        if(-not $get.Ok){return $get}
        $totalMs+=$get.Ms
        if($get.Status -notin @(301,302,303,307,308) -or -not $get.Location){$get.Ms=$totalMs;return $get}
        $next=$null
        if(-not [Uri]::TryCreate([Uri]$current,[string]$get.Location,[ref]$next) -or $next.UserInfo -or $next.GetLeftPart([UriPartial]::Authority) -ne $origin){
            return @{Ok=$false;Kind='Redirect';Text='面板跳转到其他地址，已停止检测'}
        }
        $current=$next.AbsoluteUri
    }
    return @{Ok=$false;Kind='Redirect';Text='面板重定向次数过多'}
}
function Get-ProbeSafeToken([string]$Token) {
    if($Token -and $Token.Length -le 512 -and $Token -notmatch '[\r\n]'){return $Token}
    return $null
}
function Get-ProbeHtmlCsrf([string]$Html) {
    foreach($meta in [regex]::Matches($Html,'(?is)<meta\b[^>]*>')){
        $attributes=@{}
        foreach($a in [regex]::Matches($meta.Value,'(?is)\b(name|content)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))')){
            $value=if($a.Groups[2].Success){$a.Groups[2].Value}elseif($a.Groups[3].Success){$a.Groups[3].Value}else{$a.Groups[4].Value}
            $attributes[$a.Groups[1].Value.ToLowerInvariant()]=[Net.WebUtility]::HtmlDecode($value)
        }
        if($attributes.name -eq 'csrf-token'){return (Get-ProbeSafeToken ([string]$attributes.content))}
    }
    return $null
}
function Get-ProbeCookieCsrf($Cookies,[string]$Uri) {
    foreach($cookie in $Cookies.GetCookies([Uri]$Uri)){
        if($cookie.Name -in @('XSRF-TOKEN','csrf-token','csrftoken')){
            return (Get-ProbeSafeToken ([Uri]::UnescapeDataString($cookie.Value)))
        }
    }
    return $null
}
function Initialize-ProbeSession($Spec,$Cookies,[bool]$AllowUntrusted,$Initial,[bool]$Force) {
    $token=$null;$referer=$Spec.Url
    if(-not $Force -and $Initial -and $Initial.Ok){
        $referer=$Initial.Uri;$token=Get-ProbeHtmlCsrf ([string]$Initial.Body)
        if(-not $token){$token=Get-ProbeCookieCsrf $Cookies $Initial.Uri}
    }
    if($token){return @{Token=$token;Referer=$referer}}
    # Older releases render the token into the login page; visiting /panel/ may only issue a redirect.
    if($Spec.LoginPageUri -and ($Force -or -not $Initial -or $Initial.Uri -ne $Spec.LoginPageUri)){
        $page=Invoke-ProbeGet $Spec.LoginPageUri $Cookies $AllowUntrusted
        if($page.Ok -and $page.Status -eq 200){
            $referer=$page.Uri;$token=Get-ProbeHtmlCsrf ([string]$page.Body)
            if(-not $token){$token=Get-ProbeCookieCsrf $Cookies $page.Uri}
        }
    }
    # Recent SPA releases expose the same session token via a public, read-only endpoint.
    if(-not $token -and $Spec.CsrfUri){
        $csrf=Invoke-ProbeRequest 'GET' $Spec.CsrfUri $null (Get-ProbeRemaining 3000) $Cookies $AllowUntrusted $true $null $referer $null
        if($csrf.Ok -and $csrf.Status -eq 200){
            try{$json=$csrf.Body | ConvertFrom-Json;if($json.success -eq $true -and $json.obj -is [string]){$token=Get-ProbeSafeToken $json.obj}}catch{}
        }
    }
    return @{Token=$token;Referer=$referer}
}
function Format-ProbeTrafficBytes([double]$Bytes) {
    $units=@('B','KiB','MiB','GiB','TiB','PiB');$value=$Bytes;$i=0
    while($value -ge 1024 -and $i -lt ($units.Length-1)){$value/=1024;$i++}
    return ($value.ToString('0.##',[Globalization.CultureInfo]::InvariantCulture)+' '+$units[$i])
}
function Convert-ProbeTraffic($Obj) {
    # The status API's netTraffic counters are host network-interface byte totals, not Xray quotas or monthly billing.
    $unavailable=@{State='Unavailable';UploadBytes=$null;DownloadBytes=$null;TotalBytes=$null;Source='netTraffic';Label='累计流量';Text='统计暂不可用'}
    if(-not $Obj -or -not $Obj.netTraffic){return $unavailable}
    $up=[decimal]0;$down=[decimal]0
    $style=[Globalization.NumberStyles]::Integer;$culture=[Globalization.CultureInfo]::InvariantCulture
    if(-not [decimal]::TryParse([string]$Obj.netTraffic.sent,$style,$culture,[ref]$up) -or -not [decimal]::TryParse([string]$Obj.netTraffic.recv,$style,$culture,[ref]$down) -or $up -lt 0 -or $down -lt 0 -or $up -gt [decimal][uint64]::MaxValue -or $down -gt [decimal][uint64]::MaxValue){return $unavailable}
    $total=$up+$down
    return @{State='Ok';UploadBytes=$up;DownloadBytes=$down;TotalBytes=$total;Source='netTraffic';Label='累计流量';Text=(Format-ProbeTrafficBytes ([double]$total))}
}
function Test-ProbeTunnel($Spec) {
    # Read-only: looks at the existing tunnel state file, process and listener. Never starts ssh.
    $pidValue=0
    try{
        if($Spec.TunnelStateFile -and [IO.File]::Exists($Spec.TunnelStateFile)){
            $pidValue=[int](([IO.File]::ReadAllText($Spec.TunnelStateFile) | ConvertFrom-Json).ProcessId)
        }
    }catch{$pidValue=0}
    if($pidValue -gt 0 -and $Spec.TunnelFunction){
        try{
            Set-Item -Path function:Test-PanelTunnelProcess -Value ([scriptblock]::Create($Spec.TunnelFunction))
            if(Test-PanelTunnelProcess $Spec.TunnelEntry $pidValue){return @{State='Ok';Text='隧道已建立'}}
        }catch{}
    }
    $port=[int]$Spec.TunnelEntry.Tunnel.LocalPort
    $listening=@([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object {$_.Port -eq $port}).Count
    if($listening){return @{State='Fail';Text='隧道端口被其他程序占用'}}
    return @{State='Fail';Text='隧道未建立'}
}
function Clear-ProbeCachedSession($State) {
    if($State){$State.Authenticated=$false;$State.Cookies=$null;$State.Token=$null;$State.Referer=$null;$State.Endpoint=$null}
}
function Save-ProbeCachedSession($Spec,$Cookies,$Session,$Endpoint) {
    $state=$Spec.SessionState
    if($state -and -not $state.Invalidated -and $state.Fingerprint -eq $Spec.SessionFingerprint){
        $state.Cookies=$Cookies;$state.Token=$Session.Token;$state.Referer=$Session.Referer
        $state.Endpoint=@{Method=[string]$Endpoint.Method;Uri=[string]$Endpoint.Uri};$state.Authenticated=$true
        # A reset can race the assignments; it must always win.
        if($state.Invalidated){Clear-ProbeCachedSession $state}
    }
}
function Invoke-ProbeStatus($Spec,$Cookies,$Session,[bool]$AllowUntrusted,$PreferredEndpoint) {
    $endpoints=@()
    if($PreferredEndpoint){$endpoints+=@($PreferredEndpoint)}
    foreach($endpoint in @($Spec.StatusUris)){
        if(-not $PreferredEndpoint -or $endpoint.Uri -ne $PreferredEndpoint.Uri -or $endpoint.Method -ne $PreferredEndpoint.Method){$endpoints+=@($endpoint)}
    }
    foreach($endpoint in $endpoints){
        $left=Get-ProbeRemaining 3000
        if($left -le 0){return @{Ok=$false;NetworkFailed=$true;Error=@{Text='连接超时';Kind='Timeout'}}}
        $status=Invoke-ProbeRequest $endpoint.Method $endpoint.Uri '' $left $Cookies $AllowUntrusted $true $null $Session.Referer $Session.Token
        if(-not $status.Ok){return @{Ok=$false;NetworkFailed=$true;Error=$status}}
        if($status.Status -in @(401,403,301,302,303,307,308)){return @{Ok=$false;SessionExpired=$true;Response=$status}}
        if($status.Status -ne 200){continue}
        $data=$null;try{$data=$status.Body | ConvertFrom-Json}catch{$data=$null}
        if($data -and $data.success -eq $true -and $data.obj){return @{Ok=$true;Response=$status;Data=$data;Endpoint=$endpoint}}
        # A login HTML page, malformed JSON or success=false is an expired session, not valid cached data.
        return @{Ok=$false;SessionExpired=$true;Response=$status}
    }
    return @{Ok=$false;Unavailable=$true}
}
function Set-ProbeStatusSnapshot($Result,$Data) {
    if($Data.obj.xray){
        $state=([string]$Data.obj.xray.state).ToLowerInvariant()
        if($state -notin @('running','stop','error')){$state='unknown'}
        $version=[regex]::Replace([string]$Data.obj.xray.version,'[^0-9A-Za-z\.\-]','')
        if($version.Length -gt 24){$version=$version.Substring(0,24)}
        $Result.Xray=@{State=$state;Version=$version}
    }
    $Result.Traffic=Convert-ProbeTraffic $Data.obj
    # Reuse the authenticated status payload: resource monitoring adds no HTTP request or login.
    $Result.Resources=ConvertTo-ManagerResourceSnapshot $Data.obj
}
function Invoke-PanelProbe($Spec,[string]$TlsSource) {
    $r=@{
        Id=$Spec.Id;HttpMs=$null;HttpStatus=$null;Xray=$null;LatencyMs=$null;LatencyKind=$Spec.LatencyKind;LatencySamples=@()
        AuthRejected=$false;NetworkFailed=$false;SessionReused=$false
        Metrics=@{HttpRequests=0;LoginRequests=0;SessionReused=$false}
        Resources=(ConvertTo-ManagerResourceSnapshot $null)
        Traffic=@{State='Skipped';UploadBytes=$null;DownloadBytes=$null;TotalBytes=$null;Source='netTraffic';Label='累计流量';Text='检测后显示'}
        Tunnel=@{State='Skipped';Text='直连面板，不使用 SSH 隧道'}
        Http=@{State='Skipped';Text='未检测'};Login=@{State='Skipped';Text='未检测'}
    }
    $cache=$Spec.SessionState;$cacheLocked=$false
    $script:probeMetrics=$r.Metrics;$script:probeLoginUri=$Spec.LoginUri
    try{
        if($cache){
            $cacheLocked=[Threading.Monitor]::TryEnter($cache.SyncLock)
            if(-not $cacheLocked){$r.Http=@{State='Skipped';Text='此服务器正在检测，已跳过重复请求'};return $r}
        }
        Enable-ProbeTls $TlsSource
        if(-not $Spec.UrlValid){
            $r.Http=@{State='Fail';Text='面板地址格式无效'};$r.Login=@{State='Skipped';Text='面板地址无效，已跳过'}
            return $r
        }
        if($Spec.Kind -eq 'Tunnel'){
            $r.Tunnel=Test-ProbeTunnel $Spec
            if($r.Tunnel.State -ne 'Ok' -and $Spec.TunnelFunctions){
                # Reuse the exact local forwarding workflow used by the panel button, off the UI thread.
                try{
                    $script:workspace=[string]$Spec.Workspace
                    . ([scriptblock]::Create($Spec.TunnelFunctions))
                    Ensure-PanelTunnel $Spec.TunnelEntry | Out-Null
                    $r.Tunnel=Test-ProbeTunnel $Spec
                }catch{$r.Tunnel=@{State='Fail';Text='隧道建立失败，请检查本机密钥、主机公钥或端口'}}
            }
            if($r.Tunnel.State -ne 'Ok'){
                $r.Http=@{State='Skipped';Text='隧道未建立，已跳过'};$r.Login=@{State='Skipped';Text='隧道未建立，已跳过'}
                return $r
            }
        }
        $script:probeDeadline=[DateTime]::UtcNow.AddMilliseconds([int]$Spec.TimeoutMs)
        $latencyHost=if($Spec.LatencyHost){$Spec.LatencyHost}else{$Spec.Host}
        $latencyPort=if($Spec.LatencyPort){$Spec.LatencyPort}else{$Spec.Port}
        $latency=Measure-ProbeLatency $latencyHost $latencyPort
        $r.LatencyMs=$latency.Ms;$r.LatencySamples=$latency.Samples
        if($Spec.Kind -ne 'Tunnel' -and -not $latency.First.Ok){
            $r.NetworkFailed=$true
            $r.Http=@{State='Fail';Text=$latency.First.Text};$r.Login=@{State='Skipped';Text='面板不可达，已跳过'}
            return $r
        }
        if($cache -and -not $cache.Invalidated -and $cache.Authenticated -and $cache.Fingerprint -eq $Spec.SessionFingerprint -and $cache.Cookies -and $Spec.Username -and $Spec.Password -and -not $Spec.PlainHttpRemote){
            $cookies=$cache.Cookies;$session=@{Token=$cache.Token;Referer=$cache.Referer}
            $cachedStatus=Invoke-ProbeStatus $Spec $cookies $session $false $cache.Endpoint
            if($cachedStatus.Ok){
                $r.HttpMs=$cachedStatus.Response.Ms;$r.HttpStatus=$cachedStatus.Response.Status
                $r.Http=@{State='Ok';Text='HTTP 可达（会话状态接口正常）'};$r.Login=@{State='Ok';Text='面板登录正常（复用会话）'}
                $r.SessionReused=$true;Set-ProbeStatusSnapshot $r $cachedStatus.Data
                return $r
            }
            if($cachedStatus.NetworkFailed){
                # Do not turn certificate or network failure into a successful check or retry authentication.
                Clear-ProbeCachedSession $cache;$r.NetworkFailed=$true
                $r.Http=@{State='Fail';Text=$cachedStatus.Error.Text};$r.Login=@{State='Skipped';Text='状态接口不可达，已跳过重新登录'}
                return $r
            }
            if(-not $cachedStatus.SessionExpired){
                $r.Http=@{State='Warn';Text='状态接口暂不可用'};$r.Login=@{State='Ok';Text='登录会话已保留'}
                $r.Traffic=@{State='Unavailable';UploadBytes=$null;DownloadBytes=$null;TotalBytes=$null;Source='netTraffic';Label='累计流量';Text='统计暂不可用'}
                return $r
            }
            # Session expiry triggers exactly one new bootstrap/authentication flow.
            Clear-ProbeCachedSession $cache;$cookies=$null;$session=$null
        }
        $certUntrusted=$false
        $cookies=[Net.CookieContainer]::new()
        $get=Invoke-ProbeGet $Spec.Url $cookies $false
        if(-not $get.Ok -and $get.Kind -eq 'Trust'){
            # Retry reachability while accepting the certificate. Login still runs for these panels; a plain-HTTP remote never gets the password.
            $certUntrusted=$true
            $get=Invoke-ProbeGet $Spec.Url $cookies $true
        }
        if(-not $get.Ok){
            $r.NetworkFailed=$true
            $r.Http=@{State='Fail';Text=$get.Text};$r.Login=@{State='Skipped';Text='面板不可达，已跳过'}
            return $r
        }
        $r.HttpMs=$get.Ms;$r.HttpStatus=$get.Status
        if($certUntrusted){$r.Http=@{State='Warn';Text='可达，但证书不受信任'}}
        elseif($get.Status -ge 400){$r.Http=@{State='Warn';Text=('可达，面板返回 HTTP '+$get.Status)}}
        else{$r.Http=@{State='Ok';Text='HTTP 可达'}}

        if($Spec.PlainHttpRemote){$r.Login=@{State='Skipped';Text='明文 HTTP，未发送密码'};return $r}
        if(-not $Spec.Username -or -not $Spec.Password){$r.Login=@{State='Skipped';Text='本机账号不可用，未登录'};return $r}
        $session=Initialize-ProbeSession $Spec $cookies $certUntrusted $get $false
        $body='username='+[Uri]::EscapeDataString([string]$Spec.Username)+'&password='+[Uri]::EscapeDataString([string]$Spec.Password)
        $login=Invoke-ProbeRequest 'POST' $Spec.LoginUri $body (Get-ProbeRemaining 4000) $cookies $certUntrusted $true $null $session.Referer $session.Token
        if($login.Ok -and [int]$login.Status -eq 403){
            # Match 3x-ui's browser behavior: refresh a session token, then retry once with the same form.
            $fresh=Initialize-ProbeSession $Spec $cookies $certUntrusted $null $true
            if($fresh.Token){
                $session=$fresh
                $login=Invoke-ProbeRequest 'POST' $Spec.LoginUri $body (Get-ProbeRemaining 4000) $cookies $certUntrusted $true $null $session.Referer $session.Token
            }
        }
        $body=$null
        if(-not $login.Ok){$r.NetworkFailed=$true;$r.Login=@{State='Fail';Text=('登录请求失败：'+$login.Text)};return $r}
        if($login.Status -eq 404){$r.Login=@{State='Fail';Text='登录接口未找到'};return $r}
        if($login.Status -eq 403){$r.Login=@{State='Fail';Text='登录被拒绝（HTTP 403），请检查面板访问限制'};return $r}
        if($login.Status -ne 200){$r.AuthRejected=($login.Status -eq 401);$r.Login=@{State='Fail';Text=('登录接口返回 HTTP '+$login.Status)};return $r}
        $json=$null;try{$json=$login.Body | ConvertFrom-Json}catch{$json=$null}
        if($null -eq $json -or $null -eq $json.success){$r.Login=@{State='Fail';Text='登录接口未识别'};return $r}
        if($json.success -ne $true){$r.AuthRejected=$true;$r.Login=@{State='Fail';Text='登录失败（账号或密码不正确）'};return $r}
        $r.Login=@{State='Ok';Text='面板登录成功'}
        $r.Traffic=@{State='Unavailable';UploadBytes=$null;DownloadBytes=$null;TotalBytes=$null;Source='netTraffic';Label='累计流量';Text='统计暂不可用'}
        # Read only the lightweight status API: Xray, host resources and network byte counters.
        # Inbound/client settings (UUIDs, keys and subscription details) are never requested.
        $statusRead=Invoke-ProbeStatus $Spec $cookies $session $certUntrusted $null
        if($statusRead.Ok){
            # Protected home pages can return 401/403 before login; validate the authenticated API.
            if(-not $certUntrusted -and $get.Status -in @(401,403)){$r.Http=@{State='Ok';Text='HTTP 可达（登录后状态接口正常）'}}
            Set-ProbeStatusSnapshot $r $statusRead.Data
            if(-not $certUntrusted){Save-ProbeCachedSession $Spec $cookies $session $statusRead.Endpoint}
        }elseif($statusRead.SessionExpired){
            $r.Login=@{State='Fail';Text='登录后状态接口仍拒绝访问，请检查面板会话或访问限制'}
            if($statusRead.Response.Status -in @(401,403)){$r.Login.Text+=('（HTTP '+$statusRead.Response.Status+'）')}
        }elseif($statusRead.NetworkFailed){
            $r.NetworkFailed=$true;$r.Http=@{State='Fail';Text=$statusRead.Error.Text}
        }
        return $r
    }catch{
        $r.Error='检测时发生意外错误'
        return $r
    }finally{
        $Spec.Password=$null;$Spec.Username=$null;$body=$null;$session=$null;$fresh=$null;$cookies=$null
        $r.Metrics.SessionReused=$r.SessionReused;$script:probeMetrics=$null;$script:probeLoginUri=$null
        if($cacheLocked){[Threading.Monitor]::Exit($cache.SyncLock)}
    }
}
'@
function Get-ManagerProbeFunctionSource {return ((Get-ManagerResourceFunctionSource)+"`n"+$script:managerProbeFunctions)}
function Get-ManagerProbeWorkerScript {
    $tls=$script:managerProbeTlsSource.Replace("'","''")
    return "param(`$spec)`n`$ErrorActionPreference='Stop'`n"+(Get-ManagerProbeFunctionSource)+"`nInvoke-PanelProbe `$spec '"+$tls+"'`n"
}
