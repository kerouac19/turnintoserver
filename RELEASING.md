# 构建与分发

目标为 arm64、macOS 13+。当前沿用独立整合身份 `com.local.macutils.turnintoserver.dev` 与 `turnintoserver Dev` 名称；开发版和发行候选均禁用上游更新。当前流水线生成 ZIP，不创建 GitHub Release。

## 环境与一次性配置

- 安装完整 Xcode，脚本默认使用 `/Applications/Xcode.app/Contents/Developer`；其他位置通过 `DEVELOPER_DIR` 指定。
- 构建机需要 Bash、Python 3 标准库、Xcode 的 `xcodebuild` / `xcrun`，以及 macOS 自带的 `codesign` / `ditto` / `shasum`。接收者运行 App 不需要这些构建工具。
- 公证发行需要有效的 **Developer ID Application** 证书及其私钥。检查：`security find-identity -v -p codesigning`。
- 配置 `notarytool` Keychain profile。例如运行下列命令后按提示输入 app-specific password，不把密码写进脚本或提交到仓库：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun notarytool store-credentials turnintoserver-notary \
  --apple-id 'you@example.com' --team-id 'YOUR_TEAM_ID'
```

脚本读取环境变量，不自动 `source .release.env`。请按需在终端导出变量；`.release.env` 已被忽略，私钥、密码及公证凭据均不应进入仓库。

## 版本和目录

每次显式提供 `VERSION`（三个十进制数字段，例如 `0.1.0`）及 `BUILD_NUMBER`（1–9999 的整数）。同一版本更新时递增 build。它们写入最终 `Info.plist`，不修改源文件中的默认版本设置。

- 默认工作目录：`build-release/`，每次使用单独子目录保留构建日志与 DerivedData。
- 默认产物目录：`dist/`，可通过 `DIST_DIR` 指定另一目录。
- `RELEASE_BUILD_ROOT` 可覆盖工作目录。`build-dev/` 不受影响。
- 已存在的同名目录、ZIP 或校验文件会令脚本退出，不覆盖旧包。失败时可能留下不完整目录和诊断文件；检查后手工移走它们，或用新的 build / `DIST_DIR` 重试。
- 只有脚本完整成功后才把最终 ZIP 作为交付物。`build-info.json` 记录版本、签名、公证状态、源提交及工作区是否有未提交改动。

## 本地 Release 测试包

```sh
./scripts/build-release.sh --ad-hoc 0.1.0 1
```

输出：

```text
dist/turnintoserver-dev-0.1.0-b1-arm64-adhoc/turnintoserver.app
dist/turnintoserver-dev-0.1.0-b1-arm64-adhoc.zip
dist/turnintoserver-dev-0.1.0-b1-arm64-adhoc.zip.sha256
```

这是 Release 优化、hardened runtime、ad-hoc 签名的测试包，未经公证。在其他 Mac 上经下载后不保证通过 Gatekeeper。安装方法见 [INSTALL.md](INSTALL.md)。

若当前执行环境需要禁用编译器子进程的内部 sandbox，可仅对本次命令设置 `COMPILER_SUBPROCESS_SANDBOX=NO`，与开发构建脚本一致；普通构建机保留默认设置即可。

## Developer ID 签名包

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  ./scripts/build-release.sh --signed 0.1.0 1
```

此模式检查证书，最终包使用 secure timestamp 签名；没有有效证书就失败。产物后缀为 `signed-unnotarized`，明确表示尚未完成公证。

## 公证分发包

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE=turnintoserver-notary \
  ./scripts/release.sh 0.1.0 1
```

也可以通过环境变量 `VERSION`、`BUILD_NUMBER` 传入版本，位置参数优先。

该命令：

1. 独立构建并签名 Release 包，检查 arm64、Mach-O 与 plist 的最低系统版本、版本/build、Bundle ID、LaunchAgent、许可证、签名及 entitlements。
2. 用 `ditto` 制作提交 ZIP；`notarytool submit --wait` 后解析 JSON，只有 `Accepted` 且 submission ID 有效才继续。
3. 向 `.app` 装订票据，并执行 `stapler validate`、`spctl --assess --type execute` 及最终签名验证。
4. 重新压缩已装订的应用，生成 `dist/turnintoserver-dev-0.1.0-b1-arm64-notarized.zip` 及同名 `.zip.sha256`。

公证响应保存在打印的工作目录中的 `notary-result.json`。失败时保留该文件；取得其中 `id` 后查询诊断：

```sh
xcrun notarytool log '<submission-id>' \
  --keychain-profile turnintoserver-notary notary-log.json
```

ZIP 本身不能 staple；最终 ZIP 由已装订的 `.app` 重新生成。正式凭据与公证服务未就绪时，本地可验证测试包路径，但不能宣称 Developer ID / 公证流程已完成实测。[Apple 官方流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

## 检查和交付

```sh
./scripts/test.sh
python3 -m unittest discover -s Tests -p 'test_distribution.py'
git diff --check
cd dist
shasum -a 256 -c turnintoserver-dev-0.1.0-b1-arm64-notarized.zip.sha256
```

ZIP 包含 App、`INSTALL.md`、`THIRD_PARTY_NOTICES.md`、`Licenses/` 与 `build-info.json`。通知与许可证也在签名前嵌入应用的 `Contents/Resources/ThirdParty/`。

在另一台 Mac 上通过实际下载的 ZIP 验证首次打开、授权、清洁模式、Server Mode、更新、正常退出和意外结束后的恢复。公证通过不等于全部功能验收通过。首次正式发行前还需确定长期应用身份、处理第三方分发授权和 GPL 对应源码要求，参见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

确认发行候选后，可手动在自己的仓库创建 Release 并上传 ZIP、校验文件和所需源码；脚本本身不上传到 GitHub。不要用本包更新上游仓库的同名发行版。

## 身份与更新

当前打包不更改 Bundle ID、后台项 Label 或配置目录。更换长期身份时须同步工程、`ApplicationIdentity`、LaunchAgent 名称/关联标识、`SMAppService.agent(plistName:)` 和测试，并设计既有配置与租约迁移。签名身份变化后重新验证权限连续性。

替换用户正在使用的 App 前，先关闭 Server Mode 并退出，等待恢复与后台项注销完成；构建脚本不会停止或重启运行中的 App。
