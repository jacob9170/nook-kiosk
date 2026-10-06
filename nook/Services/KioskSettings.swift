//
//  KioskSettings.swift
//  Nook
//

import AVFoundation
import Observation
import SwiftUI

/// Accessibility options a resident can switch on at the kiosk. They apply to
/// the current session only and reset when the kiosk returns to idle, so the
/// next person starts from the default.
@Observable
final class KioskSettings {
    var largeText = false
    var highContrast = false
    var reduceMotion = false
    var voiceGuidance = false { didSet { if !voiceGuidance { speech.stopSpeaking(at: .immediate) } } }
    /// Moves everything into the lower part of the screen for wheelchair users
    /// and anyone who can't comfortably reach the top of the kiosk.
    var lowReach = false

    @ObservationIgnored private let speech = AVSpeechSynthesizer()

    var isCustomised: Bool { largeText || highContrast || reduceMotion || voiceGuidance || lowReach }
    var textScale: CGFloat { largeText ? 1.3 : 1 }

    func reset() {
        largeText = false
        highContrast = false
        reduceMotion = false
        voiceGuidance = false
        lowReach = false
    }

    func speak(_ text: String) {
        guard voiceGuidance else { return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        speech.speak(utterance)
    }

    // MARK: - Palette

    var accent: Color { highContrast ? Color(hex: 0x1A1FD6) : Color(hex: 0x3D5AFE) }
    var accentSoft: Color { highContrast ? Color(hex: 0xE0E2FF) : Color(hex: 0x3D5AFE).opacity(0.08) }
    var ink: Color { Color(hex: 0x0A0B10) }
    var secondary: Color { highContrast ? Color(hex: 0x2B2F3A) : Color(hex: 0x6B7080) }
    var surface: Color { highContrast ? Color(hex: 0xEDEEF2) : Color(hex: 0xF5F6F9) }
    var hairline: Color { highContrast ? Color(hex: 0x0A0B10) : Color(hex: 0xE6E8EE) }
    var hairlineWidth: CGFloat { highContrast ? 2 : 1 }
    var success: Color { highContrast ? Color(hex: 0x05603A) : Color(hex: 0x12B76A) }
    var warning: Color { highContrast ? Color(hex: 0x93370D) : Color(hex: 0xF79009) }
    var danger: Color { highContrast ? Color(hex: 0x912018) : Color(hex: 0xF04438) }

    func color(for status: LockerStatus) -> Color {
        switch status {
        case .available: success
        case .reserved: accent
        case .onLoan: secondary
        case .maintenance: warning
        }
    }

    var animation: Animation? { reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
