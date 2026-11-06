# Server Mode 启动失败：后台服务注册状态

## 实机失败记录

2026-11-06，用户在 macOS 27.2 上运行 `/Applications/turnintoserver.app`，版本 `0.1.0` / build `1`（ad-hoc 签名）。点击 Start Server Mode 后未进入运行状态。

用户运行以下只读诊断脚本并通过界面复现：

```sh
python3 scripts/diagnose-server-mode.py --reproduce
```

输出：

```text
FAIL: Server Mode 未开启；last_command_status='Failed: Allow the development power guard in System Settings → Login Items'
```

报告显示电源模式未开启，看护目录未建立，launchd 未找到对应服务；系统日志提示后台管理记录 `record not found`。启动失败发生在看护准备租约和电源修改之前。原报告未直接读取 `SMAppService.status` 的枚举值；结合旧流程、对应回归测试和新包注册成功的结果，确认记录缺失时被旧准入流程阻断。

## 已确认的代码缺陷与修复

旧客户端只在 `status == .notRegistered` 时调用 `register()`；其他所有非 `.enabled` 状态都被当作“用户尚未允许后台运行”。这会让 `.notFound` 无法尝试登记，也会向用户提供不对应当前状态的权限指引。

现在真实客户端和回归测试共用 `PowerGuardServiceReadiness`，通过可注入的服务注册接口执行以下规则：

| 状态或结果 | 行为 |
| --- | --- |
| `.enabled` | 继续原有看护 ping 和权限预检 |
| `.notRegistered` / `.notFound` | 尝试注册一次，再检查结果 |
| `.requiresApproval` | 明确提示用户批准，不重新注册以覆盖用户选择 |
| 注册后仍未就绪 | 返回实际状态，不进入电源操作 |
| 注册抛出其他错误 | 保留 NSError domain、code 和错误描述 |

不注销或重建已有服务，不绕过用户批准，不在看护就绪前设置电源。原有恢复租约、心跳和恢复确认顺序保持原路径。

Apple 区分“注册成功但待用户操作”与“框架无法找到服务”；注册本身受用户同意约束。文档支持上述状态区分，不保证注册操作在所有签名和系统环境下都成功。[Apple：SMAppService.Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/enabled)、[Apple：register()](https://developer.apple.com/documentation/servicemanagement/smappservice/register())

## 回归与验收

先将旧注册逻辑提取到真实客户端共用入口，再加入“初始 `.notFound`，注册后 `.enabled`”的测试；修复前 `./scripts/test.sh` 稳定失败，返回同一条 Login Items 提示。修复后 92 项检查通过，覆盖首次登记、记录缺失、已启用、用户待批准、登记后仍缺失、底层错误保留等情形。11 项分发测试通过。

原测试覆盖电源租约恢复，但没有覆盖 SMAppService 注册准入；新增接口让启动准入也可以在不注册真实服务、不改电源的情况下测试。

已独立构建 `0.1.1` / build `2` 的 ad-hoc Release ZIP，校验 SHA-256、解压后的包结构及签名，并完成无 GUI 的 MCP 初始化，返回版本 `0.1.1 (2)`。产物为 `dist/turnintoserver-dev-0.1.1-b2-arm64-adhoc.zip`；未替换 `/Applications` 中的旧包。

用户随后安装 `0.1.1` / build `2`，重新运行上述诊断命令并通过界面启动 Server Mode，返回 `PASS: Server Mode 已实际开启。`。2026-11-06 18:30 的新报告确认：

- `server_mode_requested=true`、`server_mode_active=true`，没有运行中的待完成命令。
- `last_command_status=Success: Started on power adapter`。
- launchd 中电源看护为 `running`，父包版本为 `2`；系统日志显示后台记录缺失后完成登记，随后 job 提交成功。

原始启动失败已通过用户实机复测关闭。此结论覆盖该 Mac 上的启动路径，不代替睡眠唤醒、崩溃恢复或其他系统版本的专项验收。

脚本仅采集有限状态、签名信息与相关启动日志，报告保存在已忽略的 `build-dev/diagnostics/server-mode.json`。退出码为 `0` 时确认实际开启；`1` 表示读到未开启状态；`2` 表示无法读取 App，不能当作故障复现。

当前代理沙箱禁止访问运行中 App 的控制 socket 和系统日志；本次由用户终端执行诊断，代理读取保存的报告完成核对。如果将来返回签名或包登记错误，依据保留的实际错误继续诊断，不能将其归为一般登录项权限问题。
