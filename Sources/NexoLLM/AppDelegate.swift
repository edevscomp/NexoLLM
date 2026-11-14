import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let engine = LLMEngine()
    private lazy var controller = CompletionController(engine: engine)
    private var settings: Settings { Settings.shared }
    private var statusItem: NSStatusItem?
    private let iconAnimator = MenuBarAnimator()
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var unloadWork: DispatchWorkItem?
    private var engineState: LLMEngine.State = .idle
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()   // ⌘Q, ⌘W and ⌘C/⌘V/⌘A/⌘Z in our own window
        CrashReporter.shared.install()    // before Log.reset() so a previous crash report keeps the log tail
        Log.reset()
        _ = NetworkMonitor.shared

        // One-time migrations before loading the model.
        if !UserDefaults.standard.bool(forKey: "migrated.screenContext") {
            UserDefaults.standard.set(true, forKey: "migrated.screenContext")
            settings.prefs.screenMode = .smart
        }
        if !UserDefaults.standard.bool(forKey: "migrated.dualModelE4BE2B") {
            UserDefaults.standard.set(true, forKey: "migrated.dualModelE4BE2B")
            if FileManager.default.fileExists(atPath: Settings.e4bModelPath) {
                settings.prefs.modelPath = Settings.e4bModelPath
            }
            if FileManager.default.fileExists(atPath: Settings.e2bModelPath) {
                settings.prefs.batteryModelPath = Settings.e2bModelPath
            }
            settings.prefs.modelMode = .automatic
        }
        if !UserDefaults.standard.bool(forKey: "migrated.ownModelsFolder") {
            UserDefaults.standard.set(true, forKey: "migrated.ownModelsFolder")
            let moved = settings.adoptExternalModels()
            if !moved.isEmpty { Log.info("models: moved into NexoLLM's folder: \(moved.joined(separator: ", "))") }
        }
        if !UserDefaults.standard.bool(forKey: "migrated.cleanItalianInstructionsV2") {
            UserDefaults.standard.set(true, forKey: "migrated.cleanItalianInstructionsV2")
            if settings.prefs.customInstructions.contains("exagerate") || settings.prefs.customInstructions.contains("18 anni") {
                settings.prefs.customInstructions = Prefs.defaultInstructions
            }
        }

        // Plug/unplug: event-driven (no polling). Switch model automatically if the rule says so.
        Power.startMonitoring()
        NotificationCenter.default.addObserver(forName: Power.changed, object: nil, queue: .main) { [weak self] _ in
            Log.info("power: \(Power.onBattery ? "battery" : "plugged in")")
            self?.applyModelRule()
        }

        Log.info("launch: bundle=\(Bundle.main.bundlePath) model=\(settings.effectiveModelPath) onBattery=\(Power.onBattery)")

        // Screen locked or Mac asleep: save, then drop the decryption key from memory until it's needed again.
        // Screen locked or Mac asleep: Audio Context stops too (and wipes what it heard).
        let lockData: (Notification) -> Void = { [weak self] _ in
            Memory.shared.flush(); History.shared.flush(); History.lockKeyInMemory()
            if Settings.shared.prefs.micContextEnabled { Settings.shared.prefs.micContextEnabled = false }
            MainActor.assumeIsolated { self?.iconAnimator.stop() }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"),
                                                            object: nil, queue: .main, using: lockData)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                                                          queue: .main, using: lockData)

        engine.onStateChange = { [weak self] state in
            guard let self else { return }
            self.engineState = state
            self.updateIcon()
            Log.info("engine: \(state)")
            MainActor.assumeIsolated { self.refreshEngineStatus() }
            CrashReporter.shared.note(engine: AppStatus.shared.engine)
        }
        // While a model downloads, the status says so (with progress) instead of "no model".
        ModelManager.shared.$downloads
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshEngineStatus(); self?.updateIcon() } } }
            .store(in: &cancellables)
        Settings.removeLegacyCloudKeysOnce()
        reloadModel()

        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        controller.onStatsChange = { [weak self] in
            MainActor.assumeIsolated {
                self?.updateIcon()
                self?.iconAnimator.pulseAccept()
            }
        }
        controller.onStatusChange = { [weak self] in self?.updateIcon() }
        controller.onRestart = { [weak self] in self?.restartServices() }
        ScreenContext.shared.onStateChange = { [weak self] in self?.updateIcon() }
        AudioContext.shared.addListener { [weak self] in
            guard let self else { return }
            // While listening, the menu bar icon is always visible, even if the user chose to hide it.
            self.setMenuBarIcon(visible: self.settings.prefs.showMenuBarIcon || AudioContext.shared.isListening)
            self.updateIcon()
        }

        controller.onActivity = { [weak self] in self?.scheduleIdleUnload(); AudioContext.shared.noteUserActivity() }
        controller.onNeedModel = { [weak self] in self?.wakeModel() }
        controller.onEngineFailure = { [weak self] in self?.reloadModel() }

        // React to settings changes (menu bar icon, global toggle, model choice, logging).
        settings.$prefs
            .map { ($0.showMenuBarIcon, $0.globallyDisabled) }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] show, _ in self?.setMenuBarIcon(visible: show || AudioContext.shared.isListening); self?.updateIcon() }
            .store(in: &cancellables)
        settings.$prefs
            .map { [$0.modelPath, $0.batteryModelPath, $0.modelMode.rawValue] }
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyModelRule(explicit: true) }
            .store(in: &cancellables)
        settings.$prefs
            .map(\.unloadAfterMinutes)
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleIdleUnload() }
            .store(in: &cancellables)
        settings.$prefs
            .map(\.appearance)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { mode in
                NSApp.appearance = mode == .system ? nil : NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
            }
            .store(in: &cancellables)
        settings.$prefs
            .map(\.memoryDays)
            .removeDuplicates()
            .sink { days in
                Memory.shared.forgetAfter = TimeInterval(max(1, days)) * 86_400
                Memory.shared.prune()
            }
            .store(in: &cancellables)
        settings.$prefs
            .map(\.debugLogging)
            .removeDuplicates()
            .sink { Log.verbose = $0 || CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--debug") }
            .store(in: &cancellables)
        settings.$prefs
            .map { ($0.micContextEnabled, $0.exampleLanguage, $0.screenMode) }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] on, _, _ in
                AudioContext.shared.setEnabled(on)
                if let self { NSApp.mainMenu = self.makeMainMenu() }
                self?.updateIcon()
            }
            .store(in: &cancellables)

        let trusted = AX.isTrusted(prompt: true)
        Log.info("accessibility trusted: \(trusted)")
        tryStartTap()

        let screenOK = CGPreflightScreenCaptureAccess()
        Log.info("screen recording granted: \(screenOK)")
        if settings.prefs.screenMode == .smart, !screenOK { _ = CGRequestScreenCaptureAccess() }

        // Learn the writing style from the history shortly after launch (background, once).
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.settings.prefs.learnStyle, self.settings.prefs.recordWriting else { return }
            StyleProfile.shared.refreshIfNeeded(force: true)
        }

        if !trusted { openSettings() }

        Updater.shared.start()
        let updated = WhatsNew.consumeLaunchFlag()
        if !UserDefaults.standard.bool(forKey: WalkthroughState.shownKey) {   // until finished or skipped: the tour
            ModalCenter.shared.current = .walkthrough
            openSettings()
        } else if CrashReporter.shared.pendingReport != nil {
            ModalCenter.shared.current = .crashReport
            openSettings()
        } else if updated {   // first launch after an update: show what changed
            ModalCenter.shared.current = .whatsNew
            openSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()   // e.g. when the menu bar icon is hidden
        return true
    }

    /// Status line for the engine (English internally; `Fmt.status` translates it). A download in progress
    /// wins over "no model" / "loading", so a fresh install never looks broken while its first model arrives.
    static func statusText(_ state: LLMEngine.State, downloads: [(name: String, download: ModelManager.Download)]) -> (text: String, ready: Bool) {
        switch state {
        case .ready(let name): return ("Ready · \(name)", true)
        case .unloaded(let name): return ("Sleeping · \(name) (freed to save memory)", true)
        default: break
        }
        if let (name, d) = downloads.first {
            if d.verifying { return ("Verifying \(name)…", false) }
            var t = "Downloading \(name) · \(Int((d.fraction * 100).rounded()))%"
            if d.bytesPerSecond > 0 { t += " · " + Fmt.bytes(Int64(d.bytesPerSecond)) + "/s" }
            return (t, false)
        }
        switch state {
        case .idle: return ("Starting…", false)
        case .loading: return ("Loading model…", false)
        case .noModel: return ("No model installed · download one in Models", false)
        case .failed(let msg): return ("Error: \(msg)", false)
        case .ready, .unloaded: return ("", true)
        }
    }

    @MainActor private func refreshEngineStatus() {
        let mgr = ModelManager.shared
        let active = mgr.downloads.compactMap { id, d in CatalogModel.all.first { $0.id == id }.map { (name: $0.name, download: d) } }
        let s = Self.statusText(engineState, downloads: active)
        if AppStatus.shared.engine != s.text { AppStatus.shared.engine = s.text }
        if AppStatus.shared.modelReady != s.ready { AppStatus.shared.modelReady = s.ready }
    }

    private func reloadModel() {
        controller.invalidate()
        engine.load(path: settings.effectiveModelPath) { [weak self] in
            self?.controller.modelDidLoad()
            self?.scheduleIdleUnload()
        }
    }

    func restartServices() {
        Log.info("service: soft restart requested")
        controller.softRestart()
        reloadModel()
        updateIcon()
    }

    /// Loads the model the current rule asks for, if it isn't the one in memory (only one is ever loaded).
    private func applyModelRule(explicit: Bool = false) {
        let wanted = settings.effectiveModelPath
        guard wanted != engine.modelPath else { return }
        if !explicit, !wanted.isEmpty, case .unloaded = engine.state { return }   // will load the right one on wake
        Log.info("model: switching to \((wanted as NSString).lastPathComponent)")
        reloadModel()
    }

    /// Frees the model after the configured idle time; reloaded on the next keystroke.
    private func scheduleIdleUnload() {
        unloadWork?.cancel()
        let minutes = settings.prefs.unloadAfterMinutes
        guard minutes > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            Log.info("model: unloading after \(minutes) idle minutes")
            self?.engine.unload()
        }
        unloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: work)
    }

    private func wakeModel() {
        if case .loading = engine.state { return }
        reloadModel()
    }

    /// Retries until Accessibility is granted and the event tap is created.
    private func tryStartTap() {
        if AX.isTrusted(prompt: false), controller.startTap() {
            Log.info("tap: started")
            permissionTimer?.invalidate()
            permissionTimer = nil
            updateIcon()
            #if DEBUG || NEXO_DEV
            if CommandLine.arguments.contains("--probe") { startProbe() }
            #endif
            return
        }
        if permissionTimer == nil {
            Log.info("tap: waiting for permission")
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                self?.tryStartTap()
            }
        }
    }

    #if DEBUG || NEXO_DEV
    private func startProbe() {
        for i in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) {
                if i == 2, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    let c = AX.currentContext()
                    ScreenContext.shared.capture(key: "probe-\(pid)", pid: pid, fieldAX: c?.fieldFrame,
                                                 caretAX: c?.caretRect ?? CGRect(x: 0, y: 2000, width: 0, height: 10),
                                                 caret: c?.caretLocation ?? 0, reason: .firstLook) { text, _ in
                        Log.write("probe: SCREEN \(String(reflecting: String(text.prefix(500))))")
                    }
                }
                if let c = AX.currentContext() {
                    if i == 1 { Log.write("probe: DUMP \(AX.dump(c.element, loc: c.caretLocation))") }
                    Log.write("probe: OK \(c.appName) loc=\(c.caretLocation) caret=\(c.caretRect) lineEnd=\(c.atLineEnd) field=\(c.fieldFrame.map { "\($0)" } ?? "nil")")
                } else {
                    Log.write("probe: FAIL \(AX.lastFailure)")
                }
            }
        }
    }
    #endif

    // MARK: Menu bar

    private func setMenuBarIcon(visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            MainActor.assumeIsolated { iconAnimator.attach(item.button) }
            updateIcon()
        } else if !visible, let item = statusItem {
            MainActor.assumeIsolated { iconAnimator.attach(nil) }
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// The menu bar icon is our custom NexoLLM mark, with a distinct variant and smooth micro-animation per status.
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let state: MenuBarIcon.State
        var dimmed = false
        let ready = { if case .ready = engineState { return true }; if case .unloaded = engineState { return true }; return false }()
        if case .failed = engineState {
            state = .error
        } else if !ready {
            state = .loading
        } else if ScreenContext.shared.inFlight {
            state = .readingScreen
        } else if AudioContext.shared.isListening {
            state = .reading
        } else if settings.prefs.globallyDisabled || !controller.isTapRunning {
            state = .off; dimmed = true
        } else if !controller.isActiveInFrontApp {
            state = .paused
        } else if settings.prefs.screenMode == .smart {
            state = .smartScreen
        } else {
            state = .active
        }
        MainActor.assumeIsolated {
            iconAnimator.attach(button)
            iconAnimator.setState(state, dimmed: dimmed)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = controller.isTapRunning || !AX.isTrusted(prompt: false) ? AppStatus.shared.engine : "Starting"
        controller.menuItems(status: status, accessibilityMissing: !AX.isTrusted(prompt: false),
                             openAccessibility: { [weak self] in self?.openAccessibility() },
                             dismissMenu: { [weak menu] in menu?.cancelTracking() }, quit: true)
            .forEach(menu.addItem)
    }

    // MARK: Main menu

    /// App, Edit and Window menus: shown while the window is open, and the source of the standard shortcuts.
    private func makeMainMenu() -> NSMenu {
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = m
            return top
        }
        let main = NSMenu()
        main.addItem(menu(Brand.name, [
            ClosureMenuItem(L("About \(Brand.name)", "Informazioni su \(Brand.name)")) { [weak self] in self?.openSettings() },
            .separator(),
            item(L("Hide \(Brand.name)", "Nascondi \(Brand.name)"), #selector(NSApplication.hide(_:)), "h"),
            item(L("Hide Others", "Nascondi altre"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item(L("Quit \(Brand.name)", "Esci da \(Brand.name)"), #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(menu(L("Edit", "Modifica"), [
            item(L("Undo", "Annulla"), Selector(("undo:")), "z"),
            item(L("Redo", "Ripeti"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(L("Cut", "Taglia"), #selector(NSText.cut(_:)), "x"),
            item(L("Copy", "Copia"), #selector(NSText.copy(_:)), "c"),
            item(L("Paste", "Incolla"), #selector(NSText.paste(_:)), "v"),
            item(L("Select All", "Seleziona tutto"), #selector(NSText.selectAll(_:)), "a"),
        ]))
        main.addItem(menu(L("Window", "Finestra"), [
            item(L("Close Window", "Chiudi finestra"), #selector(NSWindow.performClose(_:)), "w"),
            item(L("Minimize", "Riduci a icona"), #selector(NSWindow.performMiniaturize(_:)), "m"),
        ]))
        return main
    }

    // MARK: Actions

    private func openAccessibility() {
        _ = AX.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func openSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                openAccessibilitySettings: { [weak self] in self?.openAccessibility() },
                requestScreenRecording: { [weak self] in self?.requestScreenRecording() },
                restartServices: { [weak self] in self?.restartServices() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsRootView(actions: actions)))
            w.title = Brand.name
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.collectionBehavior = [.fullScreenPrimary]
            w.isMovableByWindowBackground = false
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden   // the brand lives in the sidebar
            w.setContentSize(NSSize(width: 980, height: 700))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)   // menu bar + ⌘Q while the window is open
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        WindowState.shared.isFullScreen = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        WindowState.shared.isFullScreen = false
    }

    /// Destroy the Settings window on close so none of its views/timers keep running in the background.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        ModalCenter.shared.current = nil
        WindowState.shared.isFullScreen = false
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow?.contentViewController = nil
            self?.settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)   // back to a menu bar app, no Dock icon
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { iconAnimator.stop() }
        CrashReporter.shared.markCleanExit()
        controller.commitMemoryBurst(sync: true)
        Settings.shared.flush()
        Memory.shared.flush()
        History.shared.flush()
        Stats.shared.flush()
        AudioContext.shared.shutdown()
        engine.shutdown()
    }
}
