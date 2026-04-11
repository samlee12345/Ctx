import SwiftUI

struct ConfigEditorView: View {
    let configName: String
    let allWindows: [WindowManager.WindowInfo]
    let onSave: ([CGWindowID]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<CGWindowID>

    init(
        configName: String,
        existingIDs: [CGWindowID],
        allWindows: [WindowManager.WindowInfo],
        onSave: @escaping ([CGWindowID]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configName = configName
        self.allWindows = allWindows
        self.onSave = onSave
        self.onCancel = onCancel
        _selectedIDs = State(initialValue: Set(existingIDs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Configure \"\(configName)\"")
                .font(.headline)
                .padding()

            Divider()

            if allWindows.isEmpty {
                Text("No open windows found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(allWindows) { window in
                    HStack(spacing: 10) {
                        Image(systemName: selectedIDs.contains(window.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selectedIDs.contains(window.id) ? Color.accentColor : Color.secondary)
                            .font(.system(size: 16))

                        if let icon = window.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 18, height: 18)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(window.appName)
                                .fontWeight(.medium)
                            if !window.windowTitle.isEmpty {
                                Text(window.windowTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedIDs.contains(window.id) {
                            selectedIDs.remove(window.id)
                        } else {
                            selectedIDs.insert(window.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                Text("\(selectedIDs.count) window\(selectedIDs.count == 1 ? "" : "s") selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    let ordered = allWindows.filter { selectedIDs.contains($0.id) }.map { $0.id }
                    onSave(ordered)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 440)
    }
}
