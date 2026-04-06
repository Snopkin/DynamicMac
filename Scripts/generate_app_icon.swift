#!/usr/bin/env swift

//
//  generate_app_icon.swift
//  DynamicMac
//
//  Renders the DynamicMac app icon into a 1024×1024 PNG, then downscales
//  to every AppIcon.appiconset slot. Invoke from the repo root:
//
//      swift Scripts/generate_app_icon.swift
//
//  Outputs:
//      DynamicMac/Assets.xcassets/AppIcon.appiconset/icon_{size}.png
//  and rewrites Contents.json to point at them.
//
//  Re-run after tweaking colors, corner radii, or proportions below —
//  every render is deterministic.
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Design parameters

/// Side length of the master render. macOS icon slots top out at 1024×1024
/// (512 @2x), so anything above that is wasted pixels.
let masterSize: CGFloat = 1024

/// Background gradient. Charcoal to near-black, top to bottom, so the icon
/// reads clearly against a light or dark Dock.
let backgroundTopColor = NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.22, alpha: 1.0)
let backgroundBottomColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)

/// Rounded-square "app icon" corner radius ratio. macOS Big Sur+ uses
/// roughly 22.37% of the side length for the standard squircle.
let outerCornerRadiusRatio: CGFloat = 0.2237

/// Centered black island dimensions as fractions of the canvas. The island
/// evokes the notch pill — wide, short, rounded.
let islandWidthRatio: CGFloat = 0.64
let islandHeightRatio: CGFloat = 0.22
let islandCornerRadiusRatio: CGFloat = 0.11 // fraction of island height; matches iOS Dynamic Island curvature

/// Inner highlight stroke on the island to give it depth on darker
/// backgrounds. Alpha is low so it never shouts.
let islandHighlightColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.10)

/// Soft inner glow simulating a lit island — a bluish tint, very subtle,
/// reinforcing the "dynamic" feel without looking gaudy.
let glowColor = NSColor(calibratedRed: 0.36, green: 0.56, blue: 1.0, alpha: 0.28)
let glowBlurRadius: CGFloat = 28

// MARK: - Slot table

struct IconSlot {
    let size: Int   // in points
    let scale: Int  // 1x or 2x
    var pixelSize: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)@\(scale)x.png" }
}

let slots: [IconSlot] = [
    IconSlot(size: 16,  scale: 1),
    IconSlot(size: 16,  scale: 2),
    IconSlot(size: 32,  scale: 1),
    IconSlot(size: 32,  scale: 2),
    IconSlot(size: 128, scale: 1),
    IconSlot(size: 128, scale: 2),
    IconSlot(size: 256, scale: 1),
    IconSlot(size: 256, scale: 2),
    IconSlot(size: 512, scale: 1),
    IconSlot(size: 512, scale: 2),
]

// MARK: - Master image render

func renderMasterImage() -> NSImage {
    let rect = NSRect(x: 0, y: 0, width: masterSize, height: masterSize)

    let image = NSImage(size: rect.size)
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("No current CG context while rendering master icon")
    }

    // Background: rounded square with vertical gradient fill.
    let outerRadius = masterSize * outerCornerRadiusRatio
    let outerPath = NSBezierPath(
        roundedRect: rect,
        xRadius: outerRadius,
        yRadius: outerRadius
    )
    context.saveGState()
    outerPath.addClip()

    let gradient = NSGradient(
        colors: [backgroundTopColor, backgroundBottomColor],
        atLocations: [0.0, 1.0],
        colorSpace: .deviceRGB
    )!
    gradient.draw(in: rect, angle: -90)
    context.restoreGState()

    // Soft inner glow sitting just above the island — a diffuse colored
    // ellipse blurred through Core Image. Gives the whole icon a hint of
    // light without needing a real shader.
    let glowRect = NSRect(
        x: masterSize * 0.18,
        y: masterSize * 0.42,
        width: masterSize * 0.64,
        height: masterSize * 0.28
    )
    drawBlurredEllipse(
        in: glowRect,
        color: glowColor,
        blurRadius: glowBlurRadius
    )

    // Island: centered, wide-but-short rounded rectangle. Pure black so
    // it blends with the OLED/dark-mode notch strip visually.
    let islandWidth = masterSize * islandWidthRatio
    let islandHeight = masterSize * islandHeightRatio
    let islandOrigin = NSPoint(
        x: (masterSize - islandWidth) / 2,
        y: (masterSize - islandHeight) / 2
    )
    let islandRect = NSRect(origin: islandOrigin, size: NSSize(width: islandWidth, height: islandHeight))
    let islandRadius = islandHeight * islandCornerRadiusRatio / (islandHeightRatio) // normalize so the curve stays pill-like
    let cappedRadius = min(islandRadius, islandHeight / 2)
    let islandPath = NSBezierPath(
        roundedRect: islandRect,
        xRadius: cappedRadius,
        yRadius: cappedRadius
    )
    NSColor.black.setFill()
    islandPath.fill()

    // Thin inner highlight stroke on the island's top edge — catches light,
    // reinforces the 3D illusion.
    context.saveGState()
    islandPath.addClip()
    islandHighlightColor.setStroke()
    let highlightPath = NSBezierPath(
        roundedRect: islandRect.insetBy(dx: masterSize * 0.004, dy: masterSize * 0.004),
        xRadius: cappedRadius,
        yRadius: cappedRadius
    )
    highlightPath.lineWidth = masterSize * 0.008
    highlightPath.stroke()
    context.restoreGState()

    return image
}

