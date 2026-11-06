import AppKit
import Carbon
import Foundation
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    init(appState: AppState, updateModel: PreferencesUpdateViewModel) {
        let hostingController = NSHostingController(
            rootView: AboutView(appState: appState, updateModel: updateModel)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.aboutApplication
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 500)
        window.contentMaxSize = NSSize(width: 520, height: 500)
        window.setContentSize(NSSize(width: 520, height: 500))
        Self.configureCenteredTitle(for: window)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func configureCenteredTitle(for window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else {
            return
        }

        let titleLabel = NSTextField(labelWithString: AppText.aboutApplication)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 90),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -90)
        ])
    }
}

@MainActor
final class LowBatterySettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: LowBatteryNotificationSettingsView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.iMessageSettingsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 230)
        window.contentMaxSize = NSSize(width: 520, height: 230)
        window.setContentSize(NSSize(width: 520, height: 230))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ShortcutSettingsWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(rootView: ShortcutSettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.shortcutHintsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 195)
        window.contentMaxSize = NSSize(width: 460, height: 195)
        window.setContentSize(NSSize(width: 460, height: 195))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class TimedServerModeSettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: TimedServerModeSettingsView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.timedServerModeSettingsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 360, height: 360)
        window.contentMaxSize = NSSize(width: 360, height: 360)
        window.setContentSize(NSSize(width: 360, height: 360))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AutomaticRouteSettingsWindowController: NSWindowController {
    init(appState: AppState) {
        let hostingController = NSHostingController(rootView: AutomaticRouteSettingsView(appState: appState))
        let window = NSWindow(contentViewController: hostingController)
        window.title = AppText.automaticRouteSettingsTitle
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 720)
        window.contentMaxSize = NSSize(width: 600, height: 720)
        window.setContentSize(NSSize(width: 600, height: 720))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct AboutView: View {
    @ObservedObject private var updateModel: PreferencesUpdateViewModel
    @State private var didCopyAgentMCPInstallPrompt = false

    @MainActor
    init(appState _: AppState, updateModel: PreferencesUpdateViewModel) {
        self.updateModel = updateModel
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 2)
            header
            agentMCPInstallSection
            updateSection
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 36, leading: 34, bottom: 28, trailing: 34))
        .frame(width: 520, height: 500)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 92, height: 92)
                .cornerRadius(22)
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)

            VStack(spacing: 4) {
                Text("turnintoserver")
                    .font(.system(size: 28, weight: .bold))
                Text(AppText.currentVersion(PreferencesUpdateViewModel.currentVersionDisplay))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 7) {
                Text(AppText.developer("qianyushi"))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(AppText.githubPrefix)
                    Button(AppText.githubURLDisplay) {
                        PreferencesUpdateViewModel.openGitHub()
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var agentMCPInstallSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 10) {
                Text(AppText.agentMCPInstallPromptTitle)
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                Button(didCopyAgentMCPInstallPrompt ? AppText.copied : AppText.copyAgentMCPInstallPrompt) {
                    copyAgentMCPInstallPrompt()
                }
            }

            Text(Self.agentMCPInstallPrompt)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(5)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func copyAgentMCPInstallPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.agentMCPInstallPrompt, forType: .string)
        didCopyAgentMCPInstallPrompt = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyAgentMCPInstallPrompt = false
        }
    }

    private static var agentMCPInstallPrompt: String {
        AppText.agentMCPInstallPrompt
    }

    private var updateSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 10) {
                Spacer()

                Button(AppText.checkForUpdates) {
                    updateModel.checkForUpdates()
                }
                .disabled(updateModel.isChecking || updateModel.isDownloading || updateModel.isInstalling)

                if updateModel.canRestartToInstall {
                    Button(AppText.restartToInstallUpdate) {
                        updateModel.restartAndInstall()
                    }
                    .disabled(updateModel.isInstalling)
                }

                Spacer()
            }

            if updateModel.isDownloading {
                LinearProgressIndicator(value: updateModel.downloadProgress)
                    .frame(width: 280)
                    .frame(height: 8)
            }

            Text(updateModel.statusText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct TimedServerModeSettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var settingsModel: TimedServerModeSettingsViewModel

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        settingsModel = TimedServerModeSettingsViewModel(appState: appState)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(appState.timedServerModeDurationOptions.enumerated()), id: \.element) { index, duration in
                        TimedServerModeDurationRow(
                            title: AppText.timedServerModeDuration(minutes: duration),
                            isSelected: settingsModel.selectedDurationMinutes == duration,
                            usesAlternateBackground: index.isMultiple(of: 2)
                        ) {
                            settingsModel.selectDuration(duration)
                        }
                    }
                }
                .padding(EdgeInsets(top: 16, leading: 10, bottom: 16, trailing: 10))
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Button(AppText.resetTimedServerModeDurations) {
                        settingsModel.resetDurations()
                    }

                    Spacer()

                    HStack(spacing: 0) {
                        Button("−") {
                            settingsModel.removeSelectedDuration()
                        }
                        .disabled(!settingsModel.canRemoveSelectedDuration)
                        .frame(width: 36)

                        Divider()
                            .frame(height: 18)

                        Button("+") {
                            settingsModel.addDuration()
                        }
                        .frame(width: 36)
                    }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: 360, height: 360, alignment: .topLeading)
    }
}

