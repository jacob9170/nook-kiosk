//
//  Theme.swift
//  Nook
//

import SwiftUI

// MARK: - Type

private struct KioskFont: ViewModifier {
    @Environment(KioskSettings.self) private var settings
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * settings.textScale, weight: weight, design: design))
    }
}

extension View {
    /// Kiosk type that grows with the Large Text accessibility option.
    func kFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(KioskFont(size: size, weight: weight, design: design))
    }

    func card(padding: CGFloat = 28) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

private struct CardModifier: ViewModifier {
    @Environment(KioskSettings.self) private var settings
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                // Shadow on the shape only, so it doesn't bleed onto the contents.
                RoundedRectangle(cornerRadius: 28)
                    .fill(.white)
                    .shadow(color: .black.opacity(settings.highContrast ? 0 : 0.04), radius: 24, y: 10)
            }
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(settings.hairline, lineWidth: settings.hairlineWidth))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(KioskSettings.self) private var settings
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kFont(22, .semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 36)
            .frame(minHeight: 76)
            .frame(maxWidth: .infinity)
            .background(tint ?? settings.accent, in: .capsule)
            .scaleEffect(configuration.isPressed && !settings.reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(settings.animation, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(KioskSettings.self) private var settings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .kFont(20, .semibold)
            .foregroundStyle(settings.ink)
            .padding(.horizontal, 28)
            .frame(minHeight: 68)
            .background(settings.surface, in: .capsule)
            .overlay(Capsule().strokeBorder(settings.highContrast ? settings.ink : .clear, lineWidth: 2))
            .scaleEffect(configuration.isPressed && !settings.reduceMotion ? 0.97 : 1)
            .animation(settings.animation, value: configuration.isPressed)
    }
}

/// A large tile for the main choices on a screen.
struct TileButtonStyle: ButtonStyle {
    @Environment(KioskSettings.self) private var settings

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !settings.reduceMotion ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(settings.animation, value: configuration.isPressed)
    }
}

// MARK: - Bits

struct StatusPill: View {
    @Environment(KioskSettings.self) private var settings
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).kFont(15, .semibold)
        }
        .foregroundStyle(settings.highContrast ? settings.ink : color)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(settings.highContrast ? 0.18 : 0.1), in: .capsule)
    }
}

struct IconBadge: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    var tint: Color?
    var size: CGFloat = 64

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint ?? settings.accent)
            .frame(width: size, height: size)
            .background((tint ?? settings.accent).opacity(0.1), in: .rect(cornerRadius: size * 0.3))
    }
}

/// Soft animated colour blobs behind the home screen.
struct AmbientBackground: View {
    @Environment(KioskSettings.self) private var settings

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: settings.reduceMotion || settings.highContrast)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 8
            Canvas { ctx, size in
                let blobs: [(Color, Double, Double, CGFloat)] = [
                    (Color(hex: 0x3D5AFE), 0.0, 0.0, 0.55),
                    (Color(hex: 0x8B5CF6), 2.1, 1.3, 0.45),
                    (Color(hex: 0x22D3EE), 4.2, 2.7, 0.4),
                ]
                ctx.addFilter(.blur(radius: 90))
                for (color, phase, phase2, scale) in blobs {
                    let r = min(size.width, size.height) * scale
                    let x = size.width * (0.72 + 0.14 * cos(t + phase))
                    let y = size.height * (0.28 + 0.16 * sin(t * 1.3 + phase2))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                             with: .color(color.opacity(0.16)))
                }
            }
        }
        .opacity(settings.highContrast ? 0 : 1)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
