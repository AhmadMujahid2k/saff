// Draws the app icon: rows of rounded squares — a "saff" of worshippers, in the jamaat green.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [CGColor(srgbRed: 0.07, green: 0.09, blue: 0.11, alpha: 1),
                             CGColor(srgbRed: 0.02, green: 0.03, blue: 0.04, alpha: 1)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

let cols = 4, rows = 3
let cell: CGFloat = 150, gap: CGFloat = 46
let gridW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
let gridH = CGFloat(rows) * cell + CGFloat(rows - 1) * gap
let x0 = (CGFloat(size) - gridW) / 2, y0 = (CGFloat(size) - gridH) / 2
let alphas: [CGFloat] = [0.28, 0.6, 1.0] // bottom → top: front row brightest
for r in 0..<rows {
    for c in 0..<cols {
        let rect = CGRect(x: x0 + CGFloat(c) * (cell + gap), y: y0 + CGFloat(r) * (cell + gap), width: cell, height: cell)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 44, cornerHeight: 44, transform: nil))
        ctx.setFillColor(CGColor(srgbRed: 0.24, green: 0.85, blue: 0.58, alpha: alphas[r]))
        ctx.fillPath()
    }
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
