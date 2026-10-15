function Write-AtomicText([string]$Path,[string]$Text,[Text.Encoding]$Encoding) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    $tmp=$Path+'.tmp'
    [IO.File]::WriteAllText($tmp,$Text,$Encoding)
    # PS 5.1 needs NullString.Value to pass an actual null backup file name.
    if([IO.File]::Exists($Path)){[IO.File]::Replace($tmp,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
}
function Protect-TransferText([string]$Text,[string]$Password) {
    if($Password.Length -lt 10){throw '迁移密码至少需要 10 个字符。'}
    $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
    $salt=New-Object byte[] 16;$iv=New-Object byte[] 16;$rng.GetBytes($salt);$rng.GetBytes($iv);$rng.Dispose()
    $kdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($Password,$salt,200000,[Security.Cryptography.HashAlgorithmName]::SHA256)
    $keys=$kdf.GetBytes(64);$kdf.Dispose();[byte[]]$key=$keys[0..31];[byte[]]$macKey=$keys[32..63]
    $aes=[Security.Cryptography.Aes]::Create();$aes.Key=$key;$aes.IV=$iv
    $plain=[Text.Encoding]::UTF8.GetBytes($Text);$encryptor=$aes.CreateEncryptor()
    $cipher=$encryptor.TransformFinalBlock($plain,0,$plain.Length);$encryptor.Dispose();$aes.Dispose()
    $hmac=[Security.Cryptography.HMACSHA256]::new($macKey)
    [byte[]]$signed=$salt+$iv+$cipher;$tag=$hmac.ComputeHash($signed);$hmac.Dispose()
    return (@{Version=1;Iterations=200000;Salt=[Convert]::ToBase64String($salt);IV=[Convert]::ToBase64String($iv);Ciphertext=[Convert]::ToBase64String($cipher);Tag=[Convert]::ToBase64String($tag)} | ConvertTo-Json -Compress)
}
function Unprotect-TransferText([string]$Envelope,[string]$Password) {
    if($Envelope.Length -gt 1048576){throw '账号迁移文件过大。'}
    $e=$Envelope | ConvertFrom-Json
    if($e.Version -ne 1 -or $e.Iterations -ne 200000){throw '不支持的迁移文件格式。'}
    $salt=[Convert]::FromBase64String($e.Salt);$iv=[Convert]::FromBase64String($e.IV)
    $cipher=[Convert]::FromBase64String($e.Ciphertext);$tag=[Convert]::FromBase64String($e.Tag)
    if($salt.Length -ne 16 -or $iv.Length -ne 16 -or $tag.Length -ne 32){throw '迁移文件损坏。'}
    $kdf=[Security.Cryptography.Rfc2898DeriveBytes]::new($Password,$salt,200000,[Security.Cryptography.HashAlgorithmName]::SHA256)
    $keys=$kdf.GetBytes(64);$kdf.Dispose();[byte[]]$key=$keys[0..31];[byte[]]$macKey=$keys[32..63]
    $hmac=[Security.Cryptography.HMACSHA256]::new($macKey);[byte[]]$signed=$salt+$iv+$cipher
    $expected=$hmac.ComputeHash($signed);$hmac.Dispose();$difference=0
    for($i=0;$i -lt 32;$i++){$difference=$difference -bor ($tag[$i] -bxor $expected[$i])}
    if($difference -ne 0){throw '迁移密码错误，或文件已损坏。'}
    $aes=[Security.Cryptography.Aes]::Create();$aes.Key=$key;$aes.IV=$iv
    $decryptor=$aes.CreateDecryptor();$plain=$decryptor.TransformFinalBlock($cipher,0,$cipher.Length)
    $decryptor.Dispose();$aes.Dispose();return [Text.Encoding]::UTF8.GetString($plain)
}
function Get-TransferPassword([bool]$Confirm) {
    $d=[Windows.Forms.Form]::new();$d.Text=if($Confirm){'设置跨电脑账号迁移密码'}else{'输入账号迁移密码'}
    $d.Font=$script:form.Font;$d.ClientSize=[Drawing.Size]::new(530,230);$d.FormBorderStyle='FixedDialog';$d.StartPosition='CenterParent';$d.MaximizeBox=$false;$d.MinimizeBox=$false
    $info=[Windows.Forms.Label]::new();$info.Text=if($Confirm){'密码至少 10 个字符。请自行记住；家里电脑导入时需要。'}else{'输入导出时设置的迁移密码。'}
    $info.SetBounds(18,15,494,36);$d.Controls.Add($info)
    $box=[Windows.Forms.TextBox]::new();$box.UseSystemPasswordChar=$true;$box.SetBounds(18,58,494,30);$d.Controls.Add($box)
    $again=[Windows.Forms.TextBox]::new();$again.UseSystemPasswordChar=$true;$again.SetBounds(18,108,494,30);$again.Visible=$Confirm;$d.Controls.Add($again)
    $save=[Windows.Forms.Button]::new();$save.Text='确定';$save.SetBounds(284,170,108,32);$d.Controls.Add($save)
    $cancel=[Windows.Forms.Button]::new();$cancel.Text='取消';$cancel.DialogResult='Cancel';$cancel.SetBounds(402,170,108,32);$d.Controls.Add($cancel);$d.CancelButton=$cancel
    $save.Tag=@{Dialog=$d;Box=$box;Again=$again;Confirm=$Confirm}
    $save.Add_Click({param($sender,$eventArgs)
        $c=$sender.Tag
        if($c.Confirm -and ($c.Box.Text.Length -lt 10 -or $c.Box.Text -cne $c.Again.Text)){
            [void][Windows.Forms.MessageBox]::Show('密码至少 10 个字符，两次填写需一致。','请检查密码');return
        }
        $c.Dialog.DialogResult='OK';$c.Dialog.Close()
    })
    try{if($d.ShowDialog($script:form) -eq 'OK'){return $box.Text};return $null}finally{$d.Dispose()}
}
function Get-PanelTransferAccounts {
    return @(foreach($e in $script:entries){
        $a=Read-PanelAccount $e
        if($a.username -and $a.password){
            $item=@{Id=$e.Id;Name=$e.Name;Url=$e.Url;Account=@{username=$a.username;password=$a.password}}
            if($e.Tunnel){$item.TunnelPrivateKey=Read-TunnelPrivateKey $e}
            $item
        }
    })
}
function Export-PanelAccounts {
    try{
        $accounts=@(Get-PanelTransferAccounts)
        if(-not $accounts.Count){throw '目前没有可导出的面板账号。'}
        $password=Get-TransferPassword $true;if(-not $password){return}
        $dialog=[Windows.Forms.SaveFileDialog]::new();$dialog.Filter='加密账号文件 (*.vpsaccounts)|*.vpsaccounts';$dialog.FileName='面板账号-加密迁移.vpsaccounts'
        try{
            if($dialog.ShowDialog($script:form) -ne 'OK'){return}
            $payload=@{Version=1;Accounts=$accounts} | ConvertTo-Json -Depth 12 -Compress
            Write-AtomicText $dialog.FileName (Protect-TransferText $payload $password) ([Text.UTF8Encoding]::new($false))
            [void][Windows.Forms.MessageBox]::Show('加密导出完成。把这个文件带到家里，在管理窗口点击「导入跨电脑账号」。'+"`n"+'包含面板账号、名称及已配置面板的专用隧道密钥；不包含 root SSH 密码或节点密钥。请妥善保管迁移文件和密码。','导出完成')
        }finally{$dialog.Dispose()}
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'导出失败')}
    finally{$accounts=$null;$password=$null;$payload=$null}
}
function New-PanelImportPlan($Accounts) {
        $planned=@();$seen=@{}
        foreach($item in $Accounts){
            if($seen.ContainsKey($item.Id)){throw '迁移文件包含重复服务器。'};$seen[$item.Id]=$true
            $entry=$script:entries | Where-Object {$_.Id -eq $item.Id} | Select-Object -First 1
            if(-not $entry){throw '迁移文件包含未知服务器。'}
            $oldUri=[Uri]$entry.Url;$newUri=$null
            if(-not [Uri]::TryCreate([string]$item.Url,[UriKind]::Absolute,[ref]$newUri) -or $newUri.Scheme -notin @('http','https') -or $newUri.UserInfo -or $newUri.Host -ne $oldUri.Host){throw '迁移文件中的面板地址与服务器不匹配。'}
            if($entry.Tunnel -and ($newUri.Scheme -ne 'http' -or $newUri.Host -ne '127.0.0.1' -or $newUri.Port -ne $entry.Tunnel.LocalPort)){throw '迁移文件的隧道面板地址不正确。'}
            if(-not $item.Name -or -not $item.Account.username -or -not $item.Account.password){throw '迁移文件的账号信息不完整。'}
            $dest=Join-Path $script:workspace $entry.SecretFile
            $old=if(Test-Path -LiteralPath $dest){[IO.File]::ReadAllText($dest)}else{$null}
            $json=@{username=$item.Account.username;password=$item.Account.password} | ConvertTo-Json -Compress
            $encrypted=ConvertFrom-SecureString (ConvertTo-SecureString $json -AsPlainText -Force)
            $p=@{Entry=$entry;Item=$item;Path=$dest;Old=$old;OldName=$entry.Name;OldUrl=$entry.Url;Encrypted=$encrypted;KeyPath=$null}
            if($entry.Tunnel){
                $key=[string]$item.TunnelPrivateKey
                if($key.Length -gt 4096 -or -not $key.StartsWith('-----BEGIN OPENSSH PRIVATE KEY-----') -or -not $key.Contains('-----END OPENSSH PRIVATE KEY-----')){throw '缺少有效的面板隧道密钥，请在原电脑重新导出。'}
                $p.KeyPath=Join-Path $script:workspace $entry.Tunnel.KeyFile
                $p.OldKey=if(Test-Path -LiteralPath $p.KeyPath){[IO.File]::ReadAllText($p.KeyPath)}else{$null}
                $p.EncryptedKey=ConvertFrom-SecureString (ConvertTo-SecureString $key -AsPlainText -Force)
            }
            $planned+=$p
        }
        return $planned
}
function Save-PanelImportPlan($planned) {
        try{
            foreach($p in $planned){Write-AtomicText $p.Path $p.Encrypted ([Text.Encoding]::ASCII);if($p.KeyPath){Write-AtomicText $p.KeyPath $p.EncryptedKey ([Text.Encoding]::ASCII)};$p.Entry.Name=$p.Item.Name;$p.Entry.Url=$p.Item.Url}
            Save-ManagerConfig
        }catch{
            foreach($p in $planned){$p.Entry.Name=$p.OldName;$p.Entry.Url=$p.OldUrl;if($null -ne $p.Old){Write-AtomicText $p.Path $p.Old ([Text.Encoding]::ASCII)}elseif(Test-Path -LiteralPath $p.Path){[IO.File]::Delete($p.Path)}}
            foreach($p in $planned){if($p.KeyPath){if($null -ne $p.OldKey){Write-AtomicText $p.KeyPath $p.OldKey ([Text.Encoding]::ASCII)}elseif(Test-Path -LiteralPath $p.KeyPath){[IO.File]::Delete($p.KeyPath)}}}
            throw
        }
}
function Import-PanelAccounts {
    try{
        $dialog=[Windows.Forms.OpenFileDialog]::new();$dialog.Filter='加密账号文件 (*.vpsaccounts)|*.vpsaccounts'
        try{if($dialog.ShowDialog($script:form) -ne 'OK'){return};$path=$dialog.FileName}finally{$dialog.Dispose()}
        $password=Get-TransferPassword $false;if(-not $password){return}
        if((Get-Item -LiteralPath $path).Length -gt 1048576){throw '迁移文件过大。'}
        $payload=Unprotect-TransferText ([IO.File]::ReadAllText($path)) $password | ConvertFrom-Json
        if($payload.Version -ne 1){throw '不支持的账号内容。'}
        $planned=@(New-PanelImportPlan $payload.Accounts)
        Save-PanelImportPlan $planned
        Build-ManagerRows
        [void][Windows.Forms.MessageBox]::Show(('已导入 '+$planned.Count+' 台面板账号，并在这台电脑重新加密保存。'),'导入完成')
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'导入失败')}
    finally{$password=$null;$payload=$null;$planned=$null}
}
