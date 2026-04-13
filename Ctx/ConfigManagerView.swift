import SwiftUI

struct ConfigManagerView: View {
    @ObservedObject var windowManager: WindowManager
    @State private var selectedIndex: Int = 0
    @State private var allWindows: [WindowManager.WindowInfo] = []
    @State private var renamingIndex: Int? = nil
    @State private var renameText: String = ""
    @State private var showRenameAlert = false

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
            refreshWindows()
            selectedIndex = windowManager.activeConfigIndex
        }
        // Refresh the window list when apps launch or quit while the manager is open
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.didLaunchApplicationNotification,
                                                  object: NSWorkspace.shared)
        ) { _ in refreshWindows() }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWorkspace.didTerminateApplicationNotification,
                                                  object: NSWorkspace.shared)
        ) { _ in refreshWindows() }
    }

    private func refreshWindows() {
        allWindows = windowManager.allVisibleWindows()
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
            .contextMenu {
                Button("Rename") {
                    renamingIndex = i
                    renameText = windowManager.configs[i].name
                    showRenameAlert = true
                }
            }
        }
        .alert("Rename Config", isPresented: $showRenameAlert, presenting: renamingIndex) { idx in
            TextField("Config name", text: $renameText)
                .onSubmit { applyRename(at: idx) }
            Button("Rename") { applyRename(at: idx) }
            Button("Cancel", role: .cancel) { }
        } message: { idx in
            if windowManager.configs.indices.contains(idx) {
                Text("Rename \"\(windowManager.configs[idx].name)\"")
            }
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
                Divider().frame(height: 18)
                Button { refreshWindows() } label: {
                    Image(systemName: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .help("Refresh window list")
            }
            .buttonStyle(.borderless)
            .padding(6)
            .background(.bar)
        }
    }

    private func applyRename(at index: Int) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, windowManager.configs.indices.contains(index) else { return }
        windowManager.configs[index].name = trimmed
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
    }

    private func addConfig() {
        let existing = Set(windowManager.configs.map { $0.name })
        var n = windowManager.configs.count + 1
        while existing.contains("Config \(n)") { n += 1 }
        windowManager.configs.append(WindowConfig(name: "Config \(n)", windowIDs: []))
        selectedIndex = windowManager.configs.count - 1
    }

    private func removeConfig() {
        guard windowManager.configs.count > 1,
              windowManager.configs.indices.contains(selectedIndex) else { return }
        let k = selectedIndex
        let wasActive = k == windowManager.activeConfigIndex
        let wasBeforeActive = k < windowManager.activeConfigIndex

        windowManager.configs.remove(at: k)

        // Keep activeConfigIndex pointing at the same logical config
        if wasBeforeActive {
            windowManager.activeConfigIndex -= 1
        } else if wasActive {
            windowManager.activeConfigIndex = max(0, k - 1)
            NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
        }
        // clamp as a safety net
        windowManager.activeConfigIndex = min(windowManager.activeConfigIndex, windowManager.configs.count - 1)

        selectedIndex = max(0, k - 1)
    }
}

// MARK: - Detail

struct ConfigDetailView: View {
    let configIndex: Int
    @ObservedObject var windowManager: WindowManager
    let allWindows: [WindowManager.WindowInfo]

    private var configExists: Bool { windowManager.configs.indices.contains(configIndex) }
    private var config: WindowConfig {
        configExists ? windowManager.configs[configIndex] : WindowConfig(name: "", windowIDs: [])
    }

    var body: some View {
        if configExists {
            VStack(spacing: 0) {
                header
                Divider()
                windowList
            }
        } else {
            Text("Config was deleted")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(config.name)
                .font(.body)
                .fontWeight(.medium)

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
        guard configExists else { return }
        if windowManager.configs[configIndex].windowIDs.contains(windowID) {
            let cfg = windowManager.configs[configIndex]
            let cycledID = cfg.windowIDs.indices.contains(cfg.cycleIndex)
                ? cfg.windowIDs[cfg.cycleIndex] : nil
            windowManager.configs[configIndex].windowIDs.removeAll { $0 == windowID }
            windowManager.configs[configIndex].windowAppNames.removeValue(forKey: windowID)
            // Only reset cycleIndex if we removed the window currently being cycled,
            // or if it's now out of range
            let newCount = windowManager.configs[configIndex].windowIDs.count
            if cycledID == windowID || windowManager.configs[configIndex].cycleIndex >= newCount {
                windowManager.configs[configIndex].cycleIndex = 0
            }
        } else {
            windowManager.configs[configIndex].windowIDs.append(windowID)
            if let appName = allWindows.first(where: { $0.id == windowID })?.appName {
                windowManager.configs[configIndex].windowAppNames[windowID] = appName
            }
            // Don't reset cycleIndex when adding a window
        }
    }
}
