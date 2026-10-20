# 字体与中文排版改造说明

本项目由 [Ktclat/c001apk](https://github.com/Ktclat/c001apk) 维护，其代码源自 [TG-Twilight/c001apk](https://github.com/TG-Twilight/c001apk)（AGPL-3.0），Flutter 工程位于 `apps/flutter`。

## 为什么要改？

上游 `pubspec.yaml` 没有声明专用字体文件；Flutter Material 在 Android 默认采用 Roboto，中文通过系统字体回退渲染。上游 `utils/app_theme.dart` 的顶部标题 16sp、设置说明 12sp，标题/说明字重与中文行高缺乏统一规范。

字体问题与字号、行高、视觉层级是分开的：仅仅把所有文字替换为另一种字体，并不一定改善阅读。

## 本分支的实现

**设置 → 外观与字体 → 界面字体**：

- **跟随系统（推荐，默认）**：Android 指定 `sans-serif` 字体家族，让 Flutter 向系统字体映射请求无衬线字。设备若将 OEM 字体或用户设置的字体映射到这一家族，就能显示对应字体；厂商实现不同，因此不能保证所有 ROM 都生效。本仓库主要验证 Android；其他操作系统不在维护范围。
- **Material 默认**：不强制字体家族，使用 Flutter/Material 的平台默认行为，便于与上游外观对照。

设置保存在本地 Hive `settings` 中，切换后自动更新当前页面、亮色及深色主题。原有的字体大小滑块仍保留，并与 Android 系统无障碍文字缩放叠加。

通用排版同时作了温和调整：顶部标题 18sp/600，列表标题 16sp/500，列表说明 13sp/400；正文、说明增加适度行高，避免过密。此功能不对 WebView 展示的网页强制改字体，也不会突破 Android ROM/Flutter 引擎的字体回退限制。

### Android / Flutter 关键实现

`apps/flutter/lib/utils/app_theme.dart`：

```dart
fontChoice.familyForPlatform(TargetPlatform.android); // system => 'sans-serif'
theme.textTheme.apply(fontFamily: 'sans-serif');
```

`apps/flutter/lib/main.dart`：同时为亮暗主题调用 `applyAppTypography`，并监听 `SettingsBoxKey.fontChoice`。

`apps/flutter/lib/components/settings/font_choice_tile.dart`：显示字体选择器和两种方案的文字预览。

## 其他开源 Android 软件的字体方式

以下为**源代码里的用法**，不是根据截图猜测：

| 软件 | 可查到的方案 | 对本项目的启示 |
| --- | --- | --- |
| [Mihon](https://github.com/mihonapp/mihon) | UI 采用 Jetpack Compose 的 MaterialTheme.typography；Markdown 代码片段单独指定 Monospace | 普通正文延续设计系统字体，特殊场景再换字体 |
| [Droid-ify](https://github.com/Droid-ify/client) | 原生 Android 代码显式使用 `sans-serif-medium`、`sans-serif-light`，技术标识等单独使用 Monospace | 利用系统内置字重，而不是全局打包一套字体 |
| [Material Files](https://github.com/zhanghai/MaterialFiles) | Android Material 3 样式里依赖 `m3_ref_typeface_plain_regular` 类型资源 | 借助 Material 默认字体与层级，保持系统一致性 |

对应代码： [Mihon MarkdownRender.kt](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/presentation/manga/components/MarkdownRender.kt)、[Droid-ify Resources.kt](https://github.com/Droid-ify/client/blob/main/app/src/main/kotlin/com/looker/droidify/utility/extension/Resources.kt)、[Material Files styles_material3.xml](https://github.com/zhanghai/MaterialFiles/blob/master/app/src/main/res/values/styles_material3.xml)。

## 适合手机中文界面的字体候选

1. **系统默认无衬线字体**：首选。体积零增加，也最贴近手机自身风格；Android 原生/Pixel 系列常见为 Roboto + CJK 回退，OEM 系统可能映射为自己的字体。
2. **Noto Sans CJK / 思源黑体**：字形完整、中性清晰，适合内容密集型阅读。采用 [SIL OFL 1.1](https://github.com/notofonts/noto-cjk/blob/main/Sans/LICENSE)，但把字体包嵌入 APK 会明显增加体积。本次没有内置。
3. **霞鹜文楷**：有阅读感，适合长文章，可作为未来的「阅读字体」；不宜作为所有按钮/标题的 UI 字体。项目：[LXGW WenKai](https://github.com/lxgw/LxgwWenKai)。
4. **MiSans**：部分小米设备的字体比较协调，但[小米官方授权](https://hyperos.mi.com/font/en/download/)对字体文件的再分发有条件限制，因此**不直接把字体文件加入本仓库**；仅通过系统字体映射使用。

## 验证

- 开发机终端：`cd apps/flutter && flutter pub get --enforce-lockfile && flutter analyze --no-pub --no-fatal-infos && flutter test --no-pub`
- Android 手机上依次对比「跟随系统」和「Material 默认」，重点查看首页动态、长评论、文章、设置说明与输入框；再把系统字体改成其他样式复测。
- 检查字体放大至 1.3× 以及系统大字体时，是否出现溢出、截断、按钮碰撞。
- 某些系统上两种模式可能近乎一致，应以设备实测为准，不能只按菜单选择判断已经应用了厂商字体。

参考：[Flutter 平台字体说明](https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations)、[Flutter 自定义字体文档](https://docs.flutter.dev/cookbook/design/fonts)、[Android Material 3 Typography](https://developer.android.com/develop/ui/compose/designsystems/material3)。
