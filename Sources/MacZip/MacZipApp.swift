import SwiftUI
import AppKit

@main
struct MacZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @AppStorage("appearance") private var appearance = "dark"

    var body: some Scene {
        Window("MacZip", id: "main") {
            ContentView()
                .environmentObject(model)
                .tint(.brandAccent)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
                .onOpenURL { model.open($0) }
                .onAppear { delegate.model = model }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть архив…") { model.pickArchive() }.keyboardShortcut("o").disabled(model.busy)
                Button("Создать архив") { model.page = .create }.keyboardShortcut("n").disabled(model.busy)
                Divider()
                Button("Закрыть архив") { model.closeArchive() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(model.busy || model.document == nil)
            }
            CommandMenu("Архив") {
                Button("Распаковать всё…") { model.extract() }.keyboardShortcut("e").disabled(model.busy || model.document == nil)
                Button("Распаковать выбранное…") { model.extract(selected: true) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(model.busy || model.selection.isEmpty)
                Button("Проверить целостность") { model.testArchive() }.keyboardShortcut("t").disabled(model.busy || model.document == nil)
                Divider()
                Button("Добавить файлы…") { model.pickInput() }.keyboardShortcut("a", modifiers: [.command, .shift]).disabled(model.busy)
                Button("Добавить в открытый архив…") { model.pickArchiveAdd() }.keyboardShortcut("a", modifiers: [.command, .option]).disabled(!model.canAddOrDelete)
                Button("Редактировать документ…") { model.editSelected() }.keyboardShortcut("r").disabled(!model.canModify || model.selectedEntry == nil || model.selectedEntry?.isDirectory == true)
                Button("Удалить из архива…") { model.deleteSelected() }.keyboardShortcut(.delete, modifiers: [.command]).disabled(!model.canAddOrDelete || model.selection.isEmpty)
            }
        }
        Settings { SettingsView().tint(.brandAccent) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.busy || model.editingSession != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = model.busy ? "Операция ещё выполняется" : "Документ ещё не сохранён в архив"
        alert.informativeText = model.busy ? "Можно дождаться завершения или выйти, отменив текущую операцию." : "Вернитесь к документу, чтобы сохранить изменения, или выйдите без сохранения."
        alert.addButton(withTitle: "Вернуться")
        alert.addButton(withTitle: model.busy ? "Отменить и выйти" : "Выйти без сохранения")
        if alert.runModal() == .alertSecondButtonReturn { model.shutdown(); return .terminateNow }
        return .terminateCancel
    }
}

extension Color {
    static let brandAccent = Color(red: 1.0, green: 0.43, blue: 0.12)
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.085, alpha: 1) : NSColor(white: 0.98, alpha: 1)
    })
    static let panel = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.14, alpha: 1) : .white
    })
    static let sidebarSurface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.065, alpha: 1) : NSColor(white: 0.95, alpha: 1)
    })
}
