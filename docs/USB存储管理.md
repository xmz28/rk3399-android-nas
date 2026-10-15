# USB 存储管理

内置 NAS 与各 USB 公共卷独立显示，不合并容量。Android vold 负责识别和挂载；NAS 每两秒刷新卷入口。不能被 Android 挂载的文件系统不会自动共享。

## 编号与权限

- 新 UUID 从第一个空闲 USB 编号开始分配，记录持久保存。
- 普通换盘或外部工具格式化改变 UUID，会获得新编号。
- 存储管理中的格式化会保留原 USB 编号。
- 只读标记在 Alpine `/etc/samba/usb-readonly-UUID`，五种文件服务共用权限。
- 拔出与重插不改变已记录的 UUID 编号，离线盘保留记录。

## 安全卸载

停止传输，在 http://a.local/storage/ 登录后选择安全弹出。脚本先暂停共享、关闭 SMB 连接、解除 NAS bind、检查打开的文件，再 sync 并请求 vold 卸载。只有成功提示后才拔盘。

也可在 init 设备用 root 执行 `/system/bin/nas-usb-eject.sh USB编号`；Magisk 脚本路径为 `/data/local/rk3399-nas/scripts/nas-usb-eject.sh`。

## 格式化

格式化会删除所选卷全部数据。界面要求输入完整 USB 编号确认，当前只开放可写 USB 卷的 FAT / vfat 格式化。只读卷、内置 NAS 和系统盘没有格式化入口。

请求检查 UUID 和设备身份，旧页面或换盘后须刷新；操作串行执行。格式化后文件服务短暂重启以更新路径。页面登录依赖 RK3399 Control，文件密码不等于控制密码。

## 验证范围

开发目录后续记录了当前板子的 NTFS 读写与重挂测试；这依赖该设备 Android vold 的现有支持。本项目仍仅提供 FAT32 格式化。exFAT 在 Alpine 手动挂载的历史测试不等于 Android 自动挂载或 NAS 自动共享支持，本轮不增加 NTFS / exFAT 格式化，也不包含开发设备 UUID 或固定磁盘编号。

开发目录记录了当前设备上的多盘及三端操作测试。此次打包只执行主机端逻辑测试和语法检查，没有再次写盘、格式化或验证重启。不能将源码整合视为所有设备的实机验收。
