# RK3399 Android NAS

将已 root 的 ARM64 RK3399 Android 设备用作多盘 NAS，提供 SMB、FTP、SFTP、网页文件管理 / WebDAV、测速和 USB 存储管理。

当前版本：`0.3.0-rc1`，联网首次安装候选版。

> 已在 RK3399 独立临时 chroot 验证账号初始化和 SMB / FTP / SFTP / HTTP 文件读取。空白设备完整安装、失败恢复、重启自启及 Magisk 路径仍待验收。

## 快速开始

1. 从 [Releases](https://github.com/xmz28/rk3399-android-nas/releases) 下载 `rk3399-android-nas-0.3.0-rc1-online.zip` 并解压。
2. 开启 USB 调试；设备须具备 root、BusyBox，以及可写 system 或可用 Magisk。电脑与设备均须能访问官方下载源。
3. 新设备双击 `首次安装.bat`：准备 ADB、校验官方基础镜像、安装 Alpine 依赖、生成账号、配置服务和启动钩子、安装配套控制 App。
4. 文件账号为 `admin`，随机密码保存在解压目录的 `credentials.txt`。打开控制 App、授予 root 并启用远程控制，才能使用存储管理页面；控制密码独立设置。

首次安装拒绝覆盖 `/data/local/alpine-nas`。已有 NAS 使用 `一键部署.bat` 升级，保留账号、SFTP 身份、磁盘编号与数据。

```powershell
.\deploy.ps1 -Fresh -CheckOnly       # 新设备仅检查条件
.\deploy.ps1 -Fresh -InstallControl # 新设备安装 NAS 和配套控制 APK
.\deploy.ps1 -CheckOnly             # 已有设备检查
.\deploy.ps1                        # 已有设备升级
```

自动选择唯一 RK3399，拒绝普通手机；多个 RK3399 时需加 `-Serial <ADB序列号>`。默认不重启，可显式加 `-Reboot`。不自动 root、刷机或 remount。

源码 ZIP 不含 APK；完整候选包通过 Release 下载。公开包为联网安装包，Linux 环境在设备上由官方 Alpine 仓库构建。详见 [使用说明](docs/使用说明.md) 和 [资源准备](docs/离线资源准备.md)。

## 功能与入口

| 功能 | 默认地址 |
| --- | --- |
| 首页 | `http://a.local/` |
| 文件管理 / WebDAV | `http://a.local/files/` |
| OpenSpeedTest | `http://a.local/speedtest/` |
| USB 存储管理 | `http://a.local/storage/` |
| Samba | `\\a.local\NAS`、`\\a.local\USB1` 等 |
| FTP | `ftp://a.local:12345` |
| SFTP | `a.local:1234` |
| iperf3 | `a.local:5201` |

无法解析 a.local 时使用实际 IP。升级保留 Copyparty 自定义端口与 SMB 名称。内置共享为 `/data/media/0/NAS`，每个 USB 卷独立共享，支持热插拔、固定编号、只读标记、安全弹出和 FAT 格式化。部署本身不执行格式化。

新装测速由 Nginx 托管 OpenSpeedTest 网页，无需 Android 测速 APK；升级保留原服务。存储网页通过控制 App 的 8765 认证接口工作，文件服务和控制服务使用两套密码。

## 配套 App

- [RK3399 Control](https://github.com/xmz28/rk3399-control)：设备服务、网络、USB 与远程控制。
- [RK3399 Network Toolbox](https://github.com/xmz28/rk3399-network-toolbox)：手机测速、文件访问和远程控制。

Release 附控制 App 的调试签名候选构建。适配版保留新版 NAS watcher 和存储后端；旧控制 App 在 Magisk 下会停止 watcher，需要先更新并打开适配版。不同签名的 APK 无法直接覆盖安装。

## 目录

```text
device/                  服务、网页、首次安装、升级及恢复脚本
docs/                    部署、依赖与 USB 管理说明
tests/                   主机测试、独立 chroot 协议验证
legacy/v0.1.0/           历史参考，不参与新版部署
payload/                 资源缓存；Release 另附 APK 与 MIT 网页资源
tools/                   本地或下载的 Windows ADB
deploy.ps1               首次安装、升级、检查及恢复入口
prepare-resources.ps1    官方资源下载和校验
build-rootfs.sh          干净 Alpine 依赖构建配方
resources.json           固定资源版本、地址和 SHA-256
SHA256SUMS.txt           当前部署源码校验
```

## 验证状态

- 10 项 Python 主机测试、ADB 模拟检查及语法检查通过。
- 独立 chroot 的 SMB、FTP、SFTP、HTTP 实际读取通过；新装测速后端另行检查。
- 没有替换现有 NAS、重启或格式化。空白设备完整流程、失败恢复、重启及 Magisk 路径仍待验收。
- 升级保留原网口与测速启动方式。端口健康检查不代表全部协议和 USB 操作通过。

版本记录见 [CHANGELOG](CHANGELOG.md)。只在可信局域网使用，参见 [安全说明](SECURITY.md)。

## 许可

自有内容使用 [MIT License](LICENSE)，第三方软件保留各自许可，见 [第三方说明](THIRD_PARTY_NOTICES.md)。公开包从官方源下载 Alpine 和 ADB，不分发个人设备 rootfs；密码、私钥、会话、账号数据库与设备日志不上传。
