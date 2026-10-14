import AppKit

// Usage: swift make_icon.swift <input-1024.png> <output-1024.png> "TEXT"
let args = CommandLine.arguments
guard args.count >= 4, let base = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("cannot load input\n".data(using: .utf8)!)
    exit(1)
}
let text = args[3]
let side = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else {
    FileHandle.standardError.write("cannot make rep\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write("cannot make context\n".data(using: .utf8)!)
    exit(1)
}
NSGraphicsContext.current = ctx

// Base icon fills the canvas.
base.draw(in: NSRect(x: 0, y: 0, width: side, height: side))

// Brand text: heavy weight, white, soft shadow, centered.
let fontSize: CGFloat = 210
let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
let para = NSMutableParagraphStyle()
para.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 12
shadow.shadowOffset = NSSize(width: 0, height: -4)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: para,
    .shadow: shadow,
]
let attr = NSAttributedString(string: text, attributes: attrs)
let ts = attr.size()
attr.draw(in: NSRect(
    x: (CGFloat(side) - ts.width) / 2,
    y: (CGFloat(side) - ts.height) / 2,
    width: ts.width, height: ts.height))

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let outData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("cannot encode png\n".data(using: .utf8)!)
    exit(1)
}
try? outData.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
