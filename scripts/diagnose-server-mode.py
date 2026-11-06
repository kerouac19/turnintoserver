#!/usr/bin/env python3
"""Read-only Server Mode report. --reproduce asks you to click Start in the app."""
import argparse
import datetime
import json
import os
from pathlib import Path
import plistlib
import socket
import subprocess
import sys
import time


BUNDLE_ID = "com.local.macutils.turnintoserver.dev"
STATE_KEYS = ("server_mode_requested", "server_mode_active", "server_mode_status",
              "is_command_running", "last_command_status", "power_source", "lid_state",
              "allow_battery_server_mode")


def command_result(arguments):
    try:
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=15)
        return {"exit_code": result.returncode, "stdout": result.stdout[-20000:], "stderr": result.stderr[-3000:]}
    except (OSError, subprocess.TimeoutExpired) as error:
        return {"error": str(error)}


def app_status(path):
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(3)
            connection.connect(str(path))
            connection.sendall((json.dumps({"id": "server-mode-diagnosis", "action": "get_status", "params": {}}) + "\n").encode())
            response = json.loads(connection.makefile("rb").readline(1024 * 1024))
        if response.get("ok") is not True:
            return {"error": response.get("error", "Invalid app response")}
        data = response.get("data", {})
        state = data.get("state", {})
        return {"app": data.get("app"), "state": {key: state.get(key) for key in STATE_KEYS}}
    except (OSError, ValueError) as error:
        return {"error": str(error)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/turnintoserver.app"))
    parser.add_argument("--reproduce", action="store_true", help="Ask you to click Start, then assert that Server Mode becomes active.")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "build-dev/diagnostics/server-mode.json")
    args = parser.parse_args()
    support = Path.home() / "Library/Application Support/turnintoserver-dev"
    socket_path = support / "mcp-control.sock"
    before = app_status(socket_path)
    if args.reproduce:
        print("请在菜单栏 App 中点击 Start Server Mode，等待提示或启动结束，然后回到这里按 Enter。", flush=True)
        input()
    after = app_status(socket_path)
    for _ in range(5):
        if after.get("state", {}).get("is_command_running") is not True:
            break
        time.sleep(1)
        after = app_status(socket_path)
    report = {
        "captured_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "reproduction_requested": args.reproduce,
        "application": str(args.app),
        "before": before,
        "after": after,
        "power_guard_directory_exists": (support / "PowerGuard").is_dir(),
        "background_service": command_result(["launchctl", "print", "gui/%s/%s.power-guard" % (os.getuid(), BUNDLE_ID)]),
        "signature": command_result(["codesign", "--display", "--verbose=4", str(args.app)]),
        "system_version": command_result(["sw_vers", "-productVersion"]),
    }
    try:
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        report["bundle"] = {key: info.get(key) for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion")}
    except (OSError, ValueError) as error:
        report["bundle"] = {"error": str(error)}
    predicate = '(process == "turnintoserver" AND (eventMessage CONTAINS[c] "guard" OR eventMessage CONTAINS[c] "SMAppService" OR eventMessage CONTAINS[c] "SleepDisabled")) OR eventMessage CONTAINS "com.local.macutils.turnintoserver.dev.power-guard"'
    report["startup_logs"] = command_result(["/usr/bin/log", "show", "--last", "5m", "--style", "compact", "--info", "--predicate", predicate])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("诊断文件：%s" % args.output)
    if "state" not in after or after["state"].get("server_mode_active") is None:
        print("UNAVAILABLE: 无法读取运行中 App 的状态；本次结果不能作为启动故障的复现。")
        return 2
    if after["state"]["server_mode_active"]:
        print("PASS: Server Mode 已实际开启。")
        return 0
    print("FAIL: Server Mode 未开启；last_command_status=%r" % after["state"].get("last_command_status"))
    return 1


if __name__ == "__main__":
    sys.exit(main())
