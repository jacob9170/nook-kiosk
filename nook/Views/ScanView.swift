//
//  ScanView.swift
//  Nook
//

import SwiftUI

struct ScanView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let mode: KioskMode

    private enum Phase: Equatable {
        case scanning, checking, problem(BookingProblem)
    }

    @State private var phase: Phase = .scanning
    @State private var manualEntry = false
    @State private var cameraUnavailable = false
    @State private var lastCode = ""

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 40)) : AnyLayout(VStackLayout(spacing: 28))
            layout {
                Group {
                    if manualEntry {
                        CodeKeypad { code in submit(code) }
                    } else {
                        cameraPanel
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                sidePanel
                    .frame(maxWidth: wide ? geo.size.width * 0.38 : .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 8)
        .onAppear {
            settings.speak(mode == .borrow
                ? "Hold your booking QR code up to the camera, or enter your booking number."
                : "Scan the same QR code you used to borrow the item, or enter your booking number.")
        }
    }

    // MARK: Camera

    private var cameraPanel: some View {
        ZStack {
            if cameraUnavailable {
                RoundedRectangle(cornerRadius: 36).fill(settings.surface)
                VStack(spacing: 16) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(settings.secondary)
                    Text("Camera unavailable")
                        .kFont(24, .semibold)
                    Text("Enter your booking number instead.")
                        .kFont(18)
                        .foregroundStyle(settings.secondary)
                    Button("Enter booking number") { manualEntry = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(maxWidth: 360)
                        .padding(.top, 8)
                    #if DEBUG
                    DemoCodes { submit($0) }.padding(.top, 20)
                    #endif
                }
                .padding(32)
            } else {
                QRScannerView(isActive: phase == .scanning) { payload in
                    guard let code = BookingCodeParser.code(from: payload) else {
                        phase = .problem(.notFound)
                        return
                    }
                    submit(code)
                } onUnavailable: {
                    cameraUnavailable = true
                }
                .clipShape(.rect(cornerRadius: 36))

                Viewfinder(active: phase == .scanning)
                    .frame(width: 300, height: 300)

                VStack {
                    Spacer()
                    Label("Hold your QR code inside the frame", systemImage: "qrcode")
                        .kFont(18, .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(28)
                }
            }

            if phase == .checking {
                RoundedRectangle(cornerRadius: 36).fill(.white.opacity(0.85))
                VStack(spacing: 18) {
                    ProgressView().controlSize(.extraLarge).tint(settings.accent)
                    Text("Finding your booking…").kFont(22, .semibold)
                }
            }
        }
    }

    // MARK: Side panel

    @ViewBuilder
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            if case .problem(let problem) = phase {
                ProblemCard(problem: problem, onSwitch: switchMode) {
                    phase = .scanning
                }
            } else {
                steps
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(settings.animation) {
                    manualEntry.toggle()
                    phase = .scanning
                }
            } label: {
                Label(manualEntry ? "Scan QR code instead" : "Enter booking number",
                      systemImage: manualEntry ? "qrcode.viewfinder" : "number")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(mode == .borrow ? "Scan to collect" : "Scan to return")
                    .kFont(44, .bold)
                    .tracking(-1)
                Text(mode == .borrow
                     ? "Your locker opens as soon as we find your booking."
                     : "Use the same QR code you used to borrow the item.")
                    .kFont(20)
                    .foregroundStyle(settings.secondary)
            }
            StepRow(number: 1, text: "Open the Nook app and tap **My bookings**")
            StepRow(number: 2, text: manualEntry ? "Type the 6-digit **booking number**" : "Hold the **QR code** up to the camera")
            StepRow(number: 3, text: mode == .borrow ? "Take your item from the locker that opens" : "Place the item back in the locker that opens")
        }
    }

    // MARK: Actions

    private func submit(_ code: String) {
        guard phase != .checking else { return }
        lastCode = code
        phase = .checking
        Task {
            do {
                let booking = try await store.validate(code: code, for: mode)
                store.go(.confirm(booking, mode))
            } catch let problem as BookingProblem {
                withAnimation(settings.animation) { phase = .problem(problem) }
                settings.speak("\(problem.title). \(problem.message)")
            } catch {
                withAnimation(settings.animation) { phase = .problem(.notFound) }
            }
        }
    }

    /// The resident picked the wrong button: reuse the code they already scanned.
    private func switchMode(to other: KioskMode) {
        phase = .checking
        Task {
            if let booking = try? await store.validate(code: lastCode, for: other) {
                store.go(.confirm(booking, other))
            } else {
                store.go(.scan(other))
            }
        }
    }
}

