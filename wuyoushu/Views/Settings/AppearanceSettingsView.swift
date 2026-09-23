import SwiftUI

enum AppAppearanceMode: String, CaseIterable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

@MainActor
final class AppearanceSettings: ObservableObject {
    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppAppearanceMode.system.rawValue
        self.appearanceMode = AppAppearanceMode(rawValue: saved) ?? .system
    }

    func applyAppearance() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        switch appearanceMode {
        case .system:
            window.overrideUserInterfaceStyle = .unspecified
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        }
    }
}

struct AppearanceSettingsView: View {
    @StateObject private var appearanceSettings = AppearanceSettings()

    var body: some View {
        List {
            Section {
                ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                    Button {
                        appearanceSettings.appearanceMode = mode
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(appearanceColor(for: mode))
                                .frame(width: 28)

                            Text(mode.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            if appearanceSettings.appearanceMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.warmTeal)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("外观模式")
            } footer: {
                Text("选择浅色、深色或跟随系统设置")
            }
        }
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            appearanceSettings.applyAppearance()
        }
    }

    private func appearanceColor(for mode: AppAppearanceMode) -> Color {
        if appearanceSettings.appearanceMode == mode {
            return Color.warmTeal
        }
        return .secondary
    }
}

#Preview {
    NavigationView {
        AppearanceSettingsView()
    }
}
