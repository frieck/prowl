import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Converts a black-shape-on-white image into a template alpha mask: the shape
// becomes opaque black, white/light areas (incl. eye holes) become transparent.
// The shape is trimmed to its bounds and centered on a square canvas with a
// small margin. Output is suitable for an NSImage with isTemplate = true.
// Usage: swift make_template.swift <input.png> <output.png> [canvas=256] [fraction=0.86]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: make_template.swift <in> <out> [canvas] [fraction]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let canvas = args.count >= 4 ? (Int(args[3]) ?? 256) : 256
let fraction = args.count >= 5 ? (Double(args[4]) ?? 0.86) : 0.86

guard let srcRef = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(srcRef, 0, nil) else {
    FileHandle.standardError.write("could not read input image\n".data(using: .utf8)!)
    exit(1)
}

let w = image.width
let h = image.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bpr = w * 4
var px = [UInt8](repeating: 0, count: h * bpr)
guard let rctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                           bytesPerRow: bpr, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("could not create read context\n".data(using: .utf8)!)
    exit(1)
}
rctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// Build template: alpha = darkness, premultiplied black.
var tpl = [UInt8](repeating: 0, count: h * bpr)
var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w {
        let i = y * bpr + x * 4
        let r = Double(px[i]); let g = Double(px[i+1]); let b = Double(px[i+2])
        let srcA = Double(px[i+3]) / 255.0
        let luma = (0.299 * r + 0.587 * g + 0.114 * b)
        var a = (255.0 - luma) * srcA
        if a < 16 { a = 0 }
        let au = UInt8(max(0, min(255, a)))
        tpl[i] = 0; tpl[i+1] = 0; tpl[i+2] = 0; tpl[i+3] = au
        if au > 24 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write("no shape found\n".data(using: .utf8)!)
    exit(1)
}

guard let tplCtx = CGContext(data: &tpl, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: bpr, space: colorSpace,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let tplImage = tplCtx.makeImage() else {
    FileHandle.standardError.write("could not build template image\n".data(using: .utf8)!)
    exit(1)
}

// Crop to bounds (note: bitmap origin is top-left in our buffer scan, but
// CGImage cropping uses the image coordinate space which matches pixel rows).
let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = tplImage.cropping(to: cropRect) else {
    FileHandle.standardError.write("could not crop\n".data(using: .utf8)!)
    exit(1)
}

let obpr = canvas * 4
guard let octx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                           bytesPerRow: obpr, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("could not create out context\n".data(using: .utf8)!)
    exit(1)
}
octx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
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
