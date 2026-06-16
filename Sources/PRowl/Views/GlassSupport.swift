import SwiftUI
import AppKit

/// Loads bundled images once for reuse in the UI.
enum BundleImages {
    static let owlGlyph: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()
}

private let panelCornerRadius: CGFloat = 24

/// Makes the popover window fully transparent so Liquid Glass shows through.
struct TransparentWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configureWindow(for: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configureWindow(for: nsView) }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

/// Groups Liquid Glass controls so they blend together on macOS 26+.
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension View {
    /// Single outer Liquid Glass shell. Content stays inset so it never touches
    /// the glass rim (fixes the "leaking" look).
    @ViewBuilder
    func prowlGlassPanel() -> some View {
        if #available(macOS 26.0, *) {
            self
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.clear.interactive(), in: .rect(cornerRadius: panelCornerRadius))
                .padding(16)
        } else {
            self
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial.opacity(0.35),
                             in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                .padding(16)
        }
    }

    /// Subtle section separator — no second glass layer (nested glass looked opaque).
    @ViewBuilder
    func prowlSectionSeparator() -> some View {
        self
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.25)
            }
    }

    @ViewBuilder
    func prowlGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: .capsule)
        } else {
            self.background(.quaternary.opacity(0.35), in: Capsule())
        }
    }

    /// Optional hover chip — very light, not a full card.
    @ViewBuilder
    func prowlGlassRow(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.thinMaterial.opacity(0.25),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func prowlGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    func prowlGlassProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Legacy alias — prefer `ProwlScrollView` for scroll areas.
    @ViewBuilder
    func prowlScrollStyle() -> some View {
        self
    }
}

// MARK: - Scroll view (thin overlay scrollbars)

enum ProwlScrollConfigurator {
    static func apply(to scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none

        if let scroller = scrollView.verticalScroller {
            scroller.scrollerStyle = .overlay
            scroller.controlSize = .mini
            scroller.isHidden = false
            scroller.alphaValue = 1
        }
    }
}

private final class ProwlNSScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override var isFlipped: Bool { true }

    override func tile() {
        super.tile()
        ProwlScrollConfigurator.apply(to: self)
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// AppKit-backed scroll container with thin overlay scrollbars (avoids SwiftUI’s thick indicators on macOS 26+).
struct ProwlScrollView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ProwlScrollViewRepresentable(content: content)
    }
}

private struct ProwlScrollViewRepresentable<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ProwlNSScrollView {
        let scrollView = ProwlNSScrollView()
        ProwlScrollConfigurator.apply(to: scrollView)

        let hostingView = NSHostingView(rootView: content())
        scrollView.documentView = hostingView

        context.coordinator.hostingView = hostingView
        context.coordinator.scrollView = scrollView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateDocumentSize()
        }

        DispatchQueue.main.async {
            context.coordinator.updateDocumentSize()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: ProwlNSScrollView, context: Context) {
        context.coordinator.hostingView?.rootView = content()
        ProwlScrollConfigurator.apply(to: scrollView)
        context.coordinator.updateDocumentSize()
    }

    final class Coordinator {
        var hostingView: NSHostingView<Content>?
        weak var scrollView: NSScrollView?

        func updateDocumentSize() {
            guard let hostingView, let scrollView else { return }
            hostingView.layoutSubtreeIfNeeded()
            let width = max(scrollView.contentView.bounds.width, scrollView.bounds.width, 1)
            let height = max(hostingView.fittingSize.height, 1)
            let newFrame = NSRect(x: 0, y: 0, width: width, height: height)
            if hostingView.frame != newFrame {
                hostingView.frame = newFrame
            }
        }
    }
}
