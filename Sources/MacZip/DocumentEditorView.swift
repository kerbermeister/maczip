import SwiftUI

struct DocumentEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var discardPrompt = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "doc.text").font(.system(size: 24, weight: .light)).foregroundStyle(Color.brandAccent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.editingSession?.entry.name ?? "Документ").font(.headline).lineLimit(1)
                    Text("Из архива извлечён только этот файл").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Во внешнем редакторе") { model.switchToExternalEditor() }.font(.system(size: 11))
            }.padding(20)
            Divider()
            TextEditor(text: $model.editorText)
                .font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(16).background(Color.panel)
            Divider()
            HStack {
                Text("Изменения попадут в архив после сохранения.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Отмена") { discardPrompt = true }.keyboardShortcut(.cancelAction)
                Button("Сохранить в архив") { model.saveTextToArchive() }.buttonStyle(.borderedProminent).keyboardShortcut("s")
            }.padding(18)
        }.frame(minWidth: 760, minHeight: 560).interactiveDismissDisabled()
            .confirmationDialog("Отменить редактирование?", isPresented: $discardPrompt, titleVisibility: .visible) {
                Button("Отменить изменения", role: .destructive) { model.discardEditingSession() }
                Button("Продолжить редактирование", role: .cancel) {}
            } message: { Text("Изменения не будут записаны в архив.") }
    }
}
