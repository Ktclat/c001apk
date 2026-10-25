# Flutter 3.47.7 / Android 7.0+ 工具链迁移

## 范围与边界

本次以 `ac26d853bc9a3e3ab1a8bf88b6cc386a4d64a61d` 为基线，只迁移 Flutter / Android 构建链及其必要兼容修复。Markdown、导出、公告、上游 adaptive / expressive UI 和原生版本功能均不在本变更内。未经独立复审、完整测试和 APK 验证，不得合并或宣布完成。

- 最低运行系统变为 **Android 7.0（API 24）**。新包不能安装于 Android 5/6；已安装旧包不会被这次源码变更自动更新或迁移数据。
- `compileSdk = 36`，但显式保持 `targetSdk = 34`，避免把新 target 的系统行为变化混入本次迁移。这不是应用商店 target SDK 合规声明。
- 保持 `io.github.ktclat.c001apk`、Android namespace、名称、`0.1.0+1` 版本及现有签名策略；不生成、导入或复制上游签名密钥。
- 诊断应用的独立包名、名称、`-diag` 标记及双重 opt-in 保持不变。普通 arm64 Profile 先于诊断包生成，继续检查 AOT / 无 JIT、arm64-only、准确身份及严格小于 50,000,000 字节。
- 不改 API、账号/设备会话隔离、Hive 存储、既有字体/素材或滚动隐藏果冻导航的业务行为。SDK 升级本身可能改变渲染，仍须新截图和实际测试，不能沿用旧截图宣布验证。

## 固定版本与官方依据

