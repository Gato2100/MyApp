import SwiftUI

/// Shared geometry and styling for the unlock and lock actions.
struct VaultActionButton: View {
    static let diameter: CGFloat = 48
    let symbol: String
    let title: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.blue, Color(red: 0.10, green: 0.35, blue: 0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: symbol).font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white).accessibilityHidden(true)
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
            .contentShape(Circle())
        }
        .buttonStyle(VaultCircleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(symbol == "lock.fill" ? "vault.lock" : "vault.unlock")
    }
}

private struct VaultCircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.45)
            .shadow(color: .blue.opacity(isEnabled ? 0.22 : 0.08), radius: 7, y: 3)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview("Vault controls") {
    HStack(spacing: 24) {
        VaultActionButton(symbol: "lock.open.fill", title: L10n.text(.unlock)) {}
        VaultActionButton(symbol: "lock.fill", title: L10n.text(.lock)) {}
        VaultActionButton(symbol: "lock.open.fill", title: L10n.text(.verifying), isBusy: true) {}
    }.padding(32)
}
