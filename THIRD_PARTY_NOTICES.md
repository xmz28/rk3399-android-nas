# 第三方依赖说明

本仓库仅发布自有部署脚本、服务配置示例与文档，不包含第三方二进制、第三方源码或设备备份。MIT 许可仅适用于本仓库自有内容。

| 依赖 | 作用 | 上游与许可参考 |
| --- | --- | --- |
| Alpine Linux | ARM64 Linux 用户环境 | [官网](https://alpinelinux.org/)，各软件包分别采用自身许可 |
| Samba | SMB2 / SMB3 共享 | [官网](https://www.samba.org/)、[GNU GPL v3](https://www.samba.org/samba/docs/GPL.html) |
| Copyparty | HTTP 文件管理 | [项目](https://github.com/9001/copyparty)、[MIT](https://github.com/9001/copyparty/blob/hovudstraum/LICENSE)，内嵌依赖需另查其声明 |
| Primitive FTPd | Android FTP / SFTP | [项目与许可文件](https://github.com/wolpi/prim-ftpd) |
| OpenSpeedTest | Android 测速服务 | [官方页面](https://openspeedtest.com/)、[HTML5 项目](https://github.com/openspeedtest/Speed-Test)；Android APK 的分发条款另行核对 |
| dnsmasq | LAN DHCP | [官网](https://thekelleys.org.uk/dnsmasq/doc.html)，以使用版本附带许可为准 |
| Android Platform Tools | Windows ADB | [官方下载与条款](https://developer.android.com/tools/releases/platform-tools) |

这些依赖由用户自行准备。未来若分发 APK、ADB 或包含 Linux 软件包的 rootfs，必须保留第三方声明，并依据对应版本的许可提供所需材料；本次没有审核或授权完整二进制包的再分发。
