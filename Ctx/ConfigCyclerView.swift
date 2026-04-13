import SwiftUI

struct ConfigCyclerView: View {
    @ObservedObject var windowManager: WindowManager

    var body: some View {
        HStack(spacing: 12) {
            ForEach(windowManager.configs.indices, id: \.self) { i in
                Text(windowManager.configs[i].name)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        i == windowManager.activeConfigIndex
                            ? Color.accentColor
                            : Color.primary.opacity(0.08)
                    )
                    .foregroundStyle(
                        i == windowManager.activeConfigIndex ? Color.white : Color.primary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .animation(.easeInOut(duration: 0.1), value: windowManager.activeConfigIndex)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
