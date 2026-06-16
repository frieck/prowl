import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Removes the opaque (near-black) background surrounding the rounded-square
// icon by flood-filling transparency inward from the four corners.
// Usage: swift transparent_corners.swift <input.png> <output.png> [threshold]

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: transparent_corners.swift <in> <out> [threshold]\n".data(using: .utf8)!)
    exit(1)
}
let inPath = args[1]
let outPath = args[2]
let threshold = args.count >= 4 ? (Int(args[3]) ?? 36) : 36

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("could not read input image\n".data(using: .utf8)!)
    exit(1)
}

let width = image.width
let height = image.height
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let colorSpace = CGColorSpaceCreateDeviceRGB()

var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
guard let ctx = CGContext(data: &pixels,
                          width: width,
                          height: height,
                          bitsPerComponent: 8,
                          bytesPerRow: bytesPerRow,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("could not create context\n".data(using: .utf8)!)
    exit(1)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ idx: Int) -> Bool {
    let r = Int(pixels[idx])
    let g = Int(pixels[idx + 1])
    let b = Int(pixels[idx + 2])
    let a = Int(pixels[idx + 3])
    if a == 0 { return true }
    return max(r, max(g, b)) <= threshold
}

// Iterative flood fill (4-connected) from the corners.
var stack: [Int] = []
var visited = [Bool](repeating: false, count: width * height)

func push(_ x: Int, _ y: Int) {
    guard x >= 0, x < width, y >= 0, y < height else { return }
    let p = y * width + x
    if visited[p] { return }
    visited[p] = true
    stack.append(p)
}

push(0, 0)
push(width - 1, 0)
push(0, height - 1)
push(width - 1, height - 1)

while let p = stack.popLast() {
    let x = p % width
    let y = p / width
    let idx = y * bytesPerRow + x * bytesPerPixel
    if !isBackground(idx) { continue }
    pixels[idx] = 0
    pixels[idx + 1] = 0
    pixels[idx + 2] = 0
    pixels[idx + 3] = 0
    push(x + 1, y)
    push(x - 1, y)
    push(x, y + 1)
    push(x, y - 1)
}

guard let out = ctx.makeImage() else {
    FileHandle.standardError.write("could not render output\n".data(using: .utf8)!)
    exit(1)
}

guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("could not create destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, out, nil)
if !CGImageDestinationFinalize(dest) {
    FileHandle.standardError.write("could not write output\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outPath)")
