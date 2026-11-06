// Renders the app icon with CoreGraphics, so the artwork can be reproduced and tweaked from this repository.
//
// Usage: swift Scripts/generate-icon.swift Packaging/AppIcon.icns
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconError: Error, CustomStringConvertible {
    let description: String
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

/// Draws the icon into a 1024 x 1024 coordinate space whose origin is the bottom left corner.
func drawIcon(in context: CGContext) {
    let tile = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 186,
        cornerHeight: 186,
        transform: nil
    )

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.3))
    context.addPath(tile)
    context.setFillColor(color(0.1, 0.2, 0.7))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0.22, 0.66, 1.0), color(0.33, 0.30, 0.92)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
    context.restoreGState()

    // One query path splits into three: the top one is the routed (split) domain, the rest keep the default.
    let source = CGPoint(x: 322, y: 512)
    let targets = [CGPoint(x: 708, y: 712), CGPoint(x: 708, y: 512), CGPoint(x: 708, y: 312)]
    context.setLineWidth(40)
    context.setLineCap(.round)
    for (index, target) in targets.enumerated() {
        // A transparency layer keeps the line and its node from showing through each other where they overlap.
        context.saveGState()
        context.setAlpha(index == 0 ? 1 : 0.5)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setStrokeColor(color(1, 1, 1))
        context.setFillColor(color(1, 1, 1))
        context.move(to: source)
        context.addCurve(
            to: target,
            control1: CGPoint(x: 500, y: source.y),
            control2: CGPoint(x: 530, y: target.y)
        )
        context.strokePath()
        context.fillEllipse(in: CGRect(x: target.x - 56, y: target.y - 56, width: 112, height: 112))
        context.endTransparencyLayer()
        context.restoreGState()
    }

    context.setFillColor(color(1, 1, 1))
    context.fillEllipse(in: CGRect(x: source.x - 76, y: source.y - 76, width: 152, height: 152))
    context.setFillColor(color(0.28, 0.42, 0.96))
    context.fillEllipse(in: CGRect(x: source.x - 30, y: source.y - 30, width: 60, height: 60))
}

func renderPNG(pixels: Int) throws -> Data {
    guard
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else {
        throw IconError(description: "Could not create a \(pixels) px bitmap.")
    }
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)

    guard let image = context.makeImage() else {
        throw IconError(description: "Could not render the \(pixels) px image.")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError(description: "Could not create a PNG encoder.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError(description: "Could not encode the \(pixels) px PNG.")
    }
    return data as Data
}

func run() throws {
    guard CommandLine.arguments.count == 2 else {
        throw IconError(description: "Usage: swift Scripts/generate-icon.swift <output.icns>")
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[1])

    let iconset = FileManager.default.temporaryDirectory
        .appendingPathComponent("splitdns-\(UUID().uuidString).iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }

    let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for variant in variants {
        try renderPNG(pixels: variant.pixels).write(to: iconset.appendingPathComponent("\(variant.name).png"))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw IconError(description: "iconutil failed with status \(iconutil.terminationStatus).")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
