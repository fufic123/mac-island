// Renders the app icon (violet "pill": the collapsed island on an amethyst tile) to a 1024 px PNG.
// Usage: swift scripts/make-icon.swift <out.png>. scripts/make-icon.sh turns it into AppIcon.icns.
import AppKit

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Design units: a 100×100 box whose tile spans 4…96, mapped onto Apple's 824 px icon body
// centred in 1024 px. y grows downward, as in the design.
let s = 824.0 / 92.0
let o = 100.0 - 4 * s
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.translateBy(x: o, y: o)
ctx.scaleBy(x: s, y: s)

let tile = CGPath(roundedRect: CGRect(x: 4, y: 4, width: 92, height: 92), cornerWidth: 21, cornerHeight: 21, transform: nil)
let pill = CGPath(roundedRect: CGRect(x: 16, y: 39, width: 68, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil)

// Tile with a soft drop shadow, filled with a deep amethyst gradient.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 1.2), blur: 2.4, color: rgb(0x000000, 0.35))
ctx.addPath(tile)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x2A1F45), rgb(0x0A0711)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 50, y: 4), end: CGPoint(x: 50, y: 96), options: [])
// A faint violet bloom behind the pill.
let bloom = CGGradient(colorsSpace: space, colors: [rgb(0xB18CFF, 0.28), rgb(0xB18CFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 50, y: 50), startRadius: 0,
                       endCenter: CGPoint(x: 50, y: 50), endRadius: 46, options: [])

// Glow around the pill.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 5, color: rgb(0xB18CFF, 0.9))
ctx.addPath(pill)
ctx.setStrokeColor(rgb(0xB18CFF, 0.8))
ctx.setLineWidth(2)
ctx.strokePath()
ctx.restoreGState()

// The pill itself: pure black.
ctx.addPath(pill)
ctx.setFillColor(rgb(0x000000))
ctx.fillPath()

// Rim: amethyst light with a bright highlight, like the island's rim.
ctx.saveGState()
let rim = CGPath(roundedRect: CGRect(x: 16.7, y: 39.7, width: 66.6, height: 20.6), cornerWidth: 10.3, cornerHeight: 10.3, transform: nil)
ctx.addPath(rim)
ctx.setLineWidth(1.4)
ctx.replacePathWithStrokedPath()
ctx.clip()
let rimGradient = CGGradient(colorsSpace: space,
    colors: [rgb(0xB18CFF, 0.35), rgb(0xB18CFF), rgb(0xEFE7FF), rgb(0xB18CFF), rgb(0xB18CFF, 0.35)] as CFArray,
    locations: [0, 0.5, 0.68, 0.82, 1])!
ctx.drawLinearGradient(rimGradient, start: CGPoint(x: 16, y: 50), end: CGPoint(x: 84, y: 50), options: [])
ctx.restoreGState()

ctx.restoreGState()

// Hairline edge on the tile.
let edge = CGPath(roundedRect: CGRect(x: 4.3, y: 4.3, width: 91.4, height: 91.4), cornerWidth: 20.7, cornerHeight: 20.7, transform: nil)
ctx.addPath(edge)
ctx.setStrokeColor(rgb(0xFFFFFF, 0.1))
ctx.setLineWidth(0.4)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
