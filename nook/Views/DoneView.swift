//
//  DoneView.swift
//  Nook
//

import SwiftUI

struct DoneView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let booking: Booking
    let mode: KioskMode

    @State private var appeared = false
    @State private var remaining = 12
    private let total = 12

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(settings.success.opacity(0.1))
                    .frame(width: 220, height: 220)
                    .scaleEffect(appeared ? 1 : 0.6)
                Circle()
                    .fill(settings.success)
                    .frame(width: 150, height: 150)
                    .scaleEffect(appeared ? 1 : 0.4)
                Image(systemName: "checkmark")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
            }
            .animation(settings.reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6), value: appeared)

            VStack(spacing: 14) {
                Text(mode == .borrow ? "Enjoy, \(booking.residentFirstName)!" : "Thanks, \(booking.residentFirstName)!")
                    .kFont(56, .bold)
                    .tracking(-1.5)
                Text(message)
                    .kFont(22)
                    .foregroundStyle(settings.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)
            }

            if mode == .borrow {
                Label("Return by \(booking.returnDue.formatted(.dateTime.weekday(.wide).hour().minute())) · use the same QR code",
                      systemImage: "arrow.uturn.backward.circle.fill")
                    .kFont(18, .semibold)
                    .foregroundStyle(settings.accent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(settings.accentSoft, in: .capsule)
            }

            Spacer()

            Button {
                finish()
            } label: {
                HStack(spacing: 14) {
                    Text("Done")
                    CountdownRing(progress: Double(remaining) / Double(total))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            appeared = true
            settings.speak(mode == .borrow
                ? "All done. Enjoy the \(booking.item.name). Please return it using the same QR code."
                : "All done. Thanks for returning the \(booking.item.name).")
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                withAnimation(.linear(duration: 1)) { remaining -= 1 }
            }
            finish()
        }
    }

    private var message: String {
        switch mode {
        case .borrow:
            "Your \(booking.item.name) is all yours. We'll send a reminder to the Nook app before it's due."
        case .return:
            "The \(booking.item.name) is back in locker \(booking.lockerLabel), ready for your next neighbour. Your booking is now closed."
        }
    }

    private func finish() {
        // Hand the kiosk back to the next person with default settings.
        settings.reset()
        store.endSession()
        store.goHome()
    }
}

private struct CountdownRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 26, height: 26)
    }
}
