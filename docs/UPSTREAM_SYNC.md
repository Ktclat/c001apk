# Flutter 上游同步清单：第一批（部分同步）

第一批行为移植已通过 PR #5 合入，普通 arm64 Profile 交付检查由 PR #6 补充；这不是完整同步，也不是无关历史的合并。该批没有升级本 fork 的版本、SDK、依赖、签名或发行身份，也不代表上游 1.3.5 已安装。当前工具链迁移是另一批候选，未经本批实际门禁和独立复审不得合并或宣布完成。

> 以下为第一批同步的历史范围和验收记录。后续独立的 Flutter 3.47.7 / Android 7.0+ 工具链迁移见[迁移说明](FLUTTER_TOOLCHAIN_MIGRATION.md)，不等于下面列出的未移植 UI/Markdown 功能已完成。

## 比较基线

- 本 fork 工作基线：`1020aff898708229547fc03864b9f8a7c2d2e4f2`。
- 实际导入的上游内容基线：`f309b4382b5ef12675437d584487d54e5b890eee`。
- 第一批审计目标：`fb3e06cac5c65e9f86c902f1b4304aeee055f3e2`。
- 后续只读审计目标：`851ad81cb765a183abe99c6c9e07a57cefd18c18`；新增自动设备身份注册不在本次工具链迁移内。
- 保持 Flutter 3.24.5 / Dart 3.5、JDK 17、现有锁文件和 Android 构建设置。上游 Flutter 3.47.7 / SDK 37 / AGP 9 属于后续独立迁移，不在本批。

## 后续明确保留的待办

- 自动设备身份注册：不移植启动时向第三方注册的行为；需要用户知情 opt-in、重试预算和并发/取消边界设计。
- Issue #12 的 success-but-missing-data：尚无精确响应夹具，状态为 UNCERTAIN，不猜测修改现有 API 语义。
- Markdown、导出、公告、外部 intent 生命周期、adaptive / expressive UI 均未因本次工具链迁移而完成。

## 逐提交处置

| 上游提交 | 本批处置 | 剩余事项 |
| --- | --- | --- |
| `99ceff3fd211b5789b631dda201d9d011b0543df` 恢复维护/统一签名 | 不移植签名及 CI 更换 | 按本 fork 独立签名方案评估，不能使用上游密钥或强制要求上游 Secrets |
| `9a601e928d06205c9035868407b7ebd1ef583ed1` 自适应/expressive UI | 仅移植下面列出的网络、分享链接、评论加载门控及必要错误操作入口 | adaptive 双栏/瀑布流、expressive UI、键盘/鼠标、图片查看器、平台集成、SDK/依赖/插件迁移、桌面适配均未移植 |
| `d8a095db0396b5b3a6aa1a7f3761b8dcc9f31891` SDK 37 包名 | 未移植 | 与 SDK 迁移一起评估 |
| `e077e1506dbcd52f2c141a63fd5944a2ea85486d` release 插件注册 | 未移植 | 与新插件/构建链迁移一起评估 |
| `f1fa1b427425cda0a2e9ecb73652b6f8e7d3e3cf` Build Tools 37 证书解析 | 未移植 | 本 fork 签名验证工具单独评估，不能放松证书校验 |
| `b31ae23ea1fa022016fc21299571aa28b835bc3e` 原生库压缩 | 未移植 | 构建/安装兼容性专项验证后决定 |
| `98526cc30cc6ed5d96fc4bed32ee03dfc92b7024` Markdown/导出/公告 | 未移植 | Markdown 原文切换、内容导出、公告获取/展示、`getFeedReply(verify)` 可选参数尚未移植；不引入公告远程请求 |
| `fb3e06cac5c65e9f86c902f1b4304aeee055f3e2` 1.3.5 正式身份整合 | 未移植 | 不覆盖 fork applicationId、存储身份、版本和更新源；未来仅按本 fork 发行计划处理 |

## 精确移植范围（均来自 9a601e9，基于目标版本核对）

