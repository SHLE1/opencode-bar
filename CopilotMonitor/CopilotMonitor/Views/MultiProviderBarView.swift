import AppKit

/// Status bar view for Multi-Provider Bar mode.
/// Renders multiple (providerIcon + remaining%) pairs horizontally with no main app icon.
final class MultiProviderBarView: NSView {
    struct Entry {
        let icon: NSImage
        let remainingPercent: Double
    }

    private var entries: [Entry] = []

    /// Called whenever intrinsic width changes so the status item can resize.
    var onIntrinsicContentSizeDidChange: (() -> Void)?

    private let font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private let iconSize: CGFloat = 12
    private let pairSpacing: CGFloat = 6
    private let iconTextGap: CGFloat = 2
    private let leftPadding: CGFloat = 4
    private let rightPadding: CGFloat = 4
    private let statusBarHeight: CGFloat = 23

    func update(entries: [Entry]) {
        self.entries = entries
        needsDisplay = true
        invalidateIntrinsicContentSize()
        onIntrinsicContentSizeDidChange?()
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: totalWidth(), height: statusBarHeight)
    }

    private func totalWidth() -> CGFloat {
        guard !entries.isEmpty else { return leftPadding + rightPadding }
        var w = leftPadding + rightPadding
        for (i, entry) in entries.enumerated() {
            w += iconSize + iconTextGap
            let text = textForRemaining(entry.remainingPercent)
            w += (text as NSString).size(withAttributes: [.font: font]).width
            if i < entries.count - 1 { w += pairSpacing }
        }
        return w
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let h = bounds.height
        var x = leftPadding

        for (i, entry) in entries.enumerated() {
            let remaining = entry.remainingPercent
            let color = colorForRemaining(remaining)

            // Icon
            let iconY = (h - iconSize) / 2
            let iconRect = NSRect(x: x, y: iconY, width: iconSize, height: iconSize)
            tinted(entry.icon, color: color).draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            x += iconSize + iconTextGap

            // Text
            let text = textForRemaining(remaining)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let textSize = (text as NSString).size(withAttributes: attrs)
            let textRect = NSRect(x: x, y: (h - textSize.height) / 2, width: textSize.width, height: textSize.height)
            (text as NSString).draw(in: textRect, withAttributes: attrs)
            x += textSize.width

            if i < entries.count - 1 { x += pairSpacing }
        }
    }

    // MARK: - Helpers

    private var textColor: NSColor {
        guard let button = self.superview as? NSStatusBarButton else { return .white }
        return button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    private func colorForRemaining(_ remaining: Double) -> NSColor {
        if remaining <= 10 { return .systemRed }
        if remaining <= 30 { return .systemOrange }
        return textColor
    }

    private func textForRemaining(_ remaining: Double) -> String {
        let clamped = max(0.0, min(999.0, remaining))
        if clamped > 0.0, clamped < 1.0 { return "1%" }
        return String(format: "%.0f%%", clamped)
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}
