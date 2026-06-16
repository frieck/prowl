import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Centers an image on a transparent square canvas at a given content fraction,
// leaving transparent margins so the rounded border is never clipped.
// Usage: swift pad_icon.swift <input.png> <output.png> [canvas=1024] [fraction=0.82]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: pad_icon.swift <in> <out> [canvas] [fraction]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let canvas = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
let fraction = args.count >= 5 ? (Double(args[4]) ?? 0.82) : 0.82

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("could not read input image\n".data(using: .utf8)!)
    exit(1)
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bytesPerRow = canvas * 4
guard let ctx = CGContext(data: nil,
                          width: canvas,
                          height: canvas,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("could not create context\n".data(using: .utf8)!)
    exit(1)
}
ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
ctx.interpolationQuality = .high

let content = Double(canvas) * fraction
let origin = (Double(canvas) - content) / 2.0
ctx.draw(image, in: CGRect(x: origin, y: origin, width: content, height: content))

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("could not render output\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
if !CGImageDestinationFinalize(dest) {
    FileHandle.standardError.write("could not write output\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outPath)")
