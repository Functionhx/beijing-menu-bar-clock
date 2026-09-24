import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ClockSettings
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("日期")
            settingsCard {
                Toggle("显示日期", isOn: $settings.showDate)
                Divider()
                Toggle("显示星期", isOn: $settings.showWeekday)
            }

            sectionTitle("时间")
            settingsCard {
                Toggle("闪动时间分隔符", isOn: $settings.flashSeparators)
                Divider()
                Toggle("在时间中显示秒钟", isOn: $settings.showSeconds)
            }

            settingsCard {
                Toggle("语音报时", isOn: $settings.announceTime)
                Divider()

                HStack {
                    Text("时间间隔")
                    Spacer()
                    Picker("", selection: $settings.announceInterval) {
                        Text("每小时").tag("每小时")
                        Text("每半小时").tag("每半小时")
                        Text("每刻钟").tag("每刻钟")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                .disabled(!settings.announceTime)

                Divider()

                HStack {
                    Text("声音")
                    Spacer()
                    Picker("", selection: $settings.soundName) {
                        ForEach(settings.soundChoices, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .onChange(of: settings.soundName) { _, newValue in
                        if newValue == "自定义…" && settings.customSoundPath.isEmpty {
                            settings.chooseCustomSound()
                        }
                    }
                }
                .disabled(!settings.announceTime)

                if settings.announceTime && settings.soundName == "自定义…" {
                    HStack {
                        Text(settings.customSoundPath.isEmpty ? "尚未选择音频" : URL(fileURLWithPath: settings.customSoundPath).lastPathComponent)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("自定义声音…") { settings.chooseCustomSound() }
                    }
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 570)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(16)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.leading, 2)
            .padding(.bottom, -12)
    }
}
