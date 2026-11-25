// Draws a monogram logo for a studio that has no logo of its own.
// Usage: swift scripts/make-logo.swift "AT" "#283C80" branding/logo.png
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let rgb = UInt32(args[2].trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) else {
    FileHandle.standardError.write(Data("usage: make-logo.swift <1-3 letters> <#RRGGBB> <out.png>\n".utf8))
    exit(1)
}
let side = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// macOS icons sit on a rounded square inset from the canvas edge.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
let letters = String(args[1].prefix(3)) as NSString
let size: CGFloat = letters.length == 1 ? 520 : letters.length == 2 ? 400 : 300
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white]
let box = letters.size(withAttributes: attrs)
letters.draw(at: NSPoint(x: tile.midX - box.width / 2, y: tile.midY - box.height / 2), withAttributes: attrs)
NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
