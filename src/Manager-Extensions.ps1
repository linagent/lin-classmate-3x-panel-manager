# 本地管理器扩展入口。Windows PowerShell 5.1 / UTF-8 BOM。
# 启动器在内置动作注册完成后加载此文件；默认只保留注释，不增加按钮。
# API: Register-ManagerAction -Id -Label -Placement Toolbar|Server -Handler { param($entry) ... }
# 可选 -Primary 将动作标为重点按钮。Handler 中的 $entry 是服务器配置对象；
# Toolbar 动作可忽略 $entry。扩展仅在本机内部调用，没有 HTTP 监听。
# 详细说明见同目录「扩展开发说明.md」。修改后关闭并重新打开管理器。
#
# 下面示例默认禁用。启用前请更换唯一 Id，并确认目录与动作符合自己的用途。
# Register-ManagerAction -Id 'custom-folder' -Label '资料夹示例' -Placement Server -Handler {
#     param($entry)
#     $folderPath = Join-Path $script:workspace $entry.Folder
#     Start-Process explorer.exe -ArgumentList ('"' + $folderPath + '"')
# }
