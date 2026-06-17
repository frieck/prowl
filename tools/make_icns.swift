import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Builds AppIcon.icns from a master PNG. Uses sips for small sizes so Finder list
// view icons stay sharp (simple downscale of a 1024 master looks muddy at 16px).
// Usage: swift make_icns.swift <master.png> <output.icns>

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_icns.swift <master.png> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

let masterPath = args[1]
let outPath = args[2]
let masterURL = URL(fileURLWithPath: masterPath)

guard FileManager.default.fileExists(atPath: masterPath) else {
    FileHandle.standardError.write("master icon not found\n".data(using: .utf8)!)
    exit(1)
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func sipsResize(_ size: Int, to dest: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(size)", "\(size)", masterURL.path, "--out", dest.path]
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        throw NSError(domain: "make_icns", code: 1, userInfo: [NSLocalizedDescriptionKey: "sips failed for \(size)px"])
    }
}

let slots: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

do {
    for (name, size) in slots {
        try sipsResize(size, to: iconset.appendingPathComponent(name))
    }
} catch {
    FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outPath]
do {
    try task.run()
    task.waitUntilExit()
} catch {
    FileHandle.standardError.write("iconutil failed to launch\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)

guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(outPath)")
