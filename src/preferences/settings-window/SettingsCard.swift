import Cocoa

/// The building blocks of the Settings page: a titled section holding a rounded card of rows, each
/// row a label on the leading side and its control on the trailing side.
enum SettingsCard {
    static let cornerRadius = CGFloat(10)
    static let rowMinHeight = CGFloat(36)
    static let rowHorizontalPadding = CGFloat(14)
    static let rowVerticalPadding = CGFloat(6)
    static let titleSpacing = CGFloat(6)

    /// A small uppercase title above `rows`, which are stacked inside one card with hairlines between them.
    static func section(_ title: String, _ rows: [NSView]) -> NSView {
        let card = CardView(rows)
        let stack = NSStackView(views: [sectionTitle(title), card])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = titleSpacing
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    static func row(_ title: String, _ controls: [NSView]) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        controls.forEach { $0.setAccessibilityLabel(title) }
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: rowVerticalPadding, left: rowHorizontalPadding, bottom: rowVerticalPadding, right: rowHorizontalPadding)
        stack.setViews([label], in: .leading)
        stack.setViews(controls, in: .trailing)
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: rowMinHeight).isActive = true
        return stack
    }

    private static func sectionTitle(_ title: String) -> NSView {
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: title.localizedUppercase, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.4,
        ]))
        let inset = NSStackView(views: [label])
        inset.edgeInsets = NSEdgeInsets(top: 0, left: rowHorizontalPadding, bottom: 0, right: rowHorizontalPadding)
        return inset
    }
}

/// Rounded, softly filled background for a group of rows, separated by hairlines inset like
/// System Settings. The fill and border are resolved in `updateLayer`, so they follow light/dark.
private final class CardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    convenience init(_ rows: [NSView]) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer!.cornerRadius = SettingsCard.cornerRadius
        layer!.borderWidth = 0.5
        let stack = NSStackView(views: Self.interleaveSeparators(rows))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        stack.arrangedSubviews.forEach { pinWidth($0, stack) }
    }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isDark ? 0.05 : 0.7).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func pinWidth(_ view: NSView, _ stack: NSStackView) {
        let inset = view is Separator ? SettingsCard.rowHorizontalPadding : 0
        view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: inset).isActive = true
        view.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -inset).isActive = true
    }

    private static func interleaveSeparators(_ rows: [NSView]) -> [NSView] {
        rows.enumerated().flatMap { i, row in i == 0 ? [row] : [Separator(), row] }
    }
}

private final class Separator: NSBox {
    convenience init() {
        self.init(frame: .zero)
        boxType = .separator
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
}
