//
//  KioskStore.swift
//  Nook
//

import Foundation
import Observation

/// Screens the kiosk can show. The kiosk has no navigation stack: every
/// session starts at `.home` and flows forward, then resets.
enum KioskScreen: Equatable {
    case home
    case scan(KioskMode)
    case confirm(Booking, KioskMode)
    case locker(Booking, KioskMode, ReturnCondition?)
    case done(Booking, KioskMode)
    case available
    case schedule
    case help
    case requests
    case newRequest
    case admin
}

/// Asks the resident to sign in before doing something tied to their profile.
struct LoginPrompt: Identifiable {
    let id = UUID()
    let reason: String
    let onSuccess: (Resident) -> Void
}

@Observable
final class KioskStore {
    var screen: KioskScreen = .home
    private(set) var lockers: [Locker] = []
    private(set) var bookings: [Booking] = []
    private(set) var requests: [CommunityRequest] = []
    /// Requests the current person passed on. Cleared when they leave.
    private(set) var declinedRequests: Set<UUID> = []
    private(set) var profile: Resident?
    private(set) var tickets: [ServiceTicket] = []
    private(set) var hubHours = HubHours()
    var loginPrompt: LoginPrompt?
    var toast: String?
    let buildingName = "The Arden"

    private let backend: KioskBackend

    init(backend: KioskBackend = MockKioskBackend()) {
        self.backend = backend
    }

    var availableCount: Int { lockers.filter { $0.status == .available && $0.item != nil }.count }
    var openRequests: [CommunityRequest] {
        requests.filter { $0.isOpen && !declinedRequests.contains($0.id) }
    }

    func refresh() async {
        lockers = (try? await backend.fetchLockers()) ?? lockers
        bookings = (try? await backend.fetchBookings()) ?? bookings
        requests = (try? await backend.fetchRequests()) ?? requests
        tickets = (try? await backend.fetchTickets()) ?? tickets
        hubHours = (try? await backend.fetchHubHours()) ?? hubHours
    }

