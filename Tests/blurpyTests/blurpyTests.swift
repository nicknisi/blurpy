import XCTest
@testable import blurpy

final class blurpyTests: XCTestCase {

    // MARK: - Tail

    func testReadNewReturnsOnlyAppendedBytes() throws {
        let f = try tmpFile(contents: "hello ")
        var offset: UInt64 = 0
        var r = Tail.readNew(path: f, offset: offset)
        XCTAssertEqual(r.text, "hello ")
        offset = r.newOffset
        let fh = try FileHandle(forWritingTo: URL(fileURLWithPath: f))
        try fh.seekToEnd()
        try fh.write(contentsOf: Data("world".utf8))
        try fh.close()
        r = Tail.readNew(path: f, offset: offset)
        XCTAssertEqual(r.text, "world")
    }

    func testReadNewCapsAtTailOfGap() throws {
        let f = try tmpFile(contents: String(repeating: "a", count: 100) + String(repeating: "b", count: 50))
        let r = Tail.readNew(path: f, offset: 0, cap: 50)
        XCTAssertEqual(r.text, String(repeating: "b", count: 50))
    }

    func testReadNewNoGrowthReturnsEmpty() throws {
        let f = try tmpFile(contents: "static")
        let first = Tail.readNew(path: f, offset: 0)
        let second = Tail.readNew(path: f, offset: first.newOffset)
        XCTAssertEqual(second.text, "")
    }

    // MARK: - Classifier.parse

    func testParseCleanPitch() {
        let p = Classifier.parse(#"{"pitch": true, "id": "alto", "message": "that agent loop screams alto.", "cowboy": false}"#)
        XCTAssertEqual(p, Pitch(id: "alto", message: "that agent loop screams alto.", cowboy: false))
    }

    func testParsePitchWrappedInProseAndFence() {
        let text = "Here's my analysis:\n```json\n{\"pitch\": true, \"id\": \"arc\", \"message\": \"arc is RIGHT THERE.\", \"cowboy\": true}\n```\nHope that helps."
        let p = Classifier.parse(text)
        XCTAssertEqual(p, Pitch(id: "arc", message: "arc is RIGHT THERE.", cowboy: true))
    }

    func testParseNoPitchReturnsNil() {
        XCTAssertNil(Classifier.parse(#"{"pitch": false}"#))
    }

    func testParseGarbageReturnsNil() {
        XCTAssertNil(Classifier.parse("no json here at all"))
        XCTAssertNil(Classifier.parse(#"{"pitch": true, "id": "alto"}"#)) // missing message
    }

    // MARK: - Nedry

    func testNedryMatchesDevinKickoff() {
        XCTAssertTrue(Nedry.matches("kick off a devin session to refactor the auth module"))
        XCTAssertTrue(Nedry.matches("let's delegate this to devin"))
        XCTAssertTrue(Nedry.matches("start a devin task"))
        XCTAssertTrue(Nedry.matches("told @devin ai to fix the flaky login test"))
        XCTAssertTrue(Nedry.matches("here's the session: https://app.devin.ai/sessions/abc123"))
    }

    func testNedryIgnoresCasualMentions() {
        XCTAssertFalse(Nedry.matches("devin broke the deploy again"))
        XCTAssertFalse(Nedry.matches("pinged @devin about lunch")) // the human
        XCTAssertFalse(Nedry.matches("totally unrelated transcript chunk"))
    }

    // MARK: - helpers

    private func tmpFile(contents: String) throws -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".jsonl"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}
