# RK3399 Android NAS

将已 root 的 RK3399 Android 设备用作多盘 NAS。Samba 与 Copyparty 共享同一磁盘视图，网页统一提供文件管理、网络测速和外部 USB 存储管理。

当前版本：`0.2.0`，整合 2026-10-12 的开发实现。

> 此版本用于**升级已安装并初始化 Alpine NAS 的设备**，保留文件服务账号、SFTP 身份和磁盘编号。它不提供全新设备的 rootfs 安装包，也不会重新解压旧设备归档。升级安装器尚未在真实设备上执行验收。

## 功能

- 内置 NAS 与各 USB 卷独立共享，支持 SMB2 / SMB3、FTP、SFTP、网页和 WebDAV
- USB 热插拔、持久编号、只读标记和安全卸载
- `http://a.local/` 统一入口：文件管理、测速、存储管理
- Nginx 代理与 OpenSpeedTest 响应头适配
- iperf3 测速服务与 Avahi / mDNS 发现
- USB 容量查看、安全弹出、重新挂载和 FAT 格式化后端
- Windows 升级入口、前置检查、文件备份和失败恢复
- 兼容已有 Android init 或 Magisk NAS 开机钩子

存储管理网页通过 RK3399 Control 的 8765 端口认证接口工作。没有配套控制 App 时，文件共享仍可使用，存储页面不可用。文件服务密码与控制密码是两套凭据。

## 快速开始

1. 下载源码，按 [依赖准备](docs/离线资源准备.md) 准备 ADB 和已有 Alpine NAS 环境。
2. 开启 USB 调试，确认目标为已 root 的 ARM64 RK3399。
3. 先执行前置检查，再升级：

```powershell
.\deploy.ps1 -Serial <ADB序列号> -CheckOnly
.\deploy.ps1 -Serial <ADB序列号>
```

也可以双击 `一键部署.bat`。自动选择设备时，仅接受唯一的 RK3399；不自动选择普通手机。

默认不重启。需要在升级后验证开机恢复，可显式使用 `-Reboot`。检查模式会推送检查脚本，但不覆盖服务文件。

完整说明见 [使用说明](docs/使用说明.md)。

## 服务入口

| 服务 | 地址 |
| --- | --- |
| 首页 | `http://a.local/` |
| 文件管理 / WebDAV | `http://a.local/files/` |
| OpenSpeedTest | `http://a.local/speedtest/` |
| USB 存储管理 | `http://a.local/storage/` |
| Samba | `\\a.local\NAS`、`\\a.local\USB1` 等 |
| FTP | `ftp://a.local:12345` |
| SFTP | `a.local:1234` |
| iperf3 | `a.local:5201` |

以上是默认端口；升级保留已有 Copyparty 自定义 HTTP、FTP、SFTP 端口。无法解析 a.local 时使用设备实际 IP。SMB 网络名称保留已有配置。

内置目录是 `/data/media/0/NAS`；外部卷由 Android vold 挂载后导出，不合并容量。USB 编号存储在 `/etc/nas-usb-names/`，不会预留任何特定磁盘 UUID。

## 目录结构

```text
device/                  当前服务、网页、升级和恢复脚本
docs/                    部署、依赖与 USB 管理说明
legacy/v0.1.0/           旧 FTP 初始化及网络脚本参考
tests/                   不访问设备的升级逻辑测试
payload/                 本地可选控制 App APK，二进制不上传
tools/                   本地 Windows ADB，二进制不上传
deploy.ps1               升级、前置检查、状态、恢复入口
SHA256SUMS.txt           部署入口和当前 device 文件校验
```

## 项目状态

- 当前源码覆盖多盘共享、统一网页和 USB 存储管理；后者需要配套控制 App。
- 本次执行主机端测试与语法检查，没有执行设备升级、重启、磁盘写入或格式化。
- 新升级入口、失败恢复及 Magisk 路径需要实机验收；当前控制 App 与 Magisk watcher 不兼容，检查会拒绝这个组合。端口健康检查不代表所有协议操作通过。
- 升级保留已有网口模式与 OpenSpeedTest 启动方式，不自动替换旧网络配置。
- 两个 Android App 的源码尚未纳入本仓库；本地 APK 是可选依赖，不属于公开下载内容。

版本变化见 [CHANGELOG](CHANGELOG.md)。只在可信局域网使用，不将文件服务与控制端口直接映射到公网。参见 [安全说明](SECURITY.md)。

## 致谢与许可

依赖 Samba、Copyparty、Nginx、Avahi、iperf3、Alpine Linux、OpenSpeedTest 和 Android Platform Tools，详见 [第三方说明](THIRD_PARTY_NOTICES.md)。

自有脚本、网页与文档以 [MIT License](LICENSE) 发布；第三方软件保留各自许可。设备凭据、密钥、会话、日志、rootfs 归档与 APK 不上传。
