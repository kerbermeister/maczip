import SwiftUI
import ArchiveCore
import QuickLookUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 218, maxWidth: 260)
            VStack(spacing: 0) {
                header
                Divider()
                if let session = model.editingSession { editingBanner(session) }
                Group {
                    switch model.page {
                    case .archives:
                        if model.document == nil { WelcomeView() } else { ArchiveBrowserView() }
                    case .create: CreateArchiveView()
                    case .activity: ActivityView()
                    case .formats: FormatsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(model.busy)
                Divider()
                statusBar
            }
            .frame(minWidth: 790)
            .background(Color.canvas)
        }
        .frame(minWidth: 1020, minHeight: 680)
        .overlay(alignment: .top) {
            if !model.toast.isEmpty {
                Label(model.toast, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium)).padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.regularMaterial, in: Capsule()).shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    .padding(.top, 86).allowsHitTesting(false)
            }
        }
        .overlay {
            if dropTarget {
                RoundedRectangle(cornerRadius: 14).fill(Color.brandAccent.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.brandAccent, style: StrokeStyle(lineWidth: 2, dash: [8])))
                    .overlay(Label(model.page == .create ? "Добавить файлы в архив" : "Отпустите архив или файлы здесь", systemImage: "arrow.down.doc")
                        .font(.title2.weight(.medium)).padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !model.busy else { return false }
            model.handleDrop(urls); return true
        } isTargeted: { dropTarget = $0 }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("Понятно")))
        }
        .sheet(isPresented: $model.passwordPrompt, onDismiss: { model.passwordSheetDidDismiss() }) { PasswordView() }
        .sheet(isPresented: $model.textEditorPresented) { DocumentEditorView() }
        .confirmationDialog("Удалить выбранные объекты из архива?", isPresented: $model.deletePrompt, titleVisibility: .visible) {
            Button("Удалить из архива", role: .destructive) { model.confirmDelete() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Выбрано объектов: \(model.selection.count). Файлы будут удалены после проверки и сохранения новой версии архива.") }
        .confirmationDialog("В архиве уже есть объекты с такими именами", isPresented: $model.addConflictPrompt, titleVisibility: .visible) {
            Button("Добавить с заменой совпадающих файлов") { model.confirmArchiveAdd() }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Содержимое папок будет объединено, совпадающие файлы — заменены.") }
        .confirmationDialog("Отменить редактирование?", isPresented: $model.discardEditingPrompt, titleVisibility: .visible) {
            Button("Отменить изменения", role: .destructive) { model.discardEditingSession() }
            Button("Продолжить редактирование", role: .cancel) {}
        } message: { Text("Несохранённые изменения документа не попадут в архив.") }
        .sheet(isPresented: $model.previewPresented, onDismiss: { model.clearPreview() }) {
            VStack(spacing: 0) {
                HStack {
                    Label(model.previewURL?.lastPathComponent ?? "Предпросмотр", systemImage: "doc")
                        .font(.headline).lineLimit(1)
                    Spacer()
                    Button("Готово") { model.previewPresented = false }.keyboardShortcut(.cancelAction)
                }.padding(18)
                Divider()
                if let url = model.previewURL { QuickLookView(url: url).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }.frame(width: 780, height: 580)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                AppMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacZip").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Всё по папкам.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.top, 48).padding(.bottom, 30)

            Text("РАБОЧЕЕ ПРОСТРАНСТВО").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(.tertiary).padding(.horizontal, 22).padding(.bottom, 10)
            VStack(spacing: 5) {
                ForEach(Page.allCases) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 11) {
                            Image(systemName: page.icon).font(.system(size: 16)).frame(width: 22)
                            Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                            Spacer()
                            if page == .activity, !model.history.isEmpty {
                                Text("\(model.history.count)").font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(.primary.opacity(0.05), in: Capsule())
                            }
                        }
                        .foregroundStyle(model.page == page ? Color.brandAccent : Color.primary.opacity(0.75))
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background(model.page == page ? Color.brandAccent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.busy)
                }
            }.padding(.horizontal, 12)

            if !model.recent.isEmpty {
                HStack {
                    Text("НЕДАВНИЕ").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(.tertiary)
                    Spacer()
                    Button { model.clearRecent() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).foregroundStyle(.tertiary).help("Очистить список недавних архивов")
                }.padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 10)
                ForEach(Array(model.recent.prefix(5).enumerated()), id: \.element) { _, url in
                    Button { model.open(url) } label: {
                        HStack(spacing: 9) {
                            Image(systemName: "doc.zipper").foregroundStyle(.secondary)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle).font(.system(size: 12))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 22).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(model.busy).help(url.path)
                }
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(Color.brandAccent).frame(width: 5, height: 5)
                    Text("Локально на вашем Mac").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                Text("Файлы остаются на устройстве.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).padding(14)
            Divider().padding(.horizontal, 18)
            HStack {
                SettingsLink { Label("Настройки", systemImage: "gearshape").font(.system(size: 12)) }.buttonStyle(.plain)
                Spacer()
                Text("1.0").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }.foregroundStyle(.secondary).padding(20)
        }
        .frame(maxHeight: .infinity)
        .background(Color.sidebarSurface)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.page == .archives && model.document != nil ? model.document!.url.lastPathComponent : model.page.title)
                    .font(.system(size: 20, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(headerSubtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            if model.page == .archives, model.document != nil {
                if model.canAddOrDelete {
                    Button { model.pickArchiveAdd() } label: { Image(systemName: "plus") }
                        .help("Добавить файлы в открытый архив").accessibilityLabel("Добавить в архив")
                }
                Button { model.testArchive() } label: { Image(systemName: "checkmark.shield") }
                    .help("Проверить целостность · ⌘T").accessibilityLabel("Проверить целостность")
                Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help("Свойства архива").accessibilityLabel("Показать свойства")
                Menu {
                    Button("Открыть другой архив…") { model.pickArchive() }
                    Button("Показать в Finder") { if let url = model.document?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    Divider()
                    Button("Закрыть архив") { model.closeArchive() }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("Действия с архивом")
                Button { model.extract() } label: { Label("Распаковать всё", systemImage: "arrow.down.to.line") }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button { model.pickArchive() } label: { Label("Открыть архив", systemImage: "folder") }
                    .controlSize(.large)
                if model.page != .create {
                    Button { model.page = .create } label: { Label("Создать", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
        .buttonStyle(.bordered).disabled(model.busy)
        .padding(.horizontal, 28).padding(.top, 23).padding(.bottom, 20)
        .background(WindowDragArea())
    }

    private var headerSubtitle: String {
        switch model.page {
        case .archives:
            guard let doc = model.document else { return "Простая работа с любыми архивами" }
            return doc.editableFormat == nil ? "Просмотр и распаковка · формат доступен только для чтения" : "Просмотр и изменение содержимого без полной распаковки"
        case .create: return "Ваши файлы. Меньше места. Всё под защитой."
        case .activity: return "Результаты операций на этом Mac"
        case .formats: return "Возможности встроенного движка 7-Zip"
        }
    }

    private func editingBanner(_ session: EditingSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.outline").foregroundStyle(Color.brandAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Редактируется: \(session.entry.name)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text("Сохраните и закройте документ в редакторе, затем запишите его в архив.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Открыть редактор") { model.openExternalEditor() }
                Button("Показать файл в Finder") { NSWorkspace.shared.activateFileViewerSelecting([session.fileURL]) }
                Divider()
                Button("Отменить редактирование", role: .destructive) { model.discardEditingPrompt = true }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            Button("Сохранить в архив") { model.saveEditingSession() }.buttonStyle(.borderedProminent).font(.system(size: 11))
        }.padding(.horizontal, 24).padding(.vertical, 13).background(Color.brandAccent.opacity(0.07)).disabled(model.busy)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.busy {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text(model.operationTitle).font(.system(size: 11, weight: .medium))
                Text(model.operationDetail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Отменить") { model.cancel() }.font(.system(size: 11))
            } else {
                Image(systemName: "checkmark.circle").foregroundStyle(Color.brandAccent)
                Text("Готово к работе").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if let doc = model.document, model.page == .archives {
                    Text("\(doc.fileCount) файлов").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(readableSize(doc.totalSize)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                } else {
                    Text("ZIP · 7z · RAR · TAR и другие").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }.padding(.horizontal, 24).frame(height: 39).background(.bar)
    }
}

struct AppMark: View {
    var size: CGFloat = 64
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25)
            .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.27), .brandAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "archivebox.fill").font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .shadow(color: Color.brandAccent.opacity(0.15), radius: size * 0.15, y: size * 0.08)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Label("МАЛЕНЬШЕ РАЗМЕР. БОЛЬШЕ ПОРЯДКА.", systemImage: "sparkle")
                        .font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundStyle(Color.brandAccent)
                    Spacer()
                    Text("СДЕЛАНО ДЛЯ macOS").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.tertiary)
                }
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Все ваши архивы.\nОдно простое место.")
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Открывайте, просматривайте и упаковывайте файлы.\nБез лишних действий и сложных настроек.")
                            .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    Spacer(minLength: 0)
                    archiveIllustration.frame(width: 150, height: 150)
                }.padding(.vertical, 6)
                HStack(spacing: 16) {
                    actionCard(title: "Открыть архив", subtitle: "Загляните внутрь. Извлеките нужное.", icon: "folder.badge.plus", shortcut: "⌘ O", primary: true) { model.pickArchive() }
                    actionCard(title: "Создать архив", subtitle: "Соберите файлы и освободите место.", icon: "archivebox", shortcut: "⌘ N", primary: false) { model.page = .create }
                }
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 18)).foregroundStyle(.tertiary)
                    Text("Или просто перетащите архив, файлы или папку в окно")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }.padding(18).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5])))
                HStack(spacing: 0) {
                    feature("lock.shield", "Под защитой", "Пароли и AES-256")
                    Spacer()
                    feature("square.stack.3d.up", "Знакомые форматы", "ZIP, 7z, RAR и не только")
                    Spacer()
                    feature("bolt", "Без лишних шагов", "Просмотр до распаковки")
                }.padding(.vertical, 4)
                if !model.recent.isEmpty {
                    Divider()
                    HStack {
                        Text("Продолжить работу").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Недавно открытые").font(.caption).foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 1) {
                        ForEach(Array(model.recent.prefix(3)), id: \.self) { url in
                            Button { model.open(url) } label: {
                                HStack(spacing: 12) {
                                    FileBadge(extensionName: url.pathExtension)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(url.lastPathComponent).font(.system(size: 12, weight: .medium))
                                        Text(url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }.padding(12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.background(Color.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(36).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var archiveIllustration: some View {
        ZStack {
            Circle().fill(Color.brandAccent.opacity(0.055)).frame(width: 150)
            RoundedRectangle(cornerRadius: 13).fill(Color.brandAccent.opacity(0.10)).frame(width: 88, height: 112).rotationEffect(.degrees(-15)).offset(x: -17, y: -4)
            RoundedRectangle(cornerRadius: 13).fill(Color.panel).frame(width: 88, height: 112).rotationEffect(.degrees(10)).offset(x: 15, y: -4)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
            AppMark(size: 86).rotationEffect(.degrees(-5)).offset(y: 12)
            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.brandAccent)
                .frame(width: 32, height: 32).background(Color.panel, in: Circle()).shadow(color: .black.opacity(0.08), radius: 5, y: 2).offset(x: 46, y: 47)
        }
    }

    private func actionCard(title: String, subtitle: String, icon: String, shortcut: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: icon).font(.system(size: 24, weight: .light))
                        .foregroundStyle(primary ? Color.brandAccent : Color.secondary)
                    Spacer()
                    Text(shortcut).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                        .padding(5).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(title).font(.system(size: 17, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13)).foregroundStyle(primary ? Color.brandAccent : Color.secondary)
                    }
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(primary ? Color.brandAccent.opacity(0.055) : Color.panel.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(primary ? Color.brandAccent.opacity(0.23) : .primary.opacity(0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Color.brandAccent.opacity(0.8)).frame(width: 23)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct FileBadge: View {
    let extensionName: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.brandAccent.opacity(0.08))
            Text(extensionName.isEmpty ? "FILE" : extensionName.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color.brandAccent)
        }.frame(width: 40, height: 42)
    }
}

struct PasswordView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 32, weight: .light)).foregroundStyle(Color.brandAccent)
            VStack(alignment: .leading, spacing: 8) {
                Text("Архив под защитой").font(.title2.weight(.semibold))
                Text("Введите пароль, чтобы продолжить. Пароль не сохраняется на диск.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SecureField("Пароль архива", text: $password).textFieldStyle(.roundedBorder).controlSize(.large)
                .focused($focused).onSubmit { if !password.isEmpty { model.submitPassword(password) } }
                .disabled(model.busy)
            if !model.passwordError.isEmpty { Text(model.passwordError).font(.caption).foregroundStyle(.red) }
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.operationTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { model.cancelPassword() }.keyboardShortcut(.cancelAction)
                Button("Продолжить") { model.submitPassword(password) }.buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(password.isEmpty || model.busy)
            }
        }.padding(30).frame(width: 400).onAppear { focused = true }
            .interactiveDismissDisabled()
            .onChange(of: model.passwordAttemptID) { _, _ in password = ""; focused = true }
    }
}

struct QuickLookView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) { nsView.previewItem = url as NSURL }
    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) { nsView.close() }
}

private struct WindowDragArea: NSViewRepresentable {
    class DragView: NSView { override var mouseDownCanMoveWindow: Bool { true } }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