struct AutomaticRouteSettingsView: View {
    @ObservedObject private var appState: AppState
    @State private var routeServiceName: String
    @State private var routeDetectionSignature: String
    @State private var companionServiceName: String
    @State private var companionDetectionSignature: String
    @State private var networkServices: [AutomaticRouteNetworkService] = []
    @State private var isLoadingNetworkServices = true
    @State private var cidrText: String
    @State private var validationMessage = ""
    @State private var isSaving = false

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        let accessPoints = appState.automaticRoutingAccessPoints
        _routeServiceName = State(initialValue: accessPoints.route.serviceName)
        _routeDetectionSignature = State(initialValue: accessPoints.route.detectionSignature)
        _companionServiceName = State(initialValue: accessPoints.companion.serviceName)
        _companionDetectionSignature = State(initialValue: accessPoints.companion.detectionSignature)
        _cidrText = State(initialValue: appState.automaticRoutingCIDRs.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                accessPointEditor(
                    title: AppText.automaticRouteRouteAccessPointTitle,
                    selectedService: $routeServiceName,
                    signature: $routeDetectionSignature
                )
                accessPointEditor(
                    title: AppText.automaticRouteCompanionAccessPointTitle,
                    selectedService: $companionServiceName,
                    signature: $companionDetectionSignature
                )
            }

            if isLoadingNetworkServices {
                Text(AppText.automaticRouteLoadingServices)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider()

            Text(AppText.automaticRouteInternalCIDRsTitle)
                .font(.system(size: 13, weight: .semibold))

            CIDRTextEditor(text: $cidrText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .center, spacing: 12) {
                Text(AppText.automaticRouteCIDRCount(displayedCIDRCount))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Spacer()

                Button(AppText.automaticRouteResetBuiltIns) {
                    let examples = AutomaticRouteAccessPointConfiguration.examples
                    routeServiceName = examples.route.serviceName
                    routeDetectionSignature = examples.route.detectionSignature
                    companionServiceName = examples.companion.serviceName
                    companionDetectionSignature = examples.companion.detectionSignature
                    cidrText = AutomaticRoutePlan.exampleCIDRStrings.joined(separator: "\n")
                    validationMessage = ""
                }
                .disabled(isSaving)
            }

            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()

                Button(AppText.cancel) {
                    NSApp.keyWindow?.close()
                }
                .disabled(isSaving)

                Button(isSaving ? AppText.automaticRouteSaving : AppText.automaticRouteSave) {
                    save()
                }
                .disabled(isSaving || appState.isAutomaticRoutingChanging)
            }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 600, height: 720, alignment: .topLeading)
        .onAppear {
            loadNetworkServices()
        }
        .onReceive(appState.$automaticRoutingCIDRs.dropFirst()) { values in
            guard !isSaving else {
                return
            }
            cidrText = values.joined(separator: "\n")
        }
        .onReceive(appState.$automaticRoutingAccessPoints.dropFirst()) { accessPoints in
            guard !isSaving else {
                return
            }
            routeServiceName = accessPoints.route.serviceName
            routeDetectionSignature = accessPoints.route.detectionSignature
            companionServiceName = accessPoints.companion.serviceName
            companionDetectionSignature = accessPoints.companion.detectionSignature
        }
    }

    private func accessPointEditor(
        title: String,
        selectedService: Binding<String>,
        signature: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))

            Text(AppText.automaticRouteNetworkService)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Picker("", selection: selectedService) {
                ForEach(serviceOptions, id: \.name) { service in
                    Text("\(service.name) (\(service.device))")
                        .tag(service.name)
                }
            }
            .labelsHidden()
            .pickerStyle(PopUpButtonPickerStyle())

            Text(AppText.automaticRouteDetectionSignature)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            TextField(AppText.automaticRouteDetectionSignaturePlaceholder, text: signature)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serviceOptions: [AutomaticRouteNetworkService] {
        var result = networkServices
        let selectedNames = [routeServiceName, companionServiceName]
        for name in selectedNames where !name.isEmpty && !result.contains(where: { $0.name == name }) {
            result.append(AutomaticRouteNetworkService(name: name, device: "?"))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var displayedCIDRCount: Int {
        if let validated = try? AutomaticRoutePlan.validatedCIDRs(text: cidrText) {
            return validated.count
        }
        return cidrText.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    private func save() {
        validationMessage = ""
        isSaving = true

        Task { @MainActor in
            do {
                let accessPoints = try AutomaticRouteAccessPointConfiguration.validated(
                    routeServiceName: routeServiceName,
                    routeDetectionSignature: routeDetectionSignature,
                    companionServiceName: companionServiceName,
                    companionDetectionSignature: companionDetectionSignature
                )
                let values = try await appState.setAutomaticRoutingSettings(
                    cidrText.components(separatedBy: .newlines),
                    accessPoints: accessPoints
                )
                cidrText = values.joined(separator: "\n")
                isSaving = false
                NSApp.keyWindow?.close()
            } catch {
                validationMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    private func loadNetworkServices() {
        isLoadingNetworkServices = true
        Task { @MainActor in
            networkServices = await appState.availableAutomaticRouteNetworkServices()
            isLoadingNetworkServices = false
        }
    }
}

private struct CIDRTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else {
            return
        }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }
    }
}

private struct TimedServerModeDurationRow: View {
    let title: String
    let isSelected: Bool
    var usesAlternateBackground = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 30)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }

        if usesAlternateBackground {
            return Color.secondary.opacity(0.08)
        }

        return Color.clear
    }
}

