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
- **`c001apk-android-profile-arm64` → `app-normal-arm64-profile.apk`**：普通应用的 arm64 专用 Profile 包，适用于 arm64 Android 设备，不适用于仅支持 32 位或 x86 的设备。与通用 Profile 包使用相同源码和构建标识；不启用诊断入口。上传前检查精确包名 `io.github.ktclat.c001apk`、仅含 arm64 原生库、AOT 库存在且非空、无 Dart JIT kernel 以及 APK 严格小于 50,000,000 字节；超限会失败，不会偷偷替换成诊断包。
- **`c001apk-android-debug` → `app-debug.apk`**：开发调试包；JIT 和断言会影响性能。右上角的 DEBUG 字样已经隐藏，但程序仍在 Debug 模式运行。

注意：固定使用的 [Flutter 3.24.5 Gradle 插件](https://github.com/flutter/flutter/blob/3.24.5/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy) 的 Profile 类型从 Debug 初始化，Android 清单仍可带 `debuggable=true`；这不等于 Flutter Debug/JIT 模式。CI 通过固定的 `--profile` 构建命令和 APK 中的 AOT 库、无 JIT kernel 布局联合验证，而不是要求 Android 不可调试。Profile 仍是可分析的测试包，不应作为正式 Release 发布。

以上普通应用构建都不是正式发布签名版本，使用开发测试签名。arm64 包与通用包的包名相同，不能作为两个独立应用并存；不同 CI 运行的开发签名可能不一致，导致覆盖安装失败。不要为安装测试包而卸载未备份本地数据的已有应用。

另保留两个**独立诊断应用**制品：`c001apk-android-motion-profile`（`app-diagnostic-profile.apk`，通用）和 `c001apk-android-motion-arm64-profile`（`app-motion-arm64-profile.apk`，arm64）。它们使用 `io.github.ktclat.c001apk.diagnostic.motion` 和“c001apk 动效验证”名称，只用于动效诊断，不是普通应用的替代包。原有诊断包身份、沙箱和外链隔离检查保持独立。普通 arm64 包在所有诊断构建之前完成验证和上传，避免复用诊断输出。

Android 本 fork 的 applicationId 为 `io.github.ktclat.c001apk`；与原维护仓库的 APK 包名不同，可以并存，但本地数据不会自动迁移。Debug APK 仍没有正式发布签名；未来本仓库发布新版时，签名一致才能覆盖安装。卸载任意旧版前均应备份该应用本地数据。Debug APK 不是正式版，也不自动成为 GitHub Release。

## Android 本地构建

在 `apps/flutter` 目录运行（先拉取校验过的开源字体文件）：

```bash
bash tools/fetch_fonts.sh
flutter --version
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --profile --no-pub
# 可选：普通应用 arm64 专用包（不设置 diagnosticBuild 或 APP_DIAGNOSTIC）
flutter build apk --profile --no-pub --split-per-abi --target-platform android-arm64
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
