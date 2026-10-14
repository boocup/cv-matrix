// Draws the app icon: a dark rounded square with a knob whose pointer has a red offset copy
// (the THEREELPEET look). Usage: swift scripts/make-icon.swift out.png
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1,
      let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = ctx
let c = ctx.cgContext

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
c.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
c.setFillColor(NSColor(red: 0.114, green: 0.125, blue: 0.149, alpha: 1).cgColor)
c.fillPath()

let center = CGPoint(x: 512, y: 512)
func disc(_ r: CGFloat, _ color: NSColor) {
    c.setFillColor(color.cgColor)
    c.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
}
disc(330, NSColor(white: 0.30, alpha: 1))
disc(310, NSColor(white: 0.07, alpha: 1))
disc(235, NSColor(white: 0.13, alpha: 1))

func pointer(offset: CGSize, color: NSColor) {
    c.saveGState()
    c.translateBy(x: center.x + offset.width, y: center.y + offset.height)
    c.rotate(by: -.pi / 4)                                   // pointing up and to the right
    c.setFillColor(color.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(x: -22, y: 40, width: 44, height: 250), cornerWidth: 22, cornerHeight: 22, transform: nil))
    c.fillPath()
    c.restoreGState()
}
pointer(offset: .zero, color: NSColor(red: 0.88, green: 0.64, blue: 0.29, alpha: 1))
pointer(offset: CGSize(width: 16, height: -13), color: NSColor(red: 1, green: 0, blue: 0, alpha: 0.9))

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
