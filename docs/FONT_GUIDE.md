# 字体与中文排版 · 设计审阅说明

## 这轮为什么重做

用户的主页与图文详情截图表明：中文笔画显得过重、标题正文不分层、长文章密密麻麻，且 `**强调文字**` 被显示为星号。原版 Flutter / Android 默认字体回退会因品牌、系统版本发生变化，**只调整字号不够**。

参考资料：[Flutter 字体回退说明](https://api.flutter.dev/flutter/painting/TextStyle-class.html)，更早的 [c001apk-flutter](https://github.com/bggRGjQaUbCoE/c001apk-flutter/blob/main/lib/components/html_text.dart)（原来 16sp 正文、1.5 行高）。本分支不再直接沿用那套密集排版。

## 新版 UI 字体

**设置 → 阅读与字体 → 界面字体**：

- **思源黑体 · 清爽（新版推荐）**：Noto Sans CJK SC 字体，固定 w400 Regular、w500 Medium、w700 Bold 文件，简体中文常用字子集，离线渲染。新安装默认使用；已有安装首次升级时也会**一次性切换到新版**，其后个人设置继续有效。
- **跟随系统**：使用 Android `sans-serif` 映射；可能随着小米、OPPO、vivo、三星等 ROM 与系统加粗设置发生变化。
- **Material 原版**：尽量接近原 Flutter 的平台默认字体，便于对照。

**设置 → 阅读与字体 → 正文排版**默认使用“舒适阅读”，也可切换“原版排版”，独立于字体家族、系统文字缩放和应用字号滑块。界面字体、正文排版与字体大小统一放在“阅读与字体”；配色和悬浮导航在“外观与导航”中设置。

## 版式规范（sp）

| 区域 | 新版舒适阅读 | 旧版排版 |
| --- | --- | --- |
| 动态正文 | 14.5 / w400 / 行高 1.52 | 16 / w400 / 行高 1.50 |
| 动态标题 | 15.5 / w500 / 行高 1.40 | 16 / w700 / 行高 1.50 |
| 长文章正文 | 15 / w400 / 行高 1.52 | 16 / w400 / 行高 1.50 |
| 长文章标题 | 16.5 / w500 / 行高 1.40 | 17 / w700 / 行高 1.50 |
| 主要评论 | 14 / w400 / 行高 1.52 | 15 / w400 / 行高 1.50 |

链接、emoji、强调、嵌套评论继续单独处理。纯正文与标题颜色略柔和，保持足够对比度；禁止对整篇文章使用 w600/w700。简单 Markdown 粗体 `**文字**` 转为强调标签；超过两个连续换行的空白段落收敛到一个空段落。用于浏览动态的 HtmlWidget 与图文详情共用同一套字体样式，避免中英混排粗细不一致。

## 字体资源来源、许可和离线使用

字体从 [CodePlayer/webfont-noto](https://github.com/CodePlayer/webfont-noto/tree/7af038d32866b387c64ef8e644abf5c303e48db6/dist/NotoSans/NotoSansCJKsc-hinted/subset/NotoSansCJKsc-hinted-standard) 的固定提交获取，原始许可为 **SIL OFL 1.1**。许可原文复制在 [OFL.txt](../apps/flutter/assets/fonts/OFL.txt)。本仓库不分发 OpenAI 专有字体。

为了控制 git 仓库体积，不提交大体积二进制字体，而让 GitHub Actions 在编译前运行 `bash tools/fetch_fonts.sh`。此脚本要求所有文件的 Git blob SHA **完全匹配**；不匹配时中断构建。下载发生在**编译期**；安装到手机后的 APK 内已经带上字体，运行时无需联网。

从源码构建，请执行：

```bash
cd apps/flutter
bash tools/fetch_fonts.sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --profile --no-pub
```

## 审阅与验证边界

自动化审阅在 390dp 宽度下绘制包含动态、长文章、评论、中文标点、英语和数字的 **合成预览图**；另在 320dp 与 1.3 倍字体下检查无溢出。预览生成于 `test/ui/typography_visual_review_test.dart`，CI 上传为 `c001apk-typography-review` 产物。另有字体字重、Markdown 与 Hive 迁移测试。

**自动测试通过不代表用户提供的真实酷安帖子已经逐页目视验证，也不能代表所有 Android ROM 都相同。** 修改后的字体仍需用 Profile APK 在用户设备确认，尤其检查包含非常用字、emoji、图文混排与系统加粗设置的场景。若仍不合适，可切换系统字体或原版排版对照。
