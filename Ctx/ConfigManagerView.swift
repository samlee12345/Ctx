import SwiftUI

struct ConfigManagerView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var selectedIndex: Int = 0
    @State private var allWindows: [WindowManager.WindowInfo] = []

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if windowManager.configs.indices.contains(selectedIndex) {
                ConfigDetailView(
                    configIndex: selectedIndex,
                    windowManager: windowManager,
                    allWindows: allWindows
                )
            } else {
                Text("Select a configuration")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 580, minHeight: 400)
        .onAppear {
            allWindows = windowManager.allVisibleWindows()
            selectedIndex = windowManager.activeConfigIndex
        }
    }

    private var sidebar: some View {
        List(windowManager.configs.indices, id: \.self, selection: $selectedIndex) { i in
            HStack(spacing: 8) {
                // Dot indicates active config
                Circle()
                    .fill(i == windowManager.activeConfigIndex ? Color.accentColor : Color.clear)
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
                    .frame(width: 8, height: 8)
                Text(windowManager.configs[i].name)
            }
            .tag(i)
        }
        .navigationSplitViewColumnWidth(min: 140, ideal: 160)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                Button { addConfig() } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity)
                }
                Divider().frame(height: 18)
                Button { removeConfig() } label: {
                    Image(systemName: "minus").frame(maxWidth: .infinity)
                }
                .disabled(windowManager.configs.count <= 1)
            }
            .buttonStyle(.borderless)
            .padding(6)
            .background(.bar)
        }
    }

    private func addConfig() {
        let name = "Config \(windowManager.configs.count + 1)"
        windowManager.configs.append(WindowConfig(name: name, windowIDs: []))
        selectedIndex = windowManager.configs.count - 1
    }

    private func removeConfig() {
        guard windowManager.configs.count > 1 else { return }
        windowManager.configs.remove(at: selectedIndex)
        selectedIndex = max(0, selectedIndex - 1)
        if windowManager.activeConfigIndex >= windowManager.configs.count {
            windowManager.activeConfigIndex = windowManager.configs.count - 1
        }
    }
}

// MARK: - Detail

struct ConfigDetailView: View {
    let configIndex: Int
    @ObservedObject var windowManager: WindowManager
    let allWindows: [WindowManager.WindowInfo]

    private var config: WindowConfig { windowManager.configs[configIndex] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            windowList
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            TextField(
                "Config name",
                text: Binding(
                    get: { windowManager.configs[configIndex].name },
                    set: { windowManager.configs[configIndex].name = $0 }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.body)
            .frame(maxWidth: 200)

            Spacer()

            let count = config.windowIDs.count
            Text("\(count) window\(count == 1 ? "" : "s") selected")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var windowList: some View {
        Group {
            if allWindows.isEmpty {
                Text("No open windows found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(allWindows) { window in
                    let isChecked = config.windowIDs.contains(window.id)
                    HStack(spacing: 10) {
                        Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                            .font(.system(size: 16))

                        if let icon = window.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 18, height: 18)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.appName)
                                .fontWeight(.medium)
                            if !window.windowTitle.isEmpty {
                                Text(window.windowTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(window.id) }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func toggle(_ windowID: CGWindowID) {
        if windowManager.configs[configIndex].windowIDs.contains(windowID) {
            windowManager.configs[configIndex].windowIDs.removeAll { $0 == windowID }
        } else {
            windowManager.configs[configIndex].windowIDs.append(windowID)
        }
        windowManager.configs[configIndex].cycleIndex = 0
    }
}
