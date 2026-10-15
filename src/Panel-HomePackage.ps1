# Synchronize an already-created home package without reading local DPAPI credentials.
# These helpers only act on the fixed home mirror beneath the selected DataRoot.
function Get-ManagerHomeSafePath {
    param([string]$Root,[string]$Relative)
    if(-not $Relative -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':') -or @($Relative.Replace('\','/').Split('/') | Where-Object {$_ -in @('','..','.')}).Count){throw '家用副本包含不安全的相对路径。'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    if((Test-Path -LiteralPath $base) -and ((Get-Item -LiteralPath $base -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '家用副本根目录为链接，停止清理。'}
    $target=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(-not $target.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw '家用副本路径超出范围。'}
    $cursor=$target
    while($cursor.Length -gt $base.Length){
        if((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '家用副本包含链接目录，停止清理。'}
        $cursor=[IO.Path]::GetDirectoryName($cursor)
    }
    return $target
}
function Get-ManagerHomeRemovalPlan {
    param([Parameter(Mandatory=$true)]$Entry,[string]$DataRoot=$script:workspace)
    if(-not $DataRoot -or -not $Entry.Id){throw '缺少家用副本清理目标。'}
    $homePackageRoot=[IO.Path]::GetFullPath((Join-Path $DataRoot '统一管理\家用电脑版'))
    foreach($ancestor in @([IO.Path]::GetFullPath($DataRoot),(Join-Path $DataRoot '统一管理'))){if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw '项目资料目录为链接，停止清理。'}}
    $inventory=Get-ManagerHomeSafePath $homePackageRoot '统一管理\服务器列表.json'
    $metadata=Get-ManagerHomeSafePath $homePackageRoot '统一管理\服务器元数据.json'
    $folderFirst=([string]$Entry.Folder).Replace('\','/').Split('/')[0]
    if($folderFirst -in @('统一管理','面板浏览器','.git','.codex','.agents')){throw '家用副本服务器目录与共用程序目录重叠。'}
    $folder=Get-ManagerHomeSafePath $homePackageRoot ([string]$Entry.Folder)
    $zip=[IO.Path]::GetFullPath((Join-Path $DataRoot '统一管理\家用电脑版.zip'))
    $entries=@();$registered=$false;$reason=''
    if([IO.File]::Exists($inventory)){
        try{$decoded=[IO.File]::ReadAllText($inventory,[Text.Encoding]::UTF8) | ConvertFrom-Json;$entries=@($decoded)}catch{throw '家用副本服务器列表无法读取，未修改任何资料。'}
        $matches=@($entries | Where-Object {[string]$_.Id -eq [string]$Entry.Id})
        if($matches.Count -gt 1){$reason='家用副本存在重复服务器标识。'}
        elseif($matches.Count -eq 1){
            $matchedFolder=Get-ManagerHomeSafePath $homePackageRoot ([string]$matches[0].Folder)
            if(-not [string]::Equals($matchedFolder,$folder,[StringComparison]::OrdinalIgnoreCase)){$reason='家用副本资料目录与当前条目不一致。'}else{$registered=$true}
        }
    }
    $otherOwners=@($entries | Where-Object {
        if([string]$_.Id -eq [string]$Entry.Id){return $false}
        $otherFolder=Get-ManagerHomeSafePath $homePackageRoot ([string]$_.Folder)
        return [string]::Equals($otherFolder,$folder,[StringComparison]::OrdinalIgnoreCase) -or $otherFolder.StartsWith($folder+'\',[StringComparison]::OrdinalIgnoreCase) -or $folder.StartsWith($otherFolder+'\',[StringComparison]::OrdinalIgnoreCase)
    }).Count
    if($otherOwners){$reason='家用资料目录同时属于其他服务器，不能清理。'}
    if(-not $registered -and [IO.Directory]::Exists($folder) -and -not $reason){$reason='家用副本中无法确认此资料目录的所属条目。'}
    $files=@()
    if([IO.Directory]::Exists($folder)){
        foreach($item in @(Get-ChildItem -LiteralPath $folder -Force -Recurse)){
            if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$reason='家用资料包含链接，不能清理。';break}
            if(-not $item.PSIsContainer){$files += $item}
        }
    }
    return [pscustomobject]@{HomeRoot=$homePackageRoot;InventoryPath=$inventory;MetadataPath=$metadata;ManifestPath=(Join-Path $homePackageRoot '文件校验清单.json');ZipPath=$zip;FolderPath=$folder;Registered=$registered;Exists=[IO.Directory]::Exists($homePackageRoot);FileCount=$files.Count;CanRemove=(-not [bool]$reason);BlockedReason=$reason;ServerId=[string]$Entry.Id}
}
function Write-ManagerHomeAtomicBytes {
    param([string]$Path,[byte[]]$Bytes)
    $temp=$Path+'.tmp-'+[Guid]::NewGuid().ToString('N')
    try{
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if([IO.File]::Exists($Path)){[IO.File]::Replace($temp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
}
function ConvertTo-ManagerHomeJsonBytes {
    param($Value)
    $encoding=New-Object Text.UTF8Encoding $true
    return [byte[]]($encoding.GetPreamble()+$encoding.GetBytes((ConvertTo-Json -InputObject $Value -Depth 20)))
}
function Remove-ManagerHomeServer {
    param([Parameter(Mandatory=$true)]$Entry,[bool]$DeleteLocalFiles=$false,[string]$DataRoot=$script:workspace,[scriptblock]$RecycleAction)
    $plan=Get-ManagerHomeRemovalPlan -Entry $Entry -DataRoot $DataRoot
    if(-not $plan.CanRemove){throw $plan.BlockedReason}
    if(-not $plan.Exists -or -not $plan.Registered){return [pscustomobject]@{Changed=$false;ServerId=[string]$Entry.Id;ZipRebuilt=$false;FilesRecycled=0}}
    $snapshots=@{};$folderFiles=@();$folderDirectories=@();$temporaryZip=$plan.ZipPath+'.tmp-'+[Guid]::NewGuid().ToString('N')
    foreach($path in @($plan.InventoryPath,$plan.MetadataPath,$plan.ManifestPath,$plan.ZipPath)){
        $snapshots[$path]=if([IO.File]::Exists($path)){[IO.File]::ReadAllBytes($path)}else{$null}
    }
    if($DeleteLocalFiles -and [IO.Directory]::Exists($plan.FolderPath)){
        $folderDirectories=@($plan.FolderPath)+@(Get-ChildItem -LiteralPath $plan.FolderPath -Directory -Recurse -Force | ForEach-Object {$_.FullName})
        $folderFiles=@(Get-ChildItem -LiteralPath $plan.FolderPath -File -Recurse -Force | ForEach-Object {[pscustomobject]@{Path=$_.FullName;Bytes=[IO.File]::ReadAllBytes($_.FullName);LastWrite=$_.LastWriteTimeUtc;Attributes=$_.Attributes}})
    }
    $removedFolder=$false;$filesRecycled=0;$zipRebuilt=$false
    try{
        if(-not [IO.File]::Exists($plan.ManifestPath)){throw '家用副本缺少文件校验清单，请先重新生成家用程序包。'}
        $knownFilesValue=[IO.File]::ReadAllText($plan.ManifestPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        $knownFiles=@($knownFilesValue)
        $inventoryValue=[IO.File]::ReadAllText($plan.InventoryPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
        $remaining=@($inventoryValue | Where-Object {[string]$_.Id -ne [string]$Entry.Id})
        Write-ManagerHomeAtomicBytes $plan.InventoryPath (ConvertTo-ManagerHomeJsonBytes $remaining)
        if([IO.File]::Exists($plan.MetadataPath)){
            $meta=[IO.File]::ReadAllText($plan.MetadataPath,[Text.Encoding]::UTF8) | ConvertFrom-Json
            if(-not $meta.PSObject.Properties['Servers']){throw '家用副本服务器元数据格式无法读取。'}
            $meta.Servers=@($meta.Servers | Where-Object {[string]$_.Id -ne [string]$Entry.Id})
            Write-ManagerHomeAtomicBytes $plan.MetadataPath (ConvertTo-ManagerHomeJsonBytes $meta)
        }
        $paths=@($knownFiles | ForEach-Object {[string]$_.path})+@('统一管理/服务器列表.json')
        if([IO.File]::Exists($plan.MetadataPath)){$paths += '统一管理/服务器元数据.json'}
        $records=@();$packedFiles=@()
        foreach($relative in @($paths | Sort-Object -Unique)){
            if($relative -eq '文件校验清单.json'){continue}
            $path=Get-ManagerHomeSafePath $plan.HomeRoot $relative
            if($DeleteLocalFiles -and ($path -eq $plan.FolderPath -or $path.StartsWith($plan.FolderPath+'\',[StringComparison]::OrdinalIgnoreCase))){continue}
            if(-not [IO.File]::Exists($path)){continue}
            if([IO.Path]::GetExtension($path).ToLowerInvariant() -in @('.dpapi','.pem','.key','.db','.log','.vpsaccounts') -or ($relative.Replace('\','/') -match '/凭据/' -and [IO.Path]::GetFileName($path) -ne '说明.txt' -and [IO.Path]::GetFileName($path) -ne 'known_hosts')){throw '家用程序包清单中包含凭据或运行文件，停止重建。'}
            $info=Get-Item -LiteralPath $path
            $records += [pscustomobject]@{path=$relative.Replace('\','/');bytes=$info.Length;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
            $packedFiles += [pscustomobject]@{Path=$path;Relative=$relative.Replace('\','/')}
        }
        Write-ManagerHomeAtomicBytes $plan.ManifestPath (ConvertTo-ManagerHomeJsonBytes @($records))
        if([IO.File]::Exists($plan.ZipPath)){
            Add-Type -AssemblyName System.IO.Compression
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $stream=[IO.File]::Open($temporaryZip,[IO.FileMode]::CreateNew)
            $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
            try{
                foreach($file in @($packedFiles)+@([pscustomobject]@{Path=$plan.ManifestPath;Relative='文件校验清单.json'})){
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$file.Path,$file.Relative,[IO.Compression.CompressionLevel]::Optimal)
                }
            }finally{$zip.Dispose();$stream.Dispose()}
            $verify=[IO.Compression.ZipFile]::OpenRead($temporaryZip)
            try{
                foreach($record in $records){
                    $item=$verify.GetEntry($record.path)
                    if(-not $item){throw '家用 ZIP 缺少清单文件。'}
                    $content=$item.Open();$sha=[Security.Cryptography.SHA256]::Create()
                    try{$hash=[BitConverter]::ToString($sha.ComputeHash($content)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose();$content.Dispose()}
                    if($hash -ne $record.sha256){throw '家用 ZIP 内容校验失败。'}
                }
            }finally{$verify.Dispose()}
        }
        if($DeleteLocalFiles -and [IO.Directory]::Exists($plan.FolderPath)){
            # Recheck ownership and links immediately before the sole recursive deletion.
            $current=Get-ManagerHomeSafePath $plan.HomeRoot ([string]$Entry.Folder)
            foreach($item in @(Get-ChildItem -LiteralPath $current -Force -Recurse)){if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '家用资料出现链接，停止清理。'}}
            if($RecycleAction){& $RecycleAction $current}else{
                Add-Type -AssemblyName Microsoft.VisualBasic
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($current,[Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,[Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            }
            if([IO.Directory]::Exists($current)){throw '家用资料目录未能移入回收站。'}
            $removedFolder=$true;$filesRecycled=$folderFiles.Count
        }
        if([IO.File]::Exists($temporaryZip)){
            [IO.File]::Replace($temporaryZip,$plan.ZipPath,[Management.Automation.Language.NullString]::Value)
            $zipRebuilt=$true
        }
        return [pscustomobject]@{Changed=$true;ServerId=[string]$Entry.Id;ZipRebuilt=$zipRebuilt;FilesRecycled=$filesRecycled;RemainingServers=$remaining.Count;UndoState=[pscustomobject]@{FileSnapshots=$snapshots;FolderFiles=$folderFiles;FolderDirectories=$folderDirectories;FolderRemoved=$removedFolder}}
    }catch{
        foreach($path in $snapshots.Keys){if($null -ne $snapshots[$path]){Write-ManagerHomeAtomicBytes $path $snapshots[$path]}elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
        # Restore only the selected mirror folder if a later commit fails.
        foreach($directory in $folderDirectories){[void][IO.Directory]::CreateDirectory($directory)}
        foreach($file in $folderFiles){[IO.File]::WriteAllBytes($file.Path,$file.Bytes);[IO.File]::SetLastWriteTimeUtc($file.Path,$file.LastWrite);[IO.File]::SetAttributes($file.Path,$file.Attributes)}
        throw
    }finally{if([IO.File]::Exists($temporaryZip)){[IO.File]::Delete($temporaryZip)}}
}
function Restore-ManagerHomeRemoval {
    param([Parameter(Mandatory=$true)]$UndoState)
    foreach($path in $UndoState.FileSnapshots.Keys){if($null -ne $UndoState.FileSnapshots[$path]){Write-ManagerHomeAtomicBytes $path $UndoState.FileSnapshots[$path]}elseif([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
    if($UndoState.FolderRemoved){
        foreach($directory in $UndoState.FolderDirectories){[void][IO.Directory]::CreateDirectory($directory)}
        foreach($file in $UndoState.FolderFiles){[IO.File]::WriteAllBytes($file.Path,$file.Bytes);[IO.File]::SetLastWriteTimeUtc($file.Path,$file.LastWrite);[IO.File]::SetAttributes($file.Path,$file.Attributes)}
    }
}
