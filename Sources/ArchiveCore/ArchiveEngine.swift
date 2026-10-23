import Foundation
import CryptoKit

public final class ArchiveEngine: @unchecked Sendable {
    public let runner: ProcessRunner
    private let executable: URL
    private let fm = FileManager.default

    public static func locateExecutable() throws -> URL {
        var candidates: [String] = []
        if let explicit = ProcessInfo.processInfo.environment["MACZIP_7ZZ"] { candidates.append(explicit) }
        candidates += [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/7zz").path,
                       FileManager.default.currentDirectoryPath + "/Vendor/7zip/7zz"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ArchiveError.missingEngine
        }
        return URL(fileURLWithPath: path)
    }

    public init(executable: URL? = nil, runner: ProcessRunner = ProcessRunner()) throws {
        self.executable = try executable ?? Self.locateExecutable()
        self.runner = runner
    }

    private func command(_ arguments: [String], directory: URL? = nil, promptForRead: Bool = false) throws -> String {
        var arguments = arguments
        var input: Data?
        let switchesEnd = arguments.firstIndex(of: "--") ?? arguments.count
        if let index = arguments.indices.prefix(switchesEnd).first(where: { arguments[$0].hasPrefix("-p") }) {
            let password = String(arguments[index].dropFirst(2))
            guard password.utf8.count <= 4096,
                  !password.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw ArchiveError.invalidInput("Пароль слишком длинный или содержит управляющие символы.")
            }
            // Feed the interactive prompt rather than exposing secrets in process arguments.
            // Creation asks twice; reading asks once and ignores the second line.
            if (arguments.first == "a" || arguments.first == "u"), !promptForRead {
                arguments[index] = "-p"
            } else {
                // On read commands a bare -p means an explicitly empty password.
                // Omitting the switch makes 7-Zip request the password from stdin.
                arguments.remove(at: index)
            }
            input = Data((password + "\n" + password + "\n").utf8)
        }
        // Global switches must precede the `--` end-of-switches marker.
        return try runner.run(executable, arguments: Array(arguments.prefix(1)) + ["-sccUTF-8", "-bd"] + Array(arguments.dropFirst()), directory: directory, input: input)
    }

    private func passwordArguments(_ password: String) -> [String] {
        // Closed stdin prevents an unattended password prompt from hanging the application.
        password.isEmpty ? [] : ["-p" + password]
    }

    public static func parseListing(_ output: String) -> [ArchiveEntry] {
        let normalized = output.replacingOccurrences(of: "\r\n", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { record in
            var fields: [String: String] = [:]
            for line in record.components(separatedBy: "\n") {
                guard let range = line.range(of: " = ") else { continue }
                fields[String(line[..<range.lowerBound])] = String(line[range.upperBound...])
            }
            guard let path = fields["Path"], !path.isEmpty else { return nil }
            let attrs = fields["Attributes"] ?? ""
            let mode = fields["Mode"] ?? ""
            return ArchiveEntry(path: path, size: Int64(fields["Size"] ?? "") ?? 0,
                packedSize: Int64(fields["Packed Size"] ?? ""),
                isDirectory: fields["Folder"] == "+" || attrs.hasPrefix("D") || mode.hasPrefix("d"),
                isEncrypted: fields["Encrypted"] == "+", modified: fields["Modified"] ?? "",
                crc: fields["CRC"] ?? "", isLink: !(fields["Symbolic Link"] ?? "").isEmpty || !(fields["Hard Link"] ?? "").isEmpty
                    || attrs.split(separator: " ").contains(where: { $0.hasPrefix("l") }) || mode.hasPrefix("l"))
        }
    }

    private func list(_ url: URL, password: String) throws -> [ArchiveEntry] {
        try listInfo(url, password: password).entries
    }

    private func listInfo(_ url: URL, password: String) throws -> (entries: [ArchiveEntry], encryptedNames: Bool) {
        let output = try command(["l", "-slt", "-ba"] + passwordArguments(password) + ["--", url.path])
        return (Self.parseListing(output), output.contains("Enter password:"))
    }

    public static func validatePath(_ path: String) throws {
        let portable = path.replacingOccurrences(of: "\\", with: "/")
        guard !portable.hasPrefix("/"), !portable.contains(":"),
              !portable.components(separatedBy: "/").contains(".."),
              !portable.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ArchiveError.unsafePath(path)
        }
    }

    private func validate(_ entries: [ArchiveEntry]) throws {
        for entry in entries {
            try Self.validatePath(entry.path)
            if entry.isLink { throw ArchiveError.unsupportedLink(entry.path) }
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("MacZip-" + UUID().uuidString)
        try fm.createDirectory(at: url, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        return url
    }

    public func inspect(_ url: URL, password: String = "") throws -> ArchiveDocument {
        let info = try listInfo(url, password: password)
        let entries = info.entries
        // Open compressed TARs at their inner file tree, rather than showing a single .tar.
        let name = url.lastPathComponent.lowercased()
        let compound = [".tar.gz", ".tgz", ".tar.bz2", ".tbz", ".tbz2", ".tar.xz", ".txz", ".tar.zst", ".tzst", ".tar.z", ".taz"]
            .contains { name.hasSuffix($0) }
        if compound {
            try validate(entries)
            let temp = try temporaryDirectory()
            do {
                _ = try command(["x", "-y", "-o" + temp.path] + passwordArguments(password) + ["--", url.path])
                try validateExtractedTree(temp)
                let children = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
                guard children.count == 1, let inner = children.first else {
                    throw ArchiveError.invalidInput("Не удалось открыть внутренний TAR-архив.")
                }
                let innerEntries = try list(inner, password: password)
                return ArchiveDocument(url: url, contentURL: inner, entries: innerEntries, temporaryDirectory: temp, hasEncryptedHeaders: false)
            } catch { try? fm.removeItem(at: temp); throw error }
        }
        return ArchiveDocument(url: url, contentURL: url, entries: entries, temporaryDirectory: nil, hasEncryptedHeaders: info.encryptedNames)
    }

    /// Opening an encrypted archive authenticates even if its file names are public.
    /// Each attempt is independent: a failed password is never cached by the engine.
    public func open(_ url: URL, password: String = "") throws -> ArchiveDocument {
        let document = try inspect(url, password: password)
        do {
            if document.isEncrypted && !document.hasEncryptedHeaders {
                guard !password.isEmpty else { throw ArchiveError.passwordRequired }
                let smallest = document.entries.filter { $0.isEncrypted && !$0.isDirectory }
                    .min { $0.size < $1.size }
                var arguments = ["t", "-spd"] + passwordArguments(password)
                if let smallest { arguments += ["-i!" + smallest.path] }
                _ = try command(arguments + ["--", document.contentURL.path])
            }
            return document
        } catch { document.cleanUp(); throw error }
    }

    public func test(_ document: ArchiveDocument, password: String = "") throws {
        _ = try command(["t"] + passwordArguments(password) + ["--", document.url.path])
        if document.url != document.contentURL {
            _ = try command(["t"] + passwordArguments(password) + ["--", document.contentURL.path])
        }
    }

    private func validateExtractedTree(_ root: URL) throws {
        guard let items = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for case let url as URL in items {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw ArchiveError.unsupportedLink(url.lastPathComponent) }
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw ArchiveError.unsafePath(url.lastPathComponent)
            }
        }
    }

    /// Always publishes a new directory. Existing user files cannot be overwritten.
    public func extract(_ document: ArchiveDocument, to parent: URL, paths: Set<String>? = nil,
                        password: String = "") throws -> URL {
        // Re-list at extraction time so a changed archive is validated again.
        let current = try list(document.contentURL, password: password)
        if let paths, !paths.allSatisfy({ requested in current.contains { $0.path == requested } }) {
            throw ArchiveError.invalidInput("Содержимое архива изменилось. Откройте его заново.")
        }
        let entries = paths.map { selected in
            let directories = current.filter { $0.isDirectory && selected.contains($0.path) }.map(\.path)
            return current.filter { entry in
                selected.contains(entry.path) || directories.contains { entry.path.hasPrefix($0 + "/") }
            }
        } ?? current
        try validate(entries)
        let staging = parent.appendingPathComponent(".MacZip-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        var args = ["x", "-y", "-aos", "-spd", "-o" + staging.path] + passwordArguments(password)
        var includeFile: URL?
        defer { if let includeFile { try? fm.removeItem(at: includeFile) } }
        if let paths {
            guard !paths.isEmpty else { throw ArchiveError.invalidInput("Выберите файлы для распаковки.") }
            let listURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
            try entries.map(\.path).sorted().joined(separator: "\n").write(to: listURL, atomically: true, encoding: .utf8)
            includeFile = listURL
            args += ["-scsUTF-8", "-i@" + listURL.path]
        }
        _ = try command(args + ["--", document.contentURL.path])
        try validateExtractedTree(staging)
        try runner.checkCancellation()
        let base = Self.archiveBasename(document.url)
        var output = parent.appendingPathComponent(base)
        var suffix = 2
        while fm.fileExists(atPath: output.path) {
            output = parent.appendingPathComponent("\(base) (\(suffix))"); suffix += 1
        }
        try fm.moveItem(at: staging, to: output)
        return output
    }

    public static func archiveBasename(_ url: URL) -> String {
        var name = url.lastPathComponent
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.z"] {
            if name.lowercased().hasSuffix(suffix) { name = String(name.dropLast(suffix.count)); break }
        }
        if name == url.lastPathComponent { name = (name as NSString).deletingPathExtension }
        return name.isEmpty || name == "." || name == ".." ? "Распакованный архив" : name
    }

    public func create(files: [URL], destination: URL, format: ArchiveFormat, level: CompressionLevel = .normal,
                       password: String = "", encryptNames: Bool = true, excludeMacMetadata: Bool = true) throws {
        guard !files.isEmpty else { throw ArchiveError.invalidInput("Добавьте хотя бы один файл или папку.") }
        if format == .gzip {
            guard files.count == 1, try files[0].resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw ArchiveError.invalidInput("Gzip сжимает один файл. Для папок и нескольких файлов выберите TAR.GZ.")
            }
        }
        guard !fm.fileExists(atPath: destination.path) else { throw ArchiveError.destinationExists }
        guard password.isEmpty || format.supportsPassword else {
            throw ArchiveError.invalidInput("Этот формат не поддерживает пароль. Выберите ZIP или 7z.")
        }
        if format == .zip, password.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) {
            throw ArchiveError.invalidInput("Для ZIP используйте латинские буквы, цифры и символы. Для пароля с кириллицей или эмодзи выберите 7z.")
        }
        let names = files.map(\.lastPathComponent)
        guard Set(names).count == names.count else {
            throw ArchiveError.invalidInput("У выбранных объектов одинаковые имена. Переименуйте их перед упаковкой.")
        }
        for file in files {
            try Self.validatePath(file.lastPathComponent)
            let source = file.resolvingSymlinksInPath().standardizedFileURL.path
            let target = destination.resolvingSymlinksInPath().standardizedFileURL.path
            guard !target.hasPrefix(source + "/") else {
                throw ArchiveError.invalidInput("Сохраните архив за пределами упаковываемой папки.")
            }
        }
        let work = try temporaryDirectory()
        defer { try? fm.removeItem(at: work) }
        let inputs = work.appendingPathComponent("inputs")
        try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
        for file in files {
            try runner.checkCancellation()
            try fm.copyItem(at: file, to: inputs.appendingPathComponent(file.lastPathComponent))
        }
        if excludeMacMetadata {
            // Filter staging explicitly: wildcard switches would also affect literal
            // source names containing '*' and '?' when using 7-Zip's -spd mode.
            if let enumerator = fm.enumerator(at: inputs, includingPropertiesForKeys: nil) {
                for case let item as URL in enumerator {
                    let name = item.lastPathComponent
                    if name == ".DS_Store" || name == "__MACOSX" || name.hasPrefix("._") {
                        enumerator.skipDescendants()
                        try fm.removeItem(at: item)
                    }
                }
            }
        }
        var common = ["a", "-y", "-snl", "-spd"]
        let output = work.appendingPathComponent("result." + format.fileExtension)
        if let compressor = format.compressor {
            let tar = work.appendingPathComponent("payload.tar")
            _ = try command(common + ["-ttar", "--", tar.path] + names, directory: inputs)
            _ = try command(["a", "-t" + compressor, "-mx=\(max(1, level.rawValue))", "--", output.path, tar.path])
        } else {
            common += ["-t" + (format == .sevenZip ? "7z" : format.rawValue)]
            if format != .tar { common += ["-mx=\(format == .gzip ? max(1, level.rawValue) : level.rawValue)"] }
            if !password.isEmpty {
                common += passwordArguments(password)
                if format == .zip { common += ["-mem=AES256"] }
                if format == .sevenZip { common += ["-mhe=" + (encryptNames ? "on" : "off")] }
            }
            _ = try command(common + ["--", output.path] + names, directory: inputs)
        }
        try runner.checkCancellation()
        // copyItem fails if the destination appeared while compression was running.
        // Copy to a sibling first; publish with a rename only once the copy is complete.
        let sibling = destination.deletingLastPathComponent().appendingPathComponent(".MacZip-" + UUID().uuidString)
        defer { try? fm.removeItem(at: sibling) }
        try fm.copyItem(at: output, to: sibling)
        try runner.checkCancellation()
        guard !fm.fileExists(atPath: destination.path) else { throw ArchiveError.destinationExists }
        try fm.moveItem(at: sibling, to: destination)
    }

    private func digest(_ url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let block = try file.read(upToCount: 1024 * 1024), !block.isEmpty {
            try runner.checkCancellation()
            hash.update(data: block)
        }
        return Data(hash.finalize())
    }

    public func fingerprint(_ url: URL) throws -> Data { try digest(url) }

    /// Rewrites the archive container, without extracting its file tree. The original
    /// is replaced atomically only after integrity and concurrent-change checks pass.
    private func mutate(_ document: ArchiveDocument, password: String, keepBackup: Bool,
                        operation: (URL, URL, ArchiveDocument) throws -> Void) throws -> URL? {
        guard let format = document.editableFormat else {
            throw ArchiveError.invalidInput("Этот формат доступен только для просмотра и распаковки.")
        }
        let originalDigest = try digest(document.url)
        let fresh = try inspect(document.url, password: password)
        defer { fresh.cleanUp() }
        let work = document.url.deletingLastPathComponent().appendingPathComponent(".MacZip-edit-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }
        let archive = work.appendingPathComponent(format.compressor == nil ? "archive." + format.fileExtension : "payload.tar")
        try fm.copyItem(at: fresh.contentURL, to: archive)
        let inputs = work.appendingPathComponent("inputs")
        try fm.createDirectory(at: inputs, withIntermediateDirectories: false)
        try operation(archive, inputs, fresh)
        var result = archive
        if let compressor = format.compressor {
            result = work.appendingPathComponent("updated." + format.fileExtension)
            _ = try command(["a", "-t" + compressor, "-mx=5", "--", result.path, archive.path])
        }
        let verified = try inspect(result, password: password)
        defer { verified.cleanUp() }
        try test(verified, password: password)
        guard try digest(document.url) == originalDigest else {
            throw ArchiveError.invalidInput("Архив изменился в другой программе. Изменения не записаны. Откройте архив заново.")
        }
        try runner.checkCancellation()
        let backupName = keepBackup ? document.url.lastPathComponent + ".backup-" + String(UUID().uuidString.prefix(8)) : nil
        _ = try fm.replaceItemAt(document.url, withItemAt: result, backupItemName: backupName,
                                 options: keepBackup ? [.withoutDeletingBackupItem] : [])
        return backupName.map { document.url.deletingLastPathComponent().appendingPathComponent($0) }
    }

    public func add(files: [URL], to document: ArchiveDocument, directory: String = "",
                    password: String = "", keepBackup: Bool = true) throws -> URL? {
        guard document.editableFormat != .gzip else {
            throw ArchiveError.invalidInput("Gzip содержит один файл. Можно изменить его содержимое; для добавления файлов создайте ZIP, 7z или TAR.")
        }
        guard !files.isEmpty else { throw ArchiveError.invalidInput("Выберите файлы для добавления.") }
        if !directory.isEmpty { try Self.validatePath(directory) }
        guard Set(files.map(\.lastPathComponent)).count == files.count else {
            throw ArchiveError.invalidInput("У добавляемых объектов одинаковые имена.")
        }
        return try mutate(document, password: password, keepBackup: keepBackup) { archive, inputs, fresh in
            let folder = directory.isEmpty ? inputs : inputs.appendingPathComponent(directory)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var paths: [String] = []
            for file in files {
                try runner.checkCancellation()
                try Self.validatePath(file.lastPathComponent)
                try fm.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
                paths.append(directory.isEmpty ? file.lastPathComponent : directory + "/" + file.lastPathComponent)
            }
            // Reject a file/folder type conflict before 7-Zip sees ambiguous input.
            for path in paths {
                if let existing = fresh.entries.first(where: { $0.path == path }) {
                    let directory = try inputs.appendingPathComponent(path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                    guard directory == existing.isDirectory else {
                        throw ArchiveError.invalidInput("В архиве уже есть объект другого типа: \(path).")
                    }
                }
            }
            var args = ["a", "-y", "-spd", "-snl"]
            if document.editableFormat?.supportsPassword == true, fresh.isEncrypted {
                guard !password.isEmpty else { throw ArchiveError.passwordRequired }
                args += passwordArguments(password)
                if document.editableFormat == .zip { args += ["-mem=AES256"] }
            }
            _ = try command(args + ["--", archive.path] + paths, directory: inputs, promptForRead: fresh.hasEncryptedHeaders)
        }
    }

    public func delete(paths: Set<String>, from document: ArchiveDocument,
                       password: String = "", keepBackup: Bool = true) throws -> URL? {
        guard document.editableFormat != .gzip else {
            throw ArchiveError.invalidInput("Gzip содержит один файл. Чтобы удалить архив, используйте Finder.")
        }
        guard !paths.isEmpty else { throw ArchiveError.invalidInput("Выберите объекты для удаления.") }
        for path in paths { try Self.validatePath(path) }
        return try mutate(document, password: password, keepBackup: keepBackup) { archive, inputs, fresh in
            guard paths.allSatisfy({ requested in fresh.entries.contains { $0.path == requested || $0.path.hasPrefix(requested + "/") } }) else {
                throw ArchiveError.invalidInput("Содержимое архива изменилось. Откройте его заново.")
            }
            let list = inputs.appendingPathComponent("delete.txt")
            try paths.sorted().joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)
            _ = try command(["d", "-y", "-spd", "-scsUTF-8", "-i@" + list.path] + passwordArguments(password) + ["--", archive.path])
        }
    }

    public func replace(_ entry: ArchiveEntry, with file: URL, in document: ArchiveDocument,
                        password: String = "", keepBackup: Bool = true, expectedDigest: Data? = nil) throws -> URL? {
        try Self.validatePath(entry.path)
        guard !entry.isDirectory, !entry.isLink else { throw ArchiveError.invalidInput("Выберите обычный файл для редактирования.") }
        return try mutate(document, password: password, keepBackup: keepBackup) { archive, inputs, fresh in
            guard fresh.entries.contains(where: { $0.path == entry.path }) else {
                throw ArchiveError.invalidInput("Файл удалён из архива. Откройте архив заново.")
            }
            if let expectedDigest {
                let validation = inputs.appendingPathComponent(".validation-" + UUID().uuidString)
                try fm.createDirectory(at: validation, withIntermediateDirectories: false)
                defer { try? fm.removeItem(at: validation) }
                let current = try extract(fresh, to: validation, paths: [entry.path], password: password).appendingPathComponent(entry.path)
                guard try digest(current) == expectedDigest else {
                    throw ArchiveError.invalidInput("Этот документ уже изменён в архиве другой программой. Ваша версия осталась в редакторе; сохраните её отдельно.")
                }
            }
            let destination = inputs.appendingPathComponent(entry.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: destination)
            if document.editableFormat == .gzip {
                try fm.removeItem(at: archive)
                _ = try command(["a", "-tgzip", "--", archive.path, entry.path], directory: inputs)
            } else {
                var args = ["a", "-y", "-spd"]
                if document.editableFormat?.supportsPassword == true, fresh.isEncrypted {
                    guard !password.isEmpty else { throw ArchiveError.passwordRequired }
                    args += passwordArguments(password)
                    if document.editableFormat == .zip { args += ["-mem=AES256"] }
                }
                _ = try command(args + ["--", archive.path, entry.path], directory: inputs, promptForRead: fresh.hasEncryptedHeaders)
            }
        }
    }
}