// MARK: - Blur helper

func drawBlurredEllipse(in rect: NSRect, color: NSColor, blurRadius: CGFloat) {
    // Render the ellipse to an offscreen bitmap, blur it, then composite
    // back onto the current context.
    let scale: CGFloat = 1
    let bitmapSize = NSSize(width: rect.width * scale, height: rect.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bitmapSize.width),
        pixelsHigh: Int(bitmapSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill()
    NSBezierPath(ovalIn: NSRect(origin: .zero, size: bitmapSize)).fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = rep.cgImage else { return }
    let ciImage = CIImage(cgImage: cgImage)
    let blurFilter = CIFilter(name: "CIGaussianBlur")!
    blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
    blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)

    guard let output = blurFilter.outputImage else { return }
    let ciContext = CIContext()
    guard let blurredCG = ciContext.createCGImage(output, from: output.extent) else { return }

    let nsImage = NSImage(cgImage: blurredCG, size: rect.size)
    nsImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
}

// MARK: - Resize + write

func writePNG(_ image: NSImage, size: Int, to url: URL) {
    // NSImage + lockFocus respects the current display's backing scale, so
    // on a Retina Mac every PNG comes out 2× larger than requested and the
    // AppIcon.appiconset validator rejects it. Build an NSBitmapImageRep
    // at the exact pixel dimensions we want instead — that bypasses the
    // display-scale multiplier completely.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("Failed to allocate bitmap rep at size \(size)")
        return
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1.0
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to encode PNG at size \(size)")
        return
    }
    try? png.write(to: url)
}

// MARK: - Contents.json writer

func writeContentsJSON(at url: URL) {
    var images: [[String: String]] = []
    for slot in slots {
        images.append([
            "idiom": "mac",
            "scale": "\(slot.scale)x",
            "size": "\(slot.size)x\(slot.size)",
            "filename": slot.filename
        ])
    }

    let payload: [String: Any] = [
        "images": images,
        "info": [
            "author": "xcode",
            "version": 1
        ]
    ]

    let data = try! JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys]
    )
    try? data.write(to: url)
}

// MARK: - Main

let fileManager = FileManager.default
let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let iconset = cwd.appendingPathComponent("DynamicMac/Assets.xcassets/AppIcon.appiconset")

guard fileManager.fileExists(atPath: iconset.path) else {
    fputs("Iconset not found at \(iconset.path). Run from the repo root.\n", stderr)
    exit(1)
}

print("Rendering master icon (\(Int(masterSize))x\(Int(masterSize)))…")
let master = renderMasterImage()

for slot in slots {
    let url = iconset.appendingPathComponent(slot.filename)
    writePNG(master, size: slot.pixelSize, to: url)
    print("  wrote \(slot.filename) (\(slot.pixelSize)px)")
}

let contentsURL = iconset.appendingPathComponent("Contents.json")
writeContentsJSON(at: contentsURL)
print("  wrote Contents.json")

print("Done.")
