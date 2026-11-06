# macOS 直接分发：签名、公证与权限核查

核查日期：2026-11-06。范围：arm64、macOS 13+ GUI app；`SMAppService.agent` 从 app 内运行同一主 executable 的 `--power-guard` 模式。本笔记只核查 Apple 官方资料；未运行 app、注册服务、申请证书或进行接收端验收。

## 对构建流程的结论

建议保留本地开发构建，并增加明确的直接分发流程：完整组装 app → Developer ID 签名 → 打包 → 公证 → staple → 发布验证。Apple 对直接分发提供 ZIP、DMG 等格式，并不要求必须制作 PKG；因此借鉴其他项目时，应对齐这些发行步骤，而不是仅复制其打包外观。[Apple：Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

本次主代理检查到 `security find-identity` 为 `0 valid identities`，且当前 `build-dev.sh` 构建 Debug；Release 配置已有 `ENABLE_HARDENED_RUNTIME=YES`。这些是当前本机检查结果，不能视为已完成 Developer ID 发行签名或公证。

## 本机 ad-hoc 可用，不代表接收端可直接打开

Apple 明确区分两件事：Apple silicon 的执行签名要求可以由 ad-hoc 满足，这类签名也不限于构建它的那台 Mac；但其缺少有效开发者身份，不能通过 Gatekeeper。因此，作者本机运行成功不能证明经浏览器下载到另一台 Mac 后的默认打开体验。[Apple：macOS Big Sur 11.0.1 Universal Apps Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)

面向正常直接分发，app 使用 **Developer ID Application** 身份；公证要求有效签名、Hardened Runtime、secure timestamp，且不能携带值为 `true` 的 `com.apple.security.get-task-allow`。不要把 ad-hoc、Apple Development 或 Mac App Store 用的发行证书当成此流程的替代品。[Apple：Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

完整写入 `Info.plist`、LaunchAgent plist 和资源后再签名；如以后增加独立 helper，按由内到外的顺序签名。手工签名的具体选项应依据 Apple 的发行签名文档；主 executable 的 Hardened Runtime 对应 `codesign -o runtime`，secure timestamp 对应 `--timestamp`。[Apple：Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

## ZIP / DMG 的合理顺序

| 格式 | 发行顺序 |
| --- | --- |
| ZIP | 签好最终 `.app` → 用 `ditto -c -k --keepParent` 创建提交用 ZIP → `xcrun notarytool submit … --wait` → 确认 `Accepted` 并检查 log → `xcrun stapler staple App.app` → 用附带票据的 `.app` **重新创建最终 ZIP**。 |
| DMG | 签好最终 `.app` → 制作 DMG → 用 Developer ID Application 签 DMG 并加 timestamp → 提交最终 DMG 公证 → 确认结果并检查 log → `xcrun stapler staple Product.dmg`。 |

ZIP 可提交公证，但**不能直接签名，也不能直接 staple**；Apple 要求给其中可 staple 的项目附加票据后重新打包。DMG 可以直接签名和 staple。对于通常的嵌套容器，Apple 建议签好各层后只提交最外层公证。[Apple：Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[Apple：Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

`notarytool` 是当前命令行提交工具；`altool` 自 2023-11-01 起不再受公证服务支持。Staple 让 Gatekeeper 在离线时也能找到票据；没有 staple 的公证产物仍可能依赖在线查询。[Apple：Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

以上是流程建议和命令名称，并非本次执行记录。

## `SMAppService.agent` 的已确认要求与边界

- `agent(plistName:)` 的参数必须对应调用 app 的 `Contents/Library/LaunchAgents` 内的 plist。[Apple：agent(plistName:)](https://developer.apple.com/documentation/servicemanagement/smappservice/agent(plistname:))
- helper 留在 app bundle 内，`BundleProgram` 使用相对该 bundle 的路径。本项目复用主 executable 时，路径应指向 `Contents/MacOS/<executable>`，`--power-guard` 是启动参数，不能拼进 executable 路径。路径原则来自官方迁移文档；“复用主 executable”的适用性仍需本项目验收。[Apple：Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- Apple DTS 在排查 `SMAppService` 后台执行问题时建议 app 与内嵌 helper 使用相同的 Apple-issued code-signing identity，并指出 ad-hoc 可造成身份相关问题。这是官方工程师的实践指导；**不能外推成所有 macOS 版本上的 ad-hoc 用户级 agent 一律无法注册或运行**。[Apple DTS：SMAppService Sample Code seems broken](https://developer.apple.com/forums/thread/799910)
- Apple DTS 的入门示例将 helper 放在 `Contents/MacOS`；改为 agent 时将 plist 改放 `Contents/Library/LaunchAgents`，并使用 `SMAppService.agent`。这支持 bundle 内服务的方向，但示例使用独立 helper，不能替代对本项目同一 executable 双模式的测试。[Apple DTS：Getting Started with SMAppService](https://developer.apple.com/forums/thread/802443)

## 更新与 Accessibility / TCC

Apple 的 TN3127 说明系统用 designated requirement（DR）追踪代码身份，并以麦克风权限解释版本更新后如何继续识别同一 app。ad-hoc 的 DR 绑定特定代码版本，不能可靠维持跨版本身份；Apple Development 与 Developer ID 的默认 DR 也不同。因此，稳定的 bundle / signing identifier 和兼容的发行签名身份有助于权限连续性，不能只看文件名或“Team ID 没变”。[Apple：TN3127 Inside Code Signing: Requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

**证据边界：**该文档足以解释为何 ad-hoc rebuild 可能导致隐私授权反复出现；它没有保证本项目的 Accessibility 授权在每种升级、移动路径、GUI / LaunchAgent 启动方式之间始终保留。`AXIsProcessTrustedWithOptions` 检查的是当前进程是否为可信 Accessibility client，提示也是异步的；需分别验证 GUI 与 `--power-guard` 模式。[Apple：AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

签名和公证不会代替接收者授权：首次使用 Accessibility 功能仍需接收者本人在“隐私与安全性 → 辅助功能”授予访问；后台项也受接收端“登录项与扩展”设置控制，程序必须检查实际授权状态并按系统要求引导用户允许。不同 macOS 版本的提示形式可能不同，不应承诺每次首次注册 agent 都出现相同弹窗。[Apple：Allow accessibility apps to access your Mac](https://support.apple.com/en-ie/guide/mac-help/mh43185/mac)、[Apple：Open items automatically when you log in on Mac](https://support.apple.com/en-ie/guide/mac-help/mh15189/mac)、[Apple：Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)

## 仍待发行验收

取得实际 Developer ID 签名和公证产物后，在另一台未使用过本 app 的 Mac 上，从真实下载的 ZIP / DMG 安装，验证首次打开、离线打开、Accessibility 授权、agent 注册与状态、退出 GUI 后运行、重登，以及旧版覆盖升级后权限是否延续。Apple 明确建议用最终容器在不同 Mac 上测试首次安装、升级、重复副本和不同用户等情形。[Apple：Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

当前未发现有效签名身份；公证凭据尚未验证。仍待确认：最终产物是否通过 Gatekeeper、同一 executable 的 agent 模式在 macOS 13+ 各目标版本上的授权归属及更新连续性。以上均未进行真机验收。

抓取记录：优先尝试 `ax`；Apple 动态文档页正文为空，后续请求遇到 `certificate has expired`，故使用联网检索工具核对上述 Apple 文档及带 Apple Staff 标识的 DTS 原帖。未使用第三方博客或论坛用户陈述作为要求依据。
