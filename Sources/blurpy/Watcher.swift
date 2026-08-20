import Foundation

/// One transcript root to tail. We only ever tail the single most-recently-modified
/// .jsonl under each root — that's the active session.
struct TailSource: Sendable {
    let harness: String
    let root: String
}

enum Tail {
    /// Newest *.jsonl under root (recursive), by modification date.
    static func newestJSONL(in root: String, fm: FileManager = .default) -> String? {
        guard let e = fm.enumerator(atPath: fm.homeDirectoryForCurrentUser.appendingPathComponent(root).path) else { return nil }
        var best: (path: String, date: Date)?
        for case let file as String in e where file.hasSuffix(".jsonl") {
            let full = fm.homeDirectoryForCurrentUser.appendingPathComponent(root).appendingPathComponent(file).path
            guard let mtime = try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date else { continue }
            if best == nil || mtime > best!.date { best = (full, mtime) }
        }
        return best?.path
    }

    static func size(path: String) -> UInt64 {
        guard let fh = FileHandle(forReadingAtPath: path), let size = try? fh.seekToEnd() else { return 0 }
        try? fh.close()
        return size
    }

    /// Read new bytes since `offset`, capped at `cap` bytes (taken from the tail of the gap).
    /// Returns the text and the new offset.
    static func readNew(path: String, offset: UInt64, cap: Int = 8192) -> (text: String, newOffset: UInt64) {
        guard let fh = FileHandle(forReadingAtPath: path),
              let size = try? fh.seekToEnd() as UInt64, size > offset else {
            return ("", offset)
        }
        let gap = size - offset
        let start = gap > UInt64(cap) ? size - UInt64(cap) : offset
        fh.seek(toFileOffset: start)
        let data = fh.readDataToEndOfFile()
        try? fh.close()
        return (String(decoding: data, as: UTF8.self), size)
    }
}

/// Polls all sources on a timer, accumulates new text per harness, and flushes
/// to the classifier after `idleSeconds` of quiet.
@MainActor
final class Watcher {
    let sources: [TailSource] = [
        .init(harness: "Claude Code", root: ".claude/projects"),
        .init(harness: "Codex", root: ".codex/sessions"),
        .init(harness: "pi", root: ".pi/agent/sessions"),
    ]

    var onFlush: ((String, String) -> Void)?
    var onDevin: (() -> Void)?

    private var offsets: [String: UInt64] = [:]   // file path -> offset
    private var active: [String: String] = [:]    // harness -> file path
    private var pending: [String: String] = [:]   // harness -> accumulated text
    private var lastAppend: [String: Date] = [:]  // harness -> last append time
    private var timer: Timer?

    private let pollSeconds: TimeInterval = 5
    private let idleSeconds: TimeInterval = 15
    private let minChars = 200

    func start() {
        // Start at EOF so old transcript history cannot retrigger on launch.
        for s in sources {
            if let newest = Tail.newestJSONL(in: s.root) {
                active[s.harness] = newest
                offsets[newest] = Tail.size(path: newest)
                print("[blurpy] \(s.harness) active file: \(URL(fileURLWithPath: newest).lastPathComponent)")
            }
            print("[blurpy] watching \(s.harness): ~/\(s.root)")
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        for s in sources {
            guard let newest = Tail.newestJSONL(in: s.root) else { continue }
            if active[s.harness] != newest {
                active[s.harness] = newest
                offsets[newest] = offsets[newest] ?? 0
                print("[blurpy] \(s.harness) active file: \(URL(fileURLWithPath: newest).lastPathComponent)")
            }
            let r = Tail.readNew(path: newest, offset: offsets[newest] ?? 0)
            offsets[newest] = r.newOffset
            if !r.text.isEmpty {
                if Nedry.matches(r.text) {
                    print("[blurpy] devin detected in \(s.harness)")
                    onDevin?()
                }
                pending[s.harness, default: ""] += r.text
                lastAppend[s.harness] = Date()
            }
        }
        for (harness, text) in pending
        where text.count >= minChars && Date().timeIntervalSince(lastAppend[harness] ?? .distantPast) >= idleSeconds {
            print("[blurpy] flushing \(text.count) chars from \(harness)")
            onFlush?(harness, String(text.suffix(6000)))
            pending.removeValue(forKey: harness)
        }
    }
}
