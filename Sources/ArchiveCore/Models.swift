import Foundation

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let size: Int64
    public let packedSize: Int64?
    public let isDirectory: Bool
    public let isEncrypted: Bool
    public let modified: String
    public let crc: String
    public let isLink: Bool
    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, size: Int64 = 0, packedSize: Int64? = nil, isDirectory: Bool = false,
                isEncrypted: Bool = false, modified: String = "", crc: String = "", isLink: Bool = false) {
        self.path = path; self.size = size; self.packedSize = packedSize
        self.isDirectory = isDirectory; self.isEncrypted = isEncrypted
        self.modified = modified; self.crc = crc; self.isLink = isLink
    }
}

public struct ArchiveDocument: Sendable {
    public let url: URL
    public let contentURL: URL
    public let entries: [ArchiveEntry]
    public let temporaryDirectory: URL?
    public let hasEncryptedHeaders: Bool
    public var totalSize: Int64 { entries.filter { !$0.isDirectory }.reduce(0) { $0 + $1.size } }
    public var fileCount: Int { entries.filter { !$0.isDirectory }.count }
    public var isEncrypted: Bool { entries.contains { $0.isEncrypted } }
    public var editableFormat: ArchiveFormat? { ArchiveFormat.detect(url) }

    public func cleanUp() {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }
}

public enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip, sevenZip, tar, tarGzip, tarBzip2, tarXZ, gzip
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7z"
        case .tar: return "TAR"
        case .tarGzip: return "TAR.GZ"
        case .tarBzip2: return "TAR.BZ2"
        case .tarXZ: return "TAR.XZ"
        case .gzip: return "GZIP"
        }
    }
    public var fileExtension: String { self == .sevenZip ? "7z" : self == .gzip ? "gz" : title.lowercased() }
    public var supportsPassword: Bool { self == .zip || self == .sevenZip }
    public var compressor: String? {
        switch self {
        case .tarGzip: return "gzip"
        case .tarBzip2: return "bzip2"
        case .tarXZ: return "xz"
        default: return nil
        }
    }
    public var explanation: String {
        switch self {
        case .zip: return "Универсальный формат. Удобно отправлять и открывать на любом компьютере."
        case .sevenZip: return "Максимальное сжатие, AES-256 и возможность скрыть имена файлов."
        case .tar: return "Объединение файлов без сжатия. Сохраняет структуру папок."
        case .tarGzip: return "Привычный формат для Linux и macOS с быстрым сжатием."
        case .tarBzip2: return "TAR со сжатием Bzip2: компактнее, но медленнее Gzip."
        case .tarXZ: return "TAR со сжатием XZ: небольшой размер для хранения и резервных копий."
        case .gzip: return "Сжатие одного файла в .gz. Для нескольких файлов и папок выберите TAR.GZ."
        }
    }

    public static func detect(_ url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGzip }
        if name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") || name.hasSuffix(".tbz2") { return .tarBzip2 }
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".txz") { return .tarXZ }
        switch url.pathExtension.lowercased() {
        case "zip": return .zip
        case "7z": return .sevenZip
        case "tar": return .tar
        case "gz", "gzip": return .gzip
        default: return nil
        }
    }
}

public enum CompressionLevel: Int, CaseIterable, Identifiable, Sendable {
    case store = 0, fast = 1, normal = 5, maximum = 9
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .store: return "Без сжатия"
        case .fast: return "Быстрое"
        case .normal: return "Обычное"
        case .maximum: return "Максимальное"
        }
    }
}

public enum ArchiveError: LocalizedError {
    case missingEngine, passwordRequired, cancelled
    case unsafePath(String), unsupportedLink(String), invalidInput(String), engine(String), destinationExists
    public var errorDescription: String? {
        switch self {
        case .missingEngine: return "Движок 7-Zip не найден. Соберите приложение командой ./Scripts/build.sh."
        case .passwordRequired: return "Архив защищён паролем. Введите пароль и повторите попытку."
        case .cancelled: return "Операция отменена."
        case .unsafePath(let path): return "Небезопасный путь в архиве: \(path). Распаковка остановлена."
        case .unsupportedLink(let path): return "В архиве есть ссылка: \(path). Для безопасной распаковки выберите обычные файлы."
        case .invalidInput(let message): return message
        case .engine(let message): return "7-Zip: \(message)"
        case .destinationExists: return "Файл с таким именем уже существует. Выберите другое имя."
        }
    }
}
