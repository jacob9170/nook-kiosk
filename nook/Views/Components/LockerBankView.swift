//
//  LockerBankView.swift
//  Nook
//

import SwiftUI

/// A map of the physical locker wall, used to point people at the right door.
struct LockerBankView: View {
    @Environment(KioskSettings.self) private var settings
    let lockers: [Locker]
    var highlighted: Int?
    var doorOpen = false
    var showStatus = false
    /// Admin view: print what's inside on each door.
    var showItemNames = false
    /// Lets a tapped locker zoom into a detail view.
    var namespace: Namespace.ID?
    /// The locker currently zoomed in, which leaves a gap in the wall.
    var hidden: Int?
    var onSelect: ((Locker) -> Void)?

    private let columns = 4

    var body: some View {
        let rows = stride(from: 0, to: lockers.count, by: columns).map { Array(lockers[$0..<min($0 + columns, lockers.count)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r]) { locker in
                        if locker.number == hidden {
                            Color.clear.aspectRatio(0.9, contentMode: .fit)
                        } else {
                            cell(locker)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(settings.surface, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(settings.hairline, lineWidth: settings.hairlineWidth))
    }

    @ViewBuilder
    private func cell(_ locker: Locker) -> some View {
        let isTarget = locker.number == highlighted
        let dimmed = highlighted != nil && !isTarget
        Button {
            onSelect?(locker)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTarget ? settings.accent.opacity(0.14) : .white)

                LockerDoor(label: locker.label, isTarget: isTarget,
                           statusColor: showStatus ? settings.color(for: locker.status) : nil,
                           itemName: showItemNames ? (locker.item?.name ?? "Empty") : nil,
                           unlocked: showItemNames && locker.isUnlocked)
                    .rotation3DEffect(.degrees(isTarget && doorOpen ? -68 : 0),
                                      axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
                    .animation(settings.reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7), value: doorOpen)

                if isTarget && !settings.reduceMotion {
                    PulseRing(color: settings.accent)
                }
            }
            .aspectRatio(0.9, contentMode: .fit)
            .matchedLocker(locker.number, in: namespace)
            .opacity(dimmed ? 0.45 : 1)
        }
        .buttonStyle(TileButtonStyle())
        .disabled(onSelect == nil)
        .accessibilityLabel("Locker \(locker.number)\(locker.item.map { ", \($0.name)" } ?? "")\(showStatus ? ", \(locker.status.rawValue)" : "")")
    }
}

extension View {
    /// Ties a locker on the wall to its zoomed-in version so one animates into the other.
    @ViewBuilder
    func matchedLocker(_ number: Int, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "locker-\(number)", in: namespace)
        } else {
            self
        }
    }
}

private struct LockerDoor: View {
    @Environment(KioskSettings.self) private var settings
    let label: String
    let isTarget: Bool
    let statusColor: Color?
    var itemName: String?
    var unlocked = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(isTarget ? settings.accent : .white)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isTarget ? .clear : settings.hairline, lineWidth: settings.hairlineWidth))
            .overlay(alignment: .topLeading) {
                Text(label)
                    .kFont(18, .bold, design: .rounded)
                    .monospacedDigit()
                    .foregroundStyle(isTarget ? .white : settings.ink)
                    .padding(12)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if unlocked {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(settings.warning)
                    }
                    if let statusColor {
                        Circle().fill(statusColor).frame(width: 10, height: 10)
                    }
                }
                .padding(12)
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(isTarget ? .white.opacity(0.7) : settings.hairline)
                    .frame(width: 5, height: 26)
                    .padding(.trailing, 10)
            }
            .overlay(alignment: .bottomLeading) {
                if let itemName {
                    Text(itemName)
                        .kFont(13, .semibold)
                        .foregroundStyle(itemName == "Empty" ? settings.secondary : settings.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .padding(.trailing, 14)
                }
            }
    }
}

struct PulseRing: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(color, lineWidth: 3)
            .scaleEffect(animate ? 1.18 : 1)
            .opacity(animate ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { animate = true }
            }
            .allowsHitTesting(false)
    }
}
