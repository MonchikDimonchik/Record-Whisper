import AppKit
import Foundation

func color(_ hex: UInt32) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WhisperLocalAssets", code: 1)
    }
    try pngData.write(to: url)
}

func drawText(_ text: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph,
    ]
    NSString(string: text).draw(in: rect, withAttributes: attributes)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1.0) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func makeBackground() -> NSImage {
    let size = NSSize(width: 760, height: 440)
    let image = NSImage(size: size)

    image.lockFocus()
    color(0xf7f8f5).setFill()
    NSRect(origin: .zero, size: size).fill()

    roundedRect(
        NSRect(x: 24, y: 24, width: 712, height: 392),
        radius: 28,
        fill: color(0xffffff),
        stroke: color(0xdfe4dc),
        lineWidth: 1.5
    )

    drawText(
        "Whisper Local",
        rect: NSRect(x: 90, y: 340, width: 580, height: 42),
        size: 30,
        weight: .bold,
        color: color(0x20241f)
    )
    drawText(
        "Перетащите приложение в Applications",
        rect: NSRect(x: 90, y: 308, width: 580, height: 28),
        size: 18,
        weight: .medium,
        color: color(0x667064)
    )
    drawText(
        "Первый запуск скачает модель Whisper и нужные пакеты",
        rect: NSRect(x: 90, y: 54, width: 580, height: 24),
        size: 14,
        weight: .regular,
        color: color(0x667064)
    )

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 285, y: 222))
    arrow.curve(
        to: NSPoint(x: 475, y: 222),
        controlPoint1: NSPoint(x: 345, y: 250),
        controlPoint2: NSPoint(x: 415, y: 250)
    )
    color(0x0f7c6b).setStroke()
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: 475, y: 222))
    arrowHead.line(to: NSPoint(x: 447, y: 240))
    arrowHead.line(to: NSPoint(x: 454, y: 222))
    arrowHead.line(to: NSPoint(x: 447, y: 204))
    arrowHead.close()
    color(0x0f7c6b).setFill()
    arrowHead.fill()

    drawText("1", rect: NSRect(x: 139, y: 160, width: 80, height: 24), size: 18, weight: .bold, color: color(0x0f7c6b))
    drawText("2", rect: NSRect(x: 539, y: 160, width: 80, height: 24), size: 18, weight: .bold, color: color(0x0f7c6b))

    image.unlockFocus()
    return image
}

func makeIcon(size: Int) -> NSImage {
    let dimension = CGFloat(size)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    let scale = dimension / 1024.0

    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    roundedRect(
        NSRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale),
        radius: 210 * scale,
        fill: color(0x0f7c6b),
        stroke: color(0xffffff).withAlphaComponent(0.7),
        lineWidth: 18 * scale
    )

    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: 230 * scale, y: 510 * scale))
    wave.curve(
        to: NSPoint(x: 794 * scale, y: 510 * scale),
        controlPoint1: NSPoint(x: 360 * scale, y: 690 * scale),
        controlPoint2: NSPoint(x: 650 * scale, y: 330 * scale)
    )
    NSColor.white.setStroke()
    wave.lineWidth = max(5, 64 * scale)
    wave.lineCapStyle = .round
    wave.stroke()

    drawText(
        "W",
        rect: NSRect(x: 210 * scale, y: 248 * scale, width: 604 * scale, height: 360 * scale),
        size: 330 * scale,
        weight: .bold,
        color: NSColor.white.withAlphaComponent(0.94)
    )

    image.unlockFocus()
    return image
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate_macos_assets.swift background <path> | iconset <dir>\n", stderr)
    exit(2)
}

let mode = arguments[1]
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    if mode == "background" {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try savePNG(makeBackground(), to: outputURL)
    } else if mode == "iconset" {
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
        let sizes = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]
        for (name, size) in sizes {
            try savePNG(makeIcon(size: size), to: outputURL.appendingPathComponent(name))
        }
    } else {
        fputs("Unknown mode: \(mode)\n", stderr)
        exit(2)
    }
} catch {
    fputs("Asset generation failed: \(error)\n", stderr)
    exit(1)
}
