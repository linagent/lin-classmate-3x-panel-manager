param([string]$RepositoryRoot=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('3xui-public-smoke-'+[Guid]::NewGuid().ToString('N'))
$checks=[Collections.Generic.List[string]]::new()
function Assert-PublicCheck([bool]$Condition,[string]$Name){if(-not $Condition){throw ('Failed: '+$Name)};$checks.Add($Name)}
try{
    . (Join-Path $RepositoryRoot 'src\Panel-Manager.ps1') -DataRoot $fixture -LoadOnly
    Assert-PublicCheck (@($script:entries).Count -eq 0) 'First launch has zero servers'
    Assert-PublicCheck ($script:window.Title -eq '3X-UI 面板管家') 'Independent window title'
    $entry=Add-ManagerServer -Name 'Example server' -Url 'https://panel.example.com/' -Username 'demo' -Password ('Example-'+[Guid]::NewGuid().ToString('N')) -Country 'US' -City 'Example' -Group 'Example'
    Assert-PublicCheck (@($script:entries).Count -eq 1) 'Add server from empty inventory'
    $account=Read-PanelAccount $entry
    Assert-PublicCheck ($account.username -ceq 'demo' -and [bool]$account.password) 'DPAPI round trip'
    $secret=Join-Path $fixture $entry.SecretFile
    Assert-PublicCheck (-not ([IO.File]::ReadAllText($secret).Contains($account.password))) 'Credential file excludes plaintext password'
    Save-PanelSettings -Entry $entry -Name 'Renamed example' -Url $entry.Url -Username 'demo-updated' -Password $account.password
    Assert-PublicCheck ($entry.Name -ceq 'Renamed example' -and (Read-PanelAccount $entry).username -ceq 'demo-updated') 'Edit settings persists'
    Build-ManagerRows
    Assert-PublicCheck (@($script:cards).Count -eq 1) 'WPF renders configured server card'
    $transferPassword=[Guid]::NewGuid().ToString('N')
    $plain='{"Version":1,"Synthetic":true}'
    $envelope=Protect-TransferText $plain $transferPassword
    Assert-PublicCheck ((Unprotect-TransferText $envelope $transferPassword) -ceq $plain) 'Encrypted transfer round trip'
    $rejected=$false;try{[void](Unprotect-TransferText $envelope ($transferPassword+'x'))}catch{$rejected=$true}
    Assert-PublicCheck $rejected 'Wrong transfer password rejected'
    $item=$envelope | ConvertFrom-Json;$bytes=[Convert]::FromBase64String($item.Tag);$bytes[0]=$bytes[0] -bxor 1;$item.Tag=[Convert]::ToBase64String($bytes)
    $rejected=$false;try{[void](Unprotect-TransferText ($item | ConvertTo-Json -Compress) $transferPassword)}catch{$rejected=$true}
    Assert-PublicCheck $rejected 'Tampered transfer rejected'
    $result=Remove-ManagerServer -Entry $entry
    Assert-PublicCheck (@($script:entries).Count -eq 0 -and [IO.File]::ReadAllText($script:configPath).Trim() -match '^\[\s*\]$') 'Remove final server preserves empty JSON array'
    [void](Undo-ManagerServerRemoval -Token $result.UndoToken)
    Assert-PublicCheck (@($script:entries).Count -eq 1) 'Undo server removal'
    Save-ManagerConfig
    $doc=[IO.File]::ReadAllText($script:configPath).Trim()
    Assert-PublicCheck ($doc.StartsWith('[') -and $doc.EndsWith(']')) 'Single server inventory remains an array'
    $script:entries=@();Save-ManagerConfig
    Assert-PublicCheck ([IO.File]::ReadAllText($script:configPath).Trim() -match '^\[\s*\]$') 'Empty inventory serialization'
    [pscustomobject]@{AllPassed=$true;Checks=@($checks);ServerRequestsMade=$false} | ConvertTo-Json -Depth 5
}finally{
    if(Get-Command Stop-ManagerAutoRefresh -ErrorAction SilentlyContinue){Stop-ManagerAutoRefresh}
    if($script:window){$script:window.Close()}
    # Keep isolated fixtures in the system temporary directory for troubleshooting.
    $account=$null;$transferPassword=$null;$plain=$null
}
