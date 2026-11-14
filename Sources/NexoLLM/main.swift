import AppKit

#if DEBUG || NEXO_DEV
// `NexoLLM --selftest [model.gguf]` : headless engine check with timings.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--selftest" {
    let path = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : Settings.shared.prefs.modelPath
    SelfTest.run(modelPath: path)
    exit(0)
}

// `NexoLLM --render-ui <dir> [light]` : renders the UI to PNG files for design review.
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--render-ui" {
    UIRender.run(outDir: CommandLine.arguments[2], dark: !CommandLine.arguments.contains("light"))
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
