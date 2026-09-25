import SwiftUI

/// Building blocks for the macOS 27 Control Center look: one Liquid Glass platter holding translucent
/// modules — pills, round buttons and full-width modules — on a four-column grid.
enum ModuleGrid {
    /// Platter width minus its padding, split into four columns.
    static let gap: CGFloat = 12
    static let unit: CGFloat = (Metrics.width - 2 * Metrics.platterPadding - 3 * gap) / 4
    static let doubleUnit: CGFloat = unit * 2 + gap
    static let largeRadius: CGFloat = 24
}

/// Translucent module surface with a hairline highlight, drawn on the platter's glass. Modules deliberately
/// avoid glass-on-glass so text stays crisp (macOS 27 raised legibility the same way).
struct ModuleSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var isHighlighted = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(isHighlighted
                    ? AnyShapeStyle(Color.accentColor.gradient)
                    : AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42)))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(colorScheme == .dark ? 0.28 : 0.75), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
            .contentShape(shape)
    }
}

extension View {
    func moduleSurface<S: InsettableShape>(_ shape: S, highlighted: Bool = false) -> some View {
        modifier(ModuleSurface(shape: shape, isHighlighted: highlighted))
    }
}

/// The round icon at the start of a pill: white with a tinted glyph when on, faint when off.
struct ModuleIcon: View {
    let symbol: String
    let isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            // Solid glyph on the white circle so the tint stays legible in dark mode too.
            .symbolRenderingMode(isOn ? .monochrome : .hierarchical)
            .foregroundStyle(isOn ? tint : Color.primary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 40, height: 40)
            .background(Circle().fill(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.opacity(0.1))))
            .shadow(color: .black.opacity(isOn ? 0.12 : 0), radius: 3, y: 1)
    }
}

/// Two-column pill: tapping the icon toggles, tapping the text opens the detail page (when there is one).
struct PillModule: View {
    let symbol: String
    let title: String
    let subtitle: String
    let isOn: Bool
    var tint: Color = .accentColor
    let toggle: () -> Void
    var open: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                ModuleIcon(symbol: symbol, isOn: isOn, tint: tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "开" : "关")

            Button(action: open ?? toggle) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, (ModuleGrid.unit - 40) / 2)
        .padding(.trailing, 8)
        .frame(width: ModuleGrid.doubleUnit, height: ModuleGrid.unit)
        .moduleSurface(Capsule())
    }
}

/// One-column round button. On state fills with the accent color like Control Center's toggles.
struct CircleModule: View {
    let symbol: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .symbolEffect(.bounce, value: isOn)
                .frame(width: ModuleGrid.unit, height: ModuleGrid.unit)
                .moduleSurface(Circle(), highlighted: isOn)
        }
        .buttonStyle(.plain)
        .help("\(isOn ? "隐藏" : "显示")\(title)")
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "开" : "关")
    }
}

/// Full-width module with a small title row, like Display and Sound in Control Center. The whole module
/// opens its detail page.
struct WideModule<Accessory: View, Content: View>: View {
    let title: String
    let open: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                accessory()
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: Metrics.width - 2 * Metrics.platterPadding, alignment: .leading)
        .moduleSurface(RoundedRectangle(cornerRadius: ModuleGrid.largeRadius, style: .continuous))
        .onTapGesture(perform: open)
    }
}

/// Small capsule used for the suggestion at the top and the buttons at the bottom of the platter.
struct ChipLabel: View {
    let title: String
    var symbol: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint ?? Color.primary)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .moduleSurface(Capsule())
    }
}
