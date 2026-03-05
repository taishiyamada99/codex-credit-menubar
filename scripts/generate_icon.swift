import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "/tmp/codex-credit-menubar-icon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let rect = NSRect(origin: .zero, size: size)

let image = NSImage(size: size)

image.lockFocus()

let outerPath = NSBezierPath(roundedRect: rect.insetBy(dx: 36, dy: 36), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.07, green: 0.10, blue: 0.16, alpha: 1.0).setFill()
outerPath.fill()

if let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.46, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.06, green: 0.78, blue: 0.72, alpha: 1.0)
]) {
    let innerRect = rect.insetBy(dx: 56, dy: 56)
    let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 190, yRadius: 190)
    innerPath.addClip()
    gradient.draw(in: innerRect, angle: -35)
}

let symbolRect = NSRect(x: 0, y: 300, width: 1024, height: 420)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 330, weight: .black),
    .foregroundColor: NSColor.white.withAlphaComponent(0.96),
    .paragraphStyle: paragraph
]
("C%" as NSString).draw(in: symbolRect, withAttributes: attributes)

let shine = NSBezierPath(roundedRect: NSRect(x: 128, y: 640, width: 768, height: 150), xRadius: 75, yRadius: 75)
NSColor.white.withAlphaComponent(0.12).setFill()
shine.fill()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1.0]
    )
else {
    fputs("failed to encode icon PNG\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

do {
    try png.write(to: outputURL, options: Data.WritingOptions.atomic)
    print("Generated icon PNG: \(outputPath)")
} catch {
    fputs("failed to write icon PNG: \(error)\n", stderr)
    exit(1)
}
