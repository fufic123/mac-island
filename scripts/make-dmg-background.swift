// Draws the DMG window background: the app on the left, an arrow, Applications on the right.
// Usage: swift scripts/make-dmg-background.swift <out.png> <scale>
import AppKit

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "background.png"
let scale = args.count > 2 ? CGFloat(Double(args[2]) ?? 1) : 1
let size = CGSize(width: 560, height: 360)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Light ground with a faint amethyst wash, so Finder's dark icon labels stay readable.
let ground = CGGradient(colorsSpace: space, colors: [rgb(0xFAF8FF), rgb(0xEDE6FF)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ground, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: 0, y: 0), options: [])

// Arrow between the two icons (icons sit at x 150 and 410, y 170 from the top).
let y = size.height - 170
ctx.setStrokeColor(rgb(0xB18CFF))
ctx.setLineWidth(3)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 240, y: y))
ctx.addLine(to: CGPoint(x: 316, y: y))
ctx.strokePath()
ctx.move(to: CGPoint(x: 304, y: y + 11))
ctx.addLine(to: CGPoint(x: 318, y: y))
ctx.addLine(to: CGPoint(x: 304, y: y - 11))
ctx.strokePath()

// Caption.
let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.current = ns
let style = NSMutableParagraphStyle()
style.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(srgbRed: 0.43, green: 0.40, blue: 0.52, alpha: 1),
    .paragraphStyle: style,
]
("Drag Mac Island to Applications" as NSString)
    .draw(in: CGRect(x: 0, y: 48, width: size.width, height: 20), withAttributes: attrs)

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
