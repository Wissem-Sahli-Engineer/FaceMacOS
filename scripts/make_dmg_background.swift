// Renders the DMG window background: swift scripts/make_dmg_background.swift out.png <scale>
// Layout must match scripts/dmg_settings.py (660x390 window with a 370pt-tall background,
// icons centered at y=160, x=170 and x=490; everything sits in the top 260pt so Finder bars never hide it).
import AppKit

let width: CGFloat = 660
let height: CGFloat = 370
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let scale = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("Could not create bitmap") }
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.current = context
let ctx = context.cgContext
ctx.scaleBy(x: scale, y: scale)
let space = CGColorSpaceCreateDeviceRGB()

/// Converts a y measured from the top (Finder's convention) to Core Graphics' bottom-up y.
func top(_ y: CGFloat) -> CGFloat { height - y }

let background = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    CGColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let size = attributed.size()
    attributed.draw(at: CGPoint(x: (width - size.width) / 2, y: top(y) - size.height / 2))
}

drawCentered("FaceMacOS", y: 36, font: .systemFont(ofSize: 26, weight: .bold), color: NSColor(white: 0.08, alpha: 1))
drawCentered("Drag FaceMacOS into your Applications folder to install", y: 66,
             font: .systemFont(ofSize: 14, weight: .regular), color: NSColor(white: 0.40, alpha: 1))

// Arrow from the app icon toward Applications.
let arrowY = top(160)
let arrowColor = CGColor(red: 0.55, green: 0.58, blue: 0.63, alpha: 1)
ctx.setStrokeColor(arrowColor)
ctx.setLineWidth(5)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineDash(phase: 0, lengths: [0.1, 12])
ctx.move(to: CGPoint(x: 272, y: arrowY))
ctx.addLine(to: CGPoint(x: 372, y: arrowY))
ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])
ctx.move(to: CGPoint(x: 370, y: arrowY + 16))
ctx.addLine(to: CGPoint(x: 388, y: arrowY))
ctx.addLine(to: CGPoint(x: 370, y: arrowY - 16))
ctx.strokePath()

context.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: output)
