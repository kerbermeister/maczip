import XCTest
@testable import ArchiveCore

final class ArchiveEngineTests: XCTestCase {
    private var root: URL!
    private var input: URL!
    private var engine: ArchiveEngine!
    private let text = String(repeating: "Привет, MacZip! Unicode ✓\n", count: 500)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-tests-" + UUID().uuidString)
        input = root.appendingPathComponent("Документы")
        try FileManager.default.createDirectory(at: input.appendingPathComponent("Вложенная папка"), withIntermediateDirectories: true)
        try text.write(to: input.appendingPathComponent("Привет мир.txt"), atomically: true, encoding: .utf8)
        try "nested".write(to: input.appendingPathComponent("Вложенная папка/notes.txt"), atomically: true, encoding: .utf8)
        try "literal wildcard".write(to: input.appendingPathComponent("a*b.txt"), atomically: true, encoding: .utf8)
        try "equals".write(to: input.appendingPathComponent("имя = файл.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: input.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        engine = try ArchiveEngine()
    }

    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    private func create(_ format: ArchiveFormat = .zip, level: CompressionLevel = .normal,
                        password: String = "", encryptNames: Bool = true) throws -> URL {
        let archive = root.appendingPathComponent(UUID().uuidString + "." + format.fileExtension)
        let sources = format == .gzip ? [input.appendingPathComponent("Привет мир.txt")] : [input!]
        try engine.create(files: sources, destination: archive, format: format, level: level,
                          password: password, encryptNames: encryptNames)
        return archive
    }

    private func assertContent(_ output: URL, file: String = "Документы/Привет мир.txt", expected: String? = nil,
                               fileID: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent(file), encoding: .utf8), expected ?? text, file: fileID, line: line)
    }

    func testAllCreationFormatsRoundTrip() throws {
        for format in ArchiveFormat.allCases {
            let archive = try create(format)
            let doc = try engine.inspect(archive)
            defer { doc.cleanUp() }
            XCTAssertEqual(doc.fileCount, format == .gzip ? 1 : 4, format.title)
            XCTAssertFalse(doc.entries.contains { $0.name == ".DS_Store" })
            try engine.test(doc)
            let output = try engine.extract(doc, to: root)
            if format == .gzip {
                try assertContent(output, file: "Привет мир.txt")
                continue
            }
            try assertContent(output)
            try assertContent(output, file: "Документы/Вложенная папка/notes.txt", expected: "nested")
            try assertContent(output, file: "Документы/a*b.txt", expected: "literal wildcard")
            try assertContent(output, file: "Документы/имя = файл.txt", expected: "equals")
        }
    }

    func testAllCompressionLevelsForZIPAnd7z() throws {
        for format in [ArchiveFormat.zip, .sevenZip] {
            for level in CompressionLevel.allCases {
                let doc = try engine.inspect(create(format, level: level))
                try engine.test(doc)
                try assertContent(engine.extract(doc, to: root))
            }
        }
    }

    func testAESZIPAnd7zPasswords() throws {
        for format in [ArchiveFormat.zip, .sevenZip] {
            let password = format == .zip ? "correct horse $! 2026" : "пароль 🗝 correct horse"
            let archive = try create(format, password: password, encryptNames: false)
            let doc = try engine.inspect(archive)
            XCTAssertTrue(doc.isEncrypted)
            XCTAssertThrowsError(try engine.extract(doc, to: root, password: "wrong")) { error in
                guard case ArchiveError.passwordRequired = error else { return XCTFail("\(error)") }
            }
            XCTAssertThrowsError(try engine.extract(doc, to: root))
            try engine.test(doc, password: password)
            try assertContent(engine.extract(doc, to: root, password: password))
        }
    }

    func test7zEncryptedFileNames() throws {
        let archive = try create(.sevenZip, password: "secret", encryptNames: true)
        XCTAssertThrowsError(try engine.inspect(archive))
        XCTAssertThrowsError(try engine.inspect(archive, password: "wrong"))
        let doc = try engine.inspect(archive, password: "secret")
        XCTAssertEqual(doc.fileCount, 4)
        try assertContent(engine.extract(doc, to: root, password: "secret"))
    }

    func testSelectedExtractionUsesLiteralNames() throws {
        let doc = try engine.inspect(create())
        let output = try engine.extract(doc, to: root, paths: ["Документы/a*b.txt"])
        try assertContent(output, file: "Документы/a*b.txt", expected: "literal wildcard")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Документы/Привет мир.txt").path))
    }

    func testSelectedFolderIncludesChildren() throws {
        let doc = try engine.inspect(create())
        let output = try engine.extract(doc, to: root, paths: ["Документы/Вложенная папка"])
        try assertContent(output, file: "Документы/Вложенная папка/notes.txt", expected: "nested")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("Документы/a*b.txt").path))
    }

    func testExtractionNeverOverwritesExistingDirectory() throws {
        let archive = try create()
        let doc = try engine.inspect(archive)
        let first = try engine.extract(doc, to: root)
        try "keep me".write(to: first.appendingPathComponent("sentinel.txt"), atomically: true, encoding: .utf8)
        let second = try engine.extract(doc, to: root)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first.appendingPathComponent("sentinel.txt")), "keep me")
        try assertContent(second)
    }

    func testCreationNeverOverwritesExistingArchive() throws {
        let archive = try create()
        let before = try Data(contentsOf: archive)
        XCTAssertThrowsError(try engine.create(files: [input], destination: archive, format: .zip))
        XCTAssertEqual(try Data(contentsOf: archive), before)
    }

    func testInvalidInputs() throws {
        XCTAssertThrowsError(try engine.create(files: [], destination: root.appendingPathComponent("empty.zip"), format: .zip))
        XCTAssertThrowsError(try engine.create(files: [input], destination: input.appendingPathComponent("recursive.zip"), format: .zip))
        XCTAssertThrowsError(try engine.create(files: [input], destination: root.appendingPathComponent("bad.tar"), format: .tar, password: "secret"))
        let corrupt = root.appendingPathComponent("broken.zip")
        try "not an archive".write(to: corrupt, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try engine.inspect(corrupt))
    }

    func testRejectsTraversalAndControlCharacters() throws {
        for path in ["../escape", "/etc/passwd", "folder/../../escape", "C:\\Windows\\file", "a\\..\\escape", "file\nPath = ../escape", "a\rb"] {
            XCTAssertThrowsError(try ArchiveEngine.validatePath(path), path)
        }
        for path in ["a/b.txt", "Привет мир.txt", "a*b.txt", "имя = файл.txt", "-option"] {
            XCTAssertNoThrow(try ArchiveEngine.validatePath(path))
        }
    }

    func testRejectsSymlinksDuringExtraction() throws {
        try FileManager.default.createSymbolicLink(atPath: input.appendingPathComponent("link").path, withDestinationPath: "Привет мир.txt")
        let doc = try engine.inspect(create(.tar))
        XCTAssertTrue(doc.entries.contains { $0.isLink })
        XCTAssertThrowsError(try engine.extract(doc, to: root))
        // Selecting the directory must validate its descendants too.
        XCTAssertThrowsError(try engine.extract(doc, to: root, paths: ["Документы"]))
        let safe = try engine.extract(doc, to: root, paths: ["Документы/Привет мир.txt"])
        try assertContent(safe)
    }

    func testCancellationStopsMultiStepWork() throws {
        let runner = ProcessRunner()
        runner.cancel()
        let cancelled = try ArchiveEngine(runner: runner)
        XCTAssertThrowsError(try cancelled.create(files: [input], destination: root.appendingPathComponent("cancelled.tar.gz"), format: .tarGzip)) { error in
            guard case ArchiveError.cancelled = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled.tar.gz").path))
    }

    func testCancellationTerminatesRunningProcess() throws {
        let runner = ProcessRunner()
        let started = expectation(description: "Process started")
        let finished = expectation(description: "Process cancelled")
        DispatchQueue.global().async {
            started.fulfill()
            do {
                _ = try runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"])
                XCTFail("Expected cancellation")
            } catch {
                if case ArchiveError.cancelled = error {} else { XCTFail("\(error)") }
            }
            finished.fulfill()
        }
        wait(for: [started], timeout: 2)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { runner.cancel() }
        wait(for: [finished], timeout: 4)
    }

    func testChangedArchiveSelectionIsRejected() throws {
        let doc = try engine.inspect(create())
        XCTAssertThrowsError(try engine.extract(doc, to: root, paths: ["missing.txt"]))
    }

    func testRAR4AndRAR5Fixtures() throws {
        for version in [4, 5] {
            let fixture = try XCTUnwrap(Bundle.module.url(forResource: "rar\(version)", withExtension: "rar", subdirectory: "Fixtures"))
            let doc = try engine.inspect(fixture)
            XCTAssertGreaterThan(doc.fileCount, 0)
            try engine.test(doc)
            let name = version == 4 ? "test.txt" : "helloworld.txt"
            let output = try engine.extract(doc, to: root, paths: [name])
            let expected = version == 4 ? "test text document\r\n" : "hello libarchive test suite!\n"
            try assertContent(output, file: name, expected: expected)
        }
    }

    func testListingParserAndCompoundNames() throws {
        let entries = ArchiveEngine.parseListing("Path = папка/a = b.txt\nSize = 42\nEncrypted = +\nCRC = ABC\n\nPath = папка\nFolder = +\nSize = 0\n")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "a = b.txt")
        XCTAssertTrue(entries[0].isEncrypted)
        XCTAssertTrue(entries[1].isDirectory)
        XCTAssertEqual(ArchiveEngine.archiveBasename(URL(fileURLWithPath: "/tmp/a.tar.gz")), "a")
        XCTAssertEqual(ArchiveEngine.archiveBasename(URL(fileURLWithPath: "/tmp/a.7z")), "a")
    }

    func testAddingDeletingAndReplacingWithoutExtractingWholeArchive() throws {
        for format in ArchiveFormat.allCases where format != .gzip {
            var doc = try engine.inspect(create(format))
            let added = root.appendingPathComponent("новый.txt")
            try "added".write(to: added, atomically: true, encoding: .utf8)
            let backup = try engine.add(files: [added], to: doc, directory: "Документы", keepBackup: true)
            XCTAssertNotNil(backup)
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup!.path))
            doc.cleanUp()
            doc = try engine.inspect(doc.url)
            XCTAssertTrue(doc.entries.contains { $0.path == "Документы/новый.txt" })
            let edited = root.appendingPathComponent("edited.txt")
            try "edited version".write(to: edited, atomically: true, encoding: .utf8)
            let entry = try XCTUnwrap(doc.entries.first { $0.path == "Документы/Привет мир.txt" })
            _ = try engine.replace(entry, with: edited, in: doc, keepBackup: false)
            doc.cleanUp(); doc = try engine.inspect(doc.url)
            let output = try engine.extract(doc, to: root)
            try assertContent(output, expected: "edited version")
            try assertContent(output, file: "Документы/новый.txt", expected: "added")
            _ = try engine.delete(paths: ["Документы/a*b.txt", "Документы/Вложенная папка"], from: doc, keepBackup: false)
            doc.cleanUp(); doc = try engine.inspect(doc.url)
            XCTAssertFalse(doc.entries.contains { $0.path == "Документы/a*b.txt" || $0.path.hasPrefix("Документы/Вложенная папка") })
            XCTAssertTrue(doc.entries.contains { $0.path == "Документы/Привет мир.txt" })
            try engine.test(doc)
            doc.cleanUp()
        }
    }

    func testEncryptedArchiveUpdatesKeepNewAndReplacedFilesEncrypted() throws {
        for (format, hidden) in [(ArchiveFormat.zip, false), (.sevenZip, false), (.sevenZip, true)] {
            let password = "correct horse !2026"
            let archive = try create(format, password: password, encryptNames: hidden)
            var doc = try engine.inspect(archive, password: password)
            let added = root.appendingPathComponent("extra.txt")
            try "encrypted addition".write(to: added, atomically: true, encoding: .utf8)
            _ = try engine.add(files: [added], to: doc, password: password, keepBackup: false)
            doc = try engine.inspect(archive, password: password)
            XCTAssertTrue(try XCTUnwrap(doc.entries.first { $0.path == "extra.txt" }).isEncrypted)
            let entry = try XCTUnwrap(doc.entries.first { $0.path == "Документы/Привет мир.txt" })
            _ = try engine.replace(entry, with: added, in: doc, password: password, keepBackup: false)
            doc = try engine.inspect(archive, password: password)
            XCTAssertTrue(try XCTUnwrap(doc.entries.first { $0.path == entry.path }).isEncrypted)
            _ = try engine.delete(paths: ["extra.txt"], from: doc, password: password, keepBackup: false)
            doc = try engine.inspect(archive, password: password)
            XCTAssertFalse(doc.entries.contains { $0.path == "extra.txt" })
            if hidden { XCTAssertThrowsError(try engine.inspect(archive)) }
            let output = try engine.extract(doc, to: root, password: password)
            try assertContent(output, expected: "encrypted addition")
        }
    }

    func testGzipEditingSingleFile() throws {
        let doc = try engine.inspect(create(.gzip))
        let entry = try XCTUnwrap(doc.entries.first)
        let file = root.appendingPathComponent("edit.txt")
        try "updated gzip content".write(to: file, atomically: true, encoding: .utf8)
        _ = try engine.replace(entry, with: file, in: doc, keepBackup: false)
        let updated = try engine.inspect(doc.url)
        let output = try engine.extract(updated, to: root)
        try assertContent(output, file: entry.path, expected: "updated gzip content")
        XCTAssertThrowsError(try engine.add(files: [file], to: updated))
        XCTAssertThrowsError(try engine.delete(paths: [entry.path], from: updated))
    }

    func testStaleEditedDocumentCannotOverwriteNewerContent() throws {
        let doc = try engine.inspect(create())
        let entry = try XCTUnwrap(doc.entries.first { $0.path == "Документы/Привет мир.txt" })
        let original = try engine.extract(doc, to: root, paths: [entry.path]).appendingPathComponent(entry.path)
        let digest = try engine.fingerprint(original)
        let replacement = root.appendingPathComponent("replacement.txt")
        try "a newer version".write(to: replacement, atomically: true, encoding: .utf8)
        _ = try engine.replace(entry, with: replacement, in: doc, keepBackup: false)
        let before = try Data(contentsOf: doc.url)
        XCTAssertThrowsError(try engine.replace(entry, with: original, in: doc, keepBackup: false, expectedDigest: digest))
        XCTAssertEqual(try Data(contentsOf: doc.url), before)
    }

    func testFailedMutationLeavesOriginalArchiveIntact() throws {
        let archive = try create(.sevenZip, password: "secret")
        let doc = try engine.inspect(archive, password: "secret")
        let before = try Data(contentsOf: archive)
        XCTAssertThrowsError(try engine.delete(paths: ["Документы/a*b.txt"], from: doc, password: "wrong"))
        XCTAssertEqual(try Data(contentsOf: archive), before)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".MacZip-edit-") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testLiteralInputNameCannotBecomePasswordSwitch() throws {
        let file = root.appendingPathComponent("-pnot-a-password.txt")
        try "literal flag".write(to: file, atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("literal.zip")
        try engine.create(files: [file], destination: archive, format: .zip)
        let doc = try engine.inspect(archive)
        XCTAssertFalse(doc.isEncrypted)
        XCTAssertEqual(doc.entries.first?.path, file.lastPathComponent)
    }

    func testZIPRejectsNonASCIIPasswordWithHelpfulError() throws {
        XCTAssertThrowsError(try create(.zip, password: "пароль")) { error in
            XCTAssertTrue(error.localizedDescription.contains("7z"))
        }
    }

    func testArchiveTraversalIsBlockedBeforeExtraction() throws {
        let folder = root.appendingPathComponent("safe")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "evil".write(to: folder.appendingPathComponent("evil.txt"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("traversal.zip")
        try engine.create(files: [folder], destination: archive, format: .zip, level: .store)
        var bytes = try Data(contentsOf: archive)
        let oldName = Data("safe/evil.txt".utf8), badName = Data("../x/evil.txt".utf8)
        XCTAssertEqual(oldName.count, badName.count)
        while let range = bytes.range(of: oldName) { bytes.replaceSubrange(range, with: badName) }
        try bytes.write(to: archive)
        let doc = try engine.inspect(archive)
        XCTAssertThrowsError(try engine.extract(doc, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("x/evil.txt").path))
    }

    func testISOReadAndExtract() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "sample", withExtension: "iso", subdirectory: "Fixtures"))
        let doc = try engine.inspect(fixture)
        XCTAssertNil(doc.editableFormat)
        XCTAssertTrue(doc.entries.contains { $0.path == "hello.txt" })
        try assertContent(engine.extract(doc, to: root), file: "hello.txt", expected: "MacZip ISO fixture\n")
        XCTAssertThrowsError(try engine.delete(paths: ["hello.txt"], from: doc))
    }

    func testProtectedRARCanBeReopenedAfterRepeatedWrongPasswords() throws {
        for version in [4, 5] {
            for hidden in [false, true] {
                let name = "rar\(version)-" + (hidden ? "hidden" : "encrypted")
                let fixture = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "rar", subdirectory: "Fixtures"))
                XCTAssertThrowsError(try engine.open(fixture))
                for attempt in 1...4 {
                    XCTAssertThrowsError(try engine.open(fixture, password: "wrong-\(attempt)")) { error in
                        guard case ArchiveError.passwordRequired = error else { return XCTFail("\(error)") }
                    }
                }
                let doc = try engine.open(fixture, password: "password")
                try assertContent(engine.extract(doc, to: root, paths: ["b.txt"], password: "password"), file: "b.txt", expected: "This is from b.txt")
                let restarted = try ArchiveEngine()
                XCTAssertThrowsError(try restarted.open(fixture))
                XCTAssertThrowsError(try restarted.open(fixture, password: "wrong-again"))
                XCTAssertNoThrow(try restarted.open(fixture, password: "password"))
            }
        }
    }

    func testRAR4AndRAR5PasswordsAndEncryptedFileNames() throws {
        for version in [4, 5] {
            for hidden in [false, true] {
                let name = "rar\(version)-" + (hidden ? "hidden" : "encrypted")
                let fixture = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "rar", subdirectory: "Fixtures"))
                if hidden {
                    XCTAssertThrowsError(try engine.inspect(fixture))
                    XCTAssertThrowsError(try engine.inspect(fixture, password: "wrong"))
                }
                let doc = try engine.inspect(fixture, password: "password")
                XCTAssertTrue(doc.isEncrypted)
                XCTAssertNil(doc.editableFormat)
                XCTAssertThrowsError(try engine.extract(doc, to: root, paths: ["b.txt"], password: "wrong"))
                try assertContent(engine.extract(doc, to: root, paths: ["b.txt"], password: "password"), file: "b.txt", expected: "This is from b.txt")
            }
        }
    }
}
