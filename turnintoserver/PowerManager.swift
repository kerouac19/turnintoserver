import Foundation
import IOKit.pwr_mgt

@MainActor
final class PowerManager {
    var onGuardFailure: ((String) -> Void)?
    private var caffeinateProcess: Process?
    private var timedDisplayAwakeProcess: Process?
    private var timedUserActivityProcess: Process?
    private var timedUserActivityTimer: Timer?
    private let powerGuard = PowerSessionGuardClient()

    init() {
        powerGuard.onFailure = { [weak self] message in
            self?.stopTimedDisplayAwake()
            self?.stopCaffeinate()
            self?.onGuardFailure?(message)
        }
    }

    var hasPendingRecovery: Bool { powerGuard.hasSession }

    var isServerModeActive: Bool {
        caffeinateProcess?.isRunning == true && powerGuard.hasSession
    }

    func enableServerMode(powerSource: PowerSource) async -> PowerCommandResult {
        let sleepDisableResult = await ensurePowerPermission()
        guard case .success = sleepDisableResult else { return sleepDisableResult }
        do { try await powerGuard.begin() }
        catch { return .failure(error.localizedDescription) }
        let caffeinateResult = startCaffeinate(powerSource: powerSource)
        guard case .success = caffeinateResult else {
            try? await powerGuard.restore()
            return caffeinateResult
        }

        switch powerSource {
        case .batteryPower:
            return .success(AppText.startedOnBatteryPower)
        case .acPower:
            return .success(AppText.startedOnPowerAdapter)
        case .unknown:
            return .success(AppText.startedServerMode)
        }
    }

    func restoreSleepSettings() async -> PowerCommandResult {
        do { try await powerGuard.restore() }
        catch {
            stopTimedDisplayAwake()
            stopCaffeinate()
            return .failure(error.localizedDescription)
        }
        stopTimedDisplayAwake()
        stopCaffeinate()

        return .success(AppText.restoredClosedLidSleep)
    }

    func requestSystemSleep() -> PowerCommandResult {
        let connection = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard connection != IO_OBJECT_NULL else {
            return .failure(AppText.systemSleepConnectionUnavailable)
        }
        defer {
            IOServiceClose(connection)
        }

        let result = IOPMSleepSystem(connection)
        guard result == kIOReturnSuccess else {
            let code = String(format: "0x%08X", UInt32(bitPattern: result))
            return .failure(AppText.systemSleepRequestFailed(code))
        }

        return .success(AppText.systemSleepRequested)
    }

    func dimBuiltInDisplayForClosedLid() async -> PowerCommandResult {
        do { try await powerGuard.dim(); return .success(AppText.builtInDisplayDimmed) }
        catch { return .failure(error.localizedDescription) }
    }

    func restoreBuiltInDisplayBrightness() async -> PowerCommandResult {
        do { try await powerGuard.restoreBrightness(); return .success(AppText.builtInDisplayBrightnessRestored) }
        catch { return .failure(error.localizedDescription) }
    }

    @discardableResult
    func setTimedDisplayAwakeEnabled(_ isEnabled: Bool) -> PowerCommandResult {
        if isEnabled {
            return startTimedDisplayAwake()
        }

        stopTimedDisplayAwake()
        return .success("OK")
    }

    private func ensurePowerPermission() async -> PowerCommandResult {
        do {
            for value in ["0", "1"] {
                let result = try await ShellRunner.run("/usr/bin/sudo",
                    arguments: ["-n", "-l", "/usr/bin/pmset", "disablesleep", value])
                if result.exitCode != 0 { return await installOneTimeAuthorization() }
            }
            return .success("OK")
        } catch { return .failure(error.localizedDescription) }
    }

    private func installOneTimeAuthorization() async -> PowerCommandResult {
        let command: String
        do {
            command = try Self.oneTimeAuthorizationInstallCommand()
        } catch {
            return .failure(error.localizedDescription)
        }

        let result = await runPrivileged(command)

        switch result {
        case .success:
            return .success("OK")
        case .userCancelled:
            return .userCancelled
        case .failure(let message):
            return .failure(message)
        }
    }

