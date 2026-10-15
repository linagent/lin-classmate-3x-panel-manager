# Uses Windows OpenSSH and local DPAPI; no external service or Python runtime.
function Resolve-PanelTunnelPath([string]$Relative) {
    if(-not $script:workspace -or -not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative -match '[:*?"<>|''\x00-\x1f]'){throw 'SSH 文件路径必须是数据目录内的安全相对路径。'}
    foreach($part in $Relative.Replace('\','/').Split('/')){
        if(-not $part -or $part -in @('.','..') -or $part -match '[. ]$' -or $part -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)'){throw 'SSH 文件路径包含不安全的目录名。'}
    }
    $root=[IO.Path]::GetFullPath($script:workspace).TrimEnd('\')
    if($root -match '["''\x00-\x1f]'){throw '数据目录不能包含引号或控制字符。'}
    $target=[IO.Path]::GetFullPath((Join-Path $root $Relative))
    if(-not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'SSH 文件路径超出数据目录。'}
    # Check every existing ancestor, including the selected data root and its parents.
    $cursor=$target
    while($cursor){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'SSH 文件路径不能包含符号链接或目录联接。'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $target
}
function Get-PanelTunnelPaths($Entry) {
    $folder=[string]$Entry.Folder
    if(-not $folder -or $folder -match '[\\/:*?"<>|''\x00-\x1f]' -or $folder -in @('.','..','统一管理','面板浏览器','.git','.agents','.codex') -or $folder -match '[. ]$'){throw 'SSH 运行目录必须使用独立的单层服务器目录。'}
    $runtimeRelative=$folder+'\凭据\隧道运行'
    return [pscustomobject]@{
        PrivateKey=(Resolve-PanelTunnelPath ([string]$Entry.Tunnel.KeyFile))
        KnownHosts=(Resolve-PanelTunnelPath ([string]$Entry.Tunnel.KnownHostsFile))
        Runtime=(Resolve-PanelTunnelPath $runtimeRelative)
        State=(Resolve-PanelTunnelPath ($runtimeRelative+'\process.json'))
        Log=(Resolve-PanelTunnelPath ($runtimeRelative+'\ssh.log'))
        RuntimeRelative=$runtimeRelative
    }
}
function Read-TunnelPrivateKey($Entry) {
    $path=(Get-PanelTunnelPaths $Entry).PrivateKey
    if(-not (Test-Path -LiteralPath $path)){throw '本机缺少面板隧道密钥。请从原电脑重新导出账号，并在本机导入。'}
    $secure=ConvertTo-SecureString ([IO.File]::ReadAllText($path).Trim())
    return [PSCredential]::new('local',$secure).GetNetworkCredential().Password
}
function Test-PanelTunnelProcess($Entry,$PidValue) {
    if(-not $Entry.Tunnel -or [int]$PidValue -le 0){return $false}
    $p=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$PidValue) -ErrorAction SilentlyContinue
    if(-not $p -or $p.Name -ne 'ssh.exe' -or -not $p.CommandLine){return $false}
    $ssh=Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if(-not $p.ExecutablePath -or -not [string]::Equals([IO.Path]::GetFullPath($p.ExecutablePath),[IO.Path]::GetFullPath($ssh),[StringComparison]::OrdinalIgnoreCase)){return $false}
    $target=$Entry.Tunnel.User+'@'+$Entry.Tunnel.Host
    if($p.CommandLine -notmatch ('(?<!\S)"?'+[regex]::Escape($target)+'"?(?=\s|$)')){return $false}
    if($p.CommandLine -notmatch ('(?<!\S)-p\s+"?'+[int]$Entry.Tunnel.Port+'"?(?=\s|$)')){return $false}
    $binding='127.0.0.1:'+$Entry.Tunnel.LocalPort+':127.0.0.1:'+$Entry.Tunnel.RemotePort
    if($p.CommandLine -notmatch ('(?<!\S)-L\s+"?'+[regex]::Escape($binding)+'"?(?=\s|$)')){return $false}
    $listeners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Entry.Tunnel.LocalPort -State Listen -ErrorAction SilentlyContinue)
    return [bool]($listeners | Where-Object {$_.OwningProcess -eq [int]$PidValue})
}
function Ensure-PanelTunnel($Entry) {
    if(-not $Entry.Tunnel){return}
    $t=$Entry.Tunnel
    if([Uri]::CheckHostName([string]$t.Host) -eq [UriHostNameType]::Unknown -or [string]$t.Host -match '[\s"\x00-\x1f]' -or [string]$t.User -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,63}$'){throw 'SSH 主机名或用户名无效。'}
    foreach($value in @($t.Port,$t.RemotePort,$t.LocalPort)){
        $number=0
        if(-not [int]::TryParse([string]$value,[ref]$number) -or $number -lt 1 -or $number -gt 65535){throw 'SSH 端口必须是 1 到 65535 的整数。'}
    }
    $paths=Get-PanelTunnelPaths $Entry
    $ssh=Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if(-not (Test-Path -LiteralPath $ssh)){throw '需要 Windows 的 OpenSSH 客户端。请在系统可选功能中安装「OpenSSH 客户端」。'}
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
    # One creator per Windows user and local port, including background check workers.
    # This also prevents one launch from deleting another launch's temporary key.
    $mutex=[Threading.Mutex]::new($false,('Local\Public3XuiPanelTunnel-'+$sid.Value+'-'+$Entry.Tunnel.LocalPort))
    $lockHeld=$false;$keyPath=$null;$process=$null;$ready=$false
    try{
        try{$lockHeld=$mutex.WaitOne(20000)}catch [Threading.AbandonedMutexException]{$lockHeld=$true}
        if(-not $lockHeld){throw '已有程序正在建立面板隧道，请稍后重新检测。'}
        $paths=Get-PanelTunnelPaths $Entry
        $runtime=$paths.Runtime
        [void][IO.Directory]::CreateDirectory($runtime)
        $paths=Get-PanelTunnelPaths $Entry
        $acl=[Security.AccessControl.DirectorySecurity]::new()
        $acl.SetOwner($sid);$acl.SetAccessRuleProtection($true,$false)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
        [void](Get-PanelTunnelPaths $Entry)
        Set-Acl -LiteralPath $runtime -AclObject $acl
        [void](Get-PanelTunnelPaths $Entry)
        Get-ChildItem -LiteralPath $runtime -Filter 'key-*' -File | ForEach-Object {
            $safeKey=Resolve-PanelTunnelPath ($paths.RuntimeRelative+'\'+$_.Name)
            Remove-Item -LiteralPath $safeKey -Force
        }
        $stateFile=$paths.State
        if(Test-Path -LiteralPath $stateFile){
            # A stale or truncated state file must not prevent reconnection.
            $state=$null;try{$state=[IO.File]::ReadAllText($stateFile) | ConvertFrom-Json}catch{}
            if($state -and (Test-PanelTunnelProcess $Entry $state.ProcessId)){return}
        }
        $listeners=@(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Entry.Tunnel.LocalPort -State Listen -ErrorAction SilentlyContinue)
        if($listeners.Count -gt 0){
            # Recover a verified tunnel after its state file was lost. Never trust
            # an open port alone, and never stop the process which owns it.
            foreach($listener in $listeners){
                if(Test-PanelTunnelProcess $Entry $listener.OwningProcess){
                    [IO.File]::WriteAllText($stateFile,(@{ProcessId=[int]$listener.OwningProcess;Host=$Entry.Tunnel.Host;LocalPort=$Entry.Tunnel.LocalPort;Started=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json),[Text.Encoding]::UTF8)
                    return
                }
            }
            throw '面板隧道本机端口已被其他程序占用。请先检查端口。'
        }
        $paths=Get-PanelTunnelPaths $Entry
        $known=$paths.KnownHosts
        if(-not (Test-Path -LiteralPath $known)){throw '缺少已核对的 SSH 主机公钥，不能建立隧道。'}
        $keyRelative=$paths.RuntimeRelative+'\key-'+[Guid]::NewGuid().ToString('N')
        $keyPath=Resolve-PanelTunnelPath $keyRelative
        $logPath=$paths.Log
        # The directory ACL is applied before this short-lived plaintext file.
        [IO.File]::WriteAllText($keyPath,(Read-TunnelPrivateKey $Entry),[Text.Encoding]::ASCII)
        $forward='127.0.0.1:'+$Entry.Tunnel.LocalPort+':127.0.0.1:'+$Entry.Tunnel.RemotePort
        $args=@('-F','NUL','-N','-T','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o','ExitOnForwardFailure=yes','-o','ServerAliveInterval=30','-o','ServerAliveCountMax=3','-o','ConnectTimeout=12','-o','ConnectionAttempts=1','-o','ProxyCommand=none','-o','ProxyJump=none','-o',('UserKnownHostsFile="'+$known+'"'),'-o','GlobalKnownHostsFile=NUL','-i',('"'+$keyPath+'"'),'-p',[string]$Entry.Tunnel.Port,'-L',$forward,'-E',('"'+$logPath+'"'),($Entry.Tunnel.User+'@'+$Entry.Tunnel.Host))
        $process=Start-Process -FilePath $ssh -ArgumentList $args -WindowStyle Hidden -PassThru
        $deadline=[DateTime]::UtcNow.AddSeconds(16)
        do{
            Start-Sleep -Milliseconds 300
            $process.Refresh()
            if($process.HasExited){throw 'SSH 隧道启动失败，请检查本机隧道日志。'}
            if(Test-PanelTunnelProcess $Entry $process.Id){$ready=$true;break}
        }while([DateTime]::UtcNow -lt $deadline)
        if(-not $ready){throw 'SSH 隧道连接超时。'}
        [IO.File]::WriteAllText($stateFile,(@{ProcessId=$process.Id;Host=$Entry.Tunnel.Host;LocalPort=$Entry.Tunnel.LocalPort;Started=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json),[Text.Encoding]::UTF8)
    }catch{
        if($process -and -not $ready){try{$process.Kill()}catch{}}
        throw
    }finally{
        try{
            if($keyPath -and (Test-Path -LiteralPath $keyPath)){
                $safeKey=Resolve-PanelTunnelPath $keyRelative
                Remove-Item -LiteralPath $safeKey -Force
            }
        }finally{
            try{if($lockHeld){$mutex.ReleaseMutex()}}finally{$mutex.Dispose()}
        }
    }
}
function Get-PanelTunnelFunctionSource {
    # Export the active functions, allowing the probe runspace to use the same
    # tunnel code as the panel button without loading the WPF app or credentials.
    $functions=foreach($name in 'Resolve-PanelTunnelPath','Get-PanelTunnelPaths','Read-TunnelPrivateKey','Test-PanelTunnelProcess','Ensure-PanelTunnel'){
        $command=Get-Command $name -CommandType Function -ErrorAction Stop
        'function '+$name+' {'+[Environment]::NewLine+$command.ScriptBlock.ToString()+[Environment]::NewLine+'}'
    }
    return ($functions -join [Environment]::NewLine)
}
function Open-ManagedPanel($Entry) {
    if($Entry.Tunnel){
        $uri=[Uri]$Entry.Url
        if($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Entry.Tunnel.LocalPort -or $uri.UserInfo){throw '此面板地址必须使用已配置的本机隧道端口。'}
    }
    Ensure-PanelTunnel $Entry
    # Always the system default browser. The in-app WebView2 window stays unused.
    Start-Process $Entry.Url
}
