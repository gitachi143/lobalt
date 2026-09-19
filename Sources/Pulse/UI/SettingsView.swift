import SwiftUI
import ServiceManagement
import PulseKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PulseSettings()
                .tabItem { Label("Pulse", systemImage: "waveform.path.ecg") }
            OverlaySettings()
                .tabItem { Label("Overlay", systemImage: "macwindow.on.rectangle") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 480)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @State private var presetText = ""
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("Finish sound", selection: $settings.finishSound) {
                    ForEach(SoundPlayer.choices, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: settings.finishSound) { _, new in SoundPlayer.play(new) }

                Toggle("Send a notification when time is up", isOn: $settings.notifyOnFinish)
                Toggle("Keep counting after zero", isOn: $settings.continueIntoOvertime)
                    .onChange(of: settings.continueIntoOvertime) { _, _ in app.syncSettings() }
                Text("Counting past zero shows how far over your estimate you ran, which is what makes the history useful.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Timer") }

            Section {
                TextField("Presets (minutes)", text: $presetText)
                    .onSubmit(commitPresets)
                Text("Comma separated, e.g. 5, 15, 25, 50")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: { Text("Quick presets") }

            Section {
                Toggle("Keep the display awake while a timer runs", isOn: $settings.keepDisplayAwake)
                    .onChange(of: settings.keepDisplayAwake) { _, _ in app.syncSettings() }
                Toggle("Show in the Dock", isOn: $settings.showDockIcon)
                    .onChange(of: settings.showDockIcon) { _, show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                        if show { NSApp.activate(ignoringOtherApps: true) }
                    }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, on in setLoginItem(on) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(Palette.warn)
                }
            } header: { Text("System") }
        }
        .formStyle(.grouped)
        .onAppear { presetText = app.settings.presets.map(String.init).joined(separator: ", ") }
    }

    private func commitPresets() {
        let values = presetText
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0) }
            .filter { $0 > 0 && $0 <= 600 }
        guard !values.isEmpty else {
            presetText = app.settings.presets.map(String.init).joined(separator: ", ")
            return
        }
        app.settings.presets = Array(values.prefix(8))
        presetText = app.settings.presets.map(String.init).joined(separator: ", ")
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
            app.settings.launchAtLogin = !enabled
        }
    }
}

// MARK: - Pulse

private struct PulseSettings: View {
    @Environment(AppState.self) private var app
    @State private var demoPulse: Date?

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Flash red every minute", isOn: $settings.pulseEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    Slider(value: $settings.pulseIntensity, in: 0.15...1.0) {
                        Text("Intensity")
                    } minimumValueLabel: {
                        Text("Subtle").font(.caption2)
                    } maximumValueLabel: {
                        Text("Bold").font(.caption2)
                    }
                    .disabled(!settings.pulseEnabled)
                }

                Toggle("Play a quiet tick with each pulse", isOn: $settings.pulseSound)
                    .disabled(!settings.pulseEnabled)
            } header: {
                Text("The minute pulse")
            } footer: {
                Text("Every whole minute the ring, the corner overlay and the menu bar warm to red and cool off again. It gets firmer over the last five minutes and firmer still once you're past your estimate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                PulsePreview(intensity: settings.pulseIntensity,
                             enabled: settings.pulseEnabled,
                             trigger: demoPulse)
                    .frame(height: 96)
                Button("Show me") { demoPulse = Date() }
            } header: { Text("Preview") }
        }
        .formStyle(.grouped)
    }
}

/// Live sample of exactly what a pulse looks like at the chosen intensity.
private struct PulsePreview: View {
    var intensity: Double
    var enabled: Bool
    var trigger: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: trigger == nil)) { context in
            let elapsed = trigger.map { context.date.timeIntervalSince($0) } ?? .infinity
            let pulse = enabled ? PulseEnvelope.intensity(elapsed: elapsed) * intensity * 0.9 : 0
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Palette.canvas)
                HStack(spacing: 12) {
                    TimerRing(fraction: 0.6, color: Palette.calm, pulse: pulse, lineWidth: 3)
                        .frame(width: 26, height: 26)
                    Text("24:00")
                        .font(Theme.digits(18, weight: .semibold))
                        .foregroundStyle(Theme.pulseTint(Palette.calm, pulse: pulse))
                    Text("Write the essay")
                        .font(Theme.label(12))
                        .foregroundStyle(Palette.secondaryText)
                }
                PulseBackdrop(pulse: pulse, cornerRadius: 12, thickness: 16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Overlay

private struct OverlaySettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Picker("Show the corner overlay", selection: $settings.overlayMode) {
                    ForEach(OverlayMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Corner", selection: $settings.overlayCorner) {
                    ForEach(OverlayCorner.allCases) { Text($0.title).tag($0) }
                }
                .disabled(settings.overlayMode == .never)
                .onChange(of: settings.overlayCorner) { _, _ in
                    settings.overlayOrigin = nil
                    NotificationCenter.default.post(name: .pulseOverlayLayoutChanged, object: nil)
                }

                HStack {
                    Text("Size")
                    Slider(value: $settings.overlayScale, in: 0.8...1.6, step: 0.1)
                    Text(String(format: "%.0f%%", settings.overlayScale * 100))
                        .font(Theme.digits(11))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .disabled(settings.overlayMode == .never)

                Button("Reset position") {
                    settings.overlayOrigin = nil
                    NotificationCenter.default.post(name: .pulseOverlayLayoutChanged, object: nil)
                }
                .disabled(settings.overlayOrigin == nil)
            } header: {
                Text("Corner overlay")
            } footer: {
                Text("The overlay appears whenever the Pulse window isn't the one you're looking at, and floats above other apps — including full-screen ones. Drag it anywhere you like.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        Form {
            Section {
                Toggle("Enable system-wide shortcuts", isOn: $settings.hotkeysEnabled)
                    .onChange(of: settings.hotkeysEnabled) { _, _ in
                        NotificationCenter.default.post(name: .pulseHotKeysChanged, object: nil)
                    }
                ForEach(HotKeyAction.allCases, id: \.rawValue) { action in
                    LabeledContent(action.displayName) {
                        Text(action.shortcutText)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(settings.hotkeysEnabled ? .primary : .tertiary)
                    }
                }
            } header: {
                Text("System-wide")
            } footer: {
                Text("These work from any app. They don't need Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Start / pause") { key("Space") }
                LabeledContent("Speak a timer") { key("⌘D") }
                LabeledContent("Stop") { key("⌘.") }
                LabeledContent("Run again") { key("⌘R") }
                LabeledContent("Add five minutes") { key("⌘⇧+") }
                LabeledContent("Full screen") { key("⌃⌘F") }
            } header: { Text("In the Pulse window") }
        }
        .formStyle(.grouped)
    }

    private func key(_ text: String) -> some View {
        Text(text).font(.system(.body, design: .monospaced))
    }
}

extension Notification.Name {
    static let pulseOverlayLayoutChanged = Notification.Name("PulseOverlayLayoutChanged")
    static let pulseHotKeysChanged = Notification.Name("PulseHotKeysChanged")
}
