// Draw Decanter's icon and write the sizes an .icns needs.
//
//   swift tools/make-icon.swift <output directory>
//
// Then: iconutil -c icns <output directory>/Decanter.iconset -o assets/decanter.icns
//
// A decanter: a wide body, a narrow neck, and a handle. Drawn rather than shipped as a binary
// so that the repository holds a description of the icon rather than a picture of it.

import AppKit
import CoreGraphics
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(size: CGFloat) -> CGImage? {
    let scale: CGFloat = 1
    let width = Int(size * scale)
    guard let context = CGContext(data: nil, width: width, height: width,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // The rounded square macOS app icons sit in.
    let inset = size * 0.06
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = plate.width * 0.22
    let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(platePath)
    context.setFillColor(CGColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1))
    context.fillPath()

    // A rim, so the icon has an edge on a dark background.
    context.addPath(platePath)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(size * 0.006)
    context.strokePath()

    // The body: a decanter's neck at the top, widening downwards to a foot. Core Graphics puts
    // the origin at the bottom left, so larger y is higher on the icon.
    let body = CGMutablePath()
    let cx = size / 2
    let neckTop = size * 0.78
    let shoulder = size * 0.58
    let footBottom = size * 0.24
    let footHalf = size * 0.235
    let neckHalf = size * 0.062
    body.move(to: CGPoint(x: cx - neckHalf, y: neckTop))
    body.addLine(to: CGPoint(x: cx - neckHalf, y: shoulder))
    body.addCurve(to: CGPoint(x: cx - footHalf, y: footBottom),
                  control1: CGPoint(x: cx - footHalf, y: shoulder - size * 0.04),
                  control2: CGPoint(x: cx - footHalf, y: footBottom + size * 0.06))
    body.addLine(to: CGPoint(x: cx + footHalf, y: footBottom))
    body.addCurve(to: CGPoint(x: cx + neckHalf, y: shoulder),
                  control1: CGPoint(x: cx + footHalf, y: footBottom + size * 0.06),
                  control2: CGPoint(x: cx + footHalf, y: shoulder - size * 0.04))
    body.addLine(to: CGPoint(x: cx + neckHalf, y: neckTop))
    body.closeSubpath()

    context.addPath(body)
    context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1))
    context.fillPath()

    // The wine in it, clipped to the body so it cannot spill: the lower half of the bowl.
    context.saveGState()
    context.addPath(body)
    context.clip()
    let surface = size * 0.50
    context.setFillColor(CGColor(red: 0.55, green: 0.13, blue: 0.20, alpha: 1))
    context.fill(CGRect(x: 0, y: footBottom - size * 0.05, width: size, height: surface - footBottom + size * 0.05))
    context.setFillColor(CGColor(red: 0.74, green: 0.24, blue: 0.30, alpha: 1))
    context.fill(CGRect(x: 0, y: surface - size * 0.012, width: size, height: size * 0.014))
    context.restoreGState()

    // A stopper on the neck.
    let stopper = CGRect(x: cx - size * 0.082, y: neckTop - size * 0.004,
                         width: size * 0.164, height: size * 0.055)
    let stopperPath = CGPath(roundedRect: stopper, cornerWidth: size * 0.018,
                             cornerHeight: size * 0.018, transform: nil)
    context.addPath(stopperPath)
    context.setFillColor(CGColor(red: 0.85, green: 0.80, blue: 0.70, alpha: 1))
    context.fillPath()

    return context.makeImage()
}

let iconset = URL(fileURLWithPath: output).appendingPathComponent("Decanter.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let image = draw(size: CGFloat(pixels)) else { continue }
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let url = iconset.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { continue }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
print("wrote \(iconset.path)")
