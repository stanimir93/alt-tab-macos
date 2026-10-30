import Cocoa

/// The rabbit mascot, with a speech bubble holding a title and a message. Heads the Feedback window.
final class MascotMessageView: NSStackView {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")

    init(title: String, message: String, emphasizeMessage: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heading.font = .systemFont(ofSize: emphasizeMessage ? 13 : 18, weight: emphasizeMessage ? .regular : .semibold)
        heading.textColor = emphasizeMessage ? .secondaryLabelColor : .labelColor
        detail.font = .systemFont(ofSize: emphasizeMessage ? 20 : 13, weight: emphasizeMessage ? .bold : .regular)
        detail.textColor = emphasizeMessage ? .labelColor : .secondaryLabelColor
        heading.isSelectable = false
        detail.isSelectable = false
        update(title: title, message: message)
        let bubble = NSStackView(views: [heading, detail])
        bubble.orientation = .vertical
        bubble.alignment = .leading
        bubble.spacing = SpeechBubbleView.lineSpacing
        let balloon = SpeechBubbleView()
        balloon.pointsRight = userInterfaceLayoutDirection == .rightToLeft
        balloon.translatesAutoresizingMaskIntoConstraints = false
        balloon.addContent(bubble)
        addArrangedSubview(MascotView())
        addArrangedSubview(balloon)
        spacing = 10
    }

    func update(title: String, message: String) {
        heading.stringValue = title
        detail.stringValue = message
        detail.setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

/// `mascot-rabbit` is bundled without outer transparent margins at 152 × 140 pixels, so it covers its
/// 76-point slot at Retina resolution.
private final class MascotView: NSImageView {
    private static let artwork = NSImage(named: "mascot-rabbit")
    private static let size = CGFloat(76)

    init() {
        super.init(frame: .zero)
        image = Self.artwork
        imageScaling = .scaleProportionallyUpOrDown
        setAccessibilityElement(false)
        wantsLayer = true
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        self.shadow = shadow
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}

/// A rounded bubble with a tail on the mascot's side, drawn as one closed silhouette so no edge crosses
/// the mouth of the tail. RTL mirrors it (`pointsRight`).
private final class SpeechBubbleView: NSView {
    static let lineSpacing = CGFloat(4)
    private static let cornerRadius = CGFloat(24)
    private static let contentPadding = CGFloat(18)
    private static let tailWidth = CGFloat(10)
    private static let outlineInset = CGFloat(1)
    var pointsRight = false { didSet { needsDisplay = true } }

    func addContent(_ view: NSView) {
        let inset = Self.outlineInset + Self.contentPadding
        let left = inset + (pointsRight ? 0 : Self.tailWidth)
        let right = inset + (pointsRight ? Self.tailWidth : 0)
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: leftAnchor, constant: left),
            view.rightAnchor.constraint(equalTo: rightAnchor, constant: -right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    override func draw(_: NSRect) {
        let path = bubblePath()
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func bubblePath() -> NSBezierPath {
        let r = bounds.insetBy(dx: Self.outlineInset, dy: Self.outlineInset)
        let left = r.minX + Self.tailWidth
        let radius = max(0, min(Self.cornerRadius, (r.height - 20) / 2))
        let arc = radius * 0.5522847498
        let p = NSBezierPath()
        p.move(to: NSPoint(x: left + radius, y: r.minY))
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.curve(to: NSPoint(x: r.maxX, y: r.minY + radius),
            controlPoint1: NSPoint(x: r.maxX - radius + arc, y: r.minY),
            controlPoint2: NSPoint(x: r.maxX, y: r.minY + radius - arc))
        p.line(to: NSPoint(x: r.maxX, y: r.maxY - radius))
        p.curve(to: NSPoint(x: r.maxX - radius, y: r.maxY),
            controlPoint1: NSPoint(x: r.maxX, y: r.maxY - radius + arc),
            controlPoint2: NSPoint(x: r.maxX - radius + arc, y: r.maxY))
        p.line(to: NSPoint(x: left + radius, y: r.maxY))
        p.curve(to: NSPoint(x: left, y: r.maxY - radius),
            controlPoint1: NSPoint(x: left + radius - arc, y: r.maxY),
            controlPoint2: NSPoint(x: left, y: r.maxY - radius + arc))
        p.line(to: NSPoint(x: left, y: r.midY + 8))
        p.line(to: NSPoint(x: r.minX, y: r.midY))
        p.line(to: NSPoint(x: left, y: r.midY - 8))
        p.line(to: NSPoint(x: left, y: r.minY + radius))
        p.curve(to: NSPoint(x: left + radius, y: r.minY),
            controlPoint1: NSPoint(x: left, y: r.minY + radius - arc),
            controlPoint2: NSPoint(x: left + radius - arc, y: r.minY))
        p.close()
        if pointsRight {
            p.transform(using: AffineTransform(m11: -1, m12: 0, m21: 0, m22: 1, tX: bounds.width, tY: 0))
        }
        return p
    }
}
