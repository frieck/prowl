import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Scales icon content to fill a square opaque canvas for macOS .icns.
// Center-crops the alpha bounds to a square first so list-view sizes don't show
// letterboxed side bars when Finder downscales the master icon.
// Usage: swift flatten_icon_canvas.swift <input.png> <output.png> [canvas=1024] [fraction=1.0]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: flatten_icon_canvas.swift <in> <out> [canvas] [fraction]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let canvas = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
let fraction = args.count >= 5 ? (Double(args[4]) ?? 1.0) : 1.0

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
        if px[y * bpr + x * 4 + 3] > 16 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX >= minX, maxY >= minY else { exit(1) }

let cw = maxX - minX + 1
let ch = maxY - minY + 1
let side = max(cw, ch)
var sqMinX = minX - (side - cw) / 2
var sqMinY = minY - (side - ch) / 2
if sqMinX < 0 { sqMinX = 0 }
if sqMinY < 0 { sqMinY = 0 }
if sqMinX + side > w { sqMinX = max(0, w - side) }
if sqMinY + side > h { sqMinY = max(0, h - side) }
let sqSide = min(side, min(w - sqMinX, h - sqMinY))

var cropPx = [UInt8](repeating: 0, count: sqSide * sqSide * 4)
for y in 0..<sqSide {
    for x in 0..<sqSide {
        let src = (sqMinY + y) * bpr + (sqMinX + x) * 4
        let dst = (y * sqSide + x) * 4
        cropPx[dst] = px[src]
        cropPx[dst + 1] = px[src + 1]
        cropPx[dst + 2] = px[src + 2]
        cropPx[dst + 3] = px[src + 3]
    }
}

let cropBPR = sqSide * 4
guard let cropCtx = CGContext(data: &cropPx, width: sqSide, height: sqSide, bitsPerComponent: 8,
                              bytesPerRow: cropBPR, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let cropped = cropCtx.makeImage() else { exit(1) }

let bgRed: CGFloat = 0.12, bgGreen: CGFloat = 0.08, bgBlue: CGFloat = 0.28
let obpr = canvas * 4
guard let octx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                           bytesPerRow: obpr, space: colorSpace,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

octx.setFillColor(CGColor(red: bgRed, green: bgGreen, blue: bgBlue, alpha: 1))
octx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

octx.interpolationQuality = .high
let maxContent = Double(canvas) * fraction
let scale = maxContent / Double(sqSide)
let dw = Double(sqSide) * scale
let dh = Double(sqSide) * scale
let ox = (Double(canvas) - dw) / 2.0
let oy = (Double(canvas) - dh) / 2.0
octx.draw(cropped, in: CGRect(x: ox, y: oy, width: dw, height: dh))

guard let out = octx.makeImage() else { exit(1) }

guard let rgbCtx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                             bytesPerRow: canvas * 4, space: colorSpace,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
rgbCtx.setFillColor(CGColor(red: bgRed, green: bgGreen, blue: bgBlue, alpha: 1))
rgbCtx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
rgbCtx.draw(out, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
guard let rgb = rgbCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }

CGImageDestinationAddImage(dest, rgb, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
