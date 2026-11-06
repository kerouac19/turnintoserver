# 安装 turnintoserver Dev

适用于 Apple Silicon、macOS 13 及以上。Intel Mac 不受支持。

## 安装

1. 从提供者取得 ZIP 及同名 `.zip.sha256` 文件，确认包的来源。
2. 可在 ZIP 所在目录运行 `shasum -a 256 -c <文件名>.zip.sha256` 检查下载完整性。
3. 解压 ZIP，将其中的 `turnintoserver.app` 拖到 `/Applications`（应用程序）。保留包内的许可证与第三方来源说明。
4. 打开 App；它显示在菜单栏中，没有 Dock 图标。当前名称为 `turnintoserver Dev`。

文件名包含签名状态：`adhoc` 是未公证的测试包；`signed-unnotarized` 已使用 Developer ID 签名但尚未公证；`notarized` 已完成本次发布流程的公证、票据装订和本机构建验证。具体版本、build 和签名状态也记录在 `build-info.json` 中。

未公证包下载到其他 Mac 后可能被系统拦截。如果 macOS 拒绝打开，请向提供者索取公证包。SHA-256 校验用于发现文件变化，不能替代对发布者身份的确认。

## 首次授权

- 清洁模式需要“系统设置 → 隐私与安全性 → 辅助功能”授权；按 App 引导允许后再进入。
- 开启 Server Mode 时，按提示允许电源看护后台运行，并完成管理员授权。后台项由“系统设置 → 通用 → 登录项”（较新系统为“登录项与扩展”）管理。
- iMessage 电量提醒会另行请求控制 Messages 的自动化权限。
- 签名和公证不会自动授予上述权限。具体提示名称随系统版本变化。

清洁模式可连续按 5 次 Esc 或点击解锁退出。外接屏控制会保护最后一个可用显示输出。

## 更新、退出和移除

替换旧 App 前，先关闭 Server Mode，等待恢复完成，然后退出；不要直接覆盖正在工作的 App。将新包中的 App 复制到相同位置后重新打开。ad-hoc 重建可能需要重新授予辅助功能权限。

当前整合版禁用上游自动更新，更新通过新 ZIP 手动安装。原版与开发版的配置分开保存，但它们不能同时管理全局电源状态。

移除前同样先关闭 Server Mode 并退出，再删除 App。配置默认保留在 `~/Library/Application Support/turnintoserver-dev`。如出现恢复失败提示，先完成恢复再移除；不要删除待恢复记录。

本包包含 [第三方来源说明](THIRD_PARTY_NOTICES.md) 和 `Licenses/`。应用内部的 `Contents/Resources/ThirdParty/` 也保留相同说明。