| 组件 | 本次版本 | 依据 |
| --- | --- | --- |
| Flutter / Dart | 3.47.7 / 3.13.5 | [Flutter SDK 归档](https://docs.flutter.dev/install/archive)，官方发行 commit `abaf9c523780a608bd46686fd5e53740a07077f8` |
| Gradle | 8.14.3 bin | [官方 SHA-256](https://downloads.gradle.org/distributions/gradle-8.14.3-bin.zip.sha256)，wrapper 同时固定校验和 |
| AGP | 8.13.2 | [官方兼容说明](https://developer.android.com/build/releases/agp-8-13-0-release-notes)：Gradle 至少 8.13，JDK 17，最高 API 36.1，R8 8.13.19 支持 Kotlin 2.3 |
| Kotlin Gradle plugin | 2.3.10 | [Kotlin 官方矩阵](https://kotlinlang.org/docs/gradle-configure-project.html)：支持 Gradle 7.6.3–9.0.0、AGP 8.2.2–9.0.0 |
| Java | JDK 17 | AGP 及 Flutter SDK 的硬下限；保留应用原有 Java/Kotlin 1.8 字节码目标 |
| Android | compile 36 / min 24 / target 34 | 编译与运行系统策略分开固定，保持行为隔离 |
| Build Tools / NDK | 35.0.0 / 28.2.13676358 | Build Tools 是 AGP 8.13 默认值；NDK 使用固定 Flutter SDK 的 `flutter.ndkVersion` |
| intl | ^0.20.3 | 与 [该 SDK 的 flutter_localizations](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_localizations/pubspec.yaml) 约束一致 |

[Flutter 3.47.7 的 DependencyVersionChecker](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt) 硬下限为 Gradle 8.14.0、AGP 8.11.1、Kotlin 2.2.20 和 JDK 17；本组合满足这些下限。它仍可能提示未来迁移到 Gradle 9.1 / AGP 9.0.1 / Kotlin 2.3.20，这些警告保留可见，**不添加跳过版本检查参数，也不引入 AGP 9**。满足静态矩阵不等于插件或 APK 已通过实际验证。

## SDK 自身的运行时变化

- 保留浅色 Android 的显式 FadeUpwards 转场；把旧 SDK 隐式使用的深色 Zoom 转场改为显式配置，防止默认转场随 SDK 静默变化。Widget 回归检查两个实际应用主题的配置；不据此宣称手势返回已实机通过。
- 新 Flutter 在 Android API 29+ 默认启用 [Impeller](https://docs.flutter.dev/perf/impeller)。本次没有关闭新渲染器，也没有添加性能结论；必须在目标手机检查真实滚动、纹理/图片、WebView 等 platform view、键盘、返回和恢复流程。离线 widget PNG 不能证明 GPU 或 platform view 行为。
- [MaterialColorUtilities 的种子调色算法变化](https://docs.flutter.dev/release/breaking-changes/material-color-utilities)可能影响固定种子生成的配色。保留现有种子、动态取色选择和排版设置，不复制旧算法或增加兼容补丁；浅/深色、动态/固定色、大字和字体模式需新截图复审。
- ThemeData 的 CardTheme / DialogTheme 迁移到对应的 Data 类型，仅保留原有属性值。

## 依赖策略

仅使用 `flutter pub get` 根据旧锁文件做必要求解，不运行整批 `pub upgrade`，不加 `dependency_overrides`。提交求解后的锁文件，CI 和复现检查使用 `flutter pub get --enforce-lockfile`。Dart 语言下限暂保留 3.5，实际构建使用固定 Flutter 自带的 Dart 3.13.5。

### 必要依赖兼容修复

首次 UI 编译证实 `flutter_widget_from_html_core 0.15.1` 没有实现新 SDK 的 `Flex.spacing` / `RenderFlex.spacing`。按[维护者变更记录](https://pub.dev/packages/flutter_widget_from_html_core/changelog)只升到修复该问题的 **0.15.2**，不引入后续 Markdown 功能。这一步没有改动正文链接策略或应用 HTML 组件；后续 splash 原生编译修复又带来 `html` 解析器的必要更新，具体影响见下节，不能将整个迁移称为解析器不变。

第一轮已验证锁文件相对旧基线有 22 项版本/移除变化：Flutter SDK 所需的 intl、characters、clock、collection、fake_async、leak_tracker 三件套、matcher、material_color_utilities、meta、path、sky_engine、stack_trace、stream_channel、test_api、vector_math；为避开已从 Dart 移除的 macros，将 analyzer 6.7.0 / _fe_analyzer_shared 72.0.0 求解为 6.4.1 / 67.0.0，并移除 macros / _macros；另有上述 HTML 渲染器补丁。没有依赖 override 或整批插件升级。

### Android 插件原生编译修复候选

实际 Debug APK 的第二次构建在 `:dynamic_color:checkDebugAarMetadata` 失败：旧 1.7.0 插件固定 compile SDK 31，而它解析到的 24 项 AndroidX 依赖要求 API 32–34。应用本身 compile SDK 36 不能替代每个插件自己的编译 SDK。

- 精确固定官方 `dynamic_color: 1.8.1`，该版本的 Android compile SDK 为 34，兼容已锁定的 `material_color_utilities 0.13.0`，并保留现有测试辅助 API。1.8.0 曾移除运行时的 flutter_test 依赖，1.8.1 恢复它。Dart 差异主要是调试日志条件化和用 `toARGB32()` 代替弃用的颜色整数属性，没有导入 1.9/2.x 的调色角色/包拆分。依据：[维护者变更记录](https://pub.dev/packages/dynamic_color/changelog)。
- 静态检查另外发现 `flutter_native_splash 2.4.1` 同样固定 compile SDK 31；官方 2.4.2–2.4.5 仍为 31，2.4.6 首次为 35。因此精确固定 `flutter_native_splash: 2.4.6`，并在 CI 安装 Android 平台 35 供该插件编译，应用仍 compile 36 / min 24 / target 34。该版本 Android 生产 Java 文件与旧版相同，未运行 splash 生成器，也未改已有启动页资源。依据：[维护者变更记录](https://pub.dev/packages/flutter_native_splash/changelog)及已验证的官方版本归档源码。
- 已从上一轮锁文件增量执行 `flutter pub get`，没有整批升级。除两个精确固定插件外，splash 新下限要求 args/image/html/yaml 更新；image 再要求 archive 4，archive 引入 posix。禁止手工伪造锁文件、修改 pub cache、关闭 AAR metadata 检查或全局覆盖插件 compile SDK。
- 静态审计当前 18 个 Android 插件，除上述两项外其余均声明 compile SDK 34；未发现已移除的 V1 embedding API 引用。此结果不是原生编译通过保证，下一轮仍需实际构建。

### 最终候选锁文件增量与影响

插件修复在第一轮 22 项之外再改变 **8 项**，相对原基线共 **30 项**；不是 30 个新增依赖。当前锁文件 SHA-256 为 `de2bce88ac8663285abef2e687686bf0073857fbf7e20d8585c17aeb2be03224`。

| 依赖 | 上一轮 → 当前锁定 | 必要性 / 范围 | 许可证 |
| --- | --- | --- | --- |
| dynamic_color | 1.7.0 → 1.8.1 | 插件 compile SDK 31 → 34 | Apache-2.0 |
| flutter_native_splash | 2.4.1 → 2.4.6 | 插件 compile SDK 31 → 35；未重新生成启动页 | MIT |
| args | 2.5.0 → 2.7.0 | splash 要求 ^2.7.0；其他工具/Linux dbus 也共享该包 | BSD-3-Clause |
| html | 0.15.4 → 0.15.7 | splash 要求 ^0.15.5；应用正文/通知/登录也使用该解析器 | MIT |
| image | 4.2.0 → 4.12.0 | splash 要求 ^4.5.4；由求解器在该范围选择 | MIT |
| archive | 3.6.1 → 4.5.2 | image 4.12.0 要求 ^4.5.0，不能保留 archive 3 | MIT |
| posix | 无 → 6.5.2 | archive 要求 ^6.0.2 | MIT |
| yaml | 3.1.2 → 3.1.4 | splash 要求 ^3.1.3；代码生成工具也共享该包 | MIT |

- 以上 7 个升级包的 `LICENSE` 与原锁版本逐字相同，新增 posix 提供 MIT 许可证；继续保留第三方声明。所有包仍来自官方 pub.dev，锁文件保留归档 SHA-256。这里只记录许可证核对，不替代法律审查。
- [html 0.15.7 的维护者变更记录](https://pub.dev/packages/html/changelog)包含 CDATA 结束识别、属性 ampersand、选择器、foreign namespace 文本转义和病态深层格式标签处理等修复。因此 **HTML 解析行为确有变化**。其源码没有新增网络读取依赖，应用 URL/图片获取与过滤策略未改，`csslib` 和网络/图片平台插件仍保留原锁版本；但不能由静态检查推断显示等价。必须重新验证正文、通知、登录、链接、图片与排版。
- 当前锁图中 image 仅由两个 dev 依赖 splash / launcher_icons 引用，archive 仅由 image 引用，posix 仅由 archive 引用；应用 `lib/` / `test/` 没有直接导入这三个包。它们仍可能影响以后生成图片/图标的结果，未执行任何素材生成器或借此重写资源。保留锁定的新版本，不用依赖 override 强制回退 major。
- Dart 锁文件环境下限仍是 `>=3.11.0-0 <4.0.0`，实际使用固定 SDK 的 Dart 3.13.5；analyzer / build_runner / json_serializable 未因本轮插件修复再升级。新图上的生成工具已另做一次性副本检查，范围与限制见下节。

### 代码生成限制

在一次性副本中运行现有 `dart run build_runner build --delete-conflicting-outputs` 成功（exit 0，191 outputs），**没有对生产工作树执行覆盖生成**。插件修复后又在新锁图的一次性副本中重跑成功（exit 0，191 outputs / 1096 actions），生产源树前后未变；18 个生成文件的副本结果与第一次逐字相同，仍不能直接覆盖生产文件。两次旧 analyzer 均明确提示 language 3.4 / SDK language 3.13，不能据此宣称支持所有 Dart 3.13 语法。

副本中 18 个已有生成模型有 8 个产生差异：4 个只有注释/空白变化；另外 4 个会改变现有兼容行为，包括收藏时间由 `num?.toInt()` 退回 `int?` 强转、entity title 由 `toString()` 退回字符串强转、feed 的 apksize 类型/JSON 键映射和 check_update 的 lastupdate 输出。当前模型声明与已定制的生成文件并非完全一致，不能自动用新生成文件覆盖。18 个生产 `.g.dart` 全部保持基线字节；模型/生成器现代化需另批逐字段及存储回归，不在本次强行升级。新增 `test/model/legacy_generated_codec_test.dart` 直接测试 Hive 旧 double 时间持久化读取、非字符串标题转换、现有 isTop / location / follow 字段映射和 lastupdate 输出边界；该新增文件随后已纳入第一轮全量离线门禁；不能与集中测试数量重复相加。

### 分析覆盖

Flutter 3.47.7 的官方 [AnalysisOptionsMigration](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/lib/src/migrations/analysis_options_migration.dart) 会在 `pub get` 自动添加 build 和平台脚手架目录排除。保留这个自动生成的稳定配置，不修改 SDK；这些目录目前没有 Git 跟踪的 Dart 源码。新源码契约会在这些目录新增任何 tracked Dart 文件时失败，要求重新审查分析范围。`lib/` 和 `test/` 未排除；移除排除配置后也实际运行过相同分析，结论一致。

仅删除新版 analyzer 报警的一个从未调用的局部回调及其旧注释/未用 import，保留原公开 helper 的既有无操作行为，没有启用外部启动或复制操作。

## 本轮实际检查（仍是候选）

- 字体脚本按原固定 hash 下载并验证原有三种字重；字体配置和素材未变。
- 插件修复后的新 30 项锁图已完成 `flutter pub get`；随后 `flutter pub get --offline --enforce-lockfile`：exit 0，冻结源树未变。在线 CI 仍使用 `--enforce-lockfile`。这只证明依赖可解析及锁文件稳定，不证明编译通过。
- 第一轮 22 项锁图上的 `flutter analyze --no-pub --no-fatal-infos`：exit 0，48 条 info，0 error / warning，冻结源树未变。首次只读 HOME 环境错误及修复前依赖编译失败的日志保留，不能算通过。
- 第一轮集中运行 source contract、本地化、滚动导航、导航设置、果冻动效、Hive 账号、字体设置和排版截图等 8 个测试文件：**39 项通过、0 失败**，冻结源树未变。生成的离线 widget 截图尚不能代替视觉复审或设备证据。
- 第一轮独立代码生成检查见上节：执行成功但存在明确的语言版本警告和生成文件差异，不导入副本产物。
- Python 工具链/分析覆盖/普通 arm64/诊断身份源契约共 **15 项通过**；不是对真实 APK 的验证。
- 第一轮完整离线门禁已实际通过：analyze 48 info / 0 error / warning，Python 15 项，隔离 Hive / 字体设置 / 账号分别 1 / 13 / 2 项，全量 Flutter **373 项通过、5 项既有跳过**，独立诊断 opt-in 子集 5 项通过，源树前后相同。不同测试集合相互重叠，不能相加。此记录属于原 dynamic_color 1.7.0 / splash 2.4.1 的锁图，不证明后续插件修复已通过。
- Debug APK 第一次构建因本地 2 GiB Gradle 堆限制导致 JetifyTransform 内存不足而失败；恢复仓库原有 4 GiB 配置后的第二次构建走过转换阶段，但在 dynamic_color 的 AAR metadata 门禁失败。两次均 exit 1，均没有 APK，不能算构建成功；原失败记录保留。
- 第一次构建还由 Flutter 官方迁移器追加 `android.builtInKotlin=false` / `android.newDsl=false`，以保留现有 Kotlin 插件与 DSL 模式。该次源码前后因此不同，不能视为冻结门禁；第二次已稳定。它们不是 SDK/AAR 验证绕过开关，没有引入 AGP 9。
- 新锁图的 analyze 已重跑通过（48 info / 0 error / warning）；HTML / 登录 / 分享链接集中回归 **39 项通过、3 项既有 Windows 跳过**，冻结源树未变。新增的 11 项测试直接覆盖通知卡片首个 a[href]、HTML 实体/ampersand 链接、纯文本换行、内联图片的离线请求/协议边界，以及登录 requestHash 实体解码和缺参禁止提交；没有修改生产解析或跳转逻辑。新测试夹具初版触发默认缓存的 path_provider 缺失、第二版点击 RichText 空白区域的失败日志均保留，修复测试夹具与字形点击位置后通过，未删断言。
- 新插件修复已完成依赖求解、强制锁校验及上述集中检查；完整离线与 Debug/Profile 门禁须以同一冻结候选的独立日志为准，不能用旧图结果替代。真实 APK 身份/尺寸验证、实机安装和 GPU/platform view 测试未通过，独立复审也仍须最终候选证据；不能宣称迁移完成或可合并。

## 验证与剩余门禁

源代码契约通过 Python 检查工具链固定值、Android 支持边界和禁止绕过检查；现有普通 arm64 / 诊断身份检查保持有效。此类源码检查不是 APK 验证。

必须按同一冻结源码和锁文件完成：

1. 依赖求解后，使用 `--enforce-lockfile` 再次校验；核对依赖变化及许可。
2. `flutter analyze --no-pub --no-fatal-infos`，集中测试本地化、账号/存储、滚动隐藏导航、普通/诊断构建身份，再运行全部离线测试。
3. Debug、普通 arm64 Profile 和独立诊断 Profile 构建；使用 `tools/verify_normal_profile_apk.py` / `tools/verify_apk_identity.py` 检查真实 APK，不能用合成 ZIP 的成功替代。
4. 独立复审最终差异、日志、源码哈希和产物；有任一失败时不能宣称整体通过。
5. Android 7.0 基线和目标设备上的安装/启动/导航/键盘/返回/滚动/字体截图与行为验收。未执行前一律标为未验证，不宣称动效流畅度或设备兼容性已经确认。

历史 `docs/reviews/` 中 Flutter 3.24.5 的结果属于旧工具链，不被本次自动重写为新版本验证结果。


## 最终本地集成检查（2026-10-25，远端提交 CI 待核验）

下列结果更新前文“尚待运行”的阶段状态，不撤销前述失败或边界记录。最终待发布源码还包含一个单独复审的“我的”快捷入口大字体修复：保留图标在上、文字在下及既有路径/账号保护，按可用宽度和文字缩放选择三／二／一列，名称自然换行，不缩小用户字体或省略名称。没有改变自定义悬浮栏或滚动安全区策略。

- SDK 单独冻结候选：696 文件清单 SHA-256 `56854dda899bb1941d6fb30427da7bcd6f2f9757929316e60610fa4b7890c07d`；新锁完整门禁 **384 通过、5 项既有跳过**，Debug、普通 arm64 Profile、独立诊断 Profile 均实际构建并验证通过。
- SDK + 快捷入口集成冻结候选：清单 SHA-256 `31e92c9a12b77c28a1f6ff026a935c3e4f78f0159fd53628d157764c97b459b4`。全量 **405 通过、5 项既有跳过**；诊断子集 5 通过；隔离 Hive／设置／账号 1／13／2 通过；Python 契约 15 通过；analyze 为 48 条既有 info、0 error/warning。集合互相重叠，不相加。所有成功门禁的源码前后一致。
- 新增快捷入口用例 21 项通过，包含完整字形边界、至少 48dp 目标、完整语义名称、实际指针与语义点击路由及访客保护，以及最后内容滚动到悬浮栏上方。初版字形断言把 Noto 字形超出段落原点、但仍位于卡片内的部分误判为裁切；修正为核对实际目标／卡片的全局边界，并修正测试语义句柄清理。失败记录保留，没有删除裁切、路由或点击断言。
- 独立检查全部 27 张新 widget 图像：320dp、200%／260% 字体下六项名称完整且可区分，正常字号保留三列；精确观察窗口为 369.23×821.54dp、DPR3.25、顶部 padding43.08dp、顶部 gesture55.08dp、底部0。横屏是合成旋转场景，不是实机采集。最后入口和消息行可滚至导航栏上方。普通帧在 APP_DIAGNOSTIC 测试之前单独保留，未把诊断覆盖帧当作普通应用截图。
- 集成 Debug：174,033,944 字节，SHA-256 `e579de300516220ccf0dd904d8af55cde5f828fb6628df2cceb23490e3c63946`；普通应用身份、versionCode1、min24/target34/compile36，v2 签名有效。
- 集成普通 arm64 Profile：42,483,732 字节，SHA-256 `ff652603bb258f9219640c47ea8142bcaf336872fedef46fbb5ae8bf13adaa5d`；普通应用身份、versionCode2001、min24/target34/compile36，arm64-only、非空 AOT、无 JIT kernel、严格小于 50,000,000 字节的制品守卫通过。2001 是原有 split-ABI 编码规则，不是改了项目基础版本。这个尺寸门槛不代表聊天附件发送上限。
- 集成诊断 Profile：99,138,465 字节，SHA-256 `d1e43a1dafcfb5799e25d93bfb10bc9ed196660a735ddd1b595f11504644704b`；独立诊断包名／标签／版本后缀／沙盒设置验证通过，三 ABI AOT、无 JIT kernel。普通与诊断包没有混用。
- 三种包均实际签名校验；三种 Noto 字重的字节与原 pin 一致。以上是本地开发签名产物，不承诺覆盖既有安装，也不建议为解决签名冲突卸载或清除数据。

本节是上述冻结门禁完成后添加的文档记录，没有再次改变生产、测试、构建或锁文件。最终远端提交仍需独立核对 CI 与产物来源；Android 7.0/小米真机安装、系统手势、IME、TalkBack、Impeller/GPU 和平台视图性能仍未验证。不能以截图或测试数量宣称整项迁移、真机顺滑度或功能对齐已经完成。