private struct StepRow: View {
    @Environment(KioskSettings.self) private var settings
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 16) {
            Text("\(number)")
                .kFont(18, .bold, design: .rounded)
                .foregroundStyle(settings.accent)
                .frame(width: 40, height: 40)
                .background(settings.accentSoft, in: .circle)
            Text(text)
                .kFont(20)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProblemCard: View {
    @Environment(KioskSettings.self) private var settings
    let problem: BookingProblem
    let onSwitch: (KioskMode) -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            IconBadge(symbol: "exclamationmark.circle.fill", tint: settings.warning, size: 64)
            Text(problem.title)
                .kFont(32, .bold)
                .tracking(-0.5)
            Text(problem.message)
                .kFont(20)
                .foregroundStyle(settings.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let suggested = problem.suggestedMode {
                Button("\(suggested.title) instead") { onSwitch(suggested) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 8)
                Button("Try again", action: onRetry)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: .infinity)
            } else {
                Button("Try again", action: onRetry)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card()
    }
}

private struct Viewfinder: View {
    @Environment(KioskSettings.self) private var settings
    let active: Bool
    @State private var sweep = false

    var body: some View {
        ZStack {
            ViewfinderCorners()
                .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            if active && !settings.reduceMotion {
                LinearGradient(colors: [.clear, settings.accent.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 3)
                    .padding(.horizontal, 24)
                    .offset(y: sweep ? 120 : -120)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever()) { sweep = true }
                    }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 10)
    }
}

private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let l: CGFloat = 54
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                 (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                 (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                 (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x, y: corner.y + l * dy))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x + l * dx, y: corner.y))
        }
        return p
    }
}

// MARK: - Keypad

struct CodeKeypad: View {
    @Environment(KioskSettings.self) private var settings
    let onSubmit: (String) -> Void
    @State private var digits = ""

    private let length = 6

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 12) {
                ForEach(0..<length, id: \.self) { i in
                    let char = i < digits.count ? String(digits[digits.index(digits.startIndex, offsetBy: i)]) : ""
                    Text(char)
                        .kFont(40, .bold, design: .rounded)
                        .frame(width: 64, height: 80)
                        .background(settings.surface, in: .rect(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(i == digits.count ? settings.accent : settings.hairline,
                                          lineWidth: i == digits.count ? 3 : settings.hairlineWidth))
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Booking number, \(digits.count) of \(length) digits entered")

            NumberPad { press($0) }

            Button("Find my booking") { onSubmit(digits) }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 400)
                .disabled(digits.count < length)
                .opacity(digits.count < length ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: .rect(cornerRadius: 36))
        .overlay(RoundedRectangle(cornerRadius: 36).strokeBorder(settings.hairline, lineWidth: settings.hairlineWidth))
    }

    private func press(_ key: String) {
        switch key {
        case "delete": if !digits.isEmpty { digits.removeLast() }
        case "clear": digits = ""
        default: if digits.count < length { digits.append(key) }
        }
    }
}

#if DEBUG
/// Sample bookings from the mock backend, for testing without a camera.
private struct DemoCodes: View {
    @Environment(KioskSettings.self) private var settings
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("DEMO BOOKINGS").kFont(12, .bold).foregroundStyle(settings.secondary).tracking(1)
            HStack(spacing: 8) {
                ForEach([("482193", "Collect"), ("715024", "Return"), ("920457", "Overdue"), ("306611", "Too early")], id: \.0) { code, label in
                    Button { onPick(code) } label: {
                        VStack(spacing: 2) {
                            Text(code).kFont(15, .bold, design: .monospaced)
                            Text(label).kFont(12).foregroundStyle(settings.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white, in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(TileButtonStyle())
                }
            }
        }
    }
}
#endif
