import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Scales icon content onto an opaque square canvas for macOS .icns.
// Usage: swift flatten_icon_canvas.swift <input.png> <output.png> [canvas=1024] [fraction=1.0] [erosion=2]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: flatten_icon_canvas.swift <in> <out> [canvas] [fraction] [erosion]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let canvas = args.count >= 4 ? (Int(args[3]) ?? 1024) : 1024
let fraction = args.count >= 5 ? (Double(args[4]) ?? 1.0) : 1.0
let erosion = args.count >= 6 ? max(0, Int(args[5]) ?? 2) : 2

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

func alphaAt(_ x: Int, _ y: Int, _ source: [UInt8]) -> Int {
    guard x >= 0, x < w, y >= 0, y < h else { return 0 }
    return Int(source[y * bpr + x * 4 + 3])
}

if erosion > 0 {
    let copy = px
    for y in 0..<h {
        for x in 0..<w {
            let idx = y * bpr + x * 4
            guard copy[idx + 3] > 16 else { continue }
            var keep = true
            for dy in -erosion...erosion {
                for dx in -erosion...erosion {
                    if alphaAt(x + dx, y + dy, copy) <= 16 {
                        keep = false
                        break
                    }
                }
                if !keep { break }
            }
            if !keep {
                px[idx] = 0
                px[idx + 1] = 0
                px[idx + 2] = 0
                px[idx + 3] = 0
            }
        }
    }
}

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

let cropW = maxX - minX + 1
let cropH = maxY - minY + 1
var cropPx = [UInt8](repeating: 0, count: cropW * cropH * 4)
for y in 0..<cropH {
    for x in 0..<cropW {
        let src = ((minY + y) * bpr + (minX + x) * 4)
        let dst = (y * cropW + x) * 4
        cropPx[dst] = px[src]
        cropPx[dst + 1] = px[src + 1]
        cropPx[dst + 2] = px[src + 2]
        cropPx[dst + 3] = px[src + 3]
    }
}

let cropBPR = cropW * 4
guard let cropCtx = CGContext(data: &cropPx, width: cropW, height: cropH, bitsPerComponent: 8,
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
let cw = Double(cropW), ch = Double(cropH)
let maxContent = Double(canvas) * fraction
let scale = min(maxContent / cw, maxContent / ch)
let dw = cw * scale, dh = ch * scale
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

let rbpr = canvas * 4
var rgbPx = [UInt8](repeating: 0, count: canvas * rbpr)
guard let rgbRead = CGContext(data: &rgbPx, width: canvas, height: canvas, bitsPerComponent: 8,
                              bytesPerRow: rbpr, space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
rgbRead.draw(rgbCtx.makeImage()!, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

func isBgPurple(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    abs(r - 31) < 22 && abs(g - 20) < 22 && abs(b - 71) < 30
}

func isFringe(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    let sum = r + g + b
    if sum > 340 && g > 125 && b > 125 { return true }
    if sum > 400 && r > 130 && g > 150 { return true }
    return false
}

let bgR: UInt8 = 31, bgG: UInt8 = 20, bgB: UInt8 = 71
for _ in 0..<8 {
    let snap = rgbPx
    for y in 0..<canvas {
        for x in 0..<canvas {
            let idx = y * rbpr + x * 4
            let r = Int(snap[idx]), g = Int(snap[idx + 1]), b = Int(snap[idx + 2])
            guard isFringe(r, g, b) else { continue }
            var touchesBg = x == 0 || y == 0 || x == canvas - 1 || y == canvas - 1
            if !touchesBg {
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    let ni = ny * rbpr + nx * 4
                    if isBgPurple(Int(snap[ni]), Int(snap[ni + 1]), Int(snap[ni + 2])) {
                        touchesBg = true
                        break
                    }
                }
            }
            if touchesBg {
                rgbPx[idx] = bgR
                rgbPx[idx + 1] = bgG
                rgbPx[idx + 2] = bgB
            }
        }
    }
}

guard let scrubCtx = CGContext(data: &rgbPx, width: canvas, height: canvas, bitsPerComponent: 8,
                               bytesPerRow: rbpr, space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let rgb = scrubCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }

CGImageDestinationAddImage(dest, rgb, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")
