# Android CI、构建和签名

[返回 README](../README.md) · [本仓库 Android CI](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml)

唯一维护的构建工作流为 [android-font-build.yml](../.github/workflows/android-font-build.yml)，主要使用 Flutter **3.24.5**、JDK **17**、Android SDK **34** 和锁定的 `pubspec.lock`。本仓库不提供 Windows/Linux/iOS 的 CI 或安装包。

## 自动检查

代码合入 `main` 或提交 Pull Request 且修改 Flutter 工程、工作流时触发：

1. `flutter pub get --enforce-lockfile`
2. `flutter analyze --no-pub --no-fatal-infos`（error 和 warning 不能通过；部分 info 仅记录）
3. 先运行账号管理与字体的集中回归测试，防止单个超时隐藏错误
4. 再运行所有离线 Flutter 测试
5. Android Debug 与 Profile APK 使用独立 job 构建并上传，不依赖测试 job 的状态；**只有两项任务都成功才能宣称此版本检查通过**

测试设有明确超时，不能把卡住的测试删掉或隐藏。在线 API / 人机验证的测试默认跳过，离线测试全部通过也不表示真实账号服务稳定。

## 下载 Android 测试 APK

在 [Android CI](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml) 中打开对应提交的运行记录，展开 `Build Android debug and profile APKs` 确认任务成功，再到 Artifacts 下载（保留 14 天，可能需要登录 GitHub）：

- **`c001apk-android-profile` → `app-profile.apk`**：推荐用于比较页面切换流畅度。Profile 使用 AOT 编译，较接近 Release，但仍有少量性能分析开销；它并非正式发行版。
- **`c001apk-android-debug` → `app-debug.apk`**：开发调试包；JIT 和断言会影响性能。右上角的 DEBUG 字样已经隐藏，但程序仍在 Debug 模式运行。

这两种构建都不是正式签名版本，不同构建之间可能无法直接覆盖安装。不要在没有备份本地数据的情况下卸载已有应用。

Android 本 fork 的 applicationId 为 `io.github.ktclat.c001apk`；与原维护仓库的 APK 包名不同，可以并存，但本地数据不会自动迁移。Debug APK 仍没有正式发布签名；未来本仓库发布新版时，签名一致才能覆盖安装。卸载任意旧版前均应备份该应用本地数据。Debug APK 不是正式版，也不自动成为 GitHub Release。

## Android 本地构建

在 `apps/flutter` 目录运行：

```bash
flutter --version
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --profile --no-pub
```

Gradle 使用系统 JDK 17；必要时执行 `flutter config --jdk-dir=/path/to/jdk17`。Android SDK 包括 `platforms;android-34`、`build-tools;34.0.0`、`build-tools;30.0.3` 和 `ndk;23.1.7779620`。

## 正式版发布（待维护者配置）

本仓库**暂未配置自己的正式 Android 发布签名**，也不使用上游维护者的签名密钥、证书指纹或 GitHub Releases。计划在单独配置安全的 keystore、构建验证和签名校验后提供 Release 包。未来签名密钥必须保存在仓库 Secrets，绝不提交到源码或上传到 Artifacts。

更新检查仅使用 `https://api.github.com/repos/Ktclat/c001apk/releases/latest`。在此仓库尚无正式 Release 时，手动检查可能显示“暂未找到正式版本”，这是预期行为；不会借用原维护仓库的版本。

## 常见失败

- **APK 绿、测试红：** 并非完整通过，先点开失败 job 的 Test Failure。
- **账号测试卡住：** 优先检查 `test/ui/account_settings_test.dart` 的异步泵帧、Hive 写入和测试退出清理。
- **`invalid source release: 17`：** 确认 JDK 17 和 `flutter config --jdk-dir`。
- **旧 Node Action 弃用警告：** 使用兼容 Node 24 的最新版 GitHub Actions。
- **不能覆盖安装：** APK 包名相同但签名不一致。不要为安装而冒险删除未备份的数据。

## 真实性

云端任务只验证其对应提交的源代码和构建环境。**未在本项目设备上实测的内容不得在 README 中标为已验证。** 欢迎在 [本仓库 Issues](https://github.com/Ktclat/c001apk/issues) 提供脱敏日志。
