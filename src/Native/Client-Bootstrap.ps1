param(
    [Parameter(Mandatory=$true)][string]$DataRoot,
    [Parameter(Mandatory=$true)][string]$ClientExecutable,
    [switch]$RenderPreview,
    [string]$PreviewPath,
    [ValidateSet('Main','Settings','Transfer')][string]$PreviewView='Main',
    [switch]$StartupProbe,
    [string]$ReportPath,
    [ValidateRange(250,60000)][int]$CloseAfterMs=1500
)
$ErrorActionPreference='Stop'
$manager=Join-Path $PSScriptRoot 'Panel-Manager.ps1'
if(-not $StartupProbe){
    & $manager -DataRoot $DataRoot -ClientExecutable $ClientExecutable -RenderPreview:$RenderPreview -PreviewPath $PreviewPath -PreviewView $PreviewView
    return
}

# Instrument the real WPF content and dispatcher in the native EXE process.
# Only isolated synthetic data is used by the release verification script.
$probe=[ordered]@{
    Version='1.0.0';ProcessId=$PID;ProcessName=[Diagnostics.Process]::GetCurrentProcess().ProcessName
    StaThread=([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')
    WindowsPowerShell51=($PSVersionTable.PSVersion.Major -eq 5)
    PSHome=$PSHOME;SecurityModuleExists=[IO.File]::Exists((Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1'))
    Loaded=$false;ContentRendered=$false;DispatcherTick=$false;WindowClosed=$false;AllPassed=$false
    EmbeddedNativeHost=$true;ConsoleProcessSpawned=$false;PrivateDataIncluded=$false;NetworkRequested=$false
}
$probeTimer=$null
try{
    . $manager -DataRoot $DataRoot -ClientExecutable $ClientExecutable -LoadOnly
    $probe.ServerCount=@($script:entries).Count
    $probe.ProgramRoot=$PSScriptRoot
    $probe.UiVersion=[string]$script:window.FindName('VersionLabel').Text
    $probe.DataRootMatches=([IO.Path]::GetFullPath($script:workspace).TrimEnd('\') -eq [IO.Path]::GetFullPath($DataRoot).TrimEnd('\'))
    $probe.ClientExecutableMatches=([IO.Path]::GetFullPath($script:managerClientExecutable) -eq [IO.Path]::GetFullPath($ClientExecutable))
    $script:nativeClientProbe=$probe
    $script:window.WindowStartupLocation='Manual';$script:window.Left=-12000;$script:window.Top=0
    $script:window.ShowInTaskbar=$false;$script:window.ShowActivated=$false
    $script:window.Add_Loaded({$script:nativeClientProbe.Loaded=$true})
    $script:window.Add_ContentRendered({$script:nativeClientProbe.ContentRendered=$true})
    $script:window.Add_Closed({$script:nativeClientProbe.WindowClosed=$true})
    $probeTimer=[Windows.Threading.DispatcherTimer]::new();$probeTimer.Interval=[TimeSpan]::FromMilliseconds($CloseAfterMs)
    $probeTimer.Add_Tick({param($sender,$eventArgs) $sender.Stop();$script:nativeClientProbe.DispatcherTick=$true;$script:window.Close()})
    $probeTimer.Start()
    [void]$script:window.ShowDialog()
    $probe.AllPassed=[bool]($probe.StaThread -and $probe.WindowsPowerShell51 -and $probe.SecurityModuleExists -and $probe.Loaded -and $probe.ContentRendered -and $probe.DispatcherTick -and $probe.WindowClosed -and $probe.DataRootMatches -and $probe.ClientExecutableMatches -and $probe.UiVersion -eq '1.0.0')
}catch{
    $probe.ErrorType=$_.Exception.GetType().Name
    throw
}finally{
    if($probeTimer){$probeTimer.Stop()}
    if(Get-Command Stop-ManagerAutoRefresh -ErrorAction SilentlyContinue){Stop-ManagerAutoRefresh}
    if($script:window -and $script:window.IsVisible){$script:window.Close()}
    if($ReportPath){
        $full=[IO.Path]::GetFullPath($ReportPath);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
        [IO.File]::WriteAllText($full,($probe | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding $false))
    }
}
