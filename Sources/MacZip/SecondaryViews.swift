import SwiftUI
import ArchiveCore
import AppKit

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.history.isEmpty {
            VStack(spacing: 18) {
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(Color.brandAccent)
                Text("Здесь будет история").font(.system(size: 21, weight: .semibold))
                Text("Созданные, распакованные и проверенные архивы\nбудут появляться здесь после завершения операции.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Button("Открыть архив…") { model.pickArchive() }.controlSize(.large).padding(.top, 6)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Последние операции").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("Очистить историю") { model.clearHistory() }.buttonStyle(.borderless).font(.system(size: 11))
                    }
                    VStack(spacing: 0) {
                        ForEach(model.history) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 19)).foregroundStyle(item.succeeded ? Color.brandAccent : .orange).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 8) {
                                        Text(item.source.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                        Text(item.title).font(.system(size: 9, weight: .medium)).foregroundStyle(item.succeeded ? Color.brandAccent : .orange)
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background((item.succeeded ? Color.brandAccent : .orange).opacity(0.08), in: Capsule())
                                    }
                                    Text(item.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                                    Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 12)
                                if let result = item.result {
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([result]) } label: {
                                        Label("В Finder", systemImage: "arrow.up.right")
                                    }.buttonStyle(.borderless).font(.system(size: 11)).padding(.top, 4)
                                }
                            }.padding(20)
                            if item.id != model.history.last?.id { Divider().padding(.leading, 54) }
                        }
                    }.background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
                    Text("До 60 последних операций. Пароли в историю не записываются.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(28)
            }
        }
    }
}

struct FormatsView: View {
    private let formats: [(String, String, Bool, Bool, String)] = [
        ("ZIP", "zip", true, true, "Да"),
        ("ZIPX", "zipx", false, true, "—"),
        ("7-Zip", "7z", true, true, "Да"),
        ("RAR", "rar, r00 · RAR 4 / 5", false, true, "—"),
        ("TAR", "tar", true, false, "Да"),
        ("TAR + сжатие", "tar.gz, tgz, tar.bz2, tbz2, tar.xz, txz", true, false, "Да"),
        ("Gzip", "gz · один файл", true, false, "Файл"),
        ("Bzip2, XZ, Zstandard", "bz2, xz, zst, tar.zst, tzst", false, false, "—"),
        ("Образы дисков", "iso, dmg, udf", false, false, "—"),
        ("Пакеты и другие архивы", "cab, arj, lzh, lha, cpio, xar, deb, rpm, Z", false, false, "—")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Знакомые форматы. Одна утилита.").font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("Просматривайте и распаковывайте популярные архивы. Для новых архивов выбирайте формат, который подходит вашей задаче.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("ФОРМАТ").frame(maxWidth: .infinity, alignment: .leading)
                        Text("ОТКРЫТЬ").frame(width: 65)
                        Text("СОЗДАТЬ").frame(width: 65)
                        Text("ИЗМЕНИТЬ").frame(width: 70)
                        Text("ПАРОЛЬ").frame(width: 65)
                    }.font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.tertiary).padding(18)
                    Divider()
                    ForEach(Array(formats.enumerated()), id: \.offset) { index, format in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(format.0).font(.system(size: 12, weight: .semibold))
                                Text(format.1).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            mark(true).frame(width: 65)
                            mark(format.2).frame(width: 65)
                            Text(format.4).font(.system(size: 10, weight: .medium)).foregroundStyle(format.4 == "—" ? Color.secondary.opacity(0.35) : Color.brandAccent).frame(width: 70)
                            mark(format.3).frame(width: 65)
                        }.padding(18)
                        if index != formats.count - 1 { Divider().padding(.horizontal, 18) }
                    }
                }.background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(Color.brandAccent)
                    Text("В ZIP, 7z и TAR можно добавлять и удалять файлы, а документы — редактировать с сохранением обратно в архив. В Gzip доступна замена единственного файла. RAR и ISO открываются для просмотра и распаковки.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                }.padding(18).background(Color.brandAccent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Text("Многотомный архив открывайте с первой части (.part1.rar, .rar или .001). Все части должны находиться в одной папке. Возможности чтения зависят от метода сжатия и шифрования конкретного архива.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineSpacing(4)
            }.padding(32).frame(maxWidth: 960).frame(maxWidth: .infinity)
        }
    }

    private func mark(_ enabled: Bool) -> some View {
        Image(systemName: enabled ? "checkmark" : "minus").font(.system(size: 12, weight: enabled ? .semibold : .regular))
            .foregroundStyle(enabled ? Color.brandAccent : Color.secondary.opacity(0.35))
            .accessibilityLabel(enabled ? "Поддерживается" : "Не поддерживается")
    }
}

struct SettingsView: View {
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("defaultFormat") private var defaultFormat = "zip"
    @AppStorage("revealAfterExtract") private var revealAfterExtract = true
    @AppStorage("excludeMacMetadata") private var excludeMacMetadata = true
    @AppStorage("backupBeforeChanges") private var backupBeforeChanges = true

    var body: some View {
        Form {
            Section("Оформление") {
                Picker("Тема", selection: $appearance) {
                    Text("Как в системе").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
            }
            Section("Архивы") {
                Picker("Формат при запуске", selection: $defaultFormat) {
                    ForEach(ArchiveFormat.allCases) { format in Text(format.title).tag(format.rawValue) }
                }
                Toggle("Показывать результат распаковки в Finder", isOn: $revealAfterExtract)
                Toggle("Исключать служебные файлы macOS", isOn: $excludeMacMetadata)
                Toggle("Сохранять резервную копию перед изменением архива", isOn: $backupBeforeChanges)
            }
            Section("О приложении") {
                HStack(spacing: 13) {
                    AppMark(size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MacZip 1.0").font(.headline)
                        Text("Архивы в порядке. Файлы под рукой.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 7)
                Text("MacZip использует 7-Zip 26.05 © Igor Pavlov. 7-Zip распространяется по GNU LGPL, с компонентами BSD и ограничениями лицензии unRAR.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("7-Zip: исходный код и лицензия", destination: URL(string: "https://www.7-zip.org/")!)
                Button("Показать лицензии в Finder") {
                    let licenses = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/7zip")
                    if FileManager.default.fileExists(atPath: licenses.path) { NSWorkspace.shared.open(licenses) }
                    else { NSWorkspace.shared.open(URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Vendor/7zip")) }
                }
            }
        }.formStyle(.grouped).frame(width: 510, height: 540)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}
