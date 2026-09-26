// Renders the app icon to a 1024px PNG: swift scripts/make_icon.swift out.png
import AppKit

let canvas: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Could not create bitmap") }

let ctx = context.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// macOS icon grid: 824pt rounded square centered in 1024.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    CGColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
ctx.restoreGState()

// Face ID glyph, same geometry as FaceIDGlyph in the app (y-down unit square).
let side: CGFloat = 430
let origin = CGPoint(x: 512 - side / 2, y: 512 - side / 2)
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * side, y: origin.y + (1 - y) * side) }
let arm: CGFloat = 0.26
let r: CGFloat = 0.16

let glyph = CGMutablePath()
glyph.move(to: p(0, arm)); glyph.addLine(to: p(0, r)); glyph.addQuadCurve(to: p(r, 0), control: p(0, 0)); glyph.addLine(to: p(arm, 0))
glyph.move(to: p(1 - arm, 0)); glyph.addLine(to: p(1 - r, 0)); glyph.addQuadCurve(to: p(1, r), control: p(1, 0)); glyph.addLine(to: p(1, arm))
glyph.move(to: p(1, 1 - arm)); glyph.addLine(to: p(1, 1 - r)); glyph.addQuadCurve(to: p(1 - r, 1), control: p(1, 1)); glyph.addLine(to: p(1 - arm, 1))
glyph.move(to: p(arm, 1)); glyph.addLine(to: p(r, 1)); glyph.addQuadCurve(to: p(0, 1 - r), control: p(0, 1)); glyph.addLine(to: p(0, 1 - arm))
glyph.move(to: p(0.33, 0.33)); glyph.addLine(to: p(0.33, 0.42))
glyph.move(to: p(0.67, 0.33)); glyph.addLine(to: p(0.67, 0.42))
glyph.move(to: p(0.5, 0.33)); glyph.addLine(to: p(0.5, 0.57)); glyph.addLine(to: p(0.44, 0.57))
glyph.move(to: p(0.33, 0.70)); glyph.addQuadCurve(to: p(0.67, 0.70), control: p(0.5, 0.80))

let stroked = glyph.copy(strokingWithWidth: 40, lineCap: .round, lineJoin: .round, miterLimit: 10)
ctx.saveGState()
ctx.addPath(stroked)
ctx.clip()
let ink = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1),
    CGColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ink, start: CGPoint(x: 512, y: origin.y + side), end: CGPoint(x: 512, y: origin.y), options: [])
ctx.restoreGState()

context.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: output)
