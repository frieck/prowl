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

    /// Apply to content **inside** a `ScrollView` (not on the ScrollView itself).
    /// Hides the legacy track and keeps wheel/trackpad scrolling.
    @ViewBuilder
    func prowlScrollStyle() -> some View {
        self.background(ProwlScrollViewConfigurator())
    }

    /// Hide SwiftUI scroll indicators on a `ScrollView`.
    @ViewBuilder
    func prowlScrollIndicatorsHidden() -> some View {
        if #available(macOS 13.0, *) {
            self.scrollIndicators(.hidden)
        } else {
            self
        }
    }
}

/// Finds the enclosing NSScrollView from content placed inside a SwiftUI ScrollView.
private struct ProwlScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.onConfigure = configure
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.scheduleConfigure()
    }

    private func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
    }

    final class ConfiguratorView: NSView {
        var onConfigure: ((NSScrollView) -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleConfigure()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfigure()
        }

        func scheduleConfigure() {
            DispatchQueue.main.async { [weak self] in
                self?.configureEnclosingScrollView()
            }
        }

        private func configureEnclosingScrollView() {
            guard let onConfigure else { return }
            var current: NSView? = self
            while let view = current {
                if let scrollView = view as? NSScrollView {
                    onConfigure(scrollView)
                    return
                }
                current = view.superview
            }
        }
    }
}
