import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let manager = FileManager.default
guard let enumeration = manager.enumerator(at: folder, includingPropertiesForKeys: nil) else {
    throw NSError(domain: "SubspaceReview", code: 1)
}
let all = enumeration.compactMap { $0 as? URL }
var names: [String: String] = [:]
@MainActor func collect(_ object: Any) {
    if let map = object as? [String: Any] {
        let filename = (map["exportedFileName"] ?? map["fileName"] ?? map["filename"]) as? String
        let title = (map["suggestedHumanReadableName"] ?? map["name"]) as? String
        if let filename, let title { names[filename] = title }
        for value in map.values { collect(value) }
    } else if let list = object as? [Any] { list.forEach(collect) }
}
for url in all where url.pathExtension == "json" {
    do { collect(try JSONSerialization.jsonObject(with: Data(contentsOf: url))) }
    catch { print("Could not read attachment metadata: \(url.lastPathComponent): \(error)") }
}
let prefixes = ["Empty-", "Populated-", "Accessibility-Light-", "Landscape-", "Analytics-", "Added-", "Add-"]
let pngs = all.filter { $0.pathExtension.lowercased() == "png" && !$0.path.contains("/Previews/") }
let own = pngs.filter { url in prefixes.contains { (names[url.lastPathComponent] ?? url.lastPathComponent).hasPrefix($0) } }
let selected = pngs.sorted {
    (names[$0.lastPathComponent] ?? $0.lastPathComponent) < (names[$1.lastPathComponent] ?? $1.lastPathComponent)
}
@MainActor func nameForReview(_ url: URL) -> String { names[url.lastPathComponent] ?? url.lastPathComponent }
let output = folder.appendingPathComponent("Previews", isDirectory: true)
try manager.createDirectory(at: output, withIntermediateDirectories: true)
print("Screenshot previews: \(selected.count) images, \(names.count) attachment names")
for (i, url) in selected.enumerated() { print("SCREENSHOT \(i): \(names[url.lastPathComponent] ?? url.lastPathComponent)") }
for page in stride(from: 0, to: selected.count, by: 8) {
    let chunk = Array(selected[page..<min(page + 8, selected.count)])
    let width = 1280
    let cellWidth = 320
    let cellHeight = 740
    let rows = (chunk.count + 3) / 4
    let height = rows * cellHeight
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "SubspaceReview", code: 2)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(white: 0.12, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))).fill()
    for (index, url) in chunk.enumerated() {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { continue }
        let x = CGFloat(index % 4 * cellWidth)
        if let bitmap = NSBitmapImageRep(contentsOf: url) {
            print("SCREENSHOT_SIZE \(nameForReview(url)): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        }
        let top = CGFloat(height - index / 4 * cellHeight)
        let name = names[url.lastPathComponent] ?? url.lastPathComponent
        (name as NSString).draw(in: NSRect(x: x + 6, y: top - 42, width: 308, height: 36), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
        let scale = min(308 / image.size.width, 688 / image.size.height)
        let target = NSRect(x: x + (320 - image.size.width * scale) / 2, y: top - 48 - image.size.height * scale, width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "SubspaceReview", code: 3) }
    let number = page / 8
    try data.write(to: output.appendingPathComponent("Review-\(number).png"))
    let base64 = data.base64EncodedString()
    var offset = base64.startIndex
    var sequence = 0
    while offset < base64.endIndex {
        let end = base64.index(offset, offsetBy: 4000, limitedBy: base64.endIndex) ?? base64.endIndex
        print("SUBSPACE_PREVIEW_CHUNK \(number) \(sequence) \(base64[offset..<end])")
        offset = end
        sequence += 1
    }
}
