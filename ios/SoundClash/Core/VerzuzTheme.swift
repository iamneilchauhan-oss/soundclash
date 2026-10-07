import SwiftUI
import CoreText

/// VERZUZ-inspired design language.
/// - Menus: "Faithful" — vivid accent color vs black vertical split.
/// - Matchup + battle: "Color Clash" — two vivid colors, no black.
/// Shared: V monogram mark, condensed display type (Anton), no artist names.
enum VerzuzTheme {

    // MARK: - Accent palette (the six cheat-sheet colors)

    enum Accent: String, CaseIterable {
        case purple, red, sky, teal, orange, cream

        var color: Color {
            switch self {
            case .purple: Color(red: 0.60, green: 0.35, blue: 0.96)
            case .red:    Color(red: 0.93, green: 0.22, blue: 0.33)
            case .sky:    Color(red: 0.38, green: 0.74, blue: 0.91)
            case .teal:   Color(red: 0.20, green: 0.76, blue: 0.70)
            case .orange: Color(red: 1.00, green: 0.44, blue: 0.30)
            case .cream:  Color(red: 0.96, green: 0.95, blue: 0.92)
            }
        }

        /// Readable text color drawn directly on this accent.
        var onColor: Color {
            switch self {
            case .cream, .sky: .black
            case .purple, .red, .teal, .orange: .white
            }
        }
    }

    /// Menu accent — picked once per app launch.
    static let menuAccent: Accent = Accent.allCases.randomElement() ?? .purple

    /// Color Clash pair for matchup + battle moments (no black).
    static let clashA = Accent.orange
    static let clashB = Accent.purple

    /// Battle-side color mapped onto the clash pair.
    static func clashColor(for side: Side) -> Color {
        (side == .red ? clashA : clashB).color
    }

    static func clashGradient(for side: Side) -> LinearGradient {
        let c = clashColor(for: side)
        return LinearGradient(
            colors: [c.opacity(0.9), c.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Display type (Anton, condensed)

    static func display(_ size: CGFloat) -> Font {
        .custom("Anton", size: size)
    }
}

// MARK: - Runtime font registration (no Info.plist change needed)

enum VerzuzFonts {
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
        let candidates = [
            Bundle.main.url(forResource: "Anton-Regular", withExtension: "ttf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: "Anton-Regular", withExtension: "ttf"),
        ].compactMap { $0 }
        for url in candidates {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - Split background

/// Full-bleed vertical split: `left` on the left half, `right` on the right.
struct VerzuzSplit: View {
    let left: Color
    let right: Color

    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, maxHeight: .infinity)
            right.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

// MARK: - V monogram

/// Stylized V mark drawn as two strokes so each half can take its own color
/// (e.g. black on the accent side, accent on the black side).
struct VMark: View {
    let left: Color
    let right: Color

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                leftStroke(in: rect).fill(left)
                rightStroke(in: rect).fill(right)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func leftStroke(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        // Flared sharp tip at top-outer, heavy bar tapering to the vertex,
        // lightning notch on the inner edge.
        p.move(to: CGPoint(x: 0.00*w, y: 0.02*h))
        p.addLine(to: CGPoint(x: 0.30*w, y: 0.10*h))
        p.addLine(to: CGPoint(x: 0.37*w, y: 0.36*h))
        p.addLine(to: CGPoint(x: 0.47*w, y: 0.44*h))
        p.addLine(to: CGPoint(x: 0.37*w, y: 0.52*h))
        p.addLine(to: CGPoint(x: 0.50*w, y: 1.00*h))
        p.addLine(to: CGPoint(x: 0.28*w, y: 1.00*h))
        p.closeSubpath()
        return p
    }

    private func rightStroke(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 1.00*w, y: 0.02*h))
        p.addLine(to: CGPoint(x: 0.70*w, y: 0.10*h))
        p.addLine(to: CGPoint(x: 0.63*w, y: 0.36*h))
        p.addLine(to: CGPoint(x: 0.53*w, y: 0.44*h))
        p.addLine(to: CGPoint(x: 0.63*w, y: 0.52*h))
        p.addLine(to: CGPoint(x: 0.50*w, y: 1.00*h))
        p.addLine(to: CGPoint(x: 0.72*w, y: 1.00*h))
        p.closeSubpath()
        return p
    }
}

// MARK: - Chunky condensed button

struct VerzuzButtonStyle: ButtonStyle {
    let fill: Color
    let textColor: Color
    var fontSize: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VerzuzTheme.display(fontSize))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

// MARK: - Small black pill label (readable on any accent)

struct VerzuzPill: View {
    let text: String
    var fontSize: CGFloat = 15

    var body: some View {
        Text(text)
            .font(VerzuzTheme.display(fontSize))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black)
            .clipShape(Capsule())
    }
}
