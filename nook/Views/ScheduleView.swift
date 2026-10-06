//
//  ScheduleView.swift
//  Nook
//

import SwiftUI

/// Upcoming pickups and returns. Shows items and lockers only, never who
/// booked them, because the kiosk is in a shared space.
struct ScheduleView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @State private var day = Calendar.current.startOfDay(for: .now)

    enum EventKind { case pickup, due }

    struct Event: Identifiable {
        let id: String
        let kind: EventKind
        let date: Date
        let booking: Booking
    }

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: .now)) }
    }

    private func events(on day: Date) -> [Event] {
        let cal = Calendar.current
        var result: [Event] = []
        for b in store.bookings {
            if b.status == .reserved, cal.isDate(b.pickupStart, inSameDayAs: day) {
                result.append(Event(id: "p\(b.code)", kind: .pickup, date: b.pickupStart, booking: b))
            }
            if b.status == .onLoan || b.status == .reserved, cal.isDate(b.returnDue, inSameDayAs: day) {
                result.append(Event(id: "r\(b.code)", kind: .due, date: b.returnDue, booking: b))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    /// Overdue returns from earlier days still show on today.
    private var overdue: [Event] {
        store.bookings
            .filter { $0.isOverdue && !Calendar.current.isDateInToday($0.returnDue) }
            .map { Event(id: "o\($0.code)", kind: .due, date: $0.returnDue, booking: $0) }
    }

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        let list = events(on: day)
        let carried = isToday ? overdue : []
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                ForEach(days, id: \.self) { d in
                    DayButton(date: d, hasEvents: !events(on: d).isEmpty, selected: d == day) {
                        withAnimation(settings.animation) { day = d }
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                    .kFont(36, .bold)
                    .tracking(-1)
                Text(day.formatted(.dateTime.day().month(.wide)))
                    .kFont(22, .medium)
                    .foregroundStyle(settings.secondary)
                Spacer()
                Text(summary(list))
                    .kFont(18, .medium)
                    .foregroundStyle(settings.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(carried) { event in
                        EventRow(event: event, isPast: false)
                    }
                    if list.isEmpty && carried.isEmpty {
                        emptyState
                    }
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, event in
                        if isToday && event.date > .now && (index == 0 || list[index - 1].date <= .now) {
                            NowMarker()
                        }
                        EventRow(event: event, isPast: isToday && event.date < .now && !event.booking.isOverdue)
                    }
                    if isToday, let last = list.last, last.date <= .now {
                        NowMarker()
                    }
                }
                .padding(.bottom, 12)
            }

            HStack(spacing: 12) {
                InfoChip(symbol: "clock.fill", text: store.hubHours.summary)
                InfoChip(symbol: "hourglass", text: store.hubHours.windowSummary)
                InfoChip(symbol: "sparkles", text: "Restocked Mondays 10am – 12pm")
            }
        }
        .padding(.top, 8)
        .onAppear { settings.speak("Here's the locker schedule for the week.") }
    }

    private func summary(_ list: [Event]) -> String {
        let pickups = list.filter { $0.kind == .pickup }.count
        let returns = list.count - pickups
        return "\(pickups) pickup\(pickups == 1 ? "" : "s") · \(returns) return\(returns == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(settings.accent)
            Text("Nothing scheduled").kFont(24, .semibold)
            Text("Every locker is free to book this day.")
                .kFont(18)
                .foregroundStyle(settings.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

private struct DayButton: View {
    @Environment(KioskSettings.self) private var settings
    let date: Date
    let hasEvents: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Text(Calendar.current.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                    .kFont(15, .semibold)
                    .lineLimit(1)
                Text(date.formatted(.dateTime.day()))
                    .kFont(28, .bold, design: .rounded)
                Circle()
                    .fill(hasEvents ? (selected ? .white : settings.accent) : .clear)
                    .frame(width: 7, height: 7)
            }
            .foregroundStyle(selected ? .white : settings.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selected ? settings.accent : settings.surface, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month()))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct EventRow: View {
    @Environment(KioskSettings.self) private var settings
    let event: ScheduleView.Event
    let isPast: Bool

    private var booking: Booking { event.booking }
    private var isPickup: Bool { event.kind == .pickup }
    private var color: Color {
        isPickup ? settings.accent : (booking.isOverdue ? settings.danger : settings.success)
    }
    private var label: String {
        isPickup ? "Pickup" : (booking.isOverdue ? "Overdue" : "Return")
    }
    private var time: String {
        Calendar.current.isDateInToday(event.date) || !booking.isOverdue
            ? event.date.formatted(date: .omitted, time: .shortened)
            : event.date.formatted(.dateTime.weekday(.abbreviated))
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(time)
                .kFont(20, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(isPast ? settings.secondary : settings.ink)
                .lineLimit(1)
                .frame(width: 110 * settings.textScale, alignment: .trailing)

            ZStack {
                Rectangle().fill(settings.hairline).frame(width: 2)
                Circle()
                    .fill(isPast ? settings.hairline : color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            }
            .frame(width: 48)

            HStack(spacing: 16) {
                IconBadge(symbol: booking.item.symbol, tint: isPast ? settings.secondary : nil, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(booking.item.name)
                        .kFont(20, .semibold)
                        .lineLimit(1)
                    Text("Locker \(booking.lockerLabel)")
                        .kFont(16)
                        .foregroundStyle(settings.secondary)
                }
                Spacer(minLength: 12)
                Text(label)
                    .kFont(15, .bold)
                    .foregroundStyle(isPast ? settings.secondary : color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background((isPast ? settings.secondary : color).opacity(0.1), in: .capsule)
                    .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.white, in: .rect(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(settings.hairline, lineWidth: settings.hairlineWidth))
            .opacity(isPast ? 0.6 : 1)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NowMarker: View {
    @Environment(KioskSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            Text("Now")
                .kFont(15, .bold)
                .foregroundStyle(settings.danger)
                .frame(width: 110 * settings.textScale, alignment: .trailing)
            Circle()
                .fill(settings.danger)
                .frame(width: 10, height: 10)
                .frame(width: 48)
            Rectangle().fill(settings.danger).frame(height: 2)
        }
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}

private struct InfoChip: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(settings.accent)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .kFont(15, .medium)
        .foregroundStyle(settings.secondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(settings.surface, in: .capsule)
    }
}