- `lib/logic/network/api_failure.dart`：`readApiObject` 的 `/v6/apk/detail` + status `-2` + “应用不存在/未上架”分支。其他端点/状态保持原通用错误，验证码/登录/限流仍优先。
- `lib/logic/network/interceptor.dart`：公开数字 feed 页面删除 Cookie 时用新 Map，而非 `removeWhere`。另适配为修改头字段前先复制 headers，支持调用方不可变 Map。保留现有 API 会话捕获、账号 generation、TokenV3、验证码作用域；公开页面不建立 API 会话上下文。
- `lib/logic/network/network_repo.dart`：仅 `getFeedDetail` 的验证失败文案、公开分享页 app-only HTML 检测与原验证码/登录原因保留。正常公开 JSON 仍清除点赞状态，不冒充已登录正文；未知 HTML 仍为错误。
- `lib/logic/state/loading_state.dart`：Error 新增默认 false 的 `canVerify`；兼容现有调用。
- `lib/pages/feed/feed_page.dart`：仅错误重试/设备导入按钮、评论延迟加载/恢复操作、分页门控和分享 payload 调用。不引入上游 pane、Markdown、内容导出或 expressive 组件。
- `lib/pages/feed/feed_controller.dart`：缺少数盟 ID 时所有自动评论路径统一门控，点击后才加载。额外适配：同一页面导入/移除 ID 后更新门控；重试失败不清空已读评论；异步期间账号/设备变更后丢弃旧评论，显示可重试状态，不无限 Loading。保留 CommonController 原有会话隔离。
- `lib/utils/utils.dart`：`getShareUrl` 编码单个 ID；`getShareText` 合成短标题、镜像/官方双链接、来源；分享摘要截断改为 grapheme 安全以保留本 fork emoji 语义。`onOpenLink/_openLink` 加异常处理、精确主机白名单（coolapk.com/www/m，coolapk1s.com/www）、coolmarket 自定义 authority、去除分享 query/fragment、ID 解码一次并路由编码。
- 链接额外加固：不将带端口或 lookalike HTTP(S) 识别为内部链接；拒绝 userinfo、错误百分号转义、无效 UTF-8、控制字符、已知路由的空 ID/多段/编码分隔符和反斜杠。允许正常外部 HTTP(S)，不自动打开未知 scheme。
- `pages/{app,feed,topic,user}/*_page.dart` 的 Share 使用 payload；Copy 仍仅复制已编码 URL。仅 feed/app 提供现有标题/摘要，其余使用类型回退名。未移植 Windows 剪贴板分享分支、iPad anchor 或上游整套 `shareContent` 平台包装。

## 保留与后续完整同步矩阵

| 区域 | 状态 | 后续验证门槛 |
| --- | --- | --- |
| 网络/链接/公开正文错误/评论显式加载 | 第一批已合入 PR #5，历史门禁见下文 | 新 SDK 下重跑回归；真机 UI 仍须独立验收 |
| 原账号隔离、session/token、验证码持久化 | 保留，不用上游覆盖 | 完整 network 回归 |
| 自定义 Dock、默认滚动隐藏、字体选择 | 保留，不用上游 UI 覆盖 | 导航/字体回归和截图 |
| emoji grapheme、icon-grid 尾项修复 | 保留 | 对应现有回归测试 |
| 自适应 UI、图片查看器、键盘/鼠标/桌面 | 未同步 | 单独设计适配及视觉/交互复审 |
| Markdown、导出、公告 | 未同步 | 独立需求/隐私/依赖/网络范围评估 |
| Android 外部 intent / MethodChannel 链接接收 | 未同步 | 本批仅已有应用内链接入口；独立原生生命周期验证 |
| Flutter/Dart/SDK/AGP/锁文件/第三方插件 | 未同步 | 可复现迁移构建，不能只升版本号 |
| 签名、发行版、applicationId、更新源 | fork 身份保留 | 本仓库独立发行配置 |
| 原生 Android 客户端 | 另批协调，不由此清单宣称完成 | 原生单测/构建/独立复审/截图 |

## 回归与验证记录

新增/扩展离线测试：

- `test/network/guest_detail_test.dart`：公开 JSON/未知 HTML/app-only HTML、验证码与登录原因、取消后错误动作、缺 ID 无自动评论、显式操作重复点击、取消后重试、同控制器导入/移除、已读评论保留、账号变更丢弃异步结果。
- `test/network/request_test.dart`：不可变混合大小写 Cookie 头公开 feed 请求；已有会话隔离用例保留。
- `test/network/response_test.dart`：未上架文案仅指定 endpoint/status 生效。
- `test/ui/share_links_test.dart`：编码 payload、完整 emoji 摘要、可信 aliases/custom authorities、不同路由去分享参数、lookalike/端口外部处理、无效 URI/转义/UTF-8/ID 分隔符/userinfo 拒绝。
- `test/source/upstream_sync_contract_test.dart`：当前 fork 构建版本/身份/会话接口、Share/Copy 调用点及最小 UI 边界。

验证记录：

