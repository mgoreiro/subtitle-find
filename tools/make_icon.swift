// Genera Resources/AppIcon.icns dibujando el icono con AppKit.
// Uso: swift tools/make_icon.swift
import AppKit

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: a)
    }

    // Base: squircle de macOS con degradado.
    let base = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    ctx.saveGState()
    let sh = NSShadow()
    sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
    sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -10)
    sh.set()
    rgb(0x4F46E5).setFill(); base.fill()
    ctx.restoreGState()
    ctx.saveGState()
    base.addClip()
    NSGradient(colors: [rgb(0x22D3EE), rgb(0x4F46E5), rgb(0x7C3AED)], atLocations: [0, 0.55, 1],
               colorSpace: .sRGB)!.draw(in: base.bounds, angle: -50)
    // Brillo suave arriba.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), .clear])!
        .draw(in: NSRect(x: 100, y: 520, width: 824, height: 404), angle: -90)
    ctx.restoreGState()

    // "Pantalla" de vídeo.
    let screen = NSBezierPath(roundedRect: NSRect(x: 210, y: 380, width: 604, height: 400), xRadius: 56, yRadius: 56)
    ctx.saveGState()
    let sh2 = NSShadow()
    sh2.shadowColor = NSColor.black.withAlphaComponent(0.3)
    sh2.shadowBlurRadius = 30; sh2.shadowOffset = NSSize(width: 0, height: -14)
    sh2.set()
    rgb(0x0F172A).setFill(); screen.fill()
    ctx.restoreGState()
    rgb(0xFFFFFF, 0.18).setStroke(); screen.lineWidth = 6; screen.stroke()

    // Botón de play tenue en el centro de la pantalla.
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 470, y: 640)); play.line(to: NSPoint(x: 470, y: 520)); play.line(to: NSPoint(x: 575, y: 580))
    play.close()
    rgb(0xFFFFFF, 0.22).setFill(); play.fill()

    // Dos líneas de subtítulo.
    for (x, y, w) in [(CGFloat(290), CGFloat(468), CGFloat(444)), (CGFloat(350), CGFloat(412), CGFloat(180))] {
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: 30), xRadius: 15, yRadius: 15)
        rgb(0xFDE047).setFill(); bar.fill()
    }

    // Lupa.
    let ring = NSBezierPath(ovalIn: NSRect(x: 560, y: 190, width: 250, height: 250))
    ctx.saveGState()
    let sh3 = NSShadow()
    sh3.shadowColor = NSColor.black.withAlphaComponent(0.4)
    sh3.shadowBlurRadius = 22; sh3.shadowOffset = NSSize(width: 0, height: -10)
    sh3.set()
    rgb(0xFFFFFF, 0.28).setFill(); ring.fill()
    ring.lineWidth = 36; rgb(0xF8FAFC).setStroke(); ring.stroke()
    ctx.restoreGState()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 600, y: 232)); handle.line(to: NSPoint(x: 520, y: 152))
    handle.lineWidth = 52; handle.lineCapStyle = .round
    rgb(0xF8FAFC).setStroke(); handle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let set = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: set.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: set.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", "Resources/AppIcon.icns"]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
try render(1024).write(to: URL(fileURLWithPath: "docs/icon.png"))
print("OK")
