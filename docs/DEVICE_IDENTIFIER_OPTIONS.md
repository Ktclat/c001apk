# 不安装官方酷安时，如何管理设备标识？

## 结论（2026-10-21）

**默认浏览本身不需要安装官方酷安**。目前 `apps/flutter/lib/utils/storage_util.dart` 的 `GStorage.fullSetXAppDevice()` 会在首次生成协议参数时创建并持久化一个 `ca_` 前缀的本地安装标识，随后按既有编码格式写入 `X-App-Device` 的首字段。只有用户导入或手动填写 `ShuzlmID` 时，才替换这个首字段。其他机型参数由 Android 系统读取的非唯一设备信息组成。

这并不意味着本地 ID 等于数字联盟发行的可信设备 ID，也不代表酷安服务端会给它同等信任。

## 可行途径和限制

| 方式 | 需要官方酷安 | 说明 |
| --- | --- | --- |
| c001apk 本地安装标识 | 否（已实现） | 不额外读取硬件唯一 ID；不保证被酷安认作 ShuzlmID。 |
| Android 系统的 ANDROID_ID | 否 | Android 8.0+ 按应用签名密钥、用户、设备分域，另一个应用获取的值可能不同。不是 ShuzlmID。 |
| Google Play App Set ID | 否 | 由 Google Play services 提供，作用域可能仅限本应用，也不是 ShuzlmID。 |
| 已有的数盟 ID 手动填写 | 否（需要预先拥有自己的合法标识） | 通过设置 → 协议与设备 → 手动填写设备信息，保留原账号与本地数据。 |
| 数字联盟官方可信 ID SDK | 否（理论上） | 需要向 SDK 厂商申请接入和明确的分发使用许可；第三方 SDK 可能收集设备、网络、传感器或 OAID 等数据，必须依法进行隐私告知/同意。取得的 ID **不保证与酷安官方客户端相同或被其服务端接受**。 |

数字联盟官方：[可信 ID 及业务说明](https://www.shuzilm.cn/) · [SDK 接入申请](https://www.shuzilm.cn/apply) · [隐私政策](https://www.shuzilm.cn/privacy)。

Android 官方：[唯一标识符最佳实践](https://developer.android.com/identity/user-data-ids) · [ANDROID_ID 说明](https://developer.android.com/reference/android/provider/Settings.Secure) · [App Set ID](https://developer.android.com/identity/app-set-id)。

## 可执行的后续开发方案

1. **继续维持本地生成模式**作为默认值。它无官方客户端依赖，且原有代码已经持久化保存，避免每次启动随机改变请求设备参数。
2. 对于必须使用真实数盟 ID 的场景，**联系数字联盟申请官方 SDK 接入**。在得到允许的 SDK 包、配置、应用标识与许可范围后，再独立评审是否能集成到开源仓库。特别需要确认供应商允许公开源码发布配套集成代码及可分发二进制组件。
3. 即使数盟授予合法接入权限，也需要独立核对酷安服务端是否允许该第三方应用的标识。不能因 SDK 返回非空字符串就认定可用于登录或跳过验证。
4. 未获得确认前，继续保留“手动导入自己的已有 ID”与网站公开页面浏览途径；不使用来路不明的 ID 生成器、模拟器批量生成、签名冒充或篡改 SDK 风控逻辑。

## 研究方式与边界

已对照本项目源代码、数字联盟官网的 SDK 产品与申请页面、Android 官方标识规范。未下载或运行酷安 APK，也未验证酷安非公开 SDK 的生成算法。现有环境未发现独立的 `rea` 分析 skill；针对这一判断无需下载并逆向安装包。现有证据**不支持**“直接调用系统 API 可得到酷安认可的 ShuzlmID”的承诺。