- 初始冻结 v2 manifest SHA256 `f014fced5470b8d440dd177b632add276283fd8ca2afb024948b42ee73d68362`：`git diff --check` 通过，Flutter analyze 退出 0（10 条 info，0 error/warning）；focused tests 100 通过、1 失败，源树前后不变。不能视为完整通过。
- 唯一失败为滚动评论测试使用 `find.widgetWithText(FilledButton, ...)`；Flutter 3.24.5 的 `FilledButton.tonalIcon` 实际返回 `_FilledButtonWithIcon` 子类，精确类型 finder 永远匹配不到，50 次滚动后 `dragUntilVisible` 的 `element(finder)` 抛出 No element。已改为实际文案 + `is FilledButton` 祖先断言，并断言真实 FeedPage/正文/CustomScrollView 所属 Scrollable，等待 mock 响应完成而非固定 sleep；保留不自动请求和真实点击请求数断言。另修复新增测试的 curly-braces info。
- 加入 app-only 页面重试/设备导入按钮及取消验证 UI 测试；可设置 `UPSTREAM_SYNC_EVIDENCE` 和 `FLUTTER_ROOT` 生成四张真实 Flutter widget 渲染截图（缺 ID 评论门控、已加载空评论、公开页需验证、取消验证）。合成离线内容，不是 Android 真机/已安装 APK 截图。
- 第二轮（v3 冻结 manifest `c242c23c59d8e98893008807c9483e25b421808bf6221218abc6d2a5a4c3ad94`）analyze 退出 0；focused 测试运行到首个 widget 用例后停滞，根任务保留原日志并中止（exit 130），前后源树不变。这不是产品通过/失败结论。原因是测试在 `runAsync` 中等待由 fake zone 内 Dio `Future(() ...)` 定时器推进的完成信号，却没有泵 fake clock，形成等待闭环。修复为最多 40 帧的受限 `pumpUntil`，要求 mock 完成信号与真实成功/错误 UI 同时成立；网络等待不再用 `runAsync`，仅真实字体/图像/文件 I/O 保留 `runAsync`，不增加 wall-clock sleep。滚动、按钮点击及请求计数验证全部保留。
- 第三轮（v4 冻结 manifest `b07c6bf9c730e3b983ecd0810afabe4b10d3c6f1235af88e7f3b6e2f10291276`）：analyze 退出 0，focused tests **102 通过、0 失败**，前后源树不变；四张真实 widget 渲染截图已生成。为匹配实际 main 的设置，随后仅关闭测试壳的 Debug Banner，待全量回归重生成截图。
- 完整本地 gate（v5 冻结 manifest `b75c14128e684850befe0941946d2e6ee177e5951440749c59e07277fbbdc62d`）：7 个阶段全部退出 0，前后源树一致。analyze 为 10 条 info、0 error/warning（包含新增测试的冗余 import 提示）；Python 诊断身份合约 3 项通过；隔离 Hive / 字体设置 / 账号管理分别 1 / 13 / 2 项通过；全量 Flutter **368 项通过、5 项既有跳过**；独立 diagnostic flag 导航子集 5 项通过。跳过项为原有 3 个登录 widget 用例与 2 个需显式在线环境的 live 用例，本批未新增或放宽 skip。四张无 Debug Banner 的真实 widget 截图及现有导航/字体/图库/表情回归素材已生成。重叠的 isolated/focused/full 数量不相加。
- 本记录随后仅补充上述 gate 结果，15 个生产/测试文件与已测试 v5 字节相同。APK 构建、安装、真机截图尚未执行；待独立复审与 CI 构建产物核验，不以离线回归代替真机或在线验收。

测试仅使用合成数据和 mock adapter，不访问真实服务、不使用账号凭证。此处不得将测试未执行写成通过。


### 本地 SDK 与大字体集成检查更新

工具链和最小依赖迁移，以及“我的”快捷入口完整标签修复，已完成本地 405 项全量回归（另有 5 项既有跳过）、三种 APK 构建与实际身份检查和限定范围的独立复审；详细冻结来源、失败历史与设备边界见 [工具链迁移记录](FLUTTER_TOOLCHAIN_MIGRATION.md)。Markdown、导出、自动设备标识注册等后续候选不因此视为已同步。最终远端 CI 仍须绑定其实际提交。


### 主分支 CI91 已核验

SDK 与大字体快捷入口增量已发布为 `2aa5348790778c229f8fed647d2b92aae1143d74`，CI91 的检查与五种 APK 构建全部通过，普通 arm64 产物已独立核对。详见 [迁移记录](FLUTTER_TOOLCHAIN_MIGRATION.md)。这不包含仍在单独验证的 Flutter Markdown／导出候选，也不代表实机或完整上游同步验收。
