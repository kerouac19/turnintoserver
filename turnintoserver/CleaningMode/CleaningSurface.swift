import AppKit
import Combine

/// A full-display view consumes every click outside the explicit unlock control,
/// including when its background is transparent. It never forwards into other apps.
final class CleaningSurface: NSView {
    private weak var manager: CleaningModeManager?
    private var subscription: AnyCancellable?
    private let progress = NSTextField(labelWithString: "")

    init(manager: CleaningModeManager, keepScreenVisible: Bool) {
        self.manager = manager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = (keepScreenVisible ? NSColor.clear : NSColor.black).cgColor
        let title = NSTextField(labelWithString: AppIdentity.text("清洁模式", "Cleaning Mode"))
        title.font = .boldSystemFont(ofSize: keepScreenVisible ? 16 : 26)
        let hint = NSTextField(labelWithString: AppIdentity.text("连续按 5 次 Esc 或点击解锁", "Press Escape five times or click Unlock"))
        let button = UnlockButton(title: AppIdentity.text("解锁", "Unlock"), target: self, action: #selector(unlock))
        button.bezelStyle = .rounded
        let stack = NSStackView(views: [title, hint, progress, button])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.wantsLayer = true
        stack.layer?.backgroundColor = (keepScreenVisible ? NSColor.windowBackgroundColor : NSColor.black).cgColor
        stack.layer?.cornerRadius = 18
        for field in [title, hint, progress] { field.textColor = keepScreenVisible ? .labelColor : .white }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        if keepScreenVisible {
            NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor, constant: 50),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28)])
        } else {
            NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor)])
        }
        let threshold = manager.unlockThreshold
        subscription = manager.$unlockProgress.receive(on: RunLoop.main).sink { [weak self] value in
            self?.progress.stringValue = "Esc: \(value) / \(threshold)"
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    @objc private func unlock() { manager?.deactivate() }
    private final class UnlockButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
