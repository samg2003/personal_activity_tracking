import SwiftUI

// MARK: - Workout Design System
// Central design tokens, reusable modifiers, and animated components
// for a premium workout UI experience.

enum WDS {

    // MARK: - Color Palette

    /// Strength: warm amber → burnt orange
    static let strengthGradient = LinearGradient(
        colors: [Color(hex: 0xF59E0B), Color(hex: 0xEA580C)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Cardio: emerald → teal
    static let cardioGradient = LinearGradient(
        colors: [Color(hex: 0x10B981), Color(hex: 0x0D9488)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Neutral surface gradient for dark-mode cards
    static let surfaceGradient = LinearGradient(
        colors: [Color(.systemGray6), Color(.systemGray5).opacity(0.5)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let strengthAccent  = Color(hex: 0xF59E0B)
    static let cardioAccent    = Color(hex: 0x10B981)
    static let dangerAccent    = Color(hex: 0xEF4444)
    static let infoAccent      = Color(hex: 0x3B82F6)

    // MARK: - Shadows

    static let cardShadow: some ShapeStyle = Color.black.opacity(0.08)
    static let glowShadow: some ShapeStyle = Color.orange.opacity(0.25)

    // MARK: - Corner Radii

    static let cardRadius: CGFloat  = 16
    static let buttonRadius: CGFloat = 12
    static let chipRadius: CGFloat   = 20

    // MARK: - Haptics

    static func hapticLight()    { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func hapticMedium()   { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func hapticSuccess()  { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func hapticSelection(){ UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Premium Card Modifier

struct PremiumCardModifier: ViewModifier {
    var accentColor: Color = .clear
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: WDS.cardRadius, style: .continuous)
                            .strokeBorder(accentColor.opacity(accentColor == .clear ? 0 : 0.15), lineWidth: 1)
                    )
            }
    }
}

extension View {
    func premiumCard(accent: Color = .clear, padding: CGFloat = 16) -> some View {
        modifier(PremiumCardModifier(accentColor: accent, padding: padding))
    }
}

// MARK: - Gradient Button

struct GradientButton: View {
    let title: String
    var icon: String? = nil
    var gradient: LinearGradient = WDS.strengthGradient
    var size: ButtonSize = .regular
    let action: () -> Void

    enum ButtonSize {
        case compact, regular, large
        var verticalPadding: CGFloat {
            switch self {
            case .compact: return 8
            case .regular:  return 12
            case .large:    return 16
            }
        }
        var font: Font {
            switch self {
            case .compact: return .subheadline.weight(.semibold)
            case .regular:  return .body.weight(.semibold)
            case .large:    return .headline
            }
        }
    }

    @State private var isPressed = false

    var body: some View {
        Button {
            WDS.hapticMedium()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(size.font)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, size.verticalPadding)
            .background(gradient, in: RoundedRectangle(cornerRadius: WDS.buttonRadius, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Icon Badge

struct IconBadge: View {
    let icon: String
    var color: Color = WDS.strengthAccent
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12))
            .clipShape(Circle())
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    var color: Color = .green
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Animated Progress Ring

struct ProgressRing: View {
    let progress: Double // 0.0 ... 1.0
    var lineWidth: CGFloat = 6
    var gradient: LinearGradient = WDS.strengthGradient
    var size: CGFloat = 48

    @State private var animatedProgress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = min(progress, 1.0)
            }
        }
        .onChange(of: progress) { _, newVal in
            withAnimation(.easeOut(duration: 0.4)) {
                animatedProgress = min(newVal, 1.0)
            }
        }
    }
}

// MARK: - Metric Chip

struct MetricChip: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = WDS.strengthAccent

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .premiumCard(padding: 10)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let text: String
    var style: BadgeStyle = .success

    enum BadgeStyle {
        case success, warning, info, draft
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .info:    return WDS.infoAccent
            case .draft:   return .orange
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.color.opacity(0.15))
            .foregroundStyle(style.color)
            .clipShape(Capsule())
    }
}
