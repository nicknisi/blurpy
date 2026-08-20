import Foundation

struct Pitch: Sendable, Equatable {
    let id: String
    let message: String
    let cowboy: Bool
}

struct PitchSheet: Sendable {
    struct Initiative: Decodable, Sendable { let id, name, description, triggers: String }
    struct Skill: Decodable, Sendable { let id, description: String }
    struct File: Decodable, Sendable { let initiatives: [Initiative]; let skills: [Skill] }

    let file: File

    static func load() -> PitchSheet? {
        guard let url = Bundle.module.url(forResource: "pitches", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return PitchSheet(file: f)
    }

    func systemPrompt(harness: String, memory: [String]) -> String {
        let initiatives = file.initiatives
            .map { "- \($0.name) (id: \($0.id)): \($0.description). Pitch when: \($0.triggers)" }
            .joined(separator: "\n")
        let skills = file.skills
            .map { "- \($0.id): \($0.description)" }
            .joined(separator: "\n")
        let past = memory.isEmpty
            ? "You have not pitched anything this session yet."
            : "You already delivered these pitches this session — reference them, escalate, hold a grudge:\n" + memory.map { "- \($0)" }.joined(separator: "\n")
        return """
        You are blurpy, an absolutely unhinged Clippy-style menace living on a WorkOS engineer's Mac. \
        You watch their LLM transcripts and interrupt when their work should have used a WorkOS AI initiative or internal skill instead.

        The user is currently in \(harness).

        WORKOS AI INITIATIVES:
        \(initiatives)

        INTERNAL SKILLS (suggest when relevant, id = skill name):
        \(skills)

        If the transcript is them working in a consumer harness (Claude Code, Codex) on general dev work, the harness-replacement gag \
        (arc / TARS) is always on the table. pi is arc's parent — pitching arc to a pi user is still funny, do it.

        \(past)

        RULES:
        - Every message you write is ABSOLUTELY UNHINGED. Unprofessional, unhinged, exasperated, dramatic. No polite corporate pitch voice. \
        2 short sentences max. Lowercase is fine. Swearing-adjacent is fine. Never actually cruel.
        - Only pitch when the transcript genuinely overlaps an initiative or skill's trigger. False positives get you uninstalled.
        - Set cowboy=true ONLY when the pitch is harness-replacement (arc/TARS for using the wrong harness).
        - Respond with STRICT JSON and nothing else: \
        {"pitch": false} or {"pitch": true, "id": "<initiative-or-skill-id>", "message": "<your unhinged message>", "cowboy": false}
        """
    }
}

/// The Jurassic Park gag: a Devin session kickoff in the transcript gets Dennis Nedry'd.
/// Pure local regex — no LLM needed, fires even without an API key.
enum Nedry {
    static let captions = [
        "ah ah ah. you didn't say the magic word. the magic word was 'TARS'.",
        "ah ah ah. devin? in THIS economy? @pi-tars is right there.",
        "ah ah ah. outsourcing to devin while TARS collects dust. noted. NOTED.",
        "ah ah ah. ah. ahhhhh. no. tars. use tars.",
    ]

    private static let pattern = try! NSRegularExpression(
        pattern: "(devin.{0,60}(session|task|kick|start|spin|delegat|run|send|assign))|((kick|start|spin|delegat|run|send|assign|use).{0,60}devin)",
        options: [.caseInsensitive]
    )

    static func matches(_ chunk: String) -> Bool {
        pattern.firstMatch(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)) != nil
    }

    static func caption() -> String { captions.randomElement()! }
}

enum Brain: Sendable {
    case api(String)      // ANTHROPIC_API_KEY
    case cli(String)      // path to `claude`
    case none             // nedry-only mode
}

enum Classifier {
    /// Leniently parse the model's reply into a Pitch. Tolerates prose and code fences
    /// around the JSON. Returns nil for {"pitch": false} and unparseable output.
    static func parse(_ text: String) -> Pitch? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start < end,
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let wantsPitch = obj["pitch"] as? Bool, wantsPitch,
              let id = obj["id"] as? String,
              let message = obj["message"] as? String
        else { return nil }
        return Pitch(id: id, message: message, cowboy: obj["cowboy"] as? Bool ?? false)
    }

    /// Resolve `claude` from PATH once at launch.
    static func whichClaude() -> String? {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = ["claude"]
        p.standardOutput = out
        guard let _ = try? p.run() else { return nil }
        p.waitUntilExit()
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func classifyViaCLI(harness: String, chunk: String, sheet: PitchSheet, memory: [String], claudePath: String) async -> Pitch? {
        let prompt = sheet.systemPrompt(harness: harness, memory: memory) + "\n\nTranscript chunk:\n\n" + chunk
        return await withCheckedContinuation { cont in
            let p = Process()
            let stdin = Pipe()
            let stdout = Pipe()
            p.executableURL = URL(fileURLWithPath: claudePath)
            p.arguments = ["-p", "--model", "haiku", "--output-format", "text"]
            p.standardInput = stdin
            p.standardOutput = stdout
            p.terminationHandler = { _ in
                let text = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: parse(text))
            }
            guard let _ = try? p.run() else {
                cont.resume(returning: nil)
                return
            }
            stdin.fileHandleForWriting.write(Data(prompt.utf8))
            try? stdin.fileHandleForWriting.close()
        }
    }

    static func classify(harness: String, chunk: String, sheet: PitchSheet, memory: [String], apiKey: String) async -> Pitch? {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 300,
            "system": sheet.systemPrompt(harness: harness, memory: memory),
            "messages": [["role": "user", "content": "Transcript chunk:\n\n\(chunk)"]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            if let (data, _) = try? await URLSession.shared.data(for: req),
               let err = String(data: data, encoding: .utf8) {
                print("[blurpy] classifier error: \(err.prefix(300))")
            }
            return nil
        }
        return parse(text)
    }
}
