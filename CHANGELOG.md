# 发布记录

## 0.3.0-rc1 — 2026-10-12

- 增加联网首次安装、官方资源校验、干净 Alpine 依赖构建、随机密码和独立 SFTP 身份。
- 拒绝覆盖已有 NAS；保留失败安装状态，密码通过临时文件传递。
- 自动准备官方 ADB；Release 附适配控制 APK 与 OpenSpeedTest 网页资源。
- 新装测速使用 Nginx，无需第三方 Android 测速 APK。
- 控制 App 保留新版 watcher 和存储后端，watcher 遵循 Samba、iperf、mDNS 开关。
- 10 项主机 Python 测试、独立 chroot 的 SMB / FTP / SFTP / HTTP 读取通过。
- 空白设备完整安装、失败恢复、重启及 Magisk 流程尚未实机验收。

## 0.2.0 — 2026-10-12

- 整合多盘 SMB / FTP / SFTP / HTTP / WebDAV、固定 USB 编号与安全卸载。
- 整合统一网页、Nginx 测速适配、iperf3、Avahi 和 USB 存储管理源码。
- 新部署入口用于已有 Alpine NAS 升级，不重新解压设备 rootfs。
- 增加依赖与目标检查、源码哈希校验、文件备份和失败恢复。
- 保留 NAS 密码、SFTP 身份、已有磁盘编号和 SMB 设备名。
- 去掉测试 U 盘 UUID 的预设编号；支持脚本目录随 init / Magisk 改变。
- 配套控制 APK 为本地可选资源，两个 App 源码尚未开源。
- 本次仅主机端验证，安装器与恢复流程尚未在真实设备执行验收。

## 0.1.0 — 2026-10-12

首次公开 2026-08-25 旧版 NAS 部署脚本。

- 整理中文 README、使用说明与离线资源清单。
- 增加 MIT 许可、第三方依赖说明和安全说明。
- 排除私有 rootfs、APK、ADB、运行日志、密钥和会话数据库。
- 保留原部署、服务和配置行为，未合入后续多盘共享、统一网页入口或两个 Android App。
- 未提供完整离线安装包，也未重新执行设备部署验收。