struct LowBatteryNotificationSettingsView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject private var notificationModel: NotificationSettingsViewModel

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        notificationModel = NotificationSettingsViewModel()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            notificationChannelRow(
                title: AppText.iMessageChannelTitle,
                infoTitle: AppText.iMessageInfoTitle,
                infoMessage: AppText.iMessageInfoMessage,
                placeholder: AppText.iMessageRecipientPlaceholder,
                text: $notificationModel.iMessageRecipientAddress,
                isTesting: notificationModel.isSendingIMessageTest,
                statusText: notificationModel.iMessageStatusText
            ) {
                notificationModel.sendIMessageTest()
            }

            Divider()

            notificationChannelRow(
                title: AppText.barkChannelTitle,
                infoTitle: AppText.barkInfoTitle,
                infoMessage: AppText.barkInfoMessage,
                placeholder: AppText.barkPushEndpointPlaceholder,
                text: $notificationModel.barkPushEndpoint,
                isTesting: notificationModel.isSendingBarkTest,
                statusText: notificationModel.barkStatusText
            ) {
                notificationModel.sendBarkTest()
            }
        }
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 20, trailing: 24))
        .frame(width: 520, height: 230, alignment: .topLeading)
        .onReceive(notificationModel.$canEnableLowBatteryNotifications) { canEnable in
            if !canEnable, appState.lowBatteryNotificationsEnabled {
                appState.setLowBatteryNotificationsEnabled(false)
            }
        }
    }

    private func notificationChannelRow(
        title: String,
        infoTitle: String,
        infoMessage: String,
        placeholder: String,
        text: Binding<String>,
        isTesting: Bool,
        statusText: String,
        onTest: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                InfoCircleButton {
                    showInfo(title: infoTitle, message: infoMessage)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: text)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(AppText.testNotificationChannel) {
                    onTest()
                }
                .disabled(isTesting)
            }

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.ok)
        alert.runModal()
    }
}

private struct InfoCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.75), lineWidth: 1)
                Text("i")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 15, height: 15)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject private var shortcutModel: ShortcutSettingsViewModel

    @MainActor
    init() {
        shortcutModel = ShortcutSettingsViewModel()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppText.shortcutHintsTitle)
                .font(.system(size: 13, weight: .semibold))

            ShortcutRow(
                title: AppText.serverModeShortcutLabel,
                shortcut: shortcutModel.serverModeShortcut,
                isRecording: shortcutModel.recordingTarget == .serverMode
            ) {
                shortcutModel.record(.serverMode)
            }

            ShortcutRow(
                title: AppText.batteryModeShortcutLabel,
                shortcut: shortcutModel.batteryModeShortcut,
                isRecording: shortcutModel.recordingTarget == .batteryMode
            ) {
                shortcutModel.record(.batteryMode)
            }

            ShortcutRow(
                title: AppText.sleepShortcutLabel,
                shortcut: shortcutModel.sleepShortcut,
                isRecording: shortcutModel.recordingTarget == .sleep
            ) {
                shortcutModel.record(.sleep)
            }

            HStack(spacing: 10) {
                Button(AppText.resetShortcuts) {
                    shortcutModel.resetShortcuts()
                }

                Spacer()
            }
        }
        .padding(16)
        .frame(width: 460, height: 195, alignment: .topLeading)
    }
}

