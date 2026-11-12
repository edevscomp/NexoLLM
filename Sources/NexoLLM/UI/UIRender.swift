import AppKit
import SwiftUI

/// `NexoLLM --render-ui <dir> [dark|light]`: renders every Settings pane, the floating overlays, README glass
/// panels and (when `NEXO_DEMO_FRAMES` is set) the animated live loop frames to 2x PNG from inside the process.
enum UIRender {
    static func run(outDir: String, dark: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        Settings.shared.savingEnabled = false
        for arg in CommandLine.arguments.dropFirst(3) {
            if let lang = ExampleLanguage.allCases.first(where: { $0.iso == arg.lowercased() || $0.rawValue == arg.lowercased() }) {
                Settings.shared.prefs.exampleLanguage = lang
            }
        }
        do {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let sample: [(Int, [String: Int], Int)] = [
                (6, ["com.apple.Notes": 95, "com.apple.mail": 64, "com.apple.MobileSMS": 38], 42),
                (5, ["com.apple.mail": 122, "com.apple.Notes": 84, "com.google.Chrome": 45], 58),
                (4, ["com.apple.Notes": 148, "com.google.Chrome": 72, "com.apple.mail": 52, "com.apple.MobileSMS": 28], 71),
                (3, ["com.apple.mail": 90, "com.apple.Notes": 68, "com.apple.MobileSMS": 24], 37),
                (2, ["com.apple.Notes": 152, "com.apple.mail": 104, "com.google.Chrome": 54, "com.apple.MobileSMS": 26], 84),
                (1, ["com.apple.mail": 136, "com.apple.Notes": 92, "com.google.Chrome": 58], 66),
                (0, ["com.apple.Notes": 118, "com.apple.mail": 74, "com.google.Chrome": 46, "com.apple.MobileSMS": 22], 54),
            ]
            var previewDays: [String: Stats.Day] = [:]
            var previewPerApp: [String: Int] = [:]
            for (offset, byApp, comp) in sample {
                if let d = cal.date(byAdding: .day, value: -offset, to: today) {
                    let total = byApp.values.reduce(0, +)
                    previewDays[Stats.dayFormatter.string(from: d)] = Stats.Day(words: total, completions: comp, byApp: byApp)
                    for (k, v) in byApp { previewPerApp[k, default: 0] += v }
                }
            }
            Stats.shared.loadPreview(previewDays, perApp: previewPerApp)
        }
        let actions = SettingsActions(reloadModel: {}, openAccessibilitySettings: {}, requestScreenRecording: {}, revealModels: {})
        AppStatus.shared.engine = "Ready · gemma-4-E4B.i1-Q4_K_M.gguf"
        AppStatus.shared.modelReady = true
        let theme = dark ? "dark" : "light"

        // If NEXO_DEMO_ONLY=1, render only the 90-frame live animation + frosted panels for scripts/readme-media.sh
        if let nStr = ProcessInfo.processInfo.environment["NEXO_DEMO_FRAMES"], let total = Int(nStr), total > 0 {
            let demoSize = NSSize(width: 760, height: 325)
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -6000, y: -6000), size: demoSize),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            let host = NSHostingView(rootView: LiveDemoScene(frame: 0).frame(width: demoSize.width, height: demoSize.height))
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            for i in 0..<total {
                host.rootView = LiveDemoScene(frame: i).frame(width: demoSize.width, height: demoSize.height)
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let name = String(format: "%@/demo-%03d.png", outDir, i)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
                }
            }
            window.orderOut(nil)
        }

        // Frosted RGBA panels for wallpaper compositing (scripts/readme_media.py)
        render(FrostedPanelSurface(title: "Mail — Launch plan, final draft", badge: "Tab · next word") {
            HeroScene(showAlternatives: false, translucent: true)
        }, size: NSSize(width: 740, height: 270), to: "\(outDir)/glass-hero-\(theme).png")

        render(FrostedPanelSurface(title: "Mail — Launch plan, final draft", badge: "⌥Tab · alternatives") {
            HeroScene(showAlternatives: true, translucent: true)
        }, size: NSSize(width: 740, height: 430), to: "\(outDir)/glass-alternatives-\(theme).png")

        render(FrostedPanelSurface(title: "Notes — Weekly update", badge: "⌃⌥M · quick menu") {
            QuickMenuScene(translucent: true)
        }, size: NSSize(width: 740, height: 575), to: "\(outDir)/glass-quickmenu-\(theme).png")

        render(FrostedPanelSurface(title: "Article — Moving on", badge: "⌃⌥L · web lookup") {
            LookupScene(translucent: true)
        }, size: NSSize(width: 740, height: 470), to: "\(outDir)/glass-lookup-\(theme).png")

        StackedPastelHistogram.previewHoverBucketIndex = 2
        for pane in SettingsPane.allCases {
            let h: CGFloat = pane == .statistics ? 790 : 720
            render(SettingsRootView(actions: actions, initial: pane), size: NSSize(width: 980, height: h),
                   to: "\(outDir)/pane-\(pane.rawValue)-\(theme).png")
        }
        StackedPastelHistogram.previewHoverBucketIndex = nil

        if ProcessInfo.processInfo.environment["NEXO_FAST_MEDIA"] == "1" {
            exit(0)
        }

        let settingsSize = CGSize(width: 900, height: 760)
        for pane in [SettingsPane.setup, .models, .personalization, .context] {
            render(ShowcaseFrame(size: settingsSize) { SettingsRootView(actions: actions, initial: pane) },
                   size: frameSize(settingsSize), to: "\(outDir)/settings-\(pane.rawValue)-\(theme).png")
        }
        let mail = CGSize(width: 760, height: 290)
        render(ShowcaseFrame(size: mail, title: "Launch plan, final draft") { HeroScene() },
               size: frameSize(mail), to: "\(outDir)/hero-\(theme).png")
        render(ShowcaseFrame(size: CGSize(width: 760, height: 420), title: "Launch plan, final draft") { HeroScene(showAlternatives: true) },
               size: frameSize(CGSize(width: 760, height: 420)), to: "\(outDir)/alternatives-\(theme).png")
        let scene = CGSize(width: 760, height: 520)
        let menuScene = CGSize(width: 760, height: 580)
        render(ShowcaseFrame(size: menuScene, title: "Notes") { QuickMenuScene() }, size: frameSize(menuScene), to: "\(outDir)/quickmenu-\(theme).png")
        render(ShowcaseFrame(size: scene, title: "Article") { LookupScene() }, size: frameSize(scene), to: "\(outDir)/lookup-\(theme).png")
        render(OverlayGallery(), size: NSSize(width: 640, height: 400), to: "\(outDir)/overlays-\(theme).png")
        for step in 0..<WalkthroughState.stepCount {
            render(WalkthroughCard(previewStep: step).frame(width: 620).fixedSize(horizontal: false, vertical: true).padding(26)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
                    .tint(Theme.accent).buttonStyle(GlassButtonStyle()).padding(30),
                   size: NSSize(width: 732, height: 720), to: "\(outDir)/tour-\(step + 1)-\(theme).png")
        }
        exit(0)
    }

    private static func frameSize(_ s: CGSize) -> NSSize { NSSize(width: s.width + 140, height: s.height + 140) }

    private static func render<V: View>(_ view: V, size: NSSize, to path: String) {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -6000, y: -6000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        window.orderOut(nil)
    }
}
