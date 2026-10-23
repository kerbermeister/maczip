import SwiftUI
import AppKit
import ArchiveCore
import UniformTypeIdentifiers

struct ArchiveBrowserView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sort = "name"

    private var sortedRows: [ArchiveEntry] {
        if sort == "size" {
            return model.rows.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.size > $1.size }
        }
        if sort == "date" {
            return model.rows.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.modified > $1.modified }
        }
        return model.rows
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                browserBar
                Divider()
                Table(sortedRows, selection: $model.selection) {
                    TableColumn("Имя") { entry in
                        HStack(spacing: 9) {
                            fileIcon(entry).resizable().frame(width: 19, height: 19)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                if !model.query.isEmpty, entry.path != entry.name {
                                    Text(entry.path).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                            if entry.isEncrypted { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                            if entry.isLink { Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.orange) }
                        }.padding(.vertical, 5).help(entry.path)
                    }.width(min: 150, ideal: 240)
                    TableColumn("Размер") { entry in
                        Text(entry.isDirectory ? "—" : readableSize(entry.size))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }.width(min: 65, ideal: 85, max: 100)
                    TableColumn("Тип") { entry in
                        Text(entry.isDirectory ? "Папка" : typeLabel(entry)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }.width(min: 60, ideal: 75, max: 100)
                    TableColumn("Изменён") { entry in
                        Text(String(entry.modified.prefix(16))).font(.system(size: 10)).foregroundStyle(.secondary)
                    }.width(min: 105, ideal: 115, max: 140)
                }
                .alternatingRowBackgrounds(.enabled)
                .contextMenu(forSelectionType: String.self) { ids in
                    if !ids.isEmpty {
                        Button("Распаковать выбранное…") { model.selection = ids; model.extract(selected: true) }
                        if ids.count == 1, let path = ids.first, let entry = model.rows.first(where: { $0.path == path }) {
                            Button(entry.isDirectory ? "Открыть папку" : "Быстрый просмотр") { model.preview(entry) }
                            if model.canModify, !entry.isDirectory, !entry.isLink {
                                Button("Редактировать документ…") { model.selection = ids; model.editSelected() }
                            }
                        }
                        Divider()
                        Button("Скопировать путь") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ids.sorted().joined(separator: "\n"), forType: .string)
                        }
                        if model.canAddOrDelete {
                            Divider()
                            Button("Удалить из архива…", role: .destructive) { model.selection = ids; model.deleteSelected() }
                        }
                    }
                } primaryAction: { ids in
                    if let path = ids.first, let entry = model.rows.first(where: { $0.path == path }) { model.preview(entry) }
                }
                .onKeyPress(.space) {
                    guard let entry = model.selectedEntry else { return .ignored }
                    model.preview(entry); return .handled
                }
                .overlay {
                    if sortedRows.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: model.query.isEmpty ? "folder" : "magnifyingglass").font(.system(size: 34, weight: .ultraLight)).foregroundStyle(.tertiary)
                            Text(model.query.isEmpty ? "В этой папке пока пусто" : "Ничего не найдено").font(.headline)
                            if !model.query.isEmpty { Text("Попробуйте другое имя файла").font(.caption).foregroundStyle(.secondary) }
                        }.allowsHitTesting(false)
                    }
                }
                Divider()
                HStack {
                    Text(model.selection.isEmpty ? "Объектов: \(sortedRows.count)" : "Выбрано: \(model.selection.count)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if let entry = model.selectedEntry {
                        Button { model.preview(entry) } label: {
                            Label(entry.isDirectory ? "Открыть" : "Быстрый просмотр", systemImage: entry.isDirectory ? "folder" : "eye")
                        }.font(.system(size: 11)).buttonStyle(.borderless)
                        if model.canModify, !entry.isDirectory, !entry.isLink {
                            Button { model.editSelected() } label: { Image(systemName: "pencil") }
                                .buttonStyle(.borderless).help("Редактировать документ").accessibilityLabel("Редактировать документ")
                        }
                    }
                    if !model.selection.isEmpty {
                        if model.canAddOrDelete {
                            Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).help("Удалить из архива").accessibilityLabel("Удалить из архива")
                        }
                        Button { model.extract(selected: true) } label: { Label("Распаковать выбранное", systemImage: "arrow.down.to.line") }
                            .font(.system(size: 11)).buttonStyle(.borderless).padding(.leading, 12)
                    }
                }.padding(.horizontal, 20).frame(height: 44)
            }
            if model.showInspector {
                Divider()
                inspector.frame(width: 218)
            }
        }
    }

    private var browserBar: some View {
        HStack(spacing: 8) {
            Button {
                model.navigate((model.directory as NSString).deletingLastPathComponent)
            } label: { Image(systemName: "arrow.up").frame(width: 19, height: 20) }
                .buttonStyle(.borderless).disabled(model.directory.isEmpty).help("На уровень выше")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button { model.navigate("") } label: { Image(systemName: "archivebox").font(.system(size: 12)) }
                        .buttonStyle(.plain).help("Корень архива").accessibilityLabel("Корень архива")
                    ForEach(Array(model.directory.split(separator: "/").enumerated()), id: \.offset) { index, part in
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                        Button(String(part)) { model.navigate(model.directory.split(separator: "/").prefix(index + 1).joined(separator: "/")) }
                            .buttonStyle(.plain).font(.system(size: 11)).lineLimit(1)
                    }
                    if model.directory.isEmpty { Text("Все файлы").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(.vertical, 4)
            }
            Spacer(minLength: 4)
            Menu {
                Picker("Сортировка", selection: $sort) {
                    Text("По имени").tag("name")
                    Text("По размеру").tag("size")
                    Text("По дате").tag("date")
                }
            } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize().help("Сортировка")
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Поиск в папке", text: $model.query).textFieldStyle(.plain).font(.system(size: 11))
                    .onChange(of: model.query) { _, _ in model.selection = [] }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help("Очистить поиск")
                }
            }.padding(7).frame(width: 170).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        }.padding(.horizontal, 16).frame(height: 52)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(model.selectedEntry == nil ? "ОБ АРХИВЕ" : "ВЫБРАННЫЙ ОБЪЕКТ")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(.tertiary)
                if let entry = model.selectedEntry {
                    VStack(alignment: .leading, spacing: 13) {
                        fileIcon(entry).resizable().frame(width: 48, height: 48)
                        Text(entry.name).font(.system(size: 15, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(entry.isDirectory ? "Папка в архиве" : typeLabel(entry)).font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    property("Размер", entry.isDirectory ? "—" : readableSize(entry.size))
                    if let packed = entry.packedSize { property("В архиве", readableSize(packed)) }
                    if !entry.modified.isEmpty { property("Изменён", String(entry.modified.prefix(19))) }
                    if !entry.crc.isEmpty { property("CRC", entry.crc) }
                    property("Путь", entry.path)
                    if entry.isEncrypted { securityLabel("Файл зашифрован") }
                    if entry.isLink {
                        Label("Ссылка. Распаковка ограничена.", systemImage: "link").font(.caption).foregroundStyle(.orange)
                    }
                } else if let doc = model.document {
                    VStack(alignment: .leading, spacing: 13) {
                        FileBadge(extensionName: doc.url.pathExtension).scaleEffect(1.3, anchor: .leading).padding(.vertical, 8)
                        Text(doc.url.lastPathComponent).font(.system(size: 15, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text("\(doc.fileCount) файлов в архиве").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    let archiveSize = (try? doc.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                    property("Размер архива", readableSize(archiveSize))
                    property("Без сжатия", readableSize(doc.totalSize))
                    if doc.totalSize > archiveSize, doc.totalSize > 0 {
                        let savings = 1 - Double(archiveSize) / Double(doc.totalSize)
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("Экономия места").font(.system(size: 10)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(savings * 100))%").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Color.brandAccent)
                            }
                            GeometryReader { geometry in
                                Capsule().fill(.primary.opacity(0.07))
                                    .overlay(alignment: .leading) { Capsule().fill(Color.brandAccent).frame(width: max(0, geometry.size.width * savings)) }
                            }.frame(height: 4)
                        }
                    }
                    property("Расположение", doc.url.deletingLastPathComponent().path)
                    if doc.isEncrypted { securityLabel("Зашифрованный архив") }
                    if doc.url.pathExtension.lowercased() == "rar" {
                        Label("RAR: просмотр и распаковка", systemImage: "info.circle")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("Двойной щелчок откроет папку или предпросмотр файла. Пробел — быстрый просмотр.")
                        .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(4)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }.background(.primary.opacity(0.018))
    }

    private func property(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func securityLabel(_ text: String) -> some View {
        Label(text, systemImage: "lock.shield").font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.brandAccent).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fileIcon(_ entry: ArchiveEntry) -> Image {
        Image(nsImage: NSWorkspace.shared.icon(for: entry.isDirectory ? .folder : UTType(filenameExtension: (entry.name as NSString).pathExtension) ?? .data))
    }

    private func typeLabel(_ entry: ArchiveEntry) -> String {
        let ext = (entry.name as NSString).pathExtension
        return ext.isEmpty ? "Файл" : ext.uppercased()
    }
}
