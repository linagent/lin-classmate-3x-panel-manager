# Run with Windows PowerShell 5.1. Builds the standalone public Windows client.
param([switch]$SkipVerification)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Build with Windows PowerShell 5.1: powershell.exe -NoProfile -ExecutionPolicy Bypass -File src\Build-Windows-Client.ps1'}
$projectRoot=Split-Path $PSScriptRoot -Parent
$native=Join-Path $PSScriptRoot 'Native'
$publish=Join-Path $projectRoot 'dist'
$build=Join-Path $projectRoot '.build'
[void][IO.Directory]::CreateDirectory($publish)
[void][IO.Directory]::CreateDirectory($build)
$version='1.0.0'
$name='3XUI-Panel-Manager.exe'
$payloadPath=Join-Path $build 'Client.Payload.zip'
$manifestPath=Join-Path $build 'Client.Manifest.json'
$icoPath=Join-Path $build 'Client.ico'
$temporaryExe=Join-Path $build $name
$publishedExe=Join-Path $publish $name
# Only program resources enter the EXE. No recursive directory copy is used.
$allowlist=@(
    'Panel-Manager.ps1','Panel-Manager.Core.ps1','Panel-Manager.Wpf.ps1','Panel-StatusCheck.ps1','Panel-AutoRefresh.ps1',
    'Panel-Metadata.ps1','Panel-Lifecycle.ps1','Panel-HomePackage.ps1','Panel-CardPresentation.ps1','Panel-Resources.ps1','Panel-Purchases.ps1','Panel-MonitorUi.ps1','Panel-ResourceUi.ps1','Panel-Tunnel.ps1','Account-Transfer.ps1','Manager-Extensions.ps1',
    'Panel-ClientActions.ps1','Client-Bootstrap.ps1',
    '界面/Theme.xaml','界面/MainWindow.xaml','界面/ServerCard.xaml','界面/SettingsWindow.xaml','界面/AddWindow.xaml','界面/DeleteWindow.xaml','界面/TransferWindow.xaml','界面/UpdateWindow.xaml','界面/ResourceDrawer.xaml','界面/PurchaseWindow.xaml','界面/PurchaseManageWindow.xaml'
)
$files=[Collections.ArrayList]::new()
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Drawing
if([IO.File]::Exists($payloadPath)){[IO.File]::Delete($payloadPath)}
$stream=[IO.File]::Open($payloadPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
try{
    foreach($relative in $allowlist){
        if($relative -eq 'Manager-Extensions.ps1'){
            $content='# Public package default extension stub. No user extensions are embedded.'+"`r`n"
            $bytes=(New-Object Text.UTF8Encoding $true).GetPreamble()+(New-Object Text.UTF8Encoding $false).GetBytes($content)
        }else{
            $source=if($relative -eq 'Client-Bootstrap.ps1'){Join-Path $native $relative}else{Join-Path $PSScriptRoot $relative.Replace('/','\')}
            if(-not [IO.File]::Exists($source)){throw ('Missing allowed program source: '+$relative)}
            if($relative.EndsWith('.ps1')){
                $content=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
                $bytes=(New-Object Text.UTF8Encoding $true).GetPreamble()+(New-Object Text.UTF8Encoding $false).GetBytes($content)
            }else{$bytes=[IO.File]::ReadAllBytes($source)}
        }
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        [void]$files.Add([ordered]@{Path=$relative;Bytes=$bytes.Length;Sha256=$hash})
        $entry=$zip.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
        $output=$entry.Open();try{$output.Write($bytes,0,$bytes.Length)}finally{$output.Dispose()}
    }
}finally{$zip.Dispose();$stream.Dispose()}
$payloadHash=(Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest=[ordered]@{Version=$version;PayloadSha256=$payloadHash;Files=@($files)}
[IO.File]::WriteAllText($manifestPath,($manifest | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding $false))

# Preserve the familiar warm application accent with an independent 3X identity.
$frames=[Collections.ArrayList]::new()
foreach($size in @(16,24,32,48,64,128,256)){
    $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $shape=[Drawing.Drawing2D.GraphicsPath]::new();$brush=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#C96442'))
    $font=[Drawing.Font]::new('Segoe UI',($size*0.42),[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
    $format=[Drawing.StringFormat]::new();$format.Alignment=[Drawing.StringAlignment]::Center;$format.LineAlignment=[Drawing.StringAlignment]::Center
    $memory=[IO.MemoryStream]::new()
    try{
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias;$graphics.TextRenderingHint=[Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([Drawing.Color]::Transparent)
        $inset=[single]($size*0.05);$edge=[single]($size-$inset*2);$radius=[single]($size*0.3)
        $shape.AddArc($inset,$inset,$radius,$radius,180,90);$shape.AddArc(($inset+$edge-$radius),$inset,$radius,$radius,270,90)
        $shape.AddArc(($inset+$edge-$radius),($inset+$edge-$radius),$radius,$radius,0,90);$shape.AddArc($inset,($inset+$edge-$radius),$radius,$radius,90,90);$shape.CloseFigure()
        $graphics.FillPath($brush,$shape);$graphics.DrawString('3X',$font,[Drawing.Brushes]::White,[Drawing.RectangleF]::new(0,-($size*0.01),$size,$size),$format)
        $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png);[void]$frames.Add(@{Size=$size;Bytes=$memory.ToArray()})
    }finally{$memory.Dispose();$format.Dispose();$font.Dispose();$brush.Dispose();$shape.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
$iconStream=[IO.File]::Open($icoPath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
$writer=[IO.BinaryWriter]::new($iconStream)
try{
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$frames.Count)
    $offset=6+16*$frames.Count
    foreach($frame in $frames){$dimension=if($frame.Size -eq 256){0}else{$frame.Size};$writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$frame.Bytes.Length);$writer.Write([uint32]$offset);$offset+=$frame.Bytes.Length}
    foreach($frame in $frames){$writer.Write([byte[]]$frame.Bytes)}
}finally{$writer.Dispose();$iconStream.Dispose()}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$automation=Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation\v4.0_3.0.0.0__31bf3856ad364e35\System.Management.Automation.dll'
foreach($required in @($compiler,$automation)){if(-not [IO.File]::Exists($required)){throw ('Required Windows build component missing: '+[IO.Path]::GetFileName($required))}}
$compilerArgs=@('/nologo','/target:winexe','/platform:x64','/optimize+','/utf8output','/codepage:65001',('/out:'+$temporaryExe),('/win32manifest:'+(Join-Path $native 'Client.manifest')),('/win32icon:'+$icoPath),('/resource:'+$payloadPath+',Client.Payload.zip'),('/resource:'+$manifestPath+',Client.Manifest.json'),'/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll','/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll',('/reference:'+$automation),(Join-Path $native 'Client.cs'))
& $compiler @compilerArgs
if($LASTEXITCODE -ne 0){throw 'Native WinExe compile failed.'}
[IO.File]::Copy($temporaryExe,$publishedExe,$true)
[IO.File]::Copy($manifestPath,(Join-Path $publish ('client-manifest-'+$version+'.json')),$true)
if(-not $SkipVerification){
    foreach($mode in @('verify-package','self-test')){
        $report=Join-Path $build ($mode+'.json')
        $process=Start-Process -FilePath $publishedExe -ArgumentList @('--'+$mode,'--report',('"'+$report+'"')) -WindowStyle Hidden -PassThru
        if(-not $process.WaitForExit(30000)){throw ('Verification timed out: '+$mode)}
        if($process.ExitCode -ne 0 -or -not [IO.File]::Exists($report)){throw ('Verification failed: '+$mode)}
        if(-not (([IO.File]::ReadAllText($report,[Text.Encoding]::UTF8) | ConvertFrom-Json).AllPassed)){throw ('Verification report failed: '+$mode)}
    }
}
$exeHash=(Get-FileHash -LiteralPath $publishedExe -Algorithm SHA256).Hash
$receipt=[ordered]@{
    Product='3XUI Panel Manager Public';Version=$version;BuiltAt=(Get-Date -Format 'o')
    Executable=$name;Sha256=$exeHash;Bytes=([IO.FileInfo]$publishedExe).Length;PayloadSha256=$payloadHash;EmbeddedFileCount=$files.Count
    Platform='Windows 10/11 x64';NativeWinExe=$true;Host='System Windows PowerShell 5.1 runspace on native EXE STA thread'
    ConsoleProcessSpawned=$false;CodeSigned=$false;OnlineUpdateEnabled=$false
    ServerInventoryEmbedded=$false;CredentialsAndSshPrivateKeysEmbedded=$false;UserExtensionsEmbedded=$false
    DataIdentity='3XUI Panel Manager Public';DefaultDataRoot='%LOCALAPPDATA%\3XuiPanelManagerPublic\data'
    CacheRoot='%LOCALAPPDATA%\3XuiPanelManagerPublic\app';ExistingUnmarkedDataRootsAccepted=$false
}
[IO.File]::WriteAllText((Join-Path $publish ('build-receipt-'+$version+'.json')),($receipt | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding $true))
$receipt | ConvertTo-Json -Depth 8
