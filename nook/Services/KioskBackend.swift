//
//  KioskBackend.swift
//  Nook
//

import Foundation

/// Everything the kiosk needs from the outside world: the booking server the
/// resident app talks to, and the locker controller hardware.
///
/// `MockKioskBackend` stands in for both so the kiosk runs on its own. To go
/// live, write a type that conforms to this protocol and pass it to `KioskStore`.
protocol KioskBackend {
    func fetchLockers() async throws -> [Locker]
    func fetchBookings() async throws -> [Booking]
    func booking(code: String) async throws -> Booking
    /// Sends the unlock signal to the locker controller.
    func unlock(locker: Int) async throws
    func markCollected(code: String) async throws
    func markReturned(code: String, condition: ReturnCondition) async throws
    func reportIssue(_ issue: String, locker: Int?) async throws

    // Residents
    func signIn(unit: String, pin: String) async throws -> Resident
    /// Books an available item for immediate pickup by a signed-in resident.
    func bookNow(locker: Int, for resident: Resident) async throws -> Booking

    // Community requests
    func fetchRequests() async throws -> [CommunityRequest]
    func accept(requestID: UUID, by resident: Resident) async throws
    func post(_ request: CommunityRequest) async throws

    // Building admin
    /// Staff override: unlocks or locks a door regardless of bookings or faults.
    func setDoor(locker: Int, unlocked: Bool) async throws
    /// Saves a locker's contents and service status.
    func updateLocker(_ locker: Locker) async throws
    func updateBooking(_ booking: Booking) async throws
    func fetchTickets() async throws -> [ServiceTicket]
    func saveTicket(_ ticket: ServiceTicket) async throws
    func fetchHubHours() async throws -> HubHours
    func updateHubHours(_ hours: HubHours) async throws
}

final class MockKioskBackend: KioskBackend {
    private var lockers: [Locker]
    private var bookings: [Booking]
    private var requests: [CommunityRequest]
    private var tickets: [ServiceTicket]
    private var hubHours = HubHours()
    private let residents: [String: (pin: String, resident: Resident)]

