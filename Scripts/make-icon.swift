#!/usr/bin/env swift
// Renders Lobalt's app icon: a depleting mint ring with the minute pulse
// glowing red at its leading edge. No design assets to keep in the repo.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Lobalt.iconset"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

let canvasDark = srgb(0.047, 0.055, 0.067)
let canvasLift = srgb(0.110, 0.125, 0.145)
let mint = srgb(0.247, 0.839, 0.659)
let red = srgb(1.000, 0.271, 0.208)
let track = srgb(1, 1, 1, 0.12)

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // Apple's macOS icon grid: the rounded square sits inside the canvas.
    let inset = s * 0.0977
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [canvasLift, canvasDark] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])
    ctx.restoreGState()

    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = rect.width * 0.295
    let lineWidth = rect.width * 0.093

    // Track
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(track)
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Remaining time: a gap at the top right, sweeping anticlockwise from 12.
    let start = CGFloat.pi / 2                       // 12 o'clock
    let sweep = CGFloat.pi * 2 * 0.72
    ctx.setStrokeColor(mint)
    ctx.addArc(center: center, radius: ringRadius,
               startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    // The pulse: a red bloom sitting on the leading edge of the arc.
    let tipAngle = start - sweep
    let tip = CGPoint(x: center.x + cos(tipAngle) * ringRadius,
                      y: center.y + sin(tipAngle) * ringRadius)
    if size >= 32 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: lineWidth * 1.5, color: red)
        ctx.setFillColor(red)
        ctx.addArc(center: tip, radius: lineWidth * 0.52, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.setFillColor(red)
    ctx.addArc(center: tip, radius: lineWidth * 0.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.fillPath()

    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// name -> pixel size, per the .iconset convention
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in entries {
    guard let image = render(size: px) else { continue }
    write(image, to: "\(outputDir)/\(name).png")
}
print("wrote \(entries.count) icon images to \(outputDir)")
