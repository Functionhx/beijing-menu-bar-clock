import SwiftUI

// Control Center–style building blocks shared by every panel section.

struct ToggleTile: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool
    var subtitle: String?

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ToggleCircle(symbol: symbol, isOn: isOn)
                TileLabel(title: title, subtitle: subtitle ?? (isOn ? "开" : "关"))
                Spacer(minLength: 0)
            }
            .padding(8)
            .moduleBackground()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ToggleCircle: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isOn ? Color.accentColor : Color.primary.opacity(0.1)))
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct PillButton: View {
    let title: String
    let symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct TileLabel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ModuleBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45))
        )
    }
}

extension View {
    func moduleBackground() -> some View {
        modifier(ModuleBackground())
    }
}

/// Control Center–style segmented switcher for the panel's sections.
struct PanelTabBar: View {
    @Binding var selection: PanelTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = tab }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Color.accentColor)
                                .matchedGeometryEffect(id: "tab", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// Bold module title with trailing accessory buttons.
struct ModuleHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 4)
            accessory()
        }
    }
}

/// Hour:minute field bound to "minutes after midnight", independent of any time zone.
struct MinuteOfDayPicker: View {
    @Binding var minuteOfDay: Int

    var body: some View {
        DatePicker("", selection: Binding(
            get: { Date(timeIntervalSince1970: TimeInterval(minuteOfDay * 60)) },
            set: { minuteOfDay = WorldClockMath.minuteOfDay(of: $0, in: .gmt) }
        ), displayedComponents: .hourAndMinute)
        .labelsHidden()
        .datePickerStyle(.field)
        .environment(\.timeZone, .gmt)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .fixedSize()
    }
}
