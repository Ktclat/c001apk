# Android 开发指南

[返回首页](../README.md) · [Android CI](CI.md) · [字体设计](FONT_GUIDE.md) · [Android 路线图](ANDROID_ROADMAP.md)

## 范围

本仓库维护 Android 客户端，当前工具链迁移使用 Flutter 3.47.7 和 Material 3，而不是 Kotlin / Compose 工程。Windows、Linux、iOS 暂不进行构建、发布或适配；部分跨平台代码出于兼容和历史原因仍保留，新增功能请优先验证 Android。

工作目录：`apps/flutter/`。主要结构：

| 目录 | 职责 |
| --- | --- |
| `lib/main.dart` | 应用初始化、字体和主题、文本缩放 |
| `lib/pages/` | 浏览、搜索、评论、登录、设置等 UI |
| `lib/components/` | 动态卡片、HTML 正文、通用组件 |
| `lib/logic/` | 账号管理、网络、更新检查、会话存储 |
| `lib/utils/` | Hive 存储、主题、设备参数等 |
| `android/` | Android 原生工程和权限配置 |
| `test/` | 独立的单元及 Widget 回归测试 |

## 环境配置

安装 Flutter 3.47.7（内含 Dart 3.13.5）、JDK 17、Android SDK 35 / 36、Build Tools 35.0.0 和 NDK 28.2.13676358。Gradle 8.14.3 / AGP 8.13.2 / Kotlin 2.3.10 由工程锁定，最低运行系统为 Android 7.0（API 24），target SDK 暂保留 34。依赖使用仓库已提交的 `pubspec.lock`，不要跳过 SDK 依赖检查或整批升级依赖；兼容性和待验收项目见[迁移说明](FLUTTER_TOOLCHAIN_MIGRATION.md)。

```bash
cd apps/flutter
flutter doctor -v
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter run
```

第一次 Android 编译需要网络拉取 Gradle 及原生依赖。Debug APK 构建命令：`flutter build apk --debug --no-pub`。GitHub Actions 完整步骤见 [CI](CI.md)。

## 必须回归的 Android 流程

1. 首页动态、文章正文、评论列表与楼中楼；网络失败提供重试，而非无限加载。
2. 游客态、登录态、账号切换和“使用游客模式”；旧账号的异步响应不能污染新账号。
3. 设置中的系统字体 / Material 默认、字重、深色模式、动态取色、字体缩放和大字模式。
4. 本机收藏、本地关注、屏蔽和缓存清理；不得误删账号或历史。
5. 更新检查只访问 **Ktclat/c001apk** 的正式发布接口，GitHub 返回 404 时提供合理提示。
6. Android 设备标识导入、手动验证码和 API Cookie 作用域隔离（详情见[设备标识说明](DEVICE_ID_IMPORT.md)）。

不要使用真实密码、登录 Token、设备 ID 或验证码结果制作公开测试夹具。在线或真实账号测试仅在可控设备上自愿执行，默认 CI 只跑离线合成数据。

## Android 字体

外观与字体 → 界面字体提供“跟随系统（Android `sans-serif`）”和“Material 默认”两个选择；另有独立字号选项。系统字体能否随厂商主题变化由设备 ROM 和 Flutter 字体映射决定，不能保证每台手机都可直接获得厂商字体。详见 [FONT_GUIDE](FONT_GUIDE.md)。

## 修复测试和提交规范

先以单文件复现失败，再运行全量回归；不要通过禁用出错测试、扩大超时或者跳过清理来掩盖问题。回归中涉及真实 I/O、Hive Flush 和 `WidgetTester` 的异步操作时，要区分测试假时钟与真实异步区。PR 需说明复现方法、修复逻辑、影响范围及实际执行过的测试。

项目报告、下载、更新和 CI 链接统一使用本仓库：<https://github.com/Ktclat/c001apk>。请把 issue 只提交到[本仓库](https://github.com/Ktclat/c001apk/issues)，不要转给原作者。

## 版权、数据和素材

[LICENSE](../LICENSE) 是 AGPL-3.0，保持不变。原作者署名、协议研究来源和附带的第三方许可，见[第三方声明](THIRD_PARTY_NOTICES.md)。

文档中的 Android 实机截图必须来自**本仓库当前版本**，经过用户标识、头像、通知、Token 等脱敏后方可上传；不复用原维护仓库截图，详见[截图规范](SCREENSHOTS.md)。
