# Apple Silicon 分发构建方案

评估与实施日期：2026-11-06。目标为可供其他 Mac 用户下载、解压并安装的 arm64 / macOS 13+ 应用。本文所列脚本与文档已实现；已独立构建 ad-hoc Release 包，未替换正在使用的开发包。实际命令见 [RELEASING.md](../RELEASING.md)，接收者说明见 [INSTALL.md](../INSTALL.md)。

## 结论

已参考 Unplug 的构建与发布分层，继续使用当前 Xcode 工程，补上 Release 构建、签名校验、公证脚本及 ZIP 产物。首版以 ZIP 为交付格式；DMG、Homebrew 和自动更新可以后续加入。公证脚本尚待有效证书和凭据的端到端实测。

当前用户已确认开发包在本机运行正常。这证明了本机试用结果，其他 Mac 下载后的 Gatekeeper 检查、首次授权和后台项行为需要单独验证。Apple 官方要求与证据见 [分发签名调查](DISTRIBUTION_SIGNING_RESEARCH.md)。

## 调整前基线与 Unplug 对照

| 项目 | 当前 turnintoserver | Unplug 的可借鉴部分 |
| --- | --- | --- |
| 构建入口 | `scripts/build-dev.sh`，Debug、arm64，默认 ad-hoc | `build.sh` 将构建与签名集中到一个入口 |
| 工程结构 | Xcode 资源、entitlements、内嵌 LaunchAgent | Unplug 是单 Swift 文件的手动组包；当前继续由 Xcode 管理包结构 |
| Release 配置 | 已有 `ENABLE_HARDENED_RUNTIME=YES`；尚无发行脚本 | Developer ID 签名时使用 runtime 和 timestamp |
| 版本 | `Info.plist` 仍固定为上游 `1.5.9` / build `33` | 版本参数传入构建，产物包含版本号 |
| 身份 | `com.local.macutils.turnintoserver.dev`，独立配置及权限 | 保持稳定的 Bundle ID 与发布者签名身份 |
| 公证/打包 | 尚无发行 ZIP、公证和装订入口 | `release.sh` 提交 ZIP，装订 `.app`，重新压缩并输出 SHA-256 |
| 发布说明 | README 的安装链接和部分更新说明仍沿用上游 | 独立发布文档、下载地址和可验证的发行产物 |

参考文件：工作区中的 `unplug/build.sh`、`unplug/release.sh` 和 `unplug/RELEASING.md`。仅保留 arm64；Unplug 的 universal 构建和其作者的证书、Team ID、Homebrew tap 配置不适用于本项目。

## 已实现的入口

### `scripts/build-release.sh`

- 使用 `xcodebuild -configuration Release`，保留现有资源、entitlements 和 `Contents/Library/LaunchAgents` 复制阶段。
- 通过 `VERSION`、`BUILD_NUMBER` 设置最终 `Info.plist`；读取产物校验实际值，避免只修改 ZIP 文件名。
- 使用独立 `build-release/` 或临时 DerivedData，产物写入 `dist/`，构建时不覆盖 `build-dev/`。
- 支持本地 ad-hoc 包与 Developer ID 签名包两种明确模式；发行模式缺证书即失败，避免产出被误认为已公证的包。
- 最终包内容准备完成后签名，保留 Apple Events entitlement。Developer ID 模式启用 hardened runtime、可信时间戳，并验证签名身份和完整性。
- 检查 arm64、最低系统版本、版本/build、Bundle ID、LaunchAgent 的标签、关联 Bundle ID 和目标可执行文件。

### `scripts/release.sh`

使用环境变量提供 `SIGN_IDENTITY`、`NOTARY_PROFILE` 等输入；公证凭据使用 Keychain profile。证书私钥和账户密码不进入仓库。

1. 调用 Release 构建，校验最终签名。
2. 通过 `ditto -c -k --keepParent` 创建供公证提交的 ZIP。
3. 执行 `xcrun notarytool submit --wait --output-format json`，显式检查状态为 `Accepted`；失败保留提交 ID 和诊断信息。
4. 对 `.app` 执行 `xcrun stapler staple` 和 `xcrun stapler validate`。
5. 使用 `spctl --assess --type execute` 检查应用，再重新压缩已装订的 `.app`。
6. 输出带版本/架构的 ZIP 和 SHA-256 校验文件。ZIP 内包含应用及第三方来源、许可证和安装说明。

此脚本生成本地发行候选包；GitHub Release 上传作为独立发布步骤。实际公证与另一台 Mac 的首次启动验收完成后，才将其标记为已验证的分发包。

### `RELEASING.md` 与安装说明

- 记录证书、公证 profile、版本参数、完整命令、最终产物路径和失败排查方式。
- 更新 README 的下载入口和开发版更新行为说明，避免把本分支用户引导至上游安装包。
- 安装步骤为解压后移入 `/Applications` 再启动；接收者首次允许所需的辅助功能、后台项和管理员授权。签名/公证不会替用户完成这些授权。
- 替换应用前关闭 Server Mode 并退出，让恢复完成、后台项注销；签名完成的包不再手工修改内容。
- 发布时保留第三方许可证，并处理 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) 已记录的上游许可和组合分发要求。

## 应用身份与后台项

近期本地包沿用现有开发身份，可减少此次打包调整对配置、授权和后台项的影响。首次正式分发前确定长期使用的 fork 身份和显示名称。

更改 Bundle ID 时，需要同步工程、`ApplicationIdentity`、LaunchAgent 文件名/Label/AssociatedBundleIdentifiers、`SMAppService.agent(plistName:)` 的注册名称及相关测试；评估既有配置和待恢复租约的迁移。不能只在构建命令中替换 `PRODUCT_BUNDLE_IDENTIFIER`。开发版继续禁用上游更新，独立更新源另行设计。

当前看护通过主可执行文件的 `--power-guard` 入口运行，`.app` 中包含 agent plist。发行时应验证这个完整包及其签名；无需为打包改为安装系统级常驻 daemon。

## 当前前提与验收

本次只读检查中，`security find-identity -v -p codesigning` 返回 `0 valid identities found`。Release 和本地 ZIP 流程已完成；Developer ID 公证发行需要发布者提供相应证书及 Keychain 公证 profile。

已验证 `0.1.0` / build `1` 的 ad-hoc Release ZIP：arm64、最低 macOS 13、hardened runtime、无 `get-task-allow`、包含 Apple Events entitlement、LaunchAgent、包内及应用内许可证、SHA-256、解压后的签名，以及无 GUI 的 MCP 初始化（返回 `0.1.0 (1)`）。11 项分发测试及原有 80 项检查通过；分发测试包含拒绝公证、命令错误、公证票据装订失败时不产生最终 ZIP。

发行候选验收至少包括：在另一台符合要求的 Mac 上下载并安装；首次授权后运行清洁模式和 Server Mode；更新后后台项、配置及授权行为；正常退出与进程意外结束后的恢复。自签名或 ad-hoc 包可以用于约定的测试分发，但其下载后的系统信任体验与 Developer ID 公证包不同，不应标记为已公证。
