import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Scales opaque icon content to fill a square canvas, removing the transparent
// halo that Finder renders as a white border around .app icons.
// Usage: swift flatten_icon_canvas.swift <input.png> <output.png> [canvas=1024] [fraction=0.96]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: flatten_icon_canvas.swift <in> <out> [canvas] [fraction]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let canvas = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
let fraction = args.count >= 5 ? (Double(args[4]) ?? 0.96) : 0.96

guard let srcRef = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(srcRef, 0, nil) else {
    FileHandle.standardError.write("could not read input\n".data(using: .utf8)!)
    exit(1)
}

let w = image.width, h = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bpr = w * 4
var px = [UInt8](repeating: 0, count: h * bpr)
guard let rctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                           bytesPerRow: bpr, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
rctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w {
        let a = px[y * bpr + x * 4 + 3]
        if a > 16 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
guard maxX >= minX else { exit(1) }

guard let cropped = image.cropping(to: CGRect(x: minX, y: minY,
                                              width: maxX - minX + 1,
                                              height: maxY - minY + 1)) else { exit(1) }

let obpr = canvas * 4
guard let octx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                           bytesPerRow: obpr, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

// Opaque dark purple background (matches icon gradient) — no white halo in Finder.
octx.setFillColor(CGColor(red: 0.12, green: 0.08, blue: 0.28, alpha: 1))
octx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

octx.interpolationQuality = .high
let cw = Double(cropped.width), ch = Double(cropped.height)
let maxContent = Double(canvas) * fraction
let scale = min(maxContent / cw, maxContent / ch)
let dw = cw * scale, dh = ch * scale
let ox = (Double(canvas) - dw) / 2.0
let oy = (Double(canvas) - dh) / 2.0
octx.draw(cropped, in: CGRect(x: ox, y: oy, width: dw, height: dh))

guard let out = octx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }

// Export as opaque RGB (no alpha channel) so Finder doesn't add a white mat.
guard let rgbCtx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                             bytesPerRow: canvas * 4, space: colorSpace,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
rgbCtx.draw(out, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
guard let rgb = rgbCtx.makeImage() else { exit(1) }

CGImageDestinationAddImage(dest, rgb, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
