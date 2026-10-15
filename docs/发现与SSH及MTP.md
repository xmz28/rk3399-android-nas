# 局域网发现、SSH 管理与 MTP 同步

## 本轮范围

0.3.1-rc1 从本地开发实现整合服务，安装入口同时适配首次安装、已有 NAS 升级、init 与 Magisk 脚本目录。本轮仅执行主机测试、固定 Copyparty 源码修补检查和语法检查，没有向真实设备部署或执行重启。

## Windows 与 Bonjour 发现

wsdd 使用 IPv4，在可用网络接口发布 `a.local`，供同一局域网的 Windows“网络”发现并打开 `\\a.local`。不固定 eth0/wlan0，以适配 br-lan 与 USB 网卡；防火墙仍需允许 WSD UDP 3702 和 HTTP 元数据 TCP 5357。RK3399 Control 本轮在直连私网上游按原来源子网限制放行这些端口，跨子网多播发现仍待实测。

Avahi 发布 `a.local` 及 `_smb._tcp:445`、`_ssh._tcp:22`；服务名称使用主机名通配符，不携带开发设备身份。Bonjour 浏览、Windows WSD 与实际协议登录是不同检查，公告成功不代表传输成功。iPhone 可手动连接 `smb://a.local`，本轮未做 iPhone 实测。

wsdd 随 NAS 守护维护，启动遵循 Samba 与 mDNS 开关。开关的停止操作由配套控制器负责，不能将公告是否存在作为服务已停用的唯一依据。日志为 Alpine `/var/log/wsdd.log`。

## Alpine SSH 与 sudo

使用 `ssh admin@a.local` 或设备实际 IP，端口 22。只允许 admin 登录，禁止 root 直接登录；登录后 `sudo -i` 使用 admin 密码。该账号具有 NAS 系统管理权限，chroot 不是针对特权管理员的隔离边界。

安装器从 `/etc/copyparty-base.conf` 的 admin 账号同步 Unix 密码，保留原 UID/GID，并配置 `/home/admin`、`/bin/ash` 和 Android 网络所需 inet 组。不会重写 Samba 账号数据库，也不会在日志打印密码。若此前 Samba 与 Copyparty 密码已不一致，需自行统一后验收；Unix、Samba、Copyparty 仍是独立密码存储，之后修改一边不会自动更新另外两边。控制 App 8765 使用另一套独立控制密码。

22 端口 OpenSSH 与 1234 端口 Copyparty SFTP 各用独立 Ed25519 身份。已有私钥不替换，首次安装生成新钥；首次 SSH 连接应核对主机公钥。配置为 `/etc/ssh/nas-sshd.conf`，PID 为 `/run/nas-sshd.pid`，日志为 `/var/log/nas-sshd.log`。

Android `/data` 保持 nosuid；守护启动时仅对 root 拥有的 `/usr/bin/sudo` 文件建立独立 bind mount 并启用 suid，停止、回滚或卸载时解除。升级/卸载会中断 SSH 管理会话，须使用 ADB 恢复通道执行。

首次安装构建依赖包含 openssh-server、openssh-keygen、sudo、wsdd；已有环境升级前按资源准备文档安装。22 端口被其他服务占用时，预检拒绝继续。新的账号、密钥与 sudoers 文件进入设备本地私有备份，不能上传。

## 上传与 Android MTP

`nas-mtp-sync.py` 只扫描内置 `/mnt/nas`，连续两次稳定快照后通知 Android MediaProvider 更新新建、变化及删除路径；连接 MTP 时先恢复通知绑定。忽略隐藏文件、`.PARTIAL` 上传中间文件及符号链接。USB 公共卷仍由 Android vold 管理，不主动整盘扫描。

扫描每五秒进行一次，因此不是即时通知。守护重启会保留本轮 `/run/nas-mtp-state.json`，不会改写 NAS 用户文件；大目录扫描成本、Android 版本差异和完整断电恢复需实测。日志为 `/var/log/nas-mtp-sync.log`。

`nas-copyparty-fix.py` 对固定 Copyparty 1.20.25 的解包源码做最小修补，使动态共享重载调度不依赖索引开关；支持带缓存目录参数的 SFX 解包接口。修补重复执行不叠加，未知源码拒绝修改。不要直接替换成未经验证的新版本。
