import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and popover. Uses AppKit so both left- and
/// right-click on the icon open the panel (SwiftUI MenuBarExtra only handles
/// left-click).
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var poller: PRPoller?
    private var cancellables = Set<AnyCancellable>()
    let uiState = PopoverUIState()

    private override init() {
        super.init()
    }

    func setup(poller: PRPoller) {
        guard statusItem == nil else { return }
        self.poller = poller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 452, height: 620)

        let hosting = NSHostingController(
            rootView: MenuContentView(poller: poller, uiState: uiState)
        )
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        self.popover = popover

        updateButton()
        observePoller(poller)
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            closePopover()
            return
        }
        presentPopover(relativeTo: button.bounds, of: button)
    }

    /// Opens the menu-bar panel directly on the inline settings screen.
    func openSettingsInPopover() {
        uiState.showingSettings = true
        guard let button = statusItem?.button else { return }
        if popover?.isShown != true {
            presentPopover(relativeTo: button.bounds, of: button)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - NSPopoverDelegate

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        true
    }

    // MARK: - Private

    private func presentPopover(relativeTo rect: NSRect, of view: NSView) {
        guard let popover else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        NotificationManager.shared.prepareOnUserInteraction()
    }

    private func observePoller(_ poller: PRPoller) {
        poller.$pullRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)

        poller.$hasToken
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = statusItem?.button, let poller else { return }

        if let symbol = attentionSymbol(for: poller) {
            button.image = Self.templateSymbol(symbol)
        } else {
            button.image = Self.owlIcon
        }
        button.image?.isTemplate = true

        if poller.hasToken, !poller.pullRequests.isEmpty {
            button.title = " \(poller.pullRequests.count)"
        } else {
            button.title = ""
        }
        button.imagePosition = .imageLeading
    }

    private func attentionSymbol(for poller: PRPoller) -> String? {
        guard poller.hasToken else { return nil }
        let prs = poller.pullRequests
        if prs.contains(where: { $0.status.checks == .failure || $0.status.checks == .error }) {
            return "exclamationmark.triangle.fill"
        }
        if prs.contains(where: { $0.status.hasConflict }) {
            return "exclamationmark.triangle.fill"
        }
        return nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            presentPopover(relativeTo: button.bounds, of: button)
        }
    }

    private static var owlIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    private static func templateSymbol(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
