import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Builds AppIcon.icns from a master PNG using CoreGraphics (opaque RGB, no alpha
// matting that Finder renders as a white halo).
// Usage: swift make_icns.swift <master.png> <output.icns>

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_icns.swift <master.png> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

let masterPath = args[1]
let outPath = args[2]

guard let srcRef = CGImageSourceCreateWithURL(URL(fileURLWithPath: masterPath) as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(srcRef, 0, nil) else {
    FileHandle.standardError.write("could not read master icon\n".data(using: .utf8)!)
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let sizes = [16, 32, 128, 256, 512]

func renderOpaque(size: Int) -> CGImage? {
    let bpr = size * 4
    guard let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bpr,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }

    ctx.interpolationQuality = .high
    ctx.setFillColor(CGColor(red: 0.12, green: 0.08, blue: 0.28, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in sizes {
    guard let image = renderOpaque(size: size),
          let dest1 = CGImageDestinationCreateWithURL(
            iconset.appendingPathComponent("icon_\(size)x\(size).png") as CFURL,
            UTType.png.identifier as CFString, 1, nil
          ),
          let dest2 = CGImageDestinationCreateWithURL(
            iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png") as CFURL,
            UTType.png.identifier as CFString, 1, nil
          ) else { exit(1) }

    CGImageDestinationAddImage(dest1, image, nil)
    CGImageDestinationFinalize(dest1)

    guard let retina = renderOpaque(size: size * 2) else { exit(1) }
    CGImageDestinationAddImage(dest2, retina, nil)
    CGImageDestinationFinalize(dest2)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outPath]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)

guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(outPath)")
