# 真机连接（WSL2 无线 adb）

> 本文档原是 `spikes/tech_validation/README.md` 的一节；spike 工程已在工单 23 归档删除
> （结论沉淀于 ADR-0005/0006），WSL2 连真机的方法是日常操作，移此保留。

WSL2 不直通 USB，无线调试最简单：

1. 手机：开发者选项 → 无线调试 → **使用配对码配对设备**，把显示的 `IP:端口` 和 6 位配对码发给 Claude
2. Claude 执行 `adb pair` + `adb connect`
3. 之后 `flutter run` / `flutter install` 即可

USB 连接的手机需要 Windows 侧 `usbipd-win` 转发，非必需（一台真机够用）。

- 真机为 OPPO PCAM00，`adb devices` 里形如 `adb-<id>._adb-tls-connect._tcp  device`。
- 断连重连：手机端无线调试开关一次即生成新端口，重走 pair/connect。
