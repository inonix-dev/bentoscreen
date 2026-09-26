// Draws the app icon into an .iconset folder: `swift icon.swift build/AppIcon.iconset`
// Same four tiles as the menu bar icon (Remix Icon layout-masonry-fill), coloured like a bento box.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func draw(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(px) / 1024
    ctx.scaleBy(x: k, y: k)
    // Apple's grid: 824pt body inside the 1024 canvas
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: nil, colors: [rgb(0x3A3F4C), rgb(0x16181F)] as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    ctx.restoreGState()
    // tiles on the icon's 24-unit grid (3…21), y measured from the top
    let u: CGFloat = 584 / 18, origin: CGFloat = 220 - 3 * u
    let tiles: [(CGFloat, CGFloat, CGFloat, CGFloat, UInt32)] = [
        (3, 3, 10, 8, 0xFF7A59),   // salmon
        (15, 3, 6, 8, 0xFFC940),   // tamago
        (11, 13, 10, 8, 0x5CC98B), // greens
        (3, 13, 6, 8, 0xF4F1EA),   // rice
    ]
    for (x, y, w, h, c) in tiles {
        let r = CGRect(x: origin + x * u, y: 1024 - (origin + (y + h) * u), width: w * u, height: h * u)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 1.4 * u, cornerHeight: 1.4 * u, transform: nil))
        ctx.setFillColor(rgb(c)); ctx.fillPath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

for pt in [16, 32, 128, 256, 512] {
    try! draw(pt).write(to: out.appendingPathComponent("icon_\(pt)x\(pt).png"))
    try! draw(pt * 2).write(to: out.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}