private struct ShortcutRow: View {
    let title: String
    let shortcut: HotKeyShortcut?
    let isRecording: Bool
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 150, alignment: .leading)

            Text(isRecording ? AppText.recordingShortcut : shortcutDisplayText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(shortcut == nil && !isRecording ? .secondary : .primary)
                .frame(width: 120, alignment: .leading)

            Button(AppText.recordShortcut) {
                onRecord()
            }
            .disabled(isRecording)

            Spacer()
        }
    }

    private var shortcutDisplayText: String {
        shortcut?.displayString ?? AppText.shortcutNotSet
    }
}

private struct LinearProgressIndicator: NSViewRepresentable {
    let value: Double

    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.isIndeterminate = false
        indicator.style = .bar
        indicator.minValue = 0
        indicator.maxValue = 1
        indicator.doubleValue = 0
        indicator.controlSize = .small
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {
        nsView.doubleValue = max(0, min(1, value))
    }
}

@MainActor
private final class TimedServerModeSettingsViewModel: ObservableObject {
    @Published var selectedDurationMinutes: Int?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        selectedDurationMinutes = nil
    }

    var canRemoveSelectedDuration: Bool {
        guard let selectedDurationMinutes else {
            return false
        }

        return appState.timedServerModeDurationOptions.contains(selectedDurationMinutes)
            && appState.timedServerModeDurationOptions.count > 1
    }

    func selectDuration(_ durationMinutes: Int?) {
        selectedDurationMinutes = durationMinutes
    }

    func removeSelectedDuration() {
        guard let selectedDurationMinutes else {
            return
        }

        appState.removeTimedServerModeDuration(minutes: selectedDurationMinutes)

        if appState.timedServerModeDurationOptions.contains(selectedDurationMinutes) {
            self.selectedDurationMinutes = selectedDurationMinutes
        } else {
            self.selectedDurationMinutes = nil
        }
    }

    func resetDurations() {
        appState.resetTimedServerModeDurations()
        selectedDurationMinutes = nil
    }

    func addDuration() {
        guard let durationMinutes = Self.requestDurationMinutes(),
              let addedDuration = appState.addTimedServerModeDuration(minutes: durationMinutes) else {
            return
        }

        selectedDurationMinutes = addedDuration
    }

    private static func requestDurationMinutes() -> Int? {
        while true {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = AppText.addTimedServerModeDurationTitle
            alert.informativeText = AppText.addTimedServerModeDurationMessage
            alert.addButton(withTitle: AppText.addTimedServerModeDurationConfirm)
            alert.addButton(withTitle: AppText.cancel)

            let hoursField = makeDurationInputField()
            hoursField.placeholderString = "0"

            let minutesField = makeDurationInputField()
            minutesField.placeholderString = "0"

            let hoursLabel = NSTextField(labelWithString: AppText.timedServerModeHoursUnit)
            let minutesLabel = NSTextField(labelWithString: AppText.timedServerModeMinutesUnit)

            let stackView = NSStackView(views: [
                hoursField,
                hoursLabel,
                minutesField,
                minutesLabel
            ])
            stackView.orientation = .horizontal
            stackView.alignment = .centerY
            stackView.spacing = 8
            stackView.translatesAutoresizingMaskIntoConstraints = false

            let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
            accessoryView.addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
                stackView.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor)
            ])
            alert.accessoryView = accessoryView
            alert.window.initialFirstResponder = hoursField

            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }

            if let durationMinutes = parsedDurationMinutes(
                hours: hoursField.stringValue,
                minutes: minutesField.stringValue
            ) {
                return durationMinutes
            }

            let invalidAlert = NSAlert()
            invalidAlert.alertStyle = .warning
            invalidAlert.messageText = AppText.invalidTimedServerModeDurationComponents
            invalidAlert.addButton(withTitle: AppText.ok)
            invalidAlert.runModal()
        }
    }

    private static func makeDurationInputField() -> NSTextField {
        let field = NSTextField(frame: .zero)
        field.alignment = .right
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.isBezeled = true
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: 76),
            field.heightAnchor.constraint(equalToConstant: 28)
        ])
        return field
    }

    private static func parsedDurationMinutes(hours: String, minutes: String) -> Int? {
        let trimmedHours = hours.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMinutes = minutes.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let hourValue = trimmedHours.isEmpty ? 0 : Int(trimmedHours),
              let minuteValue = trimmedMinutes.isEmpty ? 0 : Int(trimmedMinutes),
              hourValue >= 0,
              minuteValue >= 0,
              minuteValue < 60 else {
            return nil
        }

        let totalMinutes = hourValue * 60 + minuteValue
        return AppState.normalizedTimedServerModeDuration(totalMinutes)
    }
}

