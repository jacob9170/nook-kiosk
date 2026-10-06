//
//  AccessibilityPanel.swift
//  Nook
//

import SwiftUI

struct AccessibilityPanel: View {
    @Environment(KioskSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accessibility")
                        .kFont(40, .bold)
                        .tracking(-1)
                    Text("These settings reset when you're finished, ready for the next person.")
                        .kFont(18)
                        .foregroundStyle(settings.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(settings.ink)
                        .frame(width: 64, height: 64)
                        .background(settings.surface, in: .circle)
                }
                .buttonStyle(TileButtonStyle())
                .accessibilityLabel("Close")
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    OptionTile(title: "Larger text", detail: "Make everything easier to read",
                               symbol: "textformat.size", isOn: $settings.largeText)
                    OptionTile(title: "High contrast", detail: "Bolder colours and outlines",
                               symbol: "circle.lefthalf.filled", isOn: $settings.highContrast)
                    OptionTile(title: "Voice guidance", detail: "Read each step out loud",
                               symbol: "speaker.wave.2.fill", isOn: $settings.voiceGuidance)
                    OptionTile(title: "Lower the screen", detail: "Move controls within easy reach",
                               symbol: "figure.roll", isOn: $settings.lowReach)
                    OptionTile(title: "Reduce motion", detail: "Turn off animations",
                               symbol: "circle.dotted.and.circle", isOn: $settings.reduceMotion)
                }
            }

            HStack(spacing: 16) {
                if settings.isCustomised {
                    Button("Reset") { settings.reset() }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .foregroundStyle(settings.ink)
        .padding(40)
        .background(.white)
        .onChange(of: settings.voiceGuidance) { _, on in
            if on { settings.speak("Voice guidance is on. I'll read out each step.") }
        }
    }
}

private struct OptionTile: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let detail: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(settings.animation) { isOn.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isOn ? .white : settings.accent)
                        .frame(width: 60, height: 60)
                        .background(isOn ? .white.opacity(0.2) : settings.accentSoft, in: .rect(cornerRadius: 18))
                    Spacer()
                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .tint(isOn ? .white.opacity(0.35) : settings.accent)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).kFont(22, .bold)
                    Text(detail)
                        .kFont(16)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isOn ? .white : settings.ink)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? settings.accent : settings.surface, in: .rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28)
                .strokeBorder(settings.highContrast ? settings.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(detail)
    }
}
