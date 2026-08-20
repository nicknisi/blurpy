import Cocoa

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let watcher = Watcher()
    private let popup = Popup()
    private var memory: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        let brain: Brain
        if let envKey, !envKey.isEmpty {
            brain = .api(envKey)
        } else if let claudePath = Classifier.whichClaude() {
            brain = .cli(claudePath)
        } else {
            brain = .none
        }
        switch brain {
        case .api: print("[blurpy] brain: ANTHROPIC_API_KEY")
        case .cli(let p): print("[blurpy] brain: claude -p (\(p))")
        case .none: print("[blurpy] no brain — LLM pitches off, nedry gag still armed")
        }
        guard let sheet = PitchSheet.load() else {
            print("[blurpy] FATAL: pitches.json missing or malformed")
            NSApp.terminate(nil)
            return
        }
        watcher.onDevin = { [weak self] in
            self?.popup.showNedry(Nedry.caption())
        }
        watcher.onFlush = { [weak self] harness, chunk in
            Task { @MainActor in
                guard let self else { return }
                let pitch: Pitch?
                switch brain {
                case .api(let key):
                    pitch = await Classifier.classify(harness: harness, chunk: chunk, sheet: sheet, memory: self.memory, apiKey: key)
                case .cli(let claudePath):
                    pitch = await Classifier.classifyViaCLI(harness: harness, chunk: chunk, sheet: sheet, memory: self.memory, claudePath: claudePath)
                case .none:
                    pitch = nil
                }
                if let pitch {
                    self.memory.append(pitch.message)
                    if self.memory.count > 8 { self.memory.removeFirst() }
                    self.popup.show(pitch)
                }
            }
        }
        watcher.start()
        print("[blurpy] alive. he is always here.")
    }
}

setbuf(stdout, nil)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