@MainActor
private final class NotificationSettingsViewModel: ObservableObject {
    @Published var iMessageRecipientAddress: String {
        didSet {
            let trimmedValue = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(iMessageRecipientAddress, forKey: AppDefaultsKey.iMessageRecipientAddress)
            if trimmedValue != verifiedIMessageRecipientAddress {
                iMessageStatusText = trimmedValue.isEmpty ? "" : AppText.iMessageNeedsRetest
            }
            refreshReadiness()
        }
    }
    @Published var barkPushEndpoint: String {
        didSet {
            let trimmedValue = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(barkPushEndpoint, forKey: AppDefaultsKey.barkPushEndpoint)
            if trimmedValue != verifiedBarkPushEndpoint {
                barkStatusText = trimmedValue.isEmpty ? "" : AppText.barkNeedsRetest
            }
            refreshReadiness()
        }
    }
    @Published var isSendingIMessageTest = false
    @Published var isSendingBarkTest = false
    @Published var iMessageStatusText = ""
    @Published var barkStatusText = ""
    @Published private(set) var canEnableLowBatteryNotifications = false

    private let defaults: UserDefaults
    private var verifiedIMessageRecipientAddress = ""
    private var verifiedBarkPushEndpoint = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        iMessageRecipientAddress = defaults.string(forKey: AppDefaultsKey.iMessageRecipientAddress) ?? ""
        barkPushEndpoint = defaults.string(forKey: AppDefaultsKey.barkPushEndpoint) ?? ""
        verifiedIMessageRecipientAddress = defaults.string(forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        verifiedBarkPushEndpoint = defaults.string(forKey: AppDefaultsKey.verifiedBarkPushEndpoint)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        refreshReadiness()
        refreshStatusTexts()
    }

    func sendIMessageTest() {
        Task {
            await sendIMessageTestAsync()
        }
    }

    func sendBarkTest() {
        Task {
            await sendBarkTestAsync()
        }
    }

    private func sendIMessageTestAsync() async {
        guard !isSendingIMessageTest else {
            return
        }

        let recipient = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty else {
            iMessageStatusText = AppText.iMessageRecipientMissing
            return
        }

        isSendingIMessageTest = true
        iMessageStatusText = AppText.iMessageTestSending

        defer {
            isSendingIMessageTest = false
        }

        do {
            try await IMessageNotifier.send(
                message: AppText.iMessageTestMessage(macName: IMessageNotifier.defaultMacName),
                to: recipient
            )
            verifiedIMessageRecipientAddress = recipient
            defaults.set(recipient, forKey: AppDefaultsKey.verifiedIMessageRecipientAddress)
            refreshReadiness()
            iMessageStatusText = AppText.iMessageTestSent
        } catch {
            iMessageStatusText = AppText.iMessageTestFailed(error.localizedDescription)
        }
    }

    private func sendBarkTestAsync() async {
        guard !isSendingBarkTest else {
            return
        }

        let endpoint = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            barkStatusText = AppText.barkEndpointMissing
            return
        }

        isSendingBarkTest = true
        barkStatusText = AppText.barkTestSending

        defer {
            isSendingBarkTest = false
        }

        do {
            try await BarkNotifier.send(
                title: "turnintoserver",
                body: AppText.barkTestBody(macName: IMessageNotifier.defaultMacName),
                endpoint: endpoint
            )
            verifiedBarkPushEndpoint = endpoint
            defaults.set(endpoint, forKey: AppDefaultsKey.verifiedBarkPushEndpoint)
            refreshReadiness()
            barkStatusText = AppText.barkTestSent
        } catch {
            barkStatusText = AppText.barkTestFailed(error.localizedDescription)
        }
    }

    private func refreshReadiness() {
        canEnableLowBatteryNotifications = AppState.canEnableLowBatteryNotifications(defaults: defaults)
    }

    private func refreshStatusTexts() {
        let recipient = iMessageRecipientAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !recipient.isEmpty, recipient != verifiedIMessageRecipientAddress {
            iMessageStatusText = AppText.iMessageNeedsRetest
        }

        let endpoint = barkPushEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty, endpoint != verifiedBarkPushEndpoint {
            barkStatusText = AppText.barkNeedsRetest
        }
    }
}

@MainActor
private final class ShortcutSettingsViewModel: ObservableObject {
    enum Target {
        case serverMode
        case batteryMode
        case sleep
    }

    @Published var serverModeShortcut: HotKeyShortcut?
    @Published var batteryModeShortcut: HotKeyShortcut?
    @Published var sleepShortcut: HotKeyShortcut?
    @Published var recordingTarget: Target?
    @Published var statusText = AppText.shortcutRecordHint

    private var keyEventMonitor: Any?
    private var localMouseEventMonitor: Any?
    private var globalMouseEventMonitor: Any?

