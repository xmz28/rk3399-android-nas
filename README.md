# RK3399 Android NAS

将已 root 的 RK3399 Android 设备用作局域网 NAS。使用 Windows 部署脚本配置 Samba、HTTP 文件管理、FTP / SFTP、OpenSpeedTest，以及有线网口自动 WAN / LAN。

> 当前公开的是 **2026-08-25 旧版部署脚本与配置**。此次仅整理开源目录，没有合入后续多盘共享、统一网页入口或两个 Android App。仓库不包含离线安装资源，下载源码后不能直接一键部署。

## 功能

- Samba SMB2 / SMB3 文件共享
- Copyparty HTTP 文件管理
- Primitive FTPd 提供 FTP / SFTP
- OpenSpeedTest 局域网测速
- 有线网口自动识别上游 DHCP，或进入电脑直连 LAN 模式
- Android init / Magisk 开机启动
- Windows 一键部署、状态查看与服务卸载

## 运行环境

- Windows 10 / 11，Windows PowerShell 5.1
- ARM64 RK3399，开启 USB 调试并授权 ADB
- 可用 root；Android 7.1 userdebug 使用 adb root / remount，Android 10 预留 Magisk service.d 路径
- 有线网卡名称为 eth0

Android 10 路径是脚本支持范围，此次没有重新验证不同 ROM。脚本会替换 `/data/local/alpine-nas`，并可能覆盖已有 NAS 配置；内置共享目录 `/data/media/0/NAS` 保留。此版本不适合覆盖已经配置了后续功能的设备。

## 快速开始

1. 下载源码或克隆仓库。
2. 按 [离线资源准备](docs/离线资源准备.md) 补齐 `payload/` 与 `tools/`。
3. 只连接一台目标 RK3399，确认 root 可用。
4. 双击 `一键部署.bat`；脚本会安装服务、配置开机启动，并默认重启设备。
5. 重启后运行 `查看状态.bat`，检查服务端口。

也可以在 PowerShell 中指定设备：

```powershell
.\deploy.ps1 -Serial <ADB序列号>
.\deploy.ps1 -Serial <ADB序列号> -NoReboot
.\status.ps1 -Serial <ADB序列号>
```

完整说明见 [使用说明](docs/使用说明.md)。本次发布没有提供可公开下载的完整离线部署包。

## 服务入口

默认账号及密码均为 `admin`，仅用于旧版实验环境，请在使用前修改各服务凭据。

| 服务 | 地址 | 默认账号 |
| --- | --- | --- |
| Samba | `\\设备IP\NAS` | admin |
| HTTP 文件管理 | `http://设备IP:3923` | admin |
| FTP | `ftp://设备IP:12345` | admin |
| SFTP | `设备IP:1234` | admin |
| OpenSpeedTest | `http://设备IP:3000` | 无 |

文件共享目录为 `/data/media/0/NAS`。HTTP、FTP、SFTP 和 Samba 指向同一内置目录。

## 自动 WAN / LAN

- 接到提供 DHCP 的路由器：使用 Android 获得的上游地址，进入 WAN / 客户端模式。
- 网线直连电脑，15 秒内没有取得上游地址：进入 LAN 模式。
- LAN 地址：`192.168.1.1/24`；DHCP 地址池：`192.168.1.100`–`192.168.1.200`。
- LAN DHCP 仅下发地址和掩码，不下发默认网关或 DNS。

这里的 WAN 是 DHCP 客户端模式，不包含 NAT 路由转发。

## 项目结构

```text
device/                 Android 服务、安装脚本和示例配置
docs/                   使用说明与离线资源准备
payload/                本地离线资源位置（仓库仅包含说明）
tools/                  本地 Windows ADB 位置（仓库仅包含说明）
deploy.ps1              部署入口
status.ps1              状态入口
uninstall.ps1           卸载入口
SHA256SUMS.txt          本仓库部署脚本及配置的 SHA-256
THIRD_PARTY_NOTICES.md   第三方依赖说明
```

## 项目状态与安全

- 本次只做源码发布整理，没有执行部署或重启验收，也没有更新服务实现。
- 私有设备归档、密钥、会话数据库、历史日志、APK 和 ADB 二进制不随仓库发布。
- 旧版安装脚本依赖预配置 Alpine 环境；目前没有全自动、可复现的 rootfs 构建流程。
- Primitive FTPd 7.5 存在已知导出组件授权问题；官方在 8.2 修复，见 [安全公告](https://github.com/wolpi/prim-ftpd/security/advisories/GHSA-j72x-x52h-247j)。本次保留旧版脚本接口，不升级依赖。
- 只在可信局域网使用，不将文件服务或测速端口映射到公网。

详细范围见 [发布记录](CHANGELOG.md)，安全问题处理见 [SECURITY.md](SECURITY.md)。

## 致谢与许可

依赖 Samba、Copyparty、Primitive FTPd、OpenSpeedTest、Alpine Linux 和 Android Platform Tools，见 [第三方说明](THIRD_PARTY_NOTICES.md)。

本仓库自有部署脚本与文档以 [MIT License](LICENSE) 发布。第三方软件保留各自许可，不适用本仓库 MIT 许可。
