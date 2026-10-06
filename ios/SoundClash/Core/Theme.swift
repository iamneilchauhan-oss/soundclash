import SwiftUI

/// Shared design language: near-black cinematic background,
/// red-vs-blue competitor accents, rounded cards.
enum SCTheme {
    static let background = Color(red: 0.043, green: 0.043, blue: 0.063)
    static let card = Color(red: 0.094, green: 0.094, blue: 0.133)
    static let cardBorder = Color.white.opacity(0.08)
    static let red = Color(red: 1.0, green: 0.23, blue: 0.19)
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.30)
    static let secondaryText = Color(white: 0.62)

    static func title(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func sideGradient(_ side: Side) -> LinearGradient {
        LinearGradient(
            colors: [side.color.opacity(0.85), side.color.opacity(0.25)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Card container

struct SCCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(SCTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(SCTheme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    func scCard() -> some View { modifier(SCCard()) }
}

// MARK: - Buttons

struct SCPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [SCTheme.red, SCTheme.blue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct SCSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(SCTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(SCTheme.cardBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Big tappable side button (red vs blue voting, etc.)
struct SCSideButton: ButtonStyle {
    let side: Side
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(side.color.opacity(isSelected ? 0.95 : 0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(side.color, lineWidth: isSelected ? 3 : 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}