    init() {
        serverModeShortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.serverModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled,
            default: .defaultServerMode
        )
        batteryModeShortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.batteryModeHotKey,
            disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled,
            default: .defaultBatteryMode
        )
        sleepShortcut = HotKeyShortcut.loadOptional(
            defaultsKey: AppDefaultsKey.sleepHotKey,
            disabledDefaultsKey: AppDefaultsKey.sleepHotKeyDisabled,
            default: .defaultSleep
        )
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
        }
        NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidEnd, object: nil)
    }

    func record(_ target: Target) {
        stopRecording()
        recordingTarget = target
        statusText = AppText.recordingShortcut
        NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidStart, object: nil)
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.clearRecordingShortcut()
            return event
        }
        globalMouseEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearRecordingShortcut()
            }
        }
    }

    func resetShortcuts() {
        stopRecording()
        HotKeyShortcut.reset()
        serverModeShortcut = .defaultServerMode
        batteryModeShortcut = .defaultBatteryMode
        sleepShortcut = .defaultSleep
        statusText = AppText.shortcutRecordHint
    }

    private func clearShortcut(_ target: Target) {
        stopRecording()

        switch target {
        case .serverMode:
            HotKeyShortcut.clear(
                defaultsKey: AppDefaultsKey.serverModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled
            )
            serverModeShortcut = nil
        case .batteryMode:
            HotKeyShortcut.clear(
                defaultsKey: AppDefaultsKey.batteryModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled
            )
            batteryModeShortcut = nil
        case .sleep:
            HotKeyShortcut.clear(
                defaultsKey: AppDefaultsKey.sleepHotKey,
                disabledDefaultsKey: AppDefaultsKey.sleepHotKeyDisabled
            )
            sleepShortcut = nil
        }

        statusText = AppText.shortcutRecordHint
    }

    private func clearRecordingShortcut() {
        guard let recordingTarget else {
            return
        }

        clearShortcut(recordingTarget)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else {
            stopRecording()
            statusText = AppText.shortcutRecordHint
            return
        }

        guard let shortcut = HotKeyShortcut(event: event) else {
            statusText = AppText.shortcutRecordHint
            return
        }

        switch recordingTarget {
        case .serverMode:
            shortcut.save(
                defaultsKey: AppDefaultsKey.serverModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.serverModeHotKeyDisabled
            )
            serverModeShortcut = shortcut
        case .batteryMode:
            shortcut.save(
                defaultsKey: AppDefaultsKey.batteryModeHotKey,
                disabledDefaultsKey: AppDefaultsKey.batteryModeHotKeyDisabled
            )
            batteryModeShortcut = shortcut
        case .sleep:
            shortcut.save(
                defaultsKey: AppDefaultsKey.sleepHotKey,
                disabledDefaultsKey: AppDefaultsKey.sleepHotKeyDisabled
            )
            sleepShortcut = shortcut
        case .none:
            break
        }

        stopRecording()
        statusText = AppText.shortcutRecordHint
    }

    private func stopRecording() {
        removeEventMonitors()

        if recordingTarget != nil {
            recordingTarget = nil
            NotificationCenter.default.post(name: .turnIntoServerHotKeyRecordingDidEnd, object: nil)
        }
    }

    private func removeEventMonitors() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
            self.localMouseEventMonitor = nil
        }
        if let globalMouseEventMonitor {
            NSEvent.removeMonitor(globalMouseEventMonitor)
            self.globalMouseEventMonitor = nil
        }
    }
}

@MainActor
final class PreferencesUpdateViewModel: ObservableObject {
    struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [GitHubAsset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    static let githubURL = URL(string: "https://github.com/QianYushi/turnintoserver")!
    private static let defaultReleaseEndpoint = URL(
        string: "https://api.github.com/repos/QianYushi/turnintoserver/releases/latest"
    )!
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    static var currentVersionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? AppText.unknownVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, !build.isEmpty else {
            return version
        }

        return "\(version) (\(build))"
    }

    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var isInstalling = false
    @Published var downloadProgress: Double = 0
    @Published var statusText = AppText.updateIdle
    @Published var canRestartToInstall = false

