# 安全说明

此仓库是旧版实验脚本的源码发布，默认 admin/admin 为公开示例凭据；部署会重置相关设置。仅用于可信局域网，并在实际使用前修改各服务凭据。

Primitive FTPd 7.5 有已知导出组件授权问题，官方在 8.2 修复，见 [上游公告](https://github.com/wolpi/prim-ftpd/security/advisories/GHSA-j72x-x52h-247j)。本次没有更新依赖，也没有发布该 APK。

请勿提交设备归档、私钥、Samba 账号数据库、Copyparty 会话、访问日志、个人密码或设备备份。.gitignore 是辅助措施，提交前仍应核对暂存文件。

如需报告新的安全问题，请优先使用仓库 Security 页面提供的私密报告入口；若该入口不可用，可发不含敏感细节的 Issue 请求私下联系。不要公开密码、私钥或可识别个人设备的数据。
