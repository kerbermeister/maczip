import AppKit
import ArchiveCore
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case archives, create, activity, formats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .archives: return "Архивы"
        case .create: return "Создать архив"
        case .activity: return "История"
        case .formats: return "Форматы"
        }
    }
    var icon: String {
        switch self {
        case .archives: return "archivebox"
        case .create: return "plus.square"
        case .activity: return "clock.arrow.circlepath"
        case .formats: return "square.stack.3d.up"
        }
    }
}

struct ActivityItem: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    let title: String
    let detail: String
    let source: URL
    let result: URL?
    let succeeded: Bool
}

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct EditingSession {
    let document: ArchiveDocument
    let entry: ArchiveEntry
    let fileURL: URL
    let directory: URL
    let encoding: String.Encoding
    let password: String
    let originalDigest: Data
}

struct PreparedEdit: Sendable { let file: URL; let digest: Data }

@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .archives
    @Published var document: ArchiveDocument?
    @Published var directory = ""
    @Published var query = ""
    @Published var selection = Set<String>()
    @Published var busy = false
    @Published var operationTitle = ""
    @Published var operationDetail = ""
    @Published var notice: Notice?
    @Published var passwordPrompt = false
    @Published var passwordError = ""
    @Published var passwordAttemptID = UUID()
    @Published var previewURL: URL?
    @Published var previewPresented = false
    @Published var history: [ActivityItem] = []
    @Published var recent: [URL] = []
    @Published var toast = ""
    @Published var showInspector = true
    @Published var inputFiles: [URL] = []
    @Published var format: ArchiveFormat = .zip
    @Published var compression: CompressionLevel = .normal
    @Published var newPassword = ""
    @Published var confirmPassword = ""
    @Published var protectArchive = false
    @Published var encryptNames = true
    @Published var archiveName = "Архив"
    @Published var deletePrompt = false
    @Published var addConflictPrompt = false
    @Published var discardEditingPrompt = false
    @Published var editingSession: EditingSession?
    @Published var textEditorPresented = false
    @Published var editorText = ""
    private var pendingAdd: (files: [URL], directory: String)?
    private var currentPassword = ""
    private var passwordAction: ((String) -> Void)?
    private var afterPasswordDismissal: (() -> Void)?
    private var runner: ProcessRunner?
    private var previewDirectory: URL?
    private var toastTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "history"), let items = try? JSONDecoder().decode([ActivityItem].self, from: data) {
            history = items
        }
        recent = (defaults.stringArray(forKey: "recent") ?? []).map { URL(fileURLWithPath: $0) }
        format = ArchiveFormat(rawValue: defaults.string(forKey: "defaultFormat") ?? "zip") ?? .zip
    }

    var rows: [ArchiveEntry] {
        guard let document else { return [] }
        let prefix = directory.isEmpty ? "" : directory + "/"
        var entries: [String: ArchiveEntry] = [:]
        for entry in document.entries where entry.path.hasPrefix(prefix) {
            let relative = String(entry.path.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            if query.isEmpty {
                let parts = relative.split(separator: "/")
                guard let first = parts.first else { continue }
                let path = prefix + first
                if parts.count > 1 {
                    if entries[path] == nil { entries[path] = ArchiveEntry(path: path, isDirectory: true) }
                } else { entries[path] = entry }
            } else if relative.localizedCaseInsensitiveContains(query) {
                entries[entry.path] = entry
            }
        }
        return entries.values.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    var selectedPaths: Set<String> {
        guard let document else { return [] }
        return Set(document.entries.filter { entry in
            selection.contains(entry.path) || selection.contains { entry.path.hasPrefix($0 + "/") }
        }.map(\.path))
    }

    var selectedEntry: ArchiveEntry? {
        guard selection.count == 1, let path = selection.first else { return nil }
        return rows.first { $0.path == path }
    }

    func navigate(_ path: String) {
        directory = path; selection = []; query = ""
    }

    func pickArchive() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Открыть архив"
        panel.message = "ZIP, 7z, RAR, TAR и другие форматы"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            Task { @MainActor in
                if response == .OK, let url = panel.url { self.open(url) }
            }
        }
    }

    func pickInput() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Добавить файлы и папки"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.begin { response in
            Task { @MainActor in if response == .OK { self.addInputs(panel.urls) } }
        }
    }

    func addInputs(_ urls: [URL]) {
        guard !busy else { return }
        let wasEmpty = inputFiles.isEmpty
        for url in urls where !inputFiles.contains(url) { inputFiles.append(url) }
        if wasEmpty, let first = inputFiles.first {
            archiveName = inputFiles.count == 1 ? first.deletingPathExtension().lastPathComponent : "Архив"
        }
        page = .create
    }

    func handleDrop(_ urls: [URL]) {
        guard !busy else { return }
        let extensions = Set(["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "tbz2", "txz", "zst", "tzst", "iso", "dmg", "cab", "arj", "lzh", "lha", "cpio", "xar", "deb", "rpm", "001", "z"])
        if page != .create, urls.count == 1, let url = urls.first, extensions.contains(url.pathExtension.lowercased()) {
            open(url)
        } else if page == .archives, document != nil {
            if canAddOrDelete { addToArchive(urls) }
            else { notice = Notice(title: "Архив доступен для чтения", message: "Добавление файлов в этот формат не поддерживается.") }
        } else { addInputs(urls) }
    }

    private func perform<T: Sendable>(_ title: String, detail: String,
                                     work: @escaping @Sendable (ArchiveEngine) throws -> T,
                                     success: @escaping (T) -> Void,
                                     failure: ((Error) -> Void)? = nil) {
        guard !busy else { return }
        busy = true; operationTitle = title; operationDetail = detail
        let operationRunner = ProcessRunner()
        runner = operationRunner
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try work(ArchiveEngine(runner: operationRunner))
                }.value
                try operationRunner.checkCancellation()
                busy = false; runner = nil
                if passwordPrompt {
                    // Keep the same sheet throughout failed attempts. On success,
                    // wait for its dismissal before presenting an editor or alert.
                    passwordAction = nil
                    afterPasswordDismissal = { success(result) }
                    passwordPrompt = false
                } else { success(result) }
            } catch {
                busy = false; runner = nil
                if case ArchiveError.cancelled = error { cancelPassword(); notify("Операция отменена"); return }
                if case ArchiveError.passwordRequired = error {
                    if let failure { failure(error) }
                    else { cancelPassword(); notice = Notice(title: "Требуется пароль", message: error.localizedDescription) }
                    return
                }
                let reportError = {
                    if let failure { failure(error) }
                    else { self.notice = Notice(title: "Не удалось завершить операцию", message: error.localizedDescription) }
                }
                if passwordPrompt {
                    passwordAction = nil
                    afterPasswordDismissal = reportError
                    passwordPrompt = false
                } else { reportError() }
            }
        }
    }

    func cancel() { operationTitle = "Отмена…"; runner?.cancel() }

    func open(_ url: URL, password: String = "", preservingDirectory: String = "") {
        guard !busy else { return }
        perform("Открытие архива", detail: url.lastPathComponent,
                work: { try $0.open(url, password: password) }, success: { doc in
            self.document?.cleanUp()
            self.document = doc; self.currentPassword = password
            self.navigate(preservingDirectory); self.page = .archives
            self.recent.removeAll { $0 == url }; self.recent.insert(url, at: 0)
            self.recent = Array(self.recent.prefix(8))
            UserDefaults.standard.set(self.recent.map(\.path), forKey: "recent")
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { self.open(url, password: $0) }
            } else { self.notice = Notice(title: "Не удалось открыть архив", message: error.localizedDescription) }
        })
    }

    func closeArchive() {
        guard !busy else { return }
        document?.cleanUp(); document = nil; currentPassword = ""; navigate("")
    }

    var canModify: Bool { document?.editableFormat != nil && !busy }
    var canAddOrDelete: Bool { canModify && document?.editableFormat != .gzip }

    func pickArchiveAdd() {
        guard canAddOrDelete else { return }
        let panel = NSOpenPanel()
        panel.title = "Добавить в архив"
        panel.message = directory.isEmpty ? "Файлы будут добавлены в корень архива." : "Добавить в папку: \(directory)"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.begin { response in
            Task { @MainActor in if response == .OK { self.addToArchive(panel.urls) } }
        }
    }

    func addToArchive(_ files: [URL]) {
        guard let doc = document, canAddOrDelete, !files.isEmpty else { return }
        let prefix = directory.isEmpty ? "" : directory + "/"
        pendingAdd = (files, directory)
        if files.contains(where: { file in doc.entries.contains { $0.path == prefix + file.lastPathComponent } }) {
            addConflictPrompt = true
        } else { confirmArchiveAdd() }
    }

    func confirmArchiveAdd() {
        guard let doc = document, let pending = pendingAdd else { return }
        pendingAdd = nil
        withPassword { password in
            self.mutateArchive(doc, password: password, title: "Добавление файлов", history: "Добавлено объектов: \(pending.files.count)") { engine, keepBackup, secret in
                try engine.add(files: pending.files, to: doc, directory: pending.directory, password: secret, keepBackup: keepBackup)
            }
        }
    }

    func deleteSelected() {
        guard canAddOrDelete, !selection.isEmpty else { return }
        deletePrompt = true
    }

    func confirmDelete() {
        guard let doc = document, canAddOrDelete else { return }
        // Use the visible selection; the engine also handles implicit directories.
        let paths = selection
        withPassword { password in
            self.mutateArchive(doc, password: password, title: "Удаление из архива", history: "Удалено объектов: \(paths.count)") { engine, keepBackup, secret in
                try engine.delete(paths: paths, from: doc, password: secret, keepBackup: keepBackup)
            }
        }
    }

    private func mutateArchive(_ doc: ArchiveDocument, password: String, title: String, history: String,
                               work: @escaping @Sendable (ArchiveEngine, Bool, String) throws -> URL?, after: (() -> Void)? = nil) {
        let directory = directory
        let keepBackup = UserDefaults.standard.object(forKey: "backupBeforeChanges") as? Bool ?? true
        perform(title, detail: doc.url.lastPathComponent, work: { try work($0, keepBackup, password) }, success: { backup in
            self.record("Обновлён", detail: history + (backup == nil ? "" : " · Резервная копия сохранена рядом с архивом"), source: doc.url, result: doc.url)
            self.notify(backup == nil ? "Изменения сохранены" : "Изменения сохранены. Резервная копия — рядом с архивом.")
            after?()
            if self.document?.url == doc.url { self.currentPassword = password; self.open(doc.url, password: password, preservingDirectory: directory) }
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { secret in
                    self.mutateArchive(doc, password: secret, title: title, history: history, work: work, after: after)
                }
            } else { self.notice = Notice(title: "Изменения не записаны", message: error.localizedDescription + "\nИсходный архив сохранён.") }
        })
    }

    func editSelected() {
        guard let entry = selectedEntry, let doc = document, canModify, !entry.isDirectory, !entry.isLink else { return }
        if editingSession != nil {
            notice = Notice(title: "Документ уже редактируется", message: "Сначала сохраните или отмените текущее редактирование.")
            return
        }
        guard entry.size <= 100 * 1024 * 1024 else {
            notice = Notice(title: "Большой документ", message: "Редактирование из архива доступно для файлов до 100 МБ. Для этого файла используйте распаковку.")
            return
        }
        let safeExtensions = Set(["txt", "md", "markdown", "rtf", "doc", "docx", "odt", "csv", "tsv", "xls", "xlsx", "ods", "ppt", "pptx", "odp", "pdf", "json", "yaml", "yml", "xml", "html", "css", "swift", "c", "cpp", "h", "hpp", "rs", "go", "java", "kt", "sql", "toml", "ini", "conf", "log", "tex", "png", "jpg", "jpeg", "heic", "tiff", "svg"])
        guard safeExtensions.contains((entry.name as NSString).pathExtension.lowercased()) else {
            notice = Notice(title: "Редактор недоступен", message: "Этот тип файла нельзя редактировать из архива. Распакуйте его, чтобы открыть подходящей программой.")
            return
        }
        withPassword { self.prepareEdit(doc, entry: entry, password: $0) }
    }

    private func prepareEdit(_ doc: ArchiveDocument, entry: ArchiveEntry, password: String) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-editor-" + UUID().uuidString)
        perform("Подготовка документа", detail: entry.name, work: { engine -> PreparedEdit in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do {
                let file = try engine.extract(doc, to: temp, paths: [entry.path], password: password).appendingPathComponent(entry.path)
                return PreparedEdit(file: file, digest: try engine.fingerprint(file))
            }
            catch { try? FileManager.default.removeItem(at: temp); throw error }
        }, success: { prepared in
            let file = prepared.file
            self.currentPassword = password
            let textExtensions = Set(["txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml", "xml", "html", "css", "swift", "c", "cpp", "h", "hpp", "rs", "go", "java", "kt", "sql", "toml", "ini", "conf", "log", "tex", "svg"])
            let ext = (entry.name as NSString).pathExtension.lowercased()
            var encoding = String.Encoding.utf8
            if textExtensions.contains(ext), entry.size <= 5 * 1024 * 1024,
               let text = try? String(contentsOf: file, usedEncoding: &encoding) {
                self.editorText = text
                self.editingSession = EditingSession(document: doc, entry: entry, fileURL: file, directory: temp, encoding: encoding, password: password, originalDigest: prepared.digest)
                self.textEditorPresented = true
            } else {
                self.editingSession = EditingSession(document: doc, entry: entry, fileURL: file, directory: temp, encoding: encoding, password: password, originalDigest: prepared.digest)
                self.openExternalEditor()
            }
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { self.prepareEdit(doc, entry: entry, password: $0) }
            } else { self.notice = Notice(title: "Не удалось открыть документ", message: error.localizedDescription) }
        })
    }

    func openExternalEditor() {
        guard let session = editingSession else { return }
        if !NSWorkspace.shared.open(session.fileURL) {
            notice = Notice(title: "Не найден редактор", message: "Установите программу для этого формата или выберите другой документ.")
        }
    }

    func saveTextToArchive() {
        guard let session = editingSession else { return }
        do {
            try editorText.write(to: session.fileURL, atomically: true, encoding: session.encoding)
            textEditorPresented = false
            saveEditingSession()
        } catch { notice = Notice(title: "Не удалось сохранить документ", message: error.localizedDescription) }
    }

    func switchToExternalEditor() {
        guard let session = editingSession else { return }
        do {
            try editorText.write(to: session.fileURL, atomically: true, encoding: session.encoding)
            textEditorPresented = false
            openExternalEditor()
        } catch { notice = Notice(title: "Не удалось открыть редактор", message: error.localizedDescription) }
    }

    func saveEditingSession() {
        guard let session = editingSession, !busy else { return }
        let password = session.password
        mutateArchive(session.document, password: password, title: "Сохранение документа", history: "Обновлён файл: \(session.entry.path)", work: { engine, keepBackup, secret in
            try engine.replace(session.entry, with: session.fileURL, in: session.document, password: secret, keepBackup: keepBackup, expectedDigest: session.originalDigest)
        }, after: { self.discardEditingSession() })
    }

    func discardEditingSession() {
        textEditorPresented = false
        if let session = editingSession { try? FileManager.default.removeItem(at: session.directory) }
        editingSession = nil; editorText = ""
    }

    private func askPassword(wrong: Bool = false, action: @escaping (String) -> Void) {
        passwordError = wrong ? "Неверный пароль. Попробуйте ещё раз." : ""
        passwordAttemptID = UUID()
        passwordAction = action; passwordPrompt = true
    }

    func submitPassword(_ password: String) {
        guard !busy, !password.isEmpty else { return }
        passwordError = ""
        let action = passwordAction; passwordAction = nil
        action?(password)
    }

    func cancelPassword() {
        if busy { runner?.cancel() }
        passwordPrompt = false; passwordAction = nil; passwordError = ""
        afterPasswordDismissal = nil
    }

    func passwordSheetDidDismiss() {
        let completion = afterPasswordDismissal
        afterPasswordDismissal = nil
        passwordError = ""
        completion?()
    }

    private func withPassword(_ action: @escaping (String) -> Void) {
        if document?.isEncrypted == true, currentPassword.isEmpty {
            askPassword { password in self.currentPassword = password; action(password) }
        } else { action(currentPassword) }
    }

    func extract(selected: Bool = false) {
        guard document != nil, !busy else { return }
        let paths: Set<String>? = selected ? selectedPaths : nil
        guard paths == nil || !paths!.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = "Куда распаковать архив?"
        panel.message = "В выбранной папке будет создана отдельная папка с содержимым архива."
        panel.prompt = "Распаковать сюда"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let parent = panel.url else { return }
                self.extractToDirectory(parent, paths: paths)
            }
        }
    }

    /// Shared entry point for extraction into an already selected destination.
    func extractToDirectory(_ parent: URL, paths: Set<String>? = nil) {
        guard let doc = document, !busy else { return }
        withPassword { self.extract(doc, parent: parent, paths: paths, password: $0) }
    }

    private func extract(_ doc: ArchiveDocument, parent: URL, paths: Set<String>?, password: String) {
        perform("Распаковка", detail: doc.url.lastPathComponent,
                work: { try $0.extract(doc, to: parent, paths: paths, password: password) }, success: { result in
            self.currentPassword = password
            self.record("Распакован", detail: paths == nil ? "Все файлы" : "Выбранные объекты: \(paths!.count)", source: doc.url, result: result)
            self.notify("Архив распакован")
            if UserDefaults.standard.object(forKey: "revealAfterExtract") as? Bool ?? true {
                NSWorkspace.shared.activateFileViewerSelecting([result])
            }
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { self.extract(doc, parent: parent, paths: paths, password: $0) }
            } else {
                self.record("Ошибка распаковки", detail: error.localizedDescription, source: doc.url, succeeded: false)
                self.notice = Notice(title: "Не удалось распаковать архив", message: error.localizedDescription)
            }
        })
    }

    func testArchive() {
        guard let doc = document, !busy else { return }
        withPassword { self.runTest(doc, password: $0) }
    }

    private func runTest(_ doc: ArchiveDocument, password: String) {
        perform("Проверка целостности", detail: doc.url.lastPathComponent,
                work: { try $0.test(doc, password: password) }, success: { _ in
            self.currentPassword = password
            self.record("Проверен", detail: "Ошибок не найдено", source: doc.url)
            self.notice = Notice(title: "Архив в порядке", message: "Все файлы прошли проверку целостности.")
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { self.runTest(doc, password: $0) }
            } else {
                self.record("Ошибка проверки", detail: error.localizedDescription, source: doc.url, succeeded: false)
                self.notice = Notice(title: "Проверка не пройдена", message: error.localizedDescription)
            }
        })
    }

    func preview(_ entry: ArchiveEntry) {
        if entry.isDirectory { navigate(entry.path); return }
        guard let doc = document, !busy else { return }
        guard entry.size <= 100 * 1024 * 1024 else {
            notice = Notice(title: "Большой файл", message: "Для предпросмотра доступны файлы до 100 МБ. Распакуйте этот файл, чтобы открыть его.")
            return
        }
        withPassword { self.runPreview(doc, entry: entry, password: $0) }
    }

    private func runPreview(_ doc: ArchiveDocument, entry: ArchiveEntry, password: String) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("MacZip-preview-" + UUID().uuidString)
        perform("Подготовка предпросмотра", detail: entry.name, work: { engine -> URL in
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do { return try engine.extract(doc, to: temp, paths: [entry.path], password: password) }
            catch { try? FileManager.default.removeItem(at: temp); throw error }
        }, success: { output in
            self.clearPreview()
            self.currentPassword = password; self.previewDirectory = temp
            self.previewURL = output.appendingPathComponent(entry.path); self.previewPresented = true
        }, failure: { error in
            if case ArchiveError.passwordRequired = error {
                self.askPassword(wrong: !password.isEmpty) { self.runPreview(doc, entry: entry, password: $0) }
            } else { self.notice = Notice(title: "Предпросмотр недоступен", message: error.localizedDescription) }
        })
    }

    func clearPreview() {
        previewURL = nil
        if let previewDirectory { try? FileManager.default.removeItem(at: previewDirectory) }
        previewDirectory = nil
    }

    var canCreate: Bool {
        !busy && !inputFiles.isEmpty && !archiveName.trimmingCharacters(in: .whitespaces).isEmpty
            && (!protectArchive || (!newPassword.isEmpty && newPassword == confirmPassword))
            && !zipPasswordUnsupported
    }

    var zipPasswordUnsupported: Bool {
        protectArchive && format == .zip && newPassword.unicodeScalars.contains { $0.value < 32 || $0.value > 126 }
    }

    func saveArchive() {
        guard canCreate else { return }
        guard !archiveName.contains("/"), !archiveName.contains(":"), archiveName != ".", archiveName != ".." else {
            notice = Notice(title: "Проверьте имя архива", message: "Имя не должно содержать / и :.")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Создать архив"
        panel.nameFieldStringValue = archiveName + "." + format.fileExtension
        panel.canCreateDirectories = true
        panel.message = "Выберите новое имя: существующие архивы не перезаписываются."
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let destination = panel.url else { return }
                self.createArchive(at: destination)
            }
        }
    }

    private func createArchive(at destination: URL) {
        let files = inputFiles, format = format, level = compression
        let password = protectArchive && format.supportsPassword ? newPassword : ""
        let encryptNames = encryptNames
        let exclude = UserDefaults.standard.object(forKey: "excludeMacMetadata") as? Bool ?? true
        perform("Создание архива", detail: destination.lastPathComponent,
                work: { try $0.create(files: files, destination: destination, format: format, level: level,
                                      password: password, encryptNames: encryptNames, excludeMacMetadata: exclude) }, success: { _ in
            self.record("Создан", detail: "\(format.title) · \(level.title)", source: destination, result: destination)
            self.newPassword = ""; self.confirmPassword = ""; self.protectArchive = false
            self.notify("Архив создан")
            self.open(destination, password: password)
        }, failure: { error in
            self.record("Ошибка создания", detail: error.localizedDescription, source: destination, succeeded: false)
            self.notice = Notice(title: "Не удалось создать архив", message: error.localizedDescription)
        })
    }

    private func record(_ title: String, detail: String, source: URL, result: URL? = nil, succeeded: Bool = true) {
        history.insert(ActivityItem(title: title, detail: detail, source: source, result: result, succeeded: succeeded), at: 0)
        history = Array(history.prefix(60))
        persistHistory()
    }

    func clearHistory() { history = []; persistHistory() }
    func clearRecent() { recent = []; UserDefaults.standard.removeObject(forKey: "recent") }
    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "history") }
    }

    func notify(_ text: String) {
        toastTask?.cancel(); toast = text
        toastTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { toast = "" }
        }
    }

    func shutdown() { runner?.cancel(); document?.cleanUp(); clearPreview(); discardEditingSession() }
}

func readableSize(_ size: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
}
