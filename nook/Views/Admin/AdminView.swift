//
//  AdminView.swift
//  Nook
//

import SwiftUI

/// Building staff only. Reached by signing in with the admin apartment + PIN.
struct AdminView: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    @Namespace private var lockerZoom
    @State private var selected: Int?
    @State private var tab: AdminTab = .lockers

    enum AdminTab: String, CaseIterable {
        case lockers = "Lockers"
        case service = "Service"
        case bookings = "Bookings"
    }

    private var zoom: Animation? {
        settings.reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            ZStack {
                if let number = selected, let locker = store.lockers.first(where: { $0.number == number }) {
                    AdminLockerInspector(locker: locker, namespace: lockerZoom, wide: wide, size: geo.size) {
                        withAnimation(zoom) { selected = nil }
                    }
                    .transition(.opacity)
                } else {
                    overview(wide: wide, size: geo.size)
                        .transition(.opacity)
                }
            }
        }
        .padding(.top, 8)
        .onAppear {
            if !store.isAdmin { store.goHome() }
            settings.speak("Admin. Tap a locker to inspect it.")
            #if DEBUG
            // `-adminLocker 3` opens a locker straight away, for screenshots.
            let number = UserDefaults.standard.integer(forKey: "adminLocker")
            if number > 0 { selected = number }
            #endif
        }
    }

    private func open(_ locker: Locker) {
        withAnimation(zoom) { selected = locker.number }
    }

    // MARK: - Overview

    private func overview(wide: Bool, size: CGSize) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 40)) : AnyLayout(VStackLayout(spacing: 28))
        return layout {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Locker wall")
                        .kFont(36, .bold)
                        .tracking(-1)
                    Spacer()
                    StatusPill(text: "Staff mode", color: settings.warning)
                }
                Text("Tap a locker to look inside, edit it or unlock it.")
                    .kFont(18)
                    .foregroundStyle(settings.secondary)
                LockerBankView(lockers: store.lockers, showStatus: true, showItemNames: true,
                               namespace: lockerZoom, hidden: selected, onSelect: open)
                    .frame(maxHeight: wide ? .infinity : size.height * 0.42)
                    .frame(maxWidth: .infinity)
                legend
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: wide ? size.width * 0.46 : .infinity)

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    ForEach(AdminTab.allCases, id: \.self) { t in
                        AdminTabChip(title: t.rawValue, badge: badge(for: t), selected: tab == t) {
                            withAnimation(settings.animation) { tab = t }
                        }
                    }
                }
                ScrollView {
                    Group {
                        switch tab {
                        case .lockers: AdminLockersPanel(onOpen: open, onShowService: { tab = .service })
                        case .service: AdminServicePanel(onOpen: open)
                        case .bookings: AdminBookingsPanel(onOpen: open)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func badge(for tab: AdminTab) -> Int? {
        switch tab {
        case .lockers: nil
        case .service: store.tickets.filter { $0.status != .resolved }.count
        case .bookings: store.bookings.filter { $0.status == .reserved || $0.status == .onLoan }.count
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            ForEach([LockerStatus.available, .reserved, .onLoan, .maintenance], id: \.self) { status in
                HStack(spacing: 6) {
                    Circle().fill(settings.color(for: status)).frame(width: 10, height: 10)
                    Text(status.rawValue).kFont(14, .medium).foregroundStyle(settings.secondary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.open.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(settings.warning)
                Text("Unlocked").kFont(14, .medium).foregroundStyle(settings.secondary)
            }
        }
    }
}

private struct AdminTabChip: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let badge: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).kFont(18, .semibold)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .kFont(15, .bold, design: .rounded)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(selected ? .white.opacity(0.2) : settings.hairline, in: .capsule)
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .foregroundStyle(selected ? .white : settings.ink)
            .background(selected ? settings.ink : settings.surface, in: .capsule)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Lockers tab

private struct AdminLockersPanel: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let onOpen: (Locker) -> Void
    let onShowService: () -> Void

    private func count(_ status: LockerStatus) -> Int {
        store.lockers.filter { $0.status == status && $0.item != nil }.count
    }

    var body: some View {
        let unlocked = store.lockers.filter(\.isUnlocked)
        let empty = store.lockers.filter { $0.item == nil }
        let openTickets = store.tickets.filter { $0.status != .resolved }.count

        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                StatTile(value: count(.available), label: "Available", color: settings.success)
                StatTile(value: count(.reserved), label: "Reserved", color: settings.accent)
                StatTile(value: count(.onLoan), label: "On loan", color: settings.secondary)
                StatTile(value: store.lockers.filter { $0.status == .maintenance }.count, label: "Out of service", color: settings.warning)
            }

            AdminRow(symbol: unlocked.isEmpty ? "lock.fill" : "lock.open.fill",
                     tint: unlocked.isEmpty ? settings.success : settings.warning,
                     title: unlocked.isEmpty ? "All doors locked" : "\(unlocked.count) door\(unlocked.count == 1 ? "" : "s") unlocked",
                     subtitle: unlocked.isEmpty ? "Every locker is secure." : unlocked.map { "Locker \($0.label)" }.joined(separator: ", ")) {
                if !unlocked.isEmpty {
                    Button("Lock all") { Task { await store.lockAllDoors() } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }

            AdminRow(symbol: "wrench.and.screwdriver.fill", tint: openTickets > 0 ? settings.warning : settings.success,
                     title: openTickets > 0 ? "\(openTickets) open service job\(openTickets == 1 ? "" : "s")" : "No open service jobs",
                     subtitle: "Repairs and reports from the kiosk.") {
                Button("View", action: onShowService)
                    .buttonStyle(SecondaryButtonStyle())
            }

            ForEach(empty) { locker in
                AdminRow(symbol: "tray", tint: settings.accent, title: "Locker \(locker.label) is empty",
                         subtitle: "Add an item so residents can borrow it.") {
                    Button("Add item") { onOpen(locker) }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}

private struct StatTile: View {
    @Environment(KioskSettings.self) private var settings
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .kFont(40, .bold, design: .rounded)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .kFont(16, .medium)
                .foregroundStyle(settings.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }
}

/// Icon, title, subtitle, and an optional action on the right.
struct AdminRow<Action: View>: View {
    @Environment(KioskSettings.self) private var settings
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 16) {
            IconBadge(symbol: symbol, tint: tint, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).kFont(19, .semibold)
                Text(subtitle)
                    .kFont(15)
                    .foregroundStyle(settings.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            action
        }
        .card(padding: 18)
    }
}

// MARK: - Service tab

struct AdminServicePanel: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let onOpen: (Locker) -> Void
    @State private var filter: TicketStatus = .open
    @State private var composing = false

    var body: some View {
        let shown = store.tickets.filter { $0.status == filter }
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach(TicketStatus.allCases) { status in
                    AdminTabChip(title: status.rawValue, badge: store.tickets.filter { $0.status == status }.count,
                                 selected: filter == status) { filter = status }
                }
                Spacer()
                Button {
                    withAnimation(settings.animation) { composing.toggle() }
                } label: {
                    Label("Log repair", systemImage: composing ? "xmark" : "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            if composing {
                RepairComposer(locker: nil) { composing = false }
            }

            if shown.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(settings.success)
                    Text("Nothing \(filter.rawValue.lowercased())").kFont(22, .semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            }

            ForEach(shown) { ticket in
                TicketCard(ticket: ticket, onOpen: onOpen)
            }
        }
    }
}

struct TicketCard: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let ticket: ServiceTicket
    var onOpen: ((Locker) -> Void)?

    private var color: Color {
        switch ticket.status {
        case .open: settings.danger
        case .inProgress: settings.accent
        case .resolved: settings.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                IconBadge(symbol: ticket.status.symbol, tint: color, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.title).kFont(20, .semibold)
                    Text(ticket.details)
                        .kFont(15)
                        .foregroundStyle(settings.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(ticket.reportedBy) · \(ticket.createdAt.formatted(.relative(presentation: .named)))")
                        .kFont(14, .medium)
                        .foregroundStyle(settings.secondary)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                if let label = ticket.lockerLabel {
                    Button {
                        if let onOpen, let locker = store.lockers.first(where: { $0.number == ticket.lockerNumber }) {
                            onOpen(locker)
                        }
                    } label: {
                        Text("Locker \(label)")
                            .kFont(15, .bold)
                            .foregroundStyle(settings.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(settings.accentSoft, in: .capsule)
                    }
                    .buttonStyle(TileButtonStyle())
                    .disabled(onOpen == nil)
                }
            }

            HStack(spacing: 12) {
                switch ticket.status {
                case .open:
                    Button("Start work") { Task { await store.setStatus(.inProgress, for: ticket) } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Resolve") { Task { await store.setStatus(.resolved, for: ticket) } }
                        .buttonStyle(PrimaryButtonStyle(tint: settings.success))
                case .inProgress:
                    Button("Back to open") { Task { await store.setStatus(.open, for: ticket) } }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Resolve") { Task { await store.setStatus(.resolved, for: ticket) } }
                        .buttonStyle(PrimaryButtonStyle(tint: settings.success))
                case .resolved:
                    Button("Reopen") { Task { await store.setStatus(.open, for: ticket) } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .card(padding: 20)
    }
}

/// Quick form for logging a repair, optionally pinned to a locker.
struct RepairComposer: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    /// Fixed locker, or nil to let staff pick one.
    let locker: Locker?
    let onDone: () -> Void

    @State private var pickedLocker: Int?
    @State private var reason: String?
    @State private var outOfService = true

    var body: some View {
        let target = locker ?? store.lockers.first { $0.number == pickedLocker }
        VStack(alignment: .leading, spacing: 16) {
            Text("Log a repair").kFont(20, .bold)

            if locker == nil {
                Text("Locker").kFont(15, .semibold).foregroundStyle(settings.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.lockers) { l in
                            SmallChoice(title: l.label, selected: pickedLocker == l.number) { pickedLocker = l.number }
                        }
                    }
                }
            }

            Text("What's wrong?").kFont(15, .semibold).foregroundStyle(settings.secondary)
            FlowLayout {
                ForEach(AdminCatalog.repairReasons, id: \.self) { r in
                    SmallChoice(title: r, selected: reason == r) { reason = r }
                }
            }

            Toggle(isOn: $outOfService) {
                Text("Take the locker out of service until it's fixed").kFont(16, .medium)
            }
            .tint(settings.accent)

            Button {
                guard let reason else { return }
                Task {
                    await store.logRepair(reason, locker: target, takeOutOfService: outOfService)
                    onDone()
                }
            } label: {
                Label("Log repair", systemImage: "wrench.and.screwdriver.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(reason == nil || target == nil)
            .opacity(reason == nil || target == nil ? 0.4 : 1)
        }
        .card(padding: 22)
    }
}

struct SmallChoice: View {
    @Environment(KioskSettings.self) private var settings
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .kFont(16, .semibold)
                .padding(.horizontal, 16)
                .frame(minWidth: 52, minHeight: 46)
                .foregroundStyle(selected ? .white : settings.ink)
                .background(selected ? settings.accent : settings.surface, in: .capsule)
                .overlay(Capsule().strokeBorder(settings.highContrast && !selected ? settings.ink : .clear, lineWidth: 2))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Bookings tab

private struct AdminBookingsPanel: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let onOpen: (Locker) -> Void

    var body: some View {
        let active = store.bookings
            .filter { $0.status == .reserved || $0.status == .onLoan }
            .sorted { sortDate($0) < sortDate($1) }

        VStack(alignment: .leading, spacing: 18) {
            hoursCard

            Text("Active bookings")
                .kFont(22, .bold)
                .padding(.top, 6)

            ForEach(active) { booking in
                AdminBookingCard(booking: booking) {
                    if let locker = store.lockers.first(where: { $0.number == booking.lockerNumber }) { onOpen(locker) }
                }
            }
        }
    }

    private func sortDate(_ b: Booking) -> Date {
        b.status == .reserved ? b.pickupStart : b.returnDue
    }

    private var hoursCard: some View {
        let hours = store.hubHours
        return VStack(alignment: .leading, spacing: 16) {
            Label("Hub hours", systemImage: "clock.fill")
                .kFont(20, .bold)
            HStack(spacing: 14) {
                HourStepper(label: "Opens", value: hours.openHour, range: 0...(hours.closeHour - 1)) { new in
                    var h = hours; h.openHour = new
                    Task { await store.setHubHours(h) }
                }
                HourStepper(label: "Closes", value: hours.closeHour, range: (hours.openHour + 1)...24) { new in
                    var h = hours; h.closeHour = new
                    Task { await store.setHubHours(h) }
                }
            }
            Text("Pickup window").kFont(15, .semibold).foregroundStyle(settings.secondary)
            HStack(spacing: 8) {
                ForEach([30, 60, 90, 120], id: \.self) { minutes in
                    SmallChoice(title: minutes < 60 ? "\(minutes) min" : String(format: "%g hr", Double(minutes) / 60),
                                selected: hours.pickupWindowMinutes == minutes) {
                        var h = hours; h.pickupWindowMinutes = minutes
                        Task { await store.setHubHours(h) }
                    }
                }
            }
            Text("Shown on the kiosk schedule and used for new bookings.")
                .kFont(14)
                .foregroundStyle(settings.secondary)
        }
        .card(padding: 22)
    }
}

private struct HourStepper: View {
    @Environment(KioskSettings.self) private var settings
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).kFont(12, .bold).tracking(1).foregroundStyle(settings.secondary)
                Text(HubHours.label(value)).kFont(24, .bold, design: .rounded)
            }
            Spacer()
            stepButton("minus", enabled: value > range.lowerBound) { onChange(value - 1) }
            stepButton("plus", enabled: value < range.upperBound) { onChange(value + 1) }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(settings.surface, in: .rect(cornerRadius: 20))
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(settings.ink)
                .frame(width: 48, height: 48)
                .background(.white, in: .circle)
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel("\(symbol == "plus" ? "Later" : "Earlier") \(label.lowercased()) time")
    }
}

/// A booking with the controls staff need: extend, cancel, mark returned.
struct AdminBookingCard: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let booking: Booking
    var onOpenLocker: (() -> Void)?

    private var statusText: String {
        if booking.isOverdue { return "Overdue" }
        return booking.status == .reserved ? "Awaiting pickup" : "On loan"
    }

    private var statusColor: Color {
        if booking.isOverdue { return settings.danger }
        return booking.status == .reserved ? settings.accent : settings.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                IconBadge(symbol: booking.item.symbol, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.item.name).kFont(20, .semibold)
                    Text("\(booking.residentFirstName) · Apt \(booking.unit) · #\(booking.code)")
                        .kFont(15)
                        .foregroundStyle(settings.secondary)
                    Text(booking.status == .reserved
                         ? "Pickup \(booking.pickupStart.formatted(.dateTime.weekday(.abbreviated).hour().minute())) – \(booking.pickupEnd.formatted(date: .omitted, time: .shortened))"
                         : "Due \(booking.returnDue.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .kFont(15, .medium)
                        .foregroundStyle(booking.isOverdue ? settings.danger : settings.ink)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    StatusPill(text: statusText, color: statusColor)
                    if let onOpenLocker {
                        Button(action: onOpenLocker) {
                            Text("Locker \(booking.lockerLabel)")
                                .kFont(15, .bold)
                                .foregroundStyle(settings.accent)
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                }
            }

            HStack(spacing: 12) {
                if booking.status == .reserved {
                    Button("Cancel booking") {
                        var b = booking; b.status = .cancelled
                        Task { await store.update(b, message: "Booking #\(booking.code) cancelled") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("+1 day") {
                        var b = booking
                        b.returnDue = Calendar.current.date(byAdding: .day, value: 1, to: max(booking.returnDue, .now))!
                        Task { await store.update(b, message: "Extended to \(b.returnDue.formatted(.dateTime.weekday(.wide).hour().minute()))") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Mark returned") { Task { await store.adminMarkReturned(booking) } }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .card(padding: 20)
    }
}
