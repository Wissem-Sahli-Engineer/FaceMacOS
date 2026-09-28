// Renders the DMG window background: swift scripts/make_dmg_background.swift out.png <scale>
// Layout must match scripts/dmg_settings.py (660x560 window with a 540pt-tall background,
// icons centered at y=160, x=170 and x=490, "Terminal fix.txt" at 530,330). With Finder's toolbar, path and status bars
// all on, only about the top 430pt are visible, so everything sits above that.
import AppKit

let width: CGFloat = 660
let height: CGFloat = 540
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

// "Built for macOS" badge under the arrow (a plain laptop glyph; Apple's logo is not licensed for third-party use).
let badgeFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
let badgeText = NSAttributedString(string: "Built for macOS", attributes: [.font: badgeFont, .foregroundColor: NSColor(white: 0.30, alpha: 1)])
let textSize = badgeText.size()
let glyphWidth: CGFloat = 18
let badgeWidth = 14 + glyphWidth + 7 + textSize.width + 14
let badgeRect = CGRect(x: (width - badgeWidth) / 2, y: top(212) - 13, width: badgeWidth, height: 26)
ctx.addPath(CGPath(roundedRect: badgeRect, cornerWidth: 13, cornerHeight: 13, transform: nil))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 12.5, cornerHeight: 12.5, transform: nil))
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12))
ctx.setLineWidth(1)
ctx.strokePath()
let glyphX = badgeRect.minX + 14
let glyphY = badgeRect.midY
ctx.setStrokeColor(CGColor(gray: 0.30, alpha: 1))
ctx.setLineWidth(1.4)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.addPath(CGPath(roundedRect: CGRect(x: glyphX + 2, y: glyphY - 3, width: glyphWidth - 4, height: 10), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
ctx.strokePath()
ctx.move(to: CGPoint(x: glyphX, y: glyphY - 5))
ctx.addLine(to: CGPoint(x: glyphX + glyphWidth, y: glyphY - 5))
ctx.strokePath()
badgeText.draw(at: CGPoint(x: glyphX + glyphWidth + 7, y: badgeRect.midY - textSize.height / 2))

// First-launch help: without Apple notarization, macOS blocks the app the first time it's opened.
ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
ctx.setLineWidth(1)
ctx.move(to: CGPoint(x: 60, y: top(268)))
ctx.addLine(to: CGPoint(x: width - 60, y: top(268)))
ctx.strokePath()
// Left column of text; the "Terminal fix.txt" icon sits on the right at (530, 330).
func drawLeft(_ text: String, y: CGFloat, weight: NSFont.Weight = .regular, white: CGFloat = 0.40) {
    let attributed = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 12.5, weight: weight), .foregroundColor: NSColor(white: white, alpha: 1),
    ])
    attributed.draw(at: CGPoint(x: 60, y: top(y) - attributed.size().height / 2))
}
drawLeft("macOS blocked it the first time you opened it?", y: 296, weight: .semibold, white: 0.20)
drawLeft("1.  System Settings → Privacy & Security →", y: 322)
drawLeft("     scroll down → Open Anyway", y: 340)
drawLeft("2.  Or open “Terminal fix”, copy the command,", y: 366)
drawLeft("     paste it into Terminal and press Return  →", y: 384)
drawLeft("Help: facemacos.onrender.com/#install", y: 410, white: 0.55)

context.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: output)