    private static func oneTimeAuthorizationInstallCommand() throws -> String {
        let userName = NSUserName()
        let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !userName.isEmpty,
              userName.rangeOfCharacter(from: validCharacters.inverted) == nil else {
            throw PowerManagerError.unsupportedUserName
        }

        let sudoersPath = "/private/etc/sudoers.d/\(AppIdentity.current.sudoersName)"
        let contents = """
        # turnintoserver one-time permission for Server Mode.
        \(userName) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1

        """

        return [
            "tmp=$(/usr/bin/mktemp /tmp/turnintoserver-sudoers.XXXXXX)",
            "trap '/bin/rm -f \"$tmp\"' EXIT",
            "/usr/bin/printf %s \(ShellRunner.shellQuoted(contents)) > \"$tmp\"",
            "/usr/sbin/visudo -cf \"$tmp\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$tmp\"",
            "/bin/chmod 440 \"$tmp\"",
            "/bin/mv \"$tmp\" \(ShellRunner.shellQuoted(sudoersPath))",
            "trap - EXIT"
        ].joined(separator: " && ")
    }

    @discardableResult
    private func startCaffeinate(powerSource: PowerSource) -> PowerCommandResult {
        if isServerModeActive {
            return .success(AppText.serverModeAlreadyRunning)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var arguments = ["-i", "-m"]
        if powerSource == .acPower {
            arguments.append("-s")
        }
        arguments += ["-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(AppText.caffeinateLaunchFailed(error.localizedDescription))
        }

        guard process.isRunning else {
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Self.shortFailureMessage(message ?? AppText.caffeinateExited))
        }

        caffeinateProcess = process
        return .success("OK")
    }

    private func stopCaffeinate() {
        guard let process = caffeinateProcess else {
            return
        }

        if process.isRunning {
            process.terminate()
        }

        caffeinateProcess = nil
    }

    private func startTimedDisplayAwake() -> PowerCommandResult {
        if timedDisplayAwakeProcess?.isRunning == true {
            startTimedUserActivityPulses()
            return .success("OK")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = [
            "-d",
            "-w",
            "\(ProcessInfo.processInfo.processIdentifier)"
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return .failure(AppText.caffeinateLaunchFailed(error.localizedDescription))
        }

        guard process.isRunning else {
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(Self.shortFailureMessage(message ?? AppText.caffeinateExited))
        }

        timedDisplayAwakeProcess = process
        startTimedUserActivityPulses()
        return .success("OK")
    }

    private func stopTimedDisplayAwake() {
        stopTimedUserActivityPulses()

        if timedDisplayAwakeProcess?.isRunning == true {
            timedDisplayAwakeProcess?.terminate()
        }

        timedDisplayAwakeProcess = nil
    }

    private func startTimedUserActivityPulses() {
        guard timedUserActivityTimer == nil else {
            return
        }

        sendTimedUserActivityPulse()

        let timer = Timer(timeInterval: 55, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendTimedUserActivityPulse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timedUserActivityTimer = timer
    }

    private func stopTimedUserActivityPulses() {
        timedUserActivityTimer?.invalidate()
        timedUserActivityTimer = nil

        if timedUserActivityProcess?.isRunning == true {
            timedUserActivityProcess?.terminate()
        }

        timedUserActivityProcess = nil
    }

    private func sendTimedUserActivityPulse() {
        if timedUserActivityProcess?.isRunning == true {
            timedUserActivityProcess?.terminate()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-u", "-t", "70"]

        do {
            try process.run()
            timedUserActivityProcess = process
        } catch {
            timedUserActivityProcess = nil
        }
    }

    private func runPrivileged(_ command: String) async -> PowerCommandResult {
        do {
            let result = try await ShellRunner.runAdministratorCommand(command)
            guard result.exitCode == 0 else {
                if ShellRunner.isUserCancelled(result) {
                    return .userCancelled
                }

                return .failure(Self.shortFailureMessage(from: result))
            }

            return .success("OK")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func shortFailureMessage(from result: ShellResult) -> String {
        shortFailureMessage(result.combinedOutput)
    }

    private static func shortFailureMessage(_ message: String) -> String {
        guard !message.isEmpty else {
            return AppText.commandFailed
        }

        let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
        guard firstLine.count > 36 else {
            return firstLine
        }

        return String(firstLine.prefix(33)) + "..."
    }
}
