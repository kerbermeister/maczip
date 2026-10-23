import XCTest
import ArchiveCore
@testable import MacZip

@MainActor
final class PasswordFlowTests: XCTestCase {
    private func waitForOperation(_ model: AppModel, file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(15)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.busy, "Operation timed out", file: file, line: line)
    }

    func testRepeatedWrongPasswordsThenCorrectPasswordAndRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-password-flow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("hello.txt")
        try "Password flow fixture".write(to: file, atomically: true, encoding: .utf8)
        let engine = try ArchiveEngine()

        for (format, hideNames) in [(ArchiveFormat.zip, false), (.sevenZip, false), (.sevenZip, true)] {
            let archive = root.appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
            try engine.create(files: [file], destination: archive, format: format, password: "correct", encryptNames: hideNames)
            let model = AppModel()
            model.open(archive)
            try await waitForOperation(model)
            XCTAssertTrue(model.passwordPrompt)
            XCTAssertNil(model.document)

            for attempt in 1...4 {
                let oldAttempt = model.passwordAttemptID
                model.submitPassword("wrong-\(attempt)")
                // The sheet stays up while validation runs, so a fast failure cannot
                // race with dismissal and leave the next password dialog invisible.
                XCTAssertTrue(model.passwordPrompt)
                try await waitForOperation(model)
                XCTAssertTrue(model.passwordPrompt)
                XCTAssertFalse(model.passwordError.isEmpty)
                XCTAssertNotEqual(oldAttempt, model.passwordAttemptID)
                XCTAssertNil(model.document)
            }

            model.submitPassword("correct")
            try await waitForOperation(model)
            XCTAssertFalse(model.passwordPrompt)
            model.passwordSheetDidDismiss() // SwiftUI's onDismiss callback.
            XCTAssertEqual(model.document?.url, archive)
            XCTAssertTrue(model.passwordError.isEmpty)
            model.closeArchive()
            model.open(archive)
            try await waitForOperation(model)
            XCTAssertTrue(model.passwordPrompt, "Reopening must request the password again")
            model.cancelPassword()

            // A fresh app state is the same path used after an application restart.
            let restarted = AppModel()
            restarted.open(archive)
            try await waitForOperation(restarted)
            XCTAssertTrue(restarted.passwordPrompt)
            restarted.submitPassword("still-wrong")
            try await waitForOperation(restarted)
            XCTAssertTrue(restarted.passwordPrompt)
            restarted.submitPassword("correct")
            try await waitForOperation(restarted)
            restarted.passwordSheetDidDismiss()
            XCTAssertEqual(restarted.document?.url, archive)
            model.shutdown(); restarted.shutdown()
        }
    }

    func testExtractionAcceptsAnotherPasswordAfterEveryFailedAttempt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-extract-password-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("document.txt")
        try "Successfully decrypted".write(to: source, atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("protected.zip")
        let engine = try ArchiveEngine()
        try engine.create(files: [source], destination: archive, format: .zip, password: "secret")
        let model = AppModel()
        // ZIP metadata is public, but extraction still has to authenticate.
        model.document = try engine.inspect(archive)
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "revealAfterExtract")
        defaults.set(false, forKey: "revealAfterExtract")
        defer {
            if let previous { defaults.set(previous, forKey: "revealAfterExtract") }
            else { defaults.removeObject(forKey: "revealAfterExtract") }
        }
        model.extractToDirectory(root)
        XCTAssertTrue(model.passwordPrompt)
        for attempt in 1...5 {
            model.submitPassword("bad-\(attempt)")
            try await waitForOperation(model)
            XCTAssertTrue(model.passwordPrompt)
            XCTAssertFalse(model.passwordError.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("protected").path))
        }
        model.submitPassword("secret")
        try await waitForOperation(model)
        XCTAssertFalse(model.passwordPrompt)
        model.passwordSheetDidDismiss()
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("protected/document.txt")), "Successfully decrypted")
        XCTAssertTrue(model.history.first?.succeeded == true)
        model.shutdown()
    }

    func testCancellingPasswordPromptAllowsOpeningAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-password-cancel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("file.txt")
        try "test".write(to: source, atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("protected.zip")
        try ArchiveEngine().create(files: [source], destination: archive, format: .zip, password: "secret")
        let model = AppModel()
        model.open(archive)
        try await waitForOperation(model)
        model.cancelPassword(); model.passwordSheetDidDismiss()
        XCTAssertFalse(model.passwordPrompt)
        XCTAssertNil(model.document)
        model.open(archive)
        try await waitForOperation(model)
        XCTAssertTrue(model.passwordPrompt)
        model.submitPassword("secret")
        try await waitForOperation(model)
        model.passwordSheetDidDismiss()
        XCTAssertEqual(model.document?.url, archive)
        model.shutdown()
    }
}
