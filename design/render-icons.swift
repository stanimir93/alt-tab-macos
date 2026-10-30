// Renders the icon sources in design/ into the assets the app ships:
//   design/app-icon.svg -> resources/icons/app/app.png      (1024x1024 RGBA, with the macOS icon shadow)
//   design/menubar.svg  -> resources/icons/menubar/menubar-0.pdf (22x22pt vector template image)
// Usage: swift design/render-icons.swift [preview-dir]
// With a preview dir, it also writes icon-preview-{1024,64,32}.png and menubar-preview.png (4x) there.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let design = root.appendingPathComponent("design")
let previewDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func loadSVG(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: design.appendingPathComponent(name)) else { fatalError("cannot load \(name)") }
    return image
}

func bitmapContext(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func draw(_ image: NSImage, in ctx: CGContext, rect: CGRect) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url.path)") }
}

func downscale(_ image: CGImage, _ size: Int) -> CGImage {
    let ctx = bitmapContext(size)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func renderAppIcon() -> CGImage {
    let size = 1024
    let flat = bitmapContext(size)
    draw(loadSVG("app-icon.svg"), in: flat, rect: CGRect(x: 0, y: 0, width: size, height: size))
    let ctx = bitmapContext(size)
    // Big Sur+ icon template shadow: 10px down, soft, 30% black
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
    ctx.draw(flat.makeImage()!, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func renderMenubar(_ url: URL) {
    var box = CGRect(x: 0, y: 0, width: 22, height: 22)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    draw(loadSVG("menubar.svg"), in: ctx, rect: box)
    ctx.endPDFPage()
    ctx.closePDF()
}

func renderMenubarPreview(_ pdf: URL, _ out: URL) {
    let page = CGPDFDocument(pdf as CFURL)!.page(at: 1)!
    let ctx = bitmapContext(88)
    ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 88, height: 88))
    ctx.scaleBy(x: 4, y: 4)
    ctx.drawPDFPage(page)
    writePNG(ctx.makeImage()!, out)
}

let appIcon = renderAppIcon()
writePNG(appIcon, root.appendingPathComponent("resources/icons/app/app.png"))
let menubarPDF = root.appendingPathComponent("resources/icons/menubar/menubar-0.pdf")
renderMenubar(menubarPDF)
if let previewDir {
    writePNG(appIcon, previewDir.appendingPathComponent("icon-preview-1024.png"))
    writePNG(downscale(appIcon, 64), previewDir.appendingPathComponent("icon-preview-64.png"))
    writePNG(downscale(appIcon, 32), previewDir.appendingPathComponent("icon-preview-32.png"))
    renderMenubarPreview(menubarPDF, previewDir.appendingPathComponent("menubar-preview.png"))
}
