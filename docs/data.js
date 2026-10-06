// Nook kiosk test data, matching the iPad app's mock backend.
// Times are relative to when the page loads, so the demo works any time.

const ITEM_CATEGORIES = ["Tools", "Kitchen", "Outdoors", "Home", "Leisure"];

function makeData(now = new Date()) {
  const at = (minutes) => new Date(now.getTime() + minutes * 60000);
  const dayAt = (days, hour) => {
    const d = new Date(now);
    d.setDate(d.getDate() + days);
    d.setHours(hour, 0, 0, 0);
    return d;
  };
  const todayAt = (hour) => {
    const d = dayAt(0, hour);
    return d > now ? d : at(90);
  };

  const items = {
    drill: { id: "drill", name: "Cordless Drill Kit", category: "Tools", icon: "drill", blurb: "18V drill with two batteries, charger and a 40-piece bit set.", days: 3 },
    ladder: { id: "ladder", name: "Step Ladder", category: "Tools", icon: "move-vertical", blurb: "Folding 5-step aluminium ladder, 150 kg rated.", days: 2 },
    games: { id: "games", name: "Board Game Bundle", category: "Leisure", icon: "dice-5", blurb: "Catan, Codenames and Ticket to Ride.", days: 7 },
    mixer: { id: "mixer", name: "Stand Mixer", category: "Kitchen", icon: "cake-slice", blurb: "4.8 L stand mixer with whisk, paddle and dough hook.", days: 3 },
    projector: { id: "projector", name: "Mini Projector", category: "Leisure", icon: "projector", blurb: "1080p projector with HDMI and a pull-down screen.", days: 2 },
    cleaner: { id: "cleaner", name: "Carpet Cleaner", category: "Home", icon: "sparkles", blurb: "Upright deep cleaner with upholstery tool.", days: 2 },
    tent: { id: "tent", name: "4-Person Tent", category: "Outdoors", icon: "tent", blurb: "Pop-up tent with footprint, pegs and carry bag.", days: 5 },
    washer: { id: "washer", name: "Pressure Washer", category: "Tools", icon: "spray-can", blurb: "Electric pressure washer for balconies and bikes.", days: 2 },
    picnic: { id: "picnic", name: "Picnic Set", category: "Outdoors", icon: "sandwich", blurb: "Insulated basket, rug and cutlery for four.", days: 3 },
    sewing: { id: "sewing", name: "Sewing Machine", category: "Home", icon: "scissors", blurb: "Beginner-friendly machine with thread kit.", days: 7 },
    mattress: { id: "mattress", name: "Air Mattress", category: "Home", icon: "bed-double", blurb: "Queen air bed with electric pump.", days: 5 },
    speaker: { id: "speaker", name: "Party Speaker", category: "Leisure", icon: "speaker", blurb: "Bluetooth speaker with 12-hour battery.", days: 2 },
  };

  const L = (number, size, item, status) => ({ number, size, item: item ? { ...item } : null, status, unlocked: false });
  const lockers = [
    L(1, "M", items.ladder, "available"),
    L(2, "S", items.games, "available"),
    L(3, "M", items.drill, "reserved"),
    L(4, "S", items.speaker, "available"),
    L(5, "M", items.mixer, "reserved"),
    L(6, "S", items.projector, "available"),
    L(7, "L", items.cleaner, "maintenance"),
    L(8, "L", items.tent, "onLoan"),
    L(9, "L", items.washer, "onLoan"),
    L(10, "M", items.picnic, "available"),
    L(11, "M", items.sewing, "available"),
    L(12, "L", items.mattress, "available"),
  ];

  const R = (unit, firstName, isAdmin = false) => ({ unit, firstName, isAdmin });
  const alex = R("1204", "Alex"), priya = R("803", "Priya"), sam = R("502", "Sam"),
    jordan = R("1510", "Jordan"), mei = R("307", "Mei"), chris = R("911", "Chris");
  const residents = {
    "0000": { pin: "2468", resident: R("0000", "Admin", true) },
    "1204": { pin: "1234", resident: alex },
    "803": { pin: "2580", resident: priya },
    "502": { pin: "1111", resident: sam },
    "1510": { pin: "0000", resident: jordan },
    "307": { pin: "4321", resident: mei },
    "911": { pin: "9999", resident: chris },
  };

  const B = (code, who, item, locker, pickupStart, pickupEnd, returnDue, status) =>
    ({ code, firstName: who.firstName, unit: who.unit, item: { ...item }, locker, pickupStart, pickupEnd, returnDue, status });
  const bookings = [
    B("482193", alex, items.drill, 3, at(-10), at(50), dayAt(1, 18), "reserved"),
    B("715024", priya, items.tent, 8, at(-3 * 1440), at(-3 * 1440 + 60), at(180), "onLoan"),
    B("306611", sam, items.mixer, 5, at(180), at(240), dayAt(1, 20), "reserved"),
    B("920457", jordan, items.washer, 9, at(-2 * 1440), at(-2 * 1440 + 60), at(-20 * 60), "onLoan"),
    B("118830", mei, items.projector, 6, at(300), at(360), dayAt(1, 12), "reserved"),
    B("640072", chris, items.picnic, 10, dayAt(1, 9), dayAt(1, 10), dayAt(1, 19), "reserved"),
  ];

  let rid = 0;
  const Q = (title, details, icon, by, reward, posted, neededBy, helper = null) =>
    ({ id: "r" + rid++, title, details, icon, by, reward, postedAt: at(-posted), neededBy, helper });
  const requests = [
    Q("Water my plants", "Away for the weekend. Six pots on the balcony, key is with concierge.", "leaf", priya, { kind: "coffee" }, 40, dayAt(1, 9)),
    Q("Help carry a couch upstairs", "Two-seater from the loading dock to level 5. Takes 10 minutes.", "sofa", sam, { kind: "cash", amount: 20 }, 15, todayAt(18)),
    Q("Collect a parcel for me", "Arriving at the mailroom around 2pm. Just hold onto it till I'm home.", "package", mei, { kind: "treat" }, 120, todayAt(17)),
    Q("Walk Biscuit", "Friendly cavoodle, 20 minute walk around the block.", "paw-print", chris, { kind: "cash", amount: 10 }, 8, todayAt(19)),
    Q("Borrow a phone charger", "USB-C, just for an hour. Will bring it back to your door.", "cable", jordan, { kind: "thanks" }, 3, at(60)),
    Q("Hang a picture frame", "Need a second pair of hands and a level.", "image", alex, { kind: "coffee" }, 200, dayAt(1, 12), priya),
    Q("Feed the cat Saturday", "Dry food twice a day, bowls are in the laundry.", "cat", sam, { kind: "cash", amount: 15 }, 600, dayAt(1, 8), mei),
  ];

  let tid = 0;
  const T = (locker, title, details, reportedBy, created, updated, status) =>
    ({ id: "t" + tid++, locker, title, details, reportedBy, createdAt: at(-created), updatedAt: at(-updated), status });
  const tickets = [
    T(7, "Brush roll jammed", "Carpet cleaner brush won't spin. Replacement part ordered.", "Priya · Apt 803", 26 * 60, 3 * 60, "inProgress"),
    T(11, "Door won't close", "Door sticks and needs a firm push to latch.", "Kiosk", 95, 95, "open"),
    T(3, "Battery or charger issue", "Second drill battery wasn't holding charge. Swapped for a new one.", "Building staff", 3 * 1440, 2 * 1440, "resolved"),
  ];

  return { lockers, residents, bookings, requests, tickets, hours: { open: 6, close: 23, window: 60 } };
}

const ADMIN_ICONS = [
  "drill", "hammer", "wrench", "move-vertical", "spray-can", "cake-slice", "chef-hat", "cooking-pot",
  "coffee", "tent", "sandwich", "bike", "mountain", "dice-5", "gamepad-2", "projector",
  "speaker", "bed-double", "scissors", "sparkles", "package", "umbrella", "camera", "music",
];

const REPAIR_REASONS = ["Door won't open", "Door won't close", "Item damaged", "Item missing parts", "Needs cleaning", "Battery or charger issue"];

const HELP_ISSUES = [
  ["A locker won't open", "lock-keyhole"],
  ["A door won't close", "door-open"],
  ["The item is damaged or missing", "package-x"],
  ["My QR code won't scan", "qr-code"],
  ["Something else", "message-circle-more"],
];

const REQUEST_IDEAS = ["Water my plants", "Collect a parcel", "Walk my dog", "Help moving furniture", "Borrow a charger"];

const REWARDS = [
  { kind: "thanks" }, { kind: "coffee" }, { kind: "treat" },
  { kind: "cash", amount: 5 }, { kind: "cash", amount: 10 }, { kind: "cash", amount: 20 },
];