    private var preparedDMGURL: URL?
    private var preparedVersion: String?
    private var progressObservation: NSKeyValueObservation?
    private var automaticCheckTimer: Timer?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if AppIdentity.current.updatesEnabled { restorePreparedUpdateIfPossible() }
    }

    deinit {
        automaticCheckTimer?.invalidate()
    }

    static func openGitHub() {
        NSWorkspace.shared.open(githubURL)
    }

    func checkForUpdates() {
        guard AppIdentity.current.updatesEnabled else {
            statusText = AppIdentity.text("开发版使用本地构建更新", "Use local builds to update the development app")
            return
        }
        Task {
            await checkForUpdatesAsync(isAutomatic: false)
        }
    }

    func startDailyAutomaticChecks() {
        guard AppIdentity.current.updatesEnabled else {
            statusText = AppIdentity.text("开发版使用本地构建更新", "Use local builds to update the development app")
            return
        }
        scheduleNextAutomaticCheck()
    }

    func restartAndInstall() {
        guard AppIdentity.current.updatesEnabled else {
            statusText = AppIdentity.text("开发版使用本地构建更新", "Use local builds to update the development app")
            return
        }
        guard !isInstalling else {
            return
        }

        Task {
            await restartAndInstallAsync()
        }
    }

    private func checkForUpdatesAsync(isAutomatic: Bool) async {
        guard !isChecking, !isDownloading else {
            return
        }

        if canRestartToInstall, preparedDMGURL != nil {
            statusText = AppText.updateReadyToRestart
            if isAutomatic {
                scheduleNextAutomaticCheck()
            }
            return
        }

        isChecking = true
        downloadProgress = 0
        statusText = AppText.checkingForUpdates
        if isAutomatic {
            defaults.set(Date(), forKey: AppDefaultsKey.lastAutomaticUpdateCheckDate)
        }

        defer {
            isChecking = false
            if isAutomatic {
                scheduleNextAutomaticCheck()
            }
        }

        do {
            var request = URLRequest(url: Self.releaseEndpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("turnintoserver", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await Self.fetchData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                statusText = AppText.updateCheckFailed(AppText.updateServerUnavailable)
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

            guard Self.isVersion(release.tagName, newerThan: currentVersion) else {
                statusText = AppText.alreadyUpToDate
                clearPreparedUpdate(removeFile: true)
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                statusText = AppText.noDMGFound(release.tagName)
                return
            }

            statusText = AppText.updateAvailable(release.tagName)
            do {
                try await downloadUpdate(from: dmgAsset.browserDownloadURL, tagName: release.tagName)
            } catch {
                statusText = AppText.downloadFailed(error.localizedDescription)
            }
        } catch {
            statusText = AppText.updateCheckFailed(error.localizedDescription)
        }
    }

    private func downloadUpdate(from url: URL, tagName: String) async throws {
        isDownloading = true
        downloadProgress = 0
        statusText = AppText.downloadingLatestDMG

        defer {
            isDownloading = false
            progressObservation = nil
        }

        let (data, response) = try await fetchDataWithProgress(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let destination = try Self.temporaryDMGDestination(tagName: tagName)
        try data.write(to: destination, options: .atomic)
        do {
            try await Task.detached(priority: .utility) {
                try Self.validateDownloadedDMG(at: destination, expectedVersion: tagName)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        preparedDMGURL = destination
        preparedVersion = tagName
        persistPreparedUpdate()
        downloadProgress = 1
        canRestartToInstall = true
        statusText = AppText.updateReadyToRestart
    }

    private func restartAndInstallAsync() async {
        guard let preparedDMGURL else {
            return
        }

        isInstalling = true
        canRestartToInstall = false
        statusText = AppText.restartingToInstallUpdate

        do {
            let expectedVersion = preparedVersion ?? ""
            try await Task.detached(priority: .utility) {
                try Self.validateDownloadedDMG(at: preparedDMGURL, expectedVersion: expectedVersion)
            }.value
            let targetAppURL = Self.preferredInstallTarget(for: Bundle.main.bundleURL)
            try Self.launchInstaller(dmgURL: preparedDMGURL, targetAppURL: targetAppURL)
            NotificationCenter.default.post(name: .turnIntoServerUpdateInstallShouldTerminate, object: nil)
        } catch {
            isInstalling = false
            canRestartToInstall = true
            statusText = AppText.updateInstallFailed(error.localizedDescription)
        }
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: (data, response))
            }
            .resume()
        }
    }

    private func fetchDataWithProgress(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                Task { @MainActor [weak self] in
                    self?.progressObservation = nil
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }

                continuation.resume(returning: (data, response))
            }

            progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    let fraction = progress.fractionCompleted
                    self?.downloadProgress = fraction.isFinite ? max(0, min(1, fraction)) : 0
                    self?.statusText = AppText.downloadingUpdateProgress(
                        Int((self?.downloadProgress ?? 0) * 100)
                    )
                }
            }

            task.resume()
        }
    }

    private static func temporaryDMGDestination(tagName: String) throws -> URL {
        let directory = try updateStorageDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("turnintoserver-\(tagName)-\(UUID().uuidString).dmg")
    }

    private static func updateStorageDirectory() throws -> URL {
        AppIdentity.supportDirectory.appendingPathComponent("Updates", isDirectory: true)
    }

    private static func preferredInstallTarget(for currentAppURL: URL) -> URL {
        let standardizedURL = currentAppURL.standardizedFileURL
        let path = standardizedURL.path

        if path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") {
            return URL(fileURLWithPath: "/Applications", isDirectory: true)
                .appendingPathComponent(currentAppURL.lastPathComponent, isDirectory: true)
        }

        return standardizedURL
    }

    private static func launchInstaller(dmgURL: URL, targetAppURL: URL) throws {
        guard let bundledScriptURL = Bundle.main.url(forResource: "update_installer", withExtension: "sh") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnintoserver-install-\(UUID().uuidString).sh")
        try FileManager.default.copyItem(at: bundledScriptURL, to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            dmgURL.path,
            targetAppURL.path
        ]
        try process.run()
    }

    private static var releaseEndpoint: URL {
        if let override = ProcessInfo.processInfo.environment["TURNINTOSERVER_UPDATE_FEED_URL"],
           let url = URL(string: override) {
            return url
        }
        return defaultReleaseEndpoint
    }

    private func scheduleNextAutomaticCheck() {
        automaticCheckTimer?.invalidate()
        guard !canRestartToInstall else {
            automaticCheckTimer = nil
            return
        }

        let lastCheck = defaults.object(forKey: AppDefaultsKey.lastAutomaticUpdateCheckDate) as? Date
        let dueDate = lastCheck?.addingTimeInterval(Self.automaticCheckInterval)
            ?? Date().addingTimeInterval(10)
        let interval = max(1, dueDate.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForUpdatesAsync(isAutomatic: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticCheckTimer = timer
    }

    private func restorePreparedUpdateIfPossible() {
        guard let path = defaults.string(forKey: AppDefaultsKey.preparedUpdateDMGPath),
              let version = defaults.string(forKey: AppDefaultsKey.preparedUpdateVersion),
              FileManager.default.fileExists(atPath: path),
              Self.isVersion(version, newerThan: Self.currentVersion) else {
            clearPreparedUpdate(removeFile: true)
            return
        }

        preparedDMGURL = URL(fileURLWithPath: path)
        preparedVersion = version
        canRestartToInstall = true
        downloadProgress = 1
        statusText = AppText.updateReadyToRestart
    }

    private func persistPreparedUpdate() {
        defaults.set(preparedDMGURL?.path, forKey: AppDefaultsKey.preparedUpdateDMGPath)
        defaults.set(preparedVersion, forKey: AppDefaultsKey.preparedUpdateVersion)
    }

    private func clearPreparedUpdate(removeFile: Bool) {
        let persistedPath = defaults.string(forKey: AppDefaultsKey.preparedUpdateDMGPath)
        if removeFile, let path = preparedDMGURL?.path ?? persistedPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        preparedDMGURL = nil
        preparedVersion = nil
        canRestartToInstall = false
        defaults.removeObject(forKey: AppDefaultsKey.preparedUpdateDMGPath)
        defaults.removeObject(forKey: AppDefaultsKey.preparedUpdateVersion)
    }

    private nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private nonisolated static func validateDownloadedDMG(at dmgURL: URL, expectedVersion: String) throws {
        try runAndRequireSuccess("/usr/bin/hdiutil", ["verify", dmgURL.path, "-quiet"])

        let mountURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("turnintoserver-verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountURL, withIntermediateDirectories: true)
        defer {
            _ = try? runProcess("/usr/bin/hdiutil", ["detach", mountURL.path, "-quiet"])
            try? FileManager.default.removeItem(at: mountURL)
        }

        try runAndRequireSuccess(
            "/usr/bin/hdiutil",
            ["attach", dmgURL.path, "-mountpoint", mountURL.path, "-nobrowse", "-readonly", "-quiet"]
        )

        let appURL = try FileManager.default.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).first { $0.pathExtension.lowercased() == "app" }
        guard let appURL else {
            throw UpdateValidationError.missingApp
        }

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL),
              info["CFBundleIdentifier"] as? String == "com.qianyushi.turnintoserver",
              let bundledVersion = info["CFBundleShortVersionString"] as? String,
              versionComponents(bundledVersion) == versionComponents(expectedVersion) else {
            throw UpdateValidationError.invalidIdentity
        }

        try runAndRequireSuccess(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path]
        )
    }

    private nonisolated static func runAndRequireSuccess(_ executable: String, _ arguments: [String]) throws {
        let result = try runProcess(executable, arguments)
        guard result.status == 0 else {
            throw UpdateValidationError.commandFailed(result.message)
        }
    }

    private nonisolated static func runProcess(
        _ executable: String,
        _ arguments: [String]
    ) throws -> (status: Int32, message: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private enum UpdateValidationError: LocalizedError {
        case missingApp
        case invalidIdentity
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingApp:
                return AppText.updateDMGMissingApp
            case .invalidIdentity:
                return AppText.updateDMGIdentityInvalid
            case .commandFailed(let message):
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? AppText.updateDMGValidationFailed : trimmed
            }
        }
    }

    private nonisolated static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        return false
    }

    private nonisolated static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }
}
