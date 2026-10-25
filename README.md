# c001apk · Android

> 本仓库 **Ktclat/c001apk** 是一个专注 Android 的非官方酷安客户端项目，使用 Flutter 开发。与酷安官方无隶属关系。本仓库的开发、反馈、构建及发布均由本仓库维护者负责。

[![Android CI](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml/badge.svg?branch=main)](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml) [![AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue)](LICENSE)

**项目入口：** [Android 构建](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml) · [版本发布](https://github.com/Ktclat/c001apk/releases) · [本仓库问题反馈](https://github.com/Ktclat/c001apk/issues) · [开发文档](docs/DEVELOPMENT.md)

## 现有功能

- 中文动态、评论、文章、应用详情、搜索与个人空间。
- 游客浏览、账号登录与切换、本地关注与悄悄关注、收藏及浏览历史。
- Material 3 动态取色、深色模式、**内置思源黑体／跟随系统／Material 原版字体选项**、独立字号调整、**舒适阅读／原版正文排版**，以及可切换的**悬浮 Tab 导航**（[使用说明](docs/ANDROID_NAVIGATION.md)）。
- 本仓库独立的版本更新检查；未发布正式 GitHub Release 时，会提示暂无正式版本。
- Android 设备标识可**从官方导入或手动填写**；支持编辑制造商、品牌、机型与系统参数（仅在主动粘贴时读取剪贴板）。详见[设备标识说明](docs/DEVICE_ID_IMPORT.md)。

部分功能受酷安服务端接口、登录及人机验证限制。开发中的功能不代表已经完成真机或在线验收。

## Android 安装与构建

当前可在 [Android CI](https://github.com/Ktclat/c001apk/actions/workflows/android-font-build.yml) 打开最近一次运行记录，在 **Artifacts** 下载 `c001apk-android-profile`（AOT，适合性能体验测试）或 `c001apk-android-debug`（开发调试）。右上角 DEBUG 横幅已隐藏，但 **Debug 模式性能仍低于 Profile**。**绿色 APK 构建任务只表示成功编译；必须再核对测试任务是否通过。**

本仓库 Android 应用包名调整为 `io.github.ktclat.c001apk`，可与原项目安装包并存。**包名变更不会迁移旧应用的登录状态、收藏和本地存储**，请按需在旧应用中保留或备份数据；Debug 包使用开发签名，不等于正式发布。详见[构建与签名说明](docs/CI.md)。

本次工具链迁移基线：Flutter 3.47.7 / Dart 3.13.5、JDK 17、Android compile SDK 36。最低支持 **Android 7.0（API 24）**，不再支持 Android 5/6；target SDK 暂保留 34，以便单独验证行为变化。迁移检查状态和兼容性依据见[迁移说明](docs/FLUTTER_TOOLCHAIN_MIGRATION.md)。进入 `apps/flutter` 后：

```sh
bash tools/fetch_fonts.sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --debug --no-pub
flutter build apk --profile --no-pub
```

## 截图与视觉素材

**此处暂不展示截图。** 我们不再使用原维护仓库的首页、文章、设置页或桌面端截图来代表当前版本。待本仓库的新 Android 构建完成实机验收后，使用本项目实际运行的脱敏截图填充。图片要求和文件命名见[截图维护规范](docs/SCREENSHOTS.md)。

## 维护范围与计划

本仓库**优先维护 Android**：保证 CI 测试、字体和排版、设备适配、账号状态切换、更新检查及信息安全。Windows/Linux/iOS 不是目前的发布或测试目标；仓库中保留的部分跨平台源文件不表示提供桌面版支持。

开发优先级见 [Android 路线图](docs/ANDROID_ROADMAP.md)。缺陷和功能请求请只发在[本仓库 Issues](https://github.com/Ktclat/c001apk/issues)，**不要转发到原维护仓库**。

## 许可与来源

本仓库沿用 **GNU Affero General Public License v3.0（AGPL-3.0）**，根目录 [LICENSE](LICENSE) 保持原样。依照许可证要求，保留历史作者署名、版权和第三方许可声明；fork 和改动不改变原作者及素材权利人的著作权。

本项目以 [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk) 的公开源代码为基础，历史来源还包括 c001apk-flutter 及其引用的其他项目。它们是**代码来源与致谢**，不是本项目的用户服务或售后支持渠道。完整信息见 [第三方与版权声明](docs/THIRD_PARTY_NOTICES.md)。

酷安名称、商标、官方表情及服务内容的权利归相应权利人所有。
