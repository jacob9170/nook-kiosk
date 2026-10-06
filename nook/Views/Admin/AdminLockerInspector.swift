//
//  AdminLockerInspector.swift
//  Nook
//

import SwiftUI

/// One locker, zoomed in from the wall with its door swung open.
struct AdminLockerInspector: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let locker: Locker
    let namespace: Namespace.ID
    let wide: Bool
    let size: CGSize
    let onClose: () -> Void

    @State private var doorOpen = false
    @State private var editing = false
    @State private var loggingRepair = false
    @State private var doorBusy = false

    var body: some View {
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 40)) : AnyLayout(VStackLayout(spacing: 24))
        layout {
            VStack(spacing: 16) {
                AdminCabinet(locker: locker, doorOpen: doorOpen)
                    .matchedLocker(locker.number, in: namespace)
                    .frame(maxWidth: wide ? size.width * 0.4 : size.width * 0.5,
                           maxHeight: wide ? size.height * 0.8 : size.height * 0.36)
                Text(doorOpen ? "Showing what's inside" : " ")
                    .kFont(15, .medium)
                    .foregroundStyle(settings.secondary)
            }
            .frame(maxWidth: wide ? size.width * 0.42 : .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    doorCard
                    if editing {
                        ItemEditor(locker: locker) { editing = false }
                    } else {
                        contentsCard
                    }
                    serviceStatusCard
                    if let booking = store.activeBooking(for: locker) {
                        Text("Booking").kFont(20, .bold).padding(.top, 4)
                        AdminBookingCard(booking: booking)
                    }
                    repairsSection
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if settings.reduceMotion {
                doorOpen = true
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.4)) { doorOpen = true }
            }
            settings.speak("Locker \(locker.number). \(locker.item?.name ?? "Empty").")
        }
    }

    private func close() {
        if settings.reduceMotion {
            onClose()
            return
        }
        withAnimation(.easeIn(duration: 0.25)) { doorOpen = false }
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            onClose()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Locker \(locker.label)")
                    .kFont(40, .bold)
                    .tracking(-1)
                HStack(spacing: 8) {
                    StatusPill(text: locker.status.rawValue, color: settings.color(for: locker.status))
                    StatusPill(text: sizeName, color: settings.secondary)
                }
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(settings.ink)
                    .frame(width: 64, height: 64)
                    .background(settings.surface, in: .circle)
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityLabel("Back to locker wall")
        }
    }

    private var sizeName: String {
        switch locker.size {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    private var doorCard: some View {
        HStack(spacing: 16) {
            IconBadge(symbol: locker.isUnlocked ? "lock.open.fill" : "lock.fill",
                      tint: locker.isUnlocked ? settings.warning : settings.success, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(locker.isUnlocked ? "Door unlocked" : "Door locked").kFont(20, .semibold)
                Text(locker.isUnlocked ? "Anyone can open it. Lock it when you're done." : "Unlock to restock or check the item.")
                    .kFont(15)
                    .foregroundStyle(settings.secondary)
            }
            Spacer(minLength: 8)
            Button {
                doorBusy = true
                Task {
                    await store.setDoor(locker, unlocked: !locker.isUnlocked)
                    doorBusy = false
                }
            } label: {
                if doorBusy {
                    ProgressView().tint(.white)
                } else {
                    Label(locker.isUnlocked ? "Lock" : "Unlock", systemImage: locker.isUnlocked ? "lock.fill" : "lock.open.fill")
                }
            }
            .buttonStyle(PrimaryButtonStyle(tint: locker.isUnlocked ? settings.ink : settings.accent))
            .frame(width: 180)
            .disabled(doorBusy)
        }
        .card(padding: 20)
    }

    @ViewBuilder
    private var contentsCard: some View {
        let booked = locker.status == .reserved || locker.status == .onLoan
        VStack(alignment: .leading, spacing: 16) {
            Text("Contents").kFont(14, .bold).tracking(1).foregroundStyle(settings.secondary)
            if let item = locker.item {
                HStack(alignment: .top, spacing: 16) {
                    IconBadge(symbol: item.symbol, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).kFont(26, .bold)
                        Text("\(item.category.rawValue) · Loan up to \(item.maxLoanDays) day\(item.maxLoanDays == 1 ? "" : "s")")
                            .kFont(15, .medium)
                            .foregroundStyle(settings.secondary)
                        Text(item.blurb)
                            .kFont(17)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        withAnimation(settings.animation) { editing = true }
                    } label: {
                        Label("Edit item", systemImage: "pencil")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button {
                        var l = locker
                        l.item = nil
                        Task { await store.save(l, message: "\(item.name) removed from locker \(locker.label)") }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(booked)
                    .opacity(booked ? 0.4 : 1)
                }
                if booked {
                    Text("This item is booked, so it can't be removed until the booking ends.")
                        .kFont(14)
                        .foregroundStyle(settings.secondary)
                }
            } else {
                HStack(spacing: 16) {
                    IconBadge(symbol: "tray", tint: settings.secondary, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Empty").kFont(26, .bold)
                        Text("Add an item so residents can borrow it.")
                            .kFont(16)
                            .foregroundStyle(settings.secondary)
                    }
                }
                Button {
                    withAnimation(settings.animation) { editing = true }
                } label: {
                    Label("Add an item", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .card(padding: 22)
    }

    private var serviceStatusCard: some View {
        let booked = locker.status == .reserved || locker.status == .onLoan
        return VStack(alignment: .leading, spacing: 14) {
            Text("Service status").kFont(14, .bold).tracking(1).foregroundStyle(settings.secondary)
            if booked {
                Text("\(locker.status.rawValue). This updates automatically when the booking ends.")
                    .kFont(16)
                    .foregroundStyle(settings.secondary)
            } else {
                HStack(spacing: 10) {
                    SmallChoice(title: "In service", selected: locker.status == .available) {
                        var l = locker; l.status = .available
                        Task { await store.save(l, message: "Locker \(locker.label) is back in service") }
                    }
                    SmallChoice(title: "Out of service", selected: locker.status == .maintenance) {
                        var l = locker; l.status = .maintenance
                        Task { await store.save(l, message: "Locker \(locker.label) taken out of service") }
                    }
                }
                Text(locker.status == .maintenance ? "Residents can't book this locker right now." : "Residents can book this item.")
                    .kFont(14)
                    .foregroundStyle(settings.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 22)
    }

    @ViewBuilder
    private var repairsSection: some View {
        let tickets = store.tickets.filter { $0.lockerNumber == locker.number }
        HStack {
            Text("Repairs").kFont(20, .bold)
            Spacer()
            Button {
                withAnimation(settings.animation) { loggingRepair.toggle() }
            } label: {
                Label(loggingRepair ? "Cancel" : "Log repair", systemImage: loggingRepair ? "xmark" : "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, 4)

        if loggingRepair {
            RepairComposer(locker: locker) { loggingRepair = false }
        }
        if tickets.isEmpty && !loggingRepair {
            Text("No repairs logged for this locker.")
                .kFont(16)
                .foregroundStyle(settings.secondary)
        }
        ForEach(tickets) { ticket in
            TicketCard(ticket: ticket)
        }
    }
}

// MARK: - Cabinet

/// The big version of a locker: an interior with the item inside and a door
/// that swings open on its left hinge.
private struct AdminCabinet: View {
    @Environment(KioskSettings.self) private var settings
    let locker: Locker
    let doorOpen: Bool

    var body: some View {
        ZStack {
            // Interior
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(hex: 0xE9ECF3))
                .overlay(
                    LinearGradient(colors: [.black.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                        .clipShape(.rect(cornerRadius: 28))
                )
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color(hex: 0xD3D8E2), lineWidth: 3))

            VStack(spacing: 14) {
                if let item = locker.item {
                    Image(systemName: item.symbol)
                        .font(.system(size: 96, weight: .semibold))
                        .foregroundStyle(settings.accent)
                        .shadow(color: settings.accent.opacity(0.25), radius: 16, y: 8)
                    Text(item.name)
                        .kFont(30, .bold)
                        .multilineTextAlignment(.center)
                    Text(item.category.rawValue)
                        .kFont(18, .medium)
                        .foregroundStyle(settings.secondary)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 80, weight: .regular))
                        .foregroundStyle(settings.secondary)
                    Text("Empty").kFont(28, .bold).foregroundStyle(settings.secondary)
                }
            }
            .padding(32)
            .minimumScaleFactor(0.6)
            .opacity(doorOpen ? 1 : 0)
            .scaleEffect(doorOpen ? 1 : 0.92)

            // Door
            RoundedRectangle(cornerRadius: 28)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(settings.hairline, lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    Text(locker.label)
                        .kFont(48, .bold, design: .rounded)
                        .monospacedDigit()
                        .padding(28)
                }
                .overlay(alignment: .topTrailing) {
                    Circle().fill(settings.color(for: locker.status)).frame(width: 18, height: 18).padding(30)
                }
                .overlay(alignment: .trailing) {
                    Capsule().fill(settings.hairline).frame(width: 12, height: 80).padding(.trailing, 24)
                }
                .shadow(color: .black.opacity(doorOpen ? 0.15 : 0), radius: 20, x: -10)
                // Low perspective keeps the open door tucked against its hinge
                // instead of swinging out over the contents.
                .rotation3DEffect(.degrees(doorOpen ? -84 : 0), axis: (x: 0, y: 1, z: 0),
                                  anchor: .leading, perspective: 0.18)
        }
        .aspectRatio(0.9, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locker \(locker.number), \(locker.item?.name ?? "empty")")
    }
}

// MARK: - Item editor

private struct ItemEditor: View {
    @Environment(KioskStore.self) private var store
    @Environment(KioskSettings.self) private var settings
    let locker: Locker
    let onDone: () -> Void

    @State private var name: String
    @State private var blurb: String
    @State private var category: ItemCategory
    @State private var symbol: String
    @State private var loanDays: Int
    @State private var saving = false

    init(locker: Locker, onDone: @escaping () -> Void) {
        self.locker = locker
        self.onDone = onDone
        let item = locker.item
        _name = State(initialValue: item?.name ?? "")
        _blurb = State(initialValue: item?.blurb ?? "")
        _category = State(initialValue: item?.category ?? .tools)
        _symbol = State(initialValue: item?.symbol ?? AdminCatalog.symbols[0])
        _loanDays = State(initialValue: item?.maxLoanDays ?? 3)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !saving }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(locker.item == nil ? "Add an item" : "Edit item").kFont(24, .bold)

            field("Name") {
                TextField("e.g. Cordless Drill", text: $name)
                    .kFont(22, .semibold)
                    .padding(18)
                    .background(settings.surface, in: .rect(cornerRadius: 18))
            }

            field("Details") {
                TextField("What's included, how to use it", text: $blurb, axis: .vertical)
                    .kFont(17)
                    .lineLimit(2...4)
                    .padding(18)
                    .background(settings.surface, in: .rect(cornerRadius: 18))
            }

            field("Category") {
                FlowLayout {
                    ForEach(ItemCategory.allCases) { c in
                        SmallChoice(title: c.rawValue, selected: category == c) { category = c }
                    }
                }
            }

            field("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 10), count: 6), alignment: .leading, spacing: 10) {
                    ForEach(AdminCatalog.symbols, id: \.self) { s in
                        Button { symbol = s } label: {
                            Image(systemName: s)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(symbol == s ? .white : settings.accent)
                                .frame(width: 56, height: 56)
                                .background(symbol == s ? settings.accent : settings.accentSoft, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(TileButtonStyle())
                    }
                }
            }

            field("Loan length") {
                HStack(spacing: 14) {
                    Text("\(loanDays) day\(loanDays == 1 ? "" : "s")")
                        .kFont(22, .bold, design: .rounded)
                    Spacer()
                    stepper("minus", enabled: loanDays > 1) { loanDays -= 1 }
                    stepper("plus", enabled: loanDays < 14) { loanDays += 1 }
                }
                .padding(16)
                .background(settings.surface, in: .rect(cornerRadius: 18))
            }

            HStack(spacing: 12) {
                Button("Cancel") { withAnimation(settings.animation) { onDone() } }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    save()
                } label: {
                    if saving { ProgressView().tint(.white) } else { Label("Save", systemImage: "checkmark") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
            }
        }
        .card(padding: 22)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).kFont(15, .semibold).foregroundStyle(settings.secondary)
            content()
        }
    }

    private func stepper(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
    }

    private func save() {
        saving = true
        var l = locker
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        l.item = Item(id: locker.item?.id ?? UUID().uuidString, name: trimmed, category: category, symbol: symbol,
                      blurb: blurb.trimmingCharacters(in: .whitespaces), maxLoanDays: loanDays)
        let added = locker.item == nil
        Task {
            await store.save(l, message: added ? "\(trimmed) added to locker \(locker.label)" : "\(trimmed) updated")
            withAnimation(settings.animation) { onDone() }
        }
    }
}