    var isAdmin: Bool { profile?.isAdmin == true }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3.5))
            if toast == message { toast = nil }
        }
    }

    // MARK: - Sign in

    /// Runs `action` with the signed-in resident, asking them to sign in first if needed.
    func requireLogin(_ reason: String, then action: @escaping (Resident) -> Void) {
        if let profile {
            action(profile)
        } else {
            loginPrompt = LoginPrompt(reason: reason, onSuccess: action)
        }
    }

    func signIn(unit: String, pin: String) async throws -> Resident {
        let resident = try await backend.signIn(unit: unit, pin: pin)
        profile = resident
        return resident
    }

    /// Forgets everything about the current person so the next one starts fresh.
    func endSession() {
        profile = nil
        loginPrompt = nil
        declinedRequests = []
    }

    // MARK: - Requests

    func accept(_ request: CommunityRequest, by resident: Resident) async throws {
        try await backend.accept(requestID: request.id, by: resident)
        await refresh()
    }

    func decline(_ request: CommunityRequest) {
        declinedRequests.insert(request.id)
    }

    func post(title: String, details: String, reward: RequestReward, neededBy: Date, by resident: Resident) async throws {
        let request = CommunityRequest(id: UUID(), title: title, details: details, symbol: "hand.raised.fill",
                                       requester: resident, reward: reward, postedAt: .now, neededBy: neededBy, status: .open)
        try await backend.post(request)
        await refresh()
    }

    // MARK: - Admin

    func activeBooking(for locker: Locker) -> Booking? {
        bookings.first { $0.lockerNumber == locker.number && ($0.status == .reserved || $0.status == .onLoan) }
    }

    func openTickets(for locker: Locker) -> [ServiceTicket] {
        tickets.filter { $0.lockerNumber == locker.number && $0.status != .resolved }
    }

    func setDoor(_ locker: Locker, unlocked: Bool) async {
        do {
            try await backend.setDoor(locker: locker.number, unlocked: unlocked)
            showToast("Locker \(locker.label) \(unlocked ? "unlocked" : "locked")")
        } catch {
            showToast("Couldn't reach locker \(locker.label)")
        }
        await refresh()
    }

    func lockAllDoors() async {
        for locker in lockers where locker.isUnlocked {
            try? await backend.setDoor(locker: locker.number, unlocked: false)
        }
        showToast("All doors locked")
        await refresh()
    }

    func save(_ locker: Locker, message: String) async {
        try? await backend.updateLocker(locker)
        showToast(message)
        await refresh()
    }

    func update(_ booking: Booking, message: String) async {
        try? await backend.updateBooking(booking)
        showToast(message)
        await refresh()
    }

    func adminMarkReturned(_ booking: Booking) async {
        try? await backend.markReturned(code: booking.code, condition: .good)
        showToast("\(booking.item.name) marked as returned")
        await refresh()
    }

    func logRepair(_ title: String, details: String = "", locker: Locker?, takeOutOfService: Bool) async {
        let ticket = ServiceTicket(id: UUID(), lockerNumber: locker?.number, title: title,
                                   details: details.isEmpty ? "Logged by building staff." : details,
                                   reportedBy: "Building staff", createdAt: .now, updatedAt: .now, status: .open)
        try? await backend.saveTicket(ticket)
        if takeOutOfService, var locker, locker.status == .available {
            locker.status = .maintenance
            try? await backend.updateLocker(locker)
        }
        showToast("Repair logged\(locker.map { " for locker \($0.label)" } ?? "")")
        await refresh()
    }

    func setStatus(_ status: TicketStatus, for ticket: ServiceTicket) async {
        var ticket = ticket
        ticket.status = status
        ticket.updatedAt = .now
        try? await backend.saveTicket(ticket)

        // Resolving the last open job puts the locker back in service.
        if status == .resolved, let number = ticket.lockerNumber,
           var locker = lockers.first(where: { $0.number == number }), locker.status == .maintenance,
           !tickets.contains(where: { $0.id != ticket.id && $0.lockerNumber == number && $0.status != .resolved }) {
            locker.status = .available
            try? await backend.updateLocker(locker)
            showToast("Resolved. Locker \(locker.label) is back in service")
        } else {
            showToast(status == .resolved ? "Ticket resolved" : "Ticket marked \(status.rawValue.lowercased())")
        }
        await refresh()
    }

    func setHubHours(_ hours: HubHours) async {
        try? await backend.updateHubHours(hours)
        await refresh()
    }

    func bookNow(_ locker: Locker, for resident: Resident) async throws -> Booking {
        let booking = try await backend.bookNow(locker: locker.number, for: resident)
        await refresh()
        return booking
    }

    func go(_ screen: KioskScreen) {
        self.screen = screen
    }

    func goHome() {
        screen = .home
        Task { await refresh() }
    }

    // MARK: - Booking flow

    /// Looks up a scanned or typed booking and checks it can be used for `mode`.
    func validate(code: String, for mode: KioskMode, now: Date = .now) async throws -> Booking {
        let booking = try await backend.booking(code: code)
        switch (mode, booking.status) {
        case (_, .cancelled):
            throw BookingProblem.cancelled
        case (_, .returned):
            throw BookingProblem.alreadyReturned
        case (.borrow, .onLoan):
            throw BookingProblem.alreadyCollected
        case (.return, .reserved):
            throw BookingProblem.notCollectedYet
        case (.borrow, .reserved):
            // Let people collect a few minutes before their window opens.
            if now < booking.pickupStart.addingTimeInterval(-15 * 60) {
                throw BookingProblem.tooEarly(opensAt: booking.pickupStart)
            }
            if now > booking.pickupEnd { throw BookingProblem.expired }
            return booking
        case (.return, .onLoan):
            return booking
        }
    }

    func unlock(_ booking: Booking) async throws {
        try await backend.unlock(locker: booking.lockerNumber)
    }

    func complete(_ booking: Booking, mode: KioskMode, condition: ReturnCondition?) async {
        switch mode {
        case .borrow:
            try? await backend.markCollected(code: booking.code)
        case .return:
            try? await backend.markReturned(code: booking.code, condition: condition ?? .good)
        }
        await refresh()
    }

    func reportIssue(_ issue: String, locker: Int? = nil) async {
        try? await backend.reportIssue(issue, locker: locker)
    }
}

enum BookingCodeParser {
    /// Pulls the six-digit booking number out of whatever the QR code holds,
    /// e.g. `482193`, `nook://booking/482193` or `{"booking":"482193"}`.
    static func code(from payload: String) -> String? {
        payload
            .split(whereSeparator: { !$0.isASCII || !$0.isNumber })
            .first(where: { $0.count == 6 })
            .map(String.init)
    }
}
