# 3XUI 面板管家 · 独立公开版

面向 Windows 的 3X-UI / VPS 桌面管理工具，用于集中保存服务器资料、打开管理面板、检测状态及查看资源。

公开版使用独立的程序身份和数据目录，首次运行为空列表，不附带服务器、账号、密码、密钥或个人运行记录。

## 快速开始

1. 在 Windows 10 / 11 上运行构建生成的 `dist\3XUI-Panel-Manager.exe`。
2. 点击「添加服务器」，填写自己的服务器和面板资料。
3. 按需要录入面板账号，再使用面板入口、状态检测和资源监控。新增服务器界面支持 HTTP / HTTPS 面板地址；SSH 隧道需要高级手动配置，见 [安全说明](docs/SECURITY.md)。

运行环境需要 Windows PowerShell 5.1。SSH 功能调用 Windows OpenSSH 客户端，请先确认 `ssh.exe` 可用；未配置 SSH 时，仍可管理服务器资料和打开面板。

## 已有功能

- 新增、编辑和删除服务器，保存分组、备注、到期时间等资料。
- 集中管理面板入口和面板账号。
- 检测服务器状态，查看资源信息，按配置建立面板 SSH 隧道。
- 支持明暗主题、搜索及服务器排序。
- 通过设置密码的 `.vpsaccounts` 文件迁移面板账号及已配置的隧道密钥。

服务器端功能需要有效的连接配置和相应权限，程序不会替你安装 3X-UI。

## 数据与迁移

默认数据目录：

```text
%LOCALAPPDATA%\3XuiPanelManagerPublic\data
```

公开版通过 `.3xui-panel-manager-public.json` 识别自己的数据，不自动发现或导入其他版本的数据。更新程序前请备份自己的数据目录。

本机账号使用 Windows DPAPI 保护，通常只能由原 Windows 用户在原系统环境中解密，旧 `.dpapi` 文件不能直接跨用户使用。

跨电脑迁移分两步：

1. 在原电脑导出 `.vpsaccounts` 并设置迁移密码。关闭两端程序，将公开版数据目录的目录结构、`.3xui-panel-manager-public.json`、`统一管理\服务器列表.json`、`统一管理\服务器元数据.json` 和 `统一管理\购买来源.json` 中已有的文件复制到目标公开版数据目录，保留服务器 ID。若配置了隧道，还需复制已核实的 `known_hosts` 文件。
2. 启动目标电脑的公开版，确认服务器列表已存在，再导入 `.vpsaccounts`。程序将账号和隧道密钥按目标 Windows 用户重新加密保存。

`.vpsaccounts` 只包含面板账号及已配置的隧道密钥，不会创建未知 ID 的服务器，也不替代服务器配置和元数据备份。复制前请备份目标目录；这些配置和迁移文件仍是敏感资料，不要提交到 GitHub。

## 从源码运行与构建

在仓库根目录运行：

```powershell
# 从源码启动
powershell -NoProfile -ExecutionPolicy Bypass -File src\Panel-Manager.ps1

# 构建独立可执行文件
powershell -NoProfile -ExecutionPolicy Bypass -File src\Build-Windows-Client.ps1

# 检查公开文件中的隐私泄漏风险
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\Test-PublicPrivacy.ps1
```

构建输出位于 `dist\3XUI-Panel-Manager.exe`。GitHub Actions 会在 Windows 环境构建并提供可下载的构建产物。

仓库只应包含源码、构建脚本和文档。`dist`、临时构建目录、本地运行数据、日志、账号迁移文件和 SSH 密钥均已加入忽略规则。提交前仍应检查暂存内容，避免手动强制加入自己的资料。

## 安全与授权

使用及提交前的说明见 [安全说明](docs/SECURITY.md)。

当前尚未指定开源许可证；公开源码不等于授予复制、修改或再分发许可，具体授权以仓库所有者后续声明为准。
