# 第三方依赖说明

Git 仓库发布自有部署源码。0.3.0 Release 另附 Copyparty SFX、OpenSpeedTest 静态网页及自有控制 APK；保留所附资源的许可文件。Alpine Linux 软件包与 Android Platform Tools 从官方源下载，不包含在公开 ZIP 中。自有 MIT 许可不替代第三方许可。

| 依赖 | 作用 | 上游与许可参考 |
| --- | --- | --- |
| Alpine Linux | ARM64 Linux 用户环境 | [官网](https://alpinelinux.org/)，各软件包分别采用自身许可 |
| Samba | SMB2 / SMB3 共享 | [官网](https://www.samba.org/)、[GNU GPL v3](https://www.samba.org/samba/docs/GPL.html) |
| Copyparty | HTTP 文件管理 | [项目](https://github.com/9001/copyparty)、[MIT](https://github.com/9001/copyparty/blob/hovudstraum/LICENSE)，内嵌依赖需另查其声明 |
| Primitive FTPd | Android FTP / SFTP | [项目与许可文件](https://github.com/wolpi/prim-ftpd) |
| OpenSpeedTest | Android 测速服务 | [官方页面](https://openspeedtest.com/)、[HTML5 项目](https://github.com/openspeedtest/Speed-Test)；Android APK 的分发条款另行核对 |
| dnsmasq | LAN DHCP | [官网](https://thekelleys.org.uk/dnsmasq/doc.html)，以使用版本附带许可为准 |
| Android Platform Tools | Windows ADB | [官方下载与条款](https://developer.android.com/tools/releases/platform-tools) |
| Nginx | 网页与代理 | [上游与许可](https://nginx.org/en/LICENSE) |
| Avahi | mDNS 发现 | [上游](https://github.com/avahi/avahi)，以所用包的许可声明为准 |
| iperf3 | 网络吞吐测试 | [上游](https://github.com/esnet/iperf)，以所用包的许可声明为准 |
| Paramiko | SFTP 与密钥转换 | [上游](https://github.com/paramiko/paramiko)，以所用包的许可声明为准 |
| OpenSSH | Alpine SSH 远程管理 | [上游](https://www.openssh.com/)，以所用 Alpine 包的许可声明为准 |
| sudo | Alpine admin 提权 | [上游](https://www.sudo.ws/)，以所用 Alpine 包的许可声明为准 |
| wsdd | Windows WSD 发现 | [上游](https://github.com/christgau/wsdd)，以所用 Alpine 包的许可声明为准 |

Copyparty 固定为 1.20.25，其 SFX 包含内嵌依赖声明，完整源码见 [固定版本](https://github.com/9001/copyparty/tree/v1.20.25)。OpenSpeedTest 网页固定为 [f4263546](https://github.com/openspeedtest/Speed-Test/tree/f4263546f50694a154fdd27a03000390949068df)，保留 License.md；30 MiB downloading 数据在安装时生成，HTML / JS 资源保持上游内容。其 Roboto 字体使用 Apache License 2.0，资源包另附字体许可。

Linux 依赖由设备向 Alpine 仓库获取，遵循各包许可；已安装软件包的版本、许可和构建提交记录在 `/usr/share/rk3399-nas/apk-installed.txt`，构建源码可在 [Alpine aports](https://gitlab.alpinelinux.org/alpine/aports) 对应提交查询。请勿把本地镜像当成已完成再分发许可整理的公开离线包。
