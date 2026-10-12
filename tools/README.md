# Windows ADB

优先使用本地 ADB 或 Android SDK 的 platform-tools。缺少时自动下载固定哈希的官方工具到 `tools/platform-tools/`，也可通过 `-AdbPath` 指定。工具不包含在公开 Release ZIP 中，参见 [资源准备](../docs/离线资源准备.md)。