    init(now: Date = .now) {
        let cal = Calendar.current
        func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }
        func tomorrow(hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: 1, to: now)!
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        }

        let drill = Item(id: "drill", name: "Cordless Drill Kit", category: .tools, symbol: "wrench.and.screwdriver.fill",
                         blurb: "18V drill with two batteries, charger and a 40-piece bit set.", maxLoanDays: 3)
        let ladder = Item(id: "ladder", name: "Step Ladder", category: .tools, symbol: "stairs",
                          blurb: "Folding 5-step aluminium ladder, 150 kg rated.", maxLoanDays: 2)
        let games = Item(id: "games", name: "Board Game Bundle", category: .leisure, symbol: "dice.fill",
                         blurb: "Catan, Codenames and Ticket to Ride.", maxLoanDays: 7)
        let mixer = Item(id: "mixer", name: "Stand Mixer", category: .kitchen, symbol: "birthday.cake.fill",
                         blurb: "4.8 L stand mixer with whisk, paddle and dough hook.", maxLoanDays: 3)
        let projector = Item(id: "projector", name: "Mini Projector", category: .leisure, symbol: "videoprojector.fill",
                             blurb: "1080p projector with HDMI and a pull-down screen.", maxLoanDays: 2)
        let cleaner = Item(id: "cleaner", name: "Carpet Cleaner", category: .home, symbol: "bubbles.and.sparkles.fill",
                           blurb: "Upright deep cleaner with upholstery tool.", maxLoanDays: 2)
        let tent = Item(id: "tent", name: "4-Person Tent", category: .outdoors, symbol: "tent.fill",
                        blurb: "Pop-up tent with footprint, pegs and carry bag.", maxLoanDays: 5)
        let washer = Item(id: "washer", name: "Pressure Washer", category: .tools, symbol: "shower.handheld.fill",
                          blurb: "Electric pressure washer for balconies and bikes.", maxLoanDays: 2)
        let picnic = Item(id: "picnic", name: "Picnic Set", category: .outdoors, symbol: "basket.fill",
                          blurb: "Insulated basket, rug and cutlery for four.", maxLoanDays: 3)
        let sewing = Item(id: "sewing", name: "Sewing Machine", category: .home, symbol: "scissors",
                          blurb: "Beginner-friendly machine with thread kit.", maxLoanDays: 7)
        let mattress = Item(id: "mattress", name: "Air Mattress", category: .home, symbol: "bed.double.fill",
                            blurb: "Queen air bed with electric pump.", maxLoanDays: 5)
        let speaker = Item(id: "speaker", name: "Party Speaker", category: .leisure, symbol: "hifispeaker.fill",
                           blurb: "Bluetooth speaker with 12-hour battery.", maxLoanDays: 2)

        lockers = [
            Locker(number: 1, size: .medium, item: ladder, status: .available),
            Locker(number: 2, size: .small, item: games, status: .available),
            Locker(number: 3, size: .medium, item: drill, status: .reserved),
            Locker(number: 4, size: .small, item: speaker, status: .available),
            Locker(number: 5, size: .medium, item: mixer, status: .reserved),
            Locker(number: 6, size: .small, item: projector, status: .available),
            Locker(number: 7, size: .large, item: cleaner, status: .maintenance),
            Locker(number: 8, size: .large, item: tent, status: .onLoan),
            Locker(number: 9, size: .large, item: washer, status: .onLoan),
            Locker(number: 10, size: .medium, item: picnic, status: .available),
            Locker(number: 11, size: .medium, item: sewing, status: .available),
            Locker(number: 12, size: .large, item: mattress, status: .available),
        ]

        let alex = Resident(unit: "1204", firstName: "Alex")
        let priya = Resident(unit: "803", firstName: "Priya")
        let sam = Resident(unit: "502", firstName: "Sam")
        let jordan = Resident(unit: "1510", firstName: "Jordan")
        let mei = Resident(unit: "307", firstName: "Mei")
        let chris = Resident(unit: "911", firstName: "Chris")
        residents = [
            "0000": ("2468", Resident(unit: "0000", firstName: "Admin", isAdmin: true)),
            "1204": ("1234", alex), "803": ("2580", priya), "502": ("1111", sam),
            "1510": ("0000", jordan), "307": ("4321", mei), "911": ("9999", chris),
        ]

        func today(hour: Int) -> Date {
            let date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
            return date > now ? date : at(90)
        }
        func request(_ title: String, _ details: String, _ symbol: String, by: Resident, reward: RequestReward,
                     posted: Int, needed: Date, status: RequestStatus = .open) -> CommunityRequest {
            CommunityRequest(id: UUID(), title: title, details: details, symbol: symbol, requester: by, reward: reward,
                             postedAt: at(-posted), neededBy: needed, status: status)
        }
        requests = [
            request("Water my plants", "Away for the weekend. Six pots on the balcony, key is with concierge.",
                    "leaf.fill", by: priya, reward: .coffee, posted: 40, needed: tomorrow(hour: 9)),
            request("Help carry a couch upstairs", "Two-seater from the loading dock to level 5. Takes 10 minutes.",
                    "sofa.fill", by: sam, reward: .cash(20), posted: 15, needed: today(hour: 18)),
            request("Collect a parcel for me", "Arriving at the mailroom around 2pm. Just hold onto it till I'm home.",
                    "shippingbox.fill", by: mei, reward: .treat, posted: 120, needed: today(hour: 17)),
            request("Walk Biscuit", "Friendly cavoodle, 20 minute walk around the block.",
                    "pawprint.fill", by: chris, reward: .cash(10), posted: 8, needed: today(hour: 19)),
            request("Borrow a phone charger", "USB-C, just for an hour. Will bring it back to your door.",
                    "cable.connector", by: jordan, reward: .thanks, posted: 3, needed: at(60)),
            request("Hang a picture frame", "Need a second pair of hands and a level.",
                    "photo.artframe", by: alex, reward: .coffee, posted: 200, needed: tomorrow(hour: 12),
                    status: .accepted(by: priya)),
            request("Feed the cat Saturday", "Dry food twice a day, bowls are in the laundry.",
                    "cat.fill", by: sam, reward: .cash(15), posted: 600, needed: tomorrow(hour: 8),
                    status: .accepted(by: mei)),
        ]

        tickets = [
            ServiceTicket(id: UUID(), lockerNumber: 7, title: "Brush roll jammed",
                          details: "Carpet cleaner brush won't spin. Replacement part ordered.",
                          reportedBy: "Priya · Apt 803", createdAt: at(-26 * 60), updatedAt: at(-3 * 60), status: .inProgress),
            ServiceTicket(id: UUID(), lockerNumber: 11, title: "Door won't close",
                          details: "Door sticks and needs a firm push to latch.",
                          reportedBy: "Kiosk", createdAt: at(-95), updatedAt: at(-95), status: .open),
            ServiceTicket(id: UUID(), lockerNumber: 3, title: "Battery or charger issue",
                          details: "Second drill battery wasn't holding charge. Swapped for a new one.",
                          reportedBy: "Building staff", createdAt: at(-3 * 24 * 60), updatedAt: at(-2 * 24 * 60), status: .resolved),
        ]

        bookings = [
            // Ready to collect right now.
            Booking(code: "482193", residentFirstName: "Alex", unit: "1204", item: drill, lockerNumber: 3,
                    pickupStart: at(-10), pickupEnd: at(50), returnDue: tomorrow(hour: 18), status: .reserved),
            // On loan, due back later today.
            Booking(code: "715024", residentFirstName: "Priya", unit: "803", item: tent, lockerNumber: 8,
                    pickupStart: at(-3 * 24 * 60), pickupEnd: at(-3 * 24 * 60 + 60), returnDue: at(180), status: .onLoan),
            // Pickup window hasn't opened yet.
            Booking(code: "306611", residentFirstName: "Sam", unit: "502", item: mixer, lockerNumber: 5,
                    pickupStart: at(180), pickupEnd: at(240), returnDue: tomorrow(hour: 20), status: .reserved),
            // Overdue return.
            Booking(code: "920457", residentFirstName: "Jordan", unit: "1510", item: washer, lockerNumber: 9,
                    pickupStart: at(-2 * 24 * 60), pickupEnd: at(-2 * 24 * 60 + 60), returnDue: at(-20 * 60), status: .onLoan),
            // Later today.
            Booking(code: "118830", residentFirstName: "Mei", unit: "307", item: projector, lockerNumber: 6,
                    pickupStart: at(300), pickupEnd: at(360), returnDue: tomorrow(hour: 12), status: .reserved),
            Booking(code: "640072", residentFirstName: "Chris", unit: "911", item: picnic, lockerNumber: 10,
                    pickupStart: tomorrow(hour: 9), pickupEnd: tomorrow(hour: 10), returnDue: tomorrow(hour: 19), status: .reserved),
        ]
    }

    // MARK: - Residents

    func signIn(unit: String, pin: String) async throws -> Resident {
        await simulateLatency()
        guard let match = residents[unit], match.pin == pin else { throw SignInProblem.wrongDetails }
        return match.resident
    }

    func bookNow(locker number: Int, for resident: Resident) async throws -> Booking {
        await simulateLatency()
        guard let i = lockers.firstIndex(where: { $0.number == number }),
              lockers[i].status == .available, let item = lockers[i].item else { throw BookingProblem.lockerFault }
        let cal = Calendar.current
        let dueDay = cal.date(byAdding: .day, value: item.maxLoanDays, to: .now)!
        let booking = Booking(code: String(Int.random(in: 100_000...999_999)), residentFirstName: resident.firstName,
                              unit: resident.unit, item: item, lockerNumber: number,
                              pickupStart: .now, pickupEnd: .now.addingTimeInterval(3600),
                              returnDue: cal.date(bySettingHour: 18, minute: 0, second: 0, of: dueDay)!, status: .reserved)
        bookings.append(booking)
        lockers[i].status = .reserved
        return booking
    }

    // MARK: - Requests

    func fetchRequests() async throws -> [CommunityRequest] { requests }

    func accept(requestID: UUID, by resident: Resident) async throws {
        await simulateLatency()
        guard let i = requests.firstIndex(where: { $0.id == requestID }), requests[i].isOpen else {
            throw BookingProblem.notFound
        }
        requests[i].status = .accepted(by: resident)
    }

    func post(_ request: CommunityRequest) async throws {
        await simulateLatency()
        requests.insert(request, at: 0)
    }

    private func simulateLatency() async {
        try? await Task.sleep(for: .milliseconds(450))
    }

    func fetchLockers() async throws -> [Locker] { lockers }

    func fetchBookings() async throws -> [Booking] { bookings }

    func booking(code: String) async throws -> Booking {
        await simulateLatency()
        guard let booking = bookings.first(where: { $0.code == code }) else { throw BookingProblem.notFound }
        return booking
    }

    func unlock(locker: Int) async throws {
        try? await Task.sleep(for: .milliseconds(1200))
        guard let i = lockers.firstIndex(where: { $0.number == locker }), lockers[i].status != .maintenance else {
            throw BookingProblem.lockerFault
        }
        lockers[i].isUnlocked = true
    }

    func markCollected(code: String) async throws {
        guard let i = bookings.firstIndex(where: { $0.code == code }) else { throw BookingProblem.notFound }
        bookings[i].status = .onLoan
        setLocker(bookings[i].lockerNumber, to: .onLoan)
    }

    func markReturned(code: String, condition: ReturnCondition) async throws {
        guard let i = bookings.firstIndex(where: { $0.code == code }) else { throw BookingProblem.notFound }
        bookings[i].status = .returned
        setLocker(bookings[i].lockerNumber, to: condition == .good ? .available : .maintenance)
        if condition != .good {
            let b = bookings[i]
            tickets.insert(ServiceTicket(id: UUID(), lockerNumber: b.lockerNumber, title: "Returned: \(condition.rawValue.lowercased())",
                                         details: "\(b.item.name) came back flagged by the resident.",
                                         reportedBy: "\(b.residentFirstName) · Apt \(b.unit)", createdAt: .now, updatedAt: .now,
                                         status: .open), at: 0)
        }
    }

    func reportIssue(_ issue: String, locker: Int?) async throws {
        await simulateLatency()
        tickets.insert(ServiceTicket(id: UUID(), lockerNumber: locker, title: issue, details: "Reported at the kiosk.",
                                     reportedBy: "Kiosk", createdAt: .now, updatedAt: .now, status: .open), at: 0)
    }

    // MARK: - Admin

    func setDoor(locker: Int, unlocked: Bool) async throws {
        try? await Task.sleep(for: .milliseconds(600))
        guard let i = lockers.firstIndex(where: { $0.number == locker }) else { throw BookingProblem.lockerFault }
        lockers[i].isUnlocked = unlocked
    }

    func updateLocker(_ locker: Locker) async throws {
        await simulateLatency()
        guard let i = lockers.firstIndex(where: { $0.number == locker.number }) else { throw BookingProblem.lockerFault }
        lockers[i] = locker
    }

    func updateBooking(_ booking: Booking) async throws {
        await simulateLatency()
        guard let i = bookings.firstIndex(where: { $0.code == booking.code }) else { throw BookingProblem.notFound }
        bookings[i] = booking
        // A cancelled booking frees its locker.
        if booking.status == .cancelled, let l = lockers.firstIndex(where: { $0.number == booking.lockerNumber }),
           lockers[l].status == .reserved {
            lockers[l].status = .available
        }
    }

    func fetchTickets() async throws -> [ServiceTicket] { tickets }

    func saveTicket(_ ticket: ServiceTicket) async throws {
        if let i = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[i] = ticket
        } else {
            tickets.insert(ticket, at: 0)
        }
    }

    func fetchHubHours() async throws -> HubHours { hubHours }

    func updateHubHours(_ hours: HubHours) async throws { hubHours = hours }

    private func setLocker(_ number: Int, to status: LockerStatus) {
        if let i = lockers.firstIndex(where: { $0.number == number }) {
            lockers[i].status = status
            lockers[i].isUnlocked = false // The resident has closed the door.
        }
    }
}
