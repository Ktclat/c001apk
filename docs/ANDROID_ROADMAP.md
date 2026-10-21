# Android 优先路线图

维护入口：[Ktclat/c001apk Issues](https://github.com/Ktclat/c001apk/issues) · [CI](CI.md)。此页是任务规划，不代表全部已实现或验收。

## P0 · 稳定性 / 发布基础

- [x] 分离 Android APK 编译与 Flutter 测试 job，避免单个测试阻塞 APK 构建。
- [x] 修复 CI Java 17 配置及自动构建 Debug APK。
- [x] 在设置中增加 Android 系统字体与 Material 默认字体切换。
- [ ] 修复账号管理测试超时并保证全部离线回归通过。
- [ ] 完成自己仓库的正式签名、Release 流水线及 SHA-256 校验。
- [x] 设置独立 Android applicationId `io.github.ktclat.c001apk`，避免与原项目安装包冲突；声明旧数据不会自动迁移。

## P1 · Android 体验

- [x] 增加可切换的悬浮底部 Tab 栏并在 Flutter 自动化中覆盖竖屏、横屏及页签状态（真机视觉验收仍待进行）。

- [ ] 真实 Android 设备核验系统字体切换、不同 ROM 与大字体下的换行效果。
- [ ] 长评论、图文内容、列表的字体层级、行间距和主题统一检查。
- [ ] 账号切换/退出、验证码取消与服务端失败后的 UI 恢复。
- [ ] 低内存、断网、后台恢复时的列表状态与图片缓存验证。
- [ ] 调整 Android 应用图标与发布图，全部采用本项目授权素材。
- [ ] 上传本项目真实 Android 首页/文章/设置截图，替换占位说明。

## P2 · 长期计划

- [ ] 可选内置开源中文字体，评估许可证、字体体积和 WebView 覆盖范围。
- [ ] Android 无障碍文本大小和手势检查。
- [ ] 隐私与本地存储导出、恢复方案的设计与测试。
- [ ] 评估 Kotlin / Jetpack Compose 迁移的成本；当前不会为迁移牺牲 Android 功能稳定性。

不维护 Windows/Linux/iOS 构建。公开任务反馈、修复和正式发布统一在自己的仓库完成；保留上游版权和贡献署名。
