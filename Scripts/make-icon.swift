import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var iconChunks = Data()
func bigEndianBytes(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform(); transform.scale(by: factor); transform.concat()
        let rect = NSRect(x: 36, y: 36, width: 952, height: 952)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 214, yRadius: 214)
        NSGradient(starting: NSColor(red: 1.0, green: 0.64, blue: 0.27, alpha: 1),
                   ending: NSColor(red: 0.92, green: 0.28, blue: 0.035, alpha: 1))!.draw(in: shape, angle: -65)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let box = NSBezierPath(roundedRect: NSRect(x: 242, y: 258, width: 540, height: 440), xRadius: 40, yRadius: 40)
        box.lineWidth = 30; box.stroke()
        let lid = NSBezierPath(roundedRect: NSRect(x: 210, y: 630, width: 604, height: 124), xRadius: 25, yRadius: 25)
        NSColor.white.withAlphaComponent(0.96).setFill(); lid.fill()
        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(rect: NSRect(x: 475, y: 278, width: 74, height: 352)).fill()
        NSColor.white.setFill()
        for index in 0..<5 {
            let x: CGFloat = index % 2 == 0 ? 480 : 515
            NSBezierPath(roundedRect: NSRect(x: x, y: 550 - CGFloat(index) * 47, width: 30, height: 24), xRadius: 5, yRadius: 5).fill()
        }
        let pull = NSBezierPath(roundedRect: NSRect(x: 481, y: 300, width: 62, height: 64), xRadius: 13, yRadius: 13)
        pull.lineWidth = 12; pull.stroke()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent(name))
        let tags = [16: "icp4", 32: "icp5", 64: "icp6", 128: "ic07", 256: "ic08", 512: "ic09", 1024: "ic10"]
        if (scale == 1 || pixels == 64 || pixels == 1024), let tag = tags[pixels] {
            iconChunks.append(Data(tag.utf8))
            iconChunks.append(bigEndianBytes(UInt32(png.count + 8)))
            iconChunks.append(png)
        }
    }
}
var icns = Data("icns".utf8)
icns.append(bigEndianBytes(UInt32(iconChunks.count + 8)))
icns.append(iconChunks)
try icns.write(to: output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
