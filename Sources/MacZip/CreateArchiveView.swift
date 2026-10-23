import SwiftUI
import ArchiveCore
import AppKit
import UniformTypeIdentifiers

struct CreateArchiveView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("excludeMacMetadata") private var excludeMacMetadata = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    filesCard.frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 24) {
                        formatCard
                        securityCard
                    }.frame(width: 310)
                }
                HStack(spacing: 14) {
                    Image(systemName: "info.circle").foregroundStyle(.tertiary)
                    Text("Исходные файлы останутся на месте. Архив сохранится в выбранную папку.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Divider()
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Имя архива").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            TextField("Архив", text: $model.archiveName).textFieldStyle(.plain).font(.system(size: 13))
                            Text("." + model.format.fileExtension).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        }.padding(11).background(Color.panel, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
                    }.frame(maxWidth: 360)
                    Spacer()
                    Button { model.saveArchive() } label: {
                        Label("Создать архив…", systemImage: "archivebox").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canCreate).padding(.top, 17)
                }
            }.padding(28).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                sectionTitle("01", "Файлы и папки")
                Spacer()
                if !model.inputFiles.isEmpty {
                    Button("Очистить") { model.inputFiles = [] }.buttonStyle(.borderless).font(.system(size: 10))
                }
            }
            if model.inputFiles.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Color.brandAccent)
                    VStack(spacing: 7) {
                        Text("Начните с ваших файлов").font(.system(size: 14, weight: .medium))
                        Text("Перетащите сюда файлы и папки\nили выберите их на вашем Mac")
                            .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
                    }
                    Button("Выбрать файлы…") { model.pickInput() }.controlSize(.large)
                }.frame(maxWidth: .infinity).frame(height: 255)
                    .background(Color.brandAccent.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.brandAccent.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5])))
            } else {
                VStack(spacing: 0) {
                    ForEach(model.inputFiles, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                Text(url.deletingLastPathComponent().path).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Button { model.inputFiles.removeAll { $0 == url } } label: {
                                Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(.secondary).padding(5)
                            }.buttonStyle(.plain).help("Убрать \(url.lastPathComponent)")
                        }.padding(.vertical, 12)
                        if url != model.inputFiles.last { Divider() }
                    }
                }
                Button { model.pickInput() } label: { Label("Добавить ещё", systemImage: "plus") }
                    .buttonStyle(.borderless).font(.system(size: 12))
                Text("Объектов: \(model.inputFiles.count)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Divider()
            Toggle(isOn: $excludeMacMetadata) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Без служебных файлов macOS").font(.system(size: 11, weight: .medium))
                    Text("Не добавлять .DS_Store и __MACOSX").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.checkbox)
        }.padding(22).background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionTitle("02", "Формат и сжатие")
            Picker("Формат", selection: $model.format) {
                ForEach(ArchiveFormat.allCases) { format in Text(format.title).tag(format) }
            }.pickerStyle(.menu).font(.system(size: 12))
                .onChange(of: model.format) { _, format in
                    if !format.supportsPassword { model.protectArchive = false; model.newPassword = ""; model.confirmPassword = "" }
                }
            Text(model.format.explanation).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Picker("Сжатие", selection: $model.compression) {
                ForEach(CompressionLevel.allCases.filter { (model.format.compressor == nil && model.format != .gzip) || $0 != .store }) { level in Text(level.title).tag(level) }
            }.pickerStyle(.menu).font(.system(size: 12)).disabled(model.format == .tar)
            if model.format == .tar {
                Text("TAR объединяет файлы без сжатия.").font(.system(size: 10)).foregroundStyle(.tertiary)
            } else {
                Text(model.compression == .maximum ? "Меньше размер, больше времени и памяти." : model.compression == .fast ? "Меньше времени на упаковку." : model.compression == .store ? "Объединить файлы без уменьшения размера." : "Баланс скорости и размера архива.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.padding(22).background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
            .onChange(of: model.format) { _, format in
                if format.compressor != nil || format == .gzip, model.compression == .store { model.compression = .normal }
            }
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            sectionTitle("03", "Защита")
            Toggle("Защитить паролем", isOn: $model.protectArchive)
                .font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).disabled(!model.format.supportsPassword)
            if !model.format.supportsPassword {
                Text("Для защиты паролем выберите ZIP или 7z.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else if model.protectArchive {
                VStack(spacing: 10) {
                    SecureField("Пароль", text: $model.newPassword)
                    SecureField("Повторите пароль", text: $model.confirmPassword)
                }.textFieldStyle(.roundedBorder).controlSize(.large)
                if !model.confirmPassword.isEmpty, model.newPassword != model.confirmPassword {
                    Text("Пароли не совпадают").font(.system(size: 10)).foregroundStyle(.red)
                }
                if model.zipPasswordUnsupported {
                    Text("В ZIP используйте латиницу, цифры и символы. Для кириллицы и эмодзи выберите 7z.")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                if model.format == .sevenZip {
                    Toggle("Скрыть имена файлов", isOn: $model.encryptNames).toggleStyle(.checkbox).font(.system(size: 11))
                }
                Label("Шифрование AES-256", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(Color.brandAccent)
                Text("Сохраните пароль: восстановить его нельзя.").font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Добавьте пароль, если в архиве есть личные или рабочие документы.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            }
        }.padding(22).background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07)))
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Color.brandAccent)
                .frame(width: 23, height: 23).background(Color.brandAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
    }
}
