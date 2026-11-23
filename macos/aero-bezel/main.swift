// AeroBezel — deux panneaux décoratifs « bezel d'arcade » de part et d'autre d'une fenêtre
// centrée en tiling AeroSpace (cf. macos/bin/aero-center). Une seule instance = 2 fenêtres.
// Priorité des décors (~/.config/aero-bezel/, .png/.jpg/.heic) :
//   1. wide.*        image panoramique « derrière » tout l'écran : chaque bezel en montre sa tranche,
//                    le centre est masqué par la fenêtre centrée (idéal : scène 21:9 / 32:9)
//   2. left.* / right.*  une image par panneau (côté = position réelle de la fenêtre)
//   3. décor synthwave dessiné en code
import AppKit

let home = FileManager.default.homeDirectoryForCurrentUser.path
let imageDir = ProcessInfo.processInfo.environment["AERO_BEZEL_DIR"] ?? "\(home)/.config/aero-bezel"

func customImage(_ side: String) -> NSImage? {
    for ext in ["png", "jpg", "jpeg", "heic"] {
        if let img = NSImage(contentsOfFile: "\(imageDir)/\(side).\(ext)") { return img }
    }
    return nil
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

final class BezelView: NSView {
    var blinkOn = true
    var images = (left: customImage("left"), right: customImage("right"))
    var wide = customImage("wide")
    private var imageStamp = BezelView.stamp()

    /// Date de modif du dossier d'images (ajout/remplacement de fichier) + de wide.*
    static func stamp() -> String {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(atPath: imageDir)) ?? []).sorted()
        return files.map { f -> String in
            let d = (try? fm.attributesOfItem(atPath: "\(imageDir)/\(f)"))?[.modificationDate] as? Date
            return "\(f)@\(d?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: ",")
    }

    /// Appelé par le timer : recharge les images si le dossier a changé (pas besoin de relancer).
    func reloadIfChanged() {
        let s = BezelView.stamp()
        guard s != imageStamp else { return }
        imageStamp = s
        images = (left: customImage("left"), right: customImage("right"))
        wide = customImage("wide")
    }

    var forcedSide: Bool?                          // snapshot : pas de fenêtre → côté imposé
    var forcedGeometry: (win: NSRect, screen: NSRect)?   // snapshot : frame fenêtre + visibleFrame écran

    var isLeft: Bool {
        if let f = forcedSide { return f }
        guard let win = window, let screen = win.screen else { return true }
        return win.frame.midX < screen.frame.midX
    }

    override func draw(_ dirty: NSRect) {
        rgb(0x000000).setFill(); bounds.fill()
        if let img = wide, let geo = forcedGeometry ?? currentGeometry {
            drawWide(img, geo)   // pas de scanlines : doit se fondre dans le fond d'écran
            return
        }
        if let img = isLeft ? images.left : images.right {
            drawAspectFill(img)
        } else {
            drawScene()
        }
        drawScanlines()
        drawVignette()
    }

    private var currentGeometry: (win: NSRect, screen: NSRect)? {
        guard let win = window, let screen = win.screen else { return nil }
        return (win.frame, screen.frame)   // frame entière : même cadrage que le fond d'écran « Remplir »
    }

    /// Image en aspect-fill sur tout l'écran (comme le fond d'écran macOS « Remplir l'écran »),
    /// décalée de la position de la fenêtre → wide.* = même fichier que le fond d'écran = raccord invisible.
    private func drawWide(_ img: NSImage, _ geo: (win: NSRect, screen: NSRect)) {
        let vf = geo.screen
        let s = max(vf.width / img.size.width, vf.height / img.size.height)
        let size = NSSize(width: img.size.width * s, height: img.size.height * s)
        let origin = NSPoint(x: vf.minX + (vf.width - size.width) / 2, y: vf.minY + (vf.height - size.height) / 2)
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: origin.x - geo.win.minX, y: origin.y - geo.win.minY,
                            width: size.width, height: size.height))
    }

    private func drawAspectFill(_ img: NSImage) {
        let s = max(bounds.width / img.size.width, bounds.height / img.size.height)
        let size = NSSize(width: img.size.width * s, height: img.size.height * s)
        img.draw(in: NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                            width: size.width, height: size.height))
    }

    private func drawScene() {
        let w = bounds.width, h = bounds.height
        let horizon = h * 0.40
        let cx = w / 2

        // Ciel
        NSGradient(colors: [rgb(0xff2e88), rgb(0x5b1a8a), rgb(0x1a0638), rgb(0x05010f)],
                   atLocations: [0, 0.18, 0.55, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(x: 0, y: horizon, width: w, height: h - horizon), angle: 90)

        // Étoiles pixel (pseudo-aléatoire déterministe, différent à gauche/droite)
        var seed: UInt64 = isLeft ? 0x9e3779b9 : 0x7f4a7c15
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        for _ in 0..<140 {
            let x = rnd() * w, y = horizon + h * 0.15 + rnd() * (h - horizon - h * 0.15)
            let sz: CGFloat = rnd() > 0.85 ? 3 : 2
            rgb(0xffffff, 0.35 + rnd() * 0.6).setFill()
            NSRect(x: x.rounded(), y: y.rounded(), width: sz, height: sz).fill()
        }

        // Soleil rayé
        let r = min(w * 0.36, h * 0.2)
        let sunCenter = NSPoint(x: cx, y: horizon + r * 0.55)
        let sunRect = NSRect(x: sunCenter.x - r, y: sunCenter.y - r, width: 2 * r, height: 2 * r)
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = rgb(0xff2e88, 0.9); glow.shadowBlurRadius = r * 0.6
        glow.set()
        rgb(0xff2e88, 0.25).setFill(); NSBezierPath(ovalIn: sunRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: sunRect).addClip()
        let bands = NSBezierPath(rect: NSRect(x: sunRect.minX, y: sunCenter.y, width: 2 * r, height: r))
        var y = sunCenter.y
        var gap: CGFloat = r * 0.03
        while y > sunRect.minY {
            let band = r * 0.13
            bands.appendRect(NSRect(x: sunRect.minX, y: y - band, width: 2 * r, height: band - gap))
            y -= band
            gap += r * 0.022
        }
        bands.addClip()
        NSGradient(colors: [rgb(0xff2975), rgb(0xff8c42), rgb(0xffd319)])!.draw(in: sunRect, angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Montagnes en silhouette
        let mountains = NSBezierPath()
        mountains.move(to: NSPoint(x: 0, y: horizon))
        let peaks: [(CGFloat, CGFloat)] = [(0.08, 0.10), (0.18, 0.04), (0.30, 0.13), (0.40, 0.03),
                                           (0.60, 0.03), (0.72, 0.15), (0.84, 0.05), (0.93, 0.11), (1.0, 0.06)]
        for (px, ph) in (isLeft ? peaks : peaks.reversed().map { (1 - $0.0, $0.1) }) { mountains.line(to: NSPoint(x: px * w, y: horizon + ph * h)) }
        mountains.line(to: NSPoint(x: w, y: horizon)); mountains.close()
        rgb(0x12052b).setFill(); mountains.fill()
        rgb(0x2de2e6, 0.6).setStroke(); mountains.lineWidth = 1.5; mountains.stroke()

        // Sol + grille en perspective
        rgb(0x0a0118).setFill(); NSRect(x: 0, y: 0, width: w, height: horizon).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: horizon)).addClip()
        let grid = NSBezierPath(); grid.lineWidth = 1.5
        for i in 1...14 {
            let t = CGFloat(i) / 14
            let gy = horizon - horizon * t * t
            grid.move(to: NSPoint(x: 0, y: gy)); grid.line(to: NSPoint(x: w, y: gy))
        }
        for k in -16...16 {
            grid.move(to: NSPoint(x: cx + CGFloat(k) * w * 0.035, y: horizon))
            grid.line(to: NSPoint(x: cx + CGFloat(k) * w * 0.45, y: 0))
        }
        let gridGlow = NSShadow(); gridGlow.shadowColor = rgb(0xff2e88); gridGlow.shadowBlurRadius = 6; gridGlow.set()
        rgb(0xff2e88, 0.85).setStroke(); grid.stroke()
        NSGraphicsContext.restoreGraphicsState()
        rgb(0xffd6f0).setFill(); NSRect(x: 0, y: horizon - 1, width: w, height: 2).fill()

        // Texte arcade
        let big = max(14, min(w * 0.075, 40))
        if isLeft {
            label("1UP", size: big * 0.7, color: rgb(0xff2e88), y: h - big * 2)
            label("004250", size: big * 0.7, color: rgb(0xffffff), y: h - big * 3)
            if blinkOn { label("INSERT COIN", size: big, color: rgb(0xffd319), y: horizon * 0.42) }
        } else {
            label("HI-SCORE", size: big * 0.7, color: rgb(0x2de2e6), y: h - big * 2)
            label("999990", size: big * 0.7, color: rgb(0xffffff), y: h - big * 3)
            label("CREDIT 0", size: big * 0.7, color: rgb(0xffd319), y: horizon * 0.42)
        }
    }

    private func label(_ text: String, size: CGFloat, color: NSColor, y: CGFloat) {
        let shadow = NSShadow(); shadow.shadowColor = color; shadow.shadowBlurRadius = size * 0.4
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .black),
            .foregroundColor: color, .shadow: shadow, .kern: size * 0.12,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        s.draw(at: NSPoint(x: (bounds.width - s.size().width) / 2, y: y))
    }

    private func drawScanlines() {
        rgb(0x000000, 0.22).setFill()
        var y: CGFloat = 0
        while y < bounds.height { NSRect(x: 0, y: y, width: bounds.width, height: 1).fill(); y += 3 }
    }

    private func drawVignette() {
        NSGradient(starting: rgb(0x000000, 0), ending: rgb(0x000000, 0.65))!
            .draw(in: bounds.insetBy(dx: -bounds.width * 0.25, dy: -bounds.height * 0.1),
                  relativeCenterPosition: .zero)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        for name in ["AeroBezel L", "AeroBezel R"] {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 900),
                               styleMask: [.titled, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
            win.title = name
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                win.standardWindowButton(b)?.isHidden = true
            }
            win.backgroundColor = .black
            win.isReleasedWhenClosed = false
            win.contentView = BezelView()
            win.orderFrontRegardless()
            windows.append(win)
        }
        Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            for w in self?.windows ?? [] {
                if let v = w.contentView as? BezelView { v.reloadIfChanged(); v.blinkOn.toggle(); v.needsDisplay = true }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

// AERO_BEZEL_SNAPSHOT=<dir> → rend left.png / right.png (960×1600) puis sort — aperçu sans fenêtre
if let dir = ProcessInfo.processInfo.environment["AERO_BEZEL_SNAPSHOT"] {
    // screen.png : écran 3840×1055 simulé, bezels 1/4 | fenêtre 2/4 | 1/4
    let screen = NSRect(x: 0, y: 0, width: 3840, height: 1055)
    let full = NSImage(size: screen.size)
    full.lockFocus()
    for (x, left) in [(CGFloat(0), true), (CGFloat(2880), false)] {
        let frame = NSRect(x: x, y: 0, width: 960, height: 1055)
        let v = BezelView(frame: NSRect(origin: .zero, size: frame.size))
        v.forcedSide = left; v.forcedGeometry = (frame, screen)
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        rep.draw(in: frame)
    }
    rgb(0x1e1e2e).setFill(); NSRect(x: 960, y: 0, width: 1920, height: 1055).fill()
    full.unlockFocus()
    let fullRep = NSBitmapImageRep(data: full.tiffRepresentation!)!
    try! fullRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/screen.png"))
    for (name, left) in [("left", true), ("right", false)] {
        let v = BezelView(frame: NSRect(x: 0, y: 0, width: 960, height: 1600))
        v.forcedSide = left
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
