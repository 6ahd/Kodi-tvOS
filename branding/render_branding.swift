// Renders the DexHub Apple TV artwork: layered app icon, top shelf image,
// launch image and Kodi splash. Run on a Mac:
//   swift branding/render_branding.swift <output folder>
// The drawing follows the Dex Hub add-on icon: a violet infinity loop with a
// white play triangle in its right lobe, on deep navy.
import AppKit

let navyTop = NSColor(srgbRed: 0.075, green: 0.086, blue: 0.157, alpha: 1)
let navyBottom = NSColor(srgbRed: 0.047, green: 0.055, blue: 0.106, alpha: 1)
let violet = NSColor(srgbRed: 0.553, green: 0.502, blue: 0.976, alpha: 1)
let violetLight = NSColor(srgbRed: 0.659, green: 0.616, blue: 1.0, alpha: 1)

func render(_ width: Int, _ height: Int, to path: String, opaque: Bool = true, _ draw: (CGContext, CGFloat, CGFloat) -> Void) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw(context, CGFloat(width), CGFloat(height))
    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func background(_ c: CGContext, _ w: CGFloat, _ h: CGFloat, glow: CGFloat = 0.55) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let linear = CGGradient(colorsSpace: space, colors: [navyTop.cgColor, navyBottom.cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(linear, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
    let halo = CGGradient(colorsSpace: space, colors: [violet.withAlphaComponent(0.28).cgColor, violet.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    c.drawRadialGradient(halo, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0,
                         endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: min(w, h) * glow * 1.4, options: [])
}

/// Lemniscate of Bernoulli centred on `center`, half-width `a`.
func loopPath(center: CGPoint, a: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let d = 1 + sin(t) * sin(t)
        let point = CGPoint(x: center.x + a * cos(t) / d, y: center.y + a * sin(t) * cos(t) / d * 1.25)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func drawLoop(_ c: CGContext, center: CGPoint, a: CGFloat) {
    c.saveGState()
    c.addPath(loopPath(center: center, a: a))
    c.setLineWidth(a * 0.26)
    c.setLineJoin(.round)
    c.replacePathWithStrokedPath()
    c.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [violetLight.cgColor, violet.cgColor] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: center.x, y: center.y + a), end: CGPoint(x: center.x, y: center.y - a), options: [])
    c.restoreGState()
}

func drawPlay(_ c: CGContext, center: CGPoint, a: CGFloat, shadow: Bool) {
    // Sits in the middle of the right lobe.
    let s = a * 0.30
    let mid = CGPoint(x: center.x + a * 0.60, y: center.y)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: mid.x - s * 0.45, y: mid.y + s * 0.62))
    path.addLine(to: CGPoint(x: mid.x + s * 0.62, y: mid.y))
    path.addLine(to: CGPoint(x: mid.x - s * 0.45, y: mid.y - s * 0.62))
    path.closeSubpath()
    c.saveGState()
    if shadow { c.setShadow(offset: CGSize(width: 0, height: -a * 0.03), blur: a * 0.08, color: NSColor.black.withAlphaComponent(0.45).cgColor) }
    // One layer, so the shadow falls under the whole triangle and not across its fill.
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.addPath(path)
    c.setFillColor(NSColor.white.cgColor)
    c.setLineWidth(s * 0.18)
    c.setLineJoin(.round)
    c.setStrokeColor(NSColor.white.cgColor)
    c.drawPath(using: .fillStroke)
    c.endTransparencyLayer()
    c.restoreGState()
}

func wordmark(_ text: String, size: CGFloat, center: CGPoint) {
    let font = NSFont.systemFont(ofSize: size, weight: .heavy)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white, .kern: size * 0.04]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

// App icon layers (back, middle, front). The system adds rounding, shine and parallax.
for (name, w, h) in [("icon", 800, 480), ("icon_appstore", 1280, 768)] {
    let a = CGFloat(h) * 0.40
    render(w, h, to: "\(out)/\(name)-back.png") { c, w, h in background(c, w, h) }
    render(w, h, to: "\(out)/\(name)-middle.png", opaque: false) { c, w, h in drawLoop(c, center: CGPoint(x: w / 2, y: h / 2), a: a) }
    render(w, h, to: "\(out)/\(name)-front.png", opaque: false) { c, w, h in drawPlay(c, center: CGPoint(x: w / 2, y: h / 2), a: a, shadow: true) }
}

// Top shelf images (shown when Kodi has nothing of its own to list).
for (name, w, h) in [("topshelf_wide", 2320, 720), ("topshelf", 1920, 720)] {
    render(w, h, to: "\(out)/\(name).png") { c, w, h in
        background(c, w, h, glow: 0.9)
        let a = h * 0.26
        let logo = CGPoint(x: w / 2 - h * 0.62, y: h / 2)
        drawLoop(c, center: logo, a: a)
        drawPlay(c, center: logo, a: a, shadow: false)
        wordmark("DEX HUB", size: h * 0.20, center: CGPoint(x: w / 2 + h * 0.42, y: h / 2))
    }
}

// Launch image and Kodi's splash share one calm screen, so the hand-over is seamless.
render(1920, 1080, to: "\(out)/launch.png") { c, w, h in
    background(c, w, h)
    let a = h * 0.14
    drawLoop(c, center: CGPoint(x: w / 2, y: h / 2), a: a)
    drawPlay(c, center: CGPoint(x: w / 2, y: h / 2), a: a, shadow: false)
}
print(out)
