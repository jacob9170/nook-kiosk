// Nook kiosk, web version. A browser rebuild of the SwiftUI iPad app so it
// can be tried from a link. Plain JS: state -> HTML strings -> one render().
"use strict";

const D = makeData();
const S = {
  screen: { name: "home" },
  key: null,
  v: {},                 // per-screen view state, cleared on navigation
  profile: null,
  declined: new Set(),
  login: null,           // { reason, onSuccess, field, unit, pin, checking, failed }
  a11y: false,
  menu: false,
  idle: false,
  detail: null,          // locker number shown in the "What's available" detail
  set: { large: false, hc: false, rm: false, voice: false, reach: false },
};

// ---------- Helpers ----------

const $ = (sel, root = document) => root.querySelector(sel);
const h = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const icon = (name, size = 24) => `<i data-lucide="${name}" style="width:${size}px;height:${size}px"></i>`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pad2 = (n) => String(n).padStart(2, "0");
const label = (n) => pad2(n);

// Australian English, 12-hour times ("4:30 pm"), to match the iPad app.
const LOCALE = "en-AU";
const fmtTime = (d) => d.toLocaleTimeString(LOCALE, { hour: "numeric", minute: "2-digit", hour12: true }).toLowerCase();
const fmtWeekday = (d, long = false) => d.toLocaleDateString(LOCALE, { weekday: long ? "long" : "short" });
const fmtDayTime = (d, long = false) => `${fmtWeekday(d, long)} ${fmtTime(d)}`;
const sameDay = (a, b) => a.toDateString() === b.toDateString();
const isToday = (d) => sameDay(d, new Date());
const isTomorrow = (d) => { const t = new Date(); t.setDate(t.getDate() + 1); return sameDay(d, t); };
const relative = (d) => {
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs} hr${hrs === 1 ? "" : "s"} ago`;
  const days = Math.round(hrs / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
};

const STATUS = {
  available: { label: "Available", color: "var(--success)" },
  reserved: { label: "Reserved", color: "var(--accent)" },
  onLoan: { label: "On loan", color: "var(--secondary)" },
  maintenance: { label: "Maintenance", color: "var(--warning)" },
};
const pill = (text, color) => `<span class="pill" style="--c:${color}">${h(text)}</span>`;
const badge = (name, size = 64, color) => `<div class="badge" style="--s:${size}px${color ? `;--c:${color}` : ""}">${icon(name)}</div>`;

const locker = (n) => D.lockers.find((l) => l.number === n);
const availableCount = () => D.lockers.filter((l) => l.status === "available" && l.item).length;
const openRequests = () => D.requests.filter((r) => !r.helper && !r.done && !S.declined.has(r.id));
const isAdmin = () => !!S.profile?.isAdmin;
const customised = () => Object.values(S.set).some(Boolean);
const publicName = (r) => `${r.firstName} · Level ${parseInt(r.unit.slice(0, -2), 10) || 0}`;
const isOverdue = (b) => b.status === "onLoan" && new Date() > b.returnDue;
const activeBooking = (l) => D.bookings.find((b) => b.locker === l.number && (b.status === "reserved" || b.status === "onLoan"));

function speak(text) {
  if (!S.set.voice || !("speechSynthesis" in window)) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  u.rate = 0.95;
  speechSynthesis.speak(u);
}

let toastTimer;
function toast(msg) {
  const el = $("#toast");
  el.textContent = msg;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 3500);
}

// ---------- Navigation ----------

function go(name, params = {}) {
  if (S.screen.name === "scan" && name !== "scan") stopCamera();
  S.screen = { name, ...params };
  S.v = {};
  render();
}

function goHome() { go("home"); }

function endSession() {
  S.profile = null;
  S.login = null;
  S.menu = false;
  S.declined = new Set();
}

function resetSettings() {
  S.set = { large: false, hc: false, rm: false, voice: false, reach: false };
  if ("speechSynthesis" in window) speechSynthesis.cancel();
}

function requireLogin(reason, then) {
  if (S.profile) then(S.profile);
  else {
    S.login = { reason, onSuccess: then, field: "unit", unit: "", pin: "", checking: false, failed: false };
    renderOverlay(true);
    speak("Sign in with your apartment number and PIN.");
  }
}

const REQUIRES_SIGN_IN = ["schedule", "requests", "newRequest", "admin"];

// ---------- Render ----------

let afterRender = [];
const after = (fn) => afterRender.push(fn);

function screenKey() {
  const s = S.screen;
  return [s.name, s.mode, s.code].filter(Boolean).join("-");
}

function render() {
  document.documentElement.classList.toggle("large", S.set.large);
  document.body.classList.toggle("hc", S.set.hc);
  document.body.classList.toggle("rm", S.set.rm);
  document.body.classList.toggle("reach", S.set.reach);
  $("#ambient").classList.toggle("hidden", S.screen.name !== "home");

  $("#topbar").innerHTML = topbar();
  const scr = $("#screen");
  scr.innerHTML = SCREENS[S.screen.name]();
  const key = screenKey();
  scr.classList.remove("enter");
  if (key !== S.key) { void scr.offsetWidth; scr.classList.add("enter"); S.key = key; }

  renderOverlay(false);
  flush();
}

let overlayKey = null;
function renderOverlay(standalone = true) {
  const html = overlayHTML();
  const key = S.idle ? "idle" : S.login ? "login" : S.a11y ? "a11y" : S.menu ? "menu" : S.detail ? "detail" : null;
  $("#overlay").innerHTML = html;
  // Only animate a modal in when it first appears, not on every keypress.
  if (key && key === overlayKey) $("#overlay").querySelectorAll(".backdrop, .modal").forEach((el) => (el.style.animation = "none"));
  overlayKey = key;
  if (standalone) flush();
}

function flush() {
  window.lucide?.createIcons();
  const fns = afterRender;
  afterRender = [];
  fns.forEach((fn) => fn());
}

// ---------- Top bar ----------

const TITLES = {
  scan: () => (S.screen.mode === "borrow" ? "Borrow an item" : "Return an item"),
  confirm: () => (S.screen.mode === "borrow" ? "Check your booking" : "Check your return"),
  available: () => "What's in the lockers",
  schedule: () => "Locker schedule",
  help: () => "Help",
  requests: () => "Community requests",
  newRequest: () => "New request",
  admin: () => "Building admin",
};

function wordmark() {
  return `<div class="wordmark">
    <div class="logo">${icon("grid-3x3", 22)}</div>
    <div><div class="name">nook</div><div class="sub">The Arden · Community Hub</div></div>
  </div>`;
}

function clockHTML() {
  const now = new Date();
  return `<div class="clock"><div class="time">${fmtTime(now)}</div>
    <div class="date">${now.toLocaleDateString(LOCALE, { weekday: "long", day: "numeric", month: "short" })}</div></div>`;
}

function topbar() {
  const n = S.screen.name;
  let left;
  if (n === "home" || n === "locker" || n === "done") left = wordmark();
  else if (n === "admin") left = `<button class="btn-secondary" data-act="exitAdmin">${icon("log-out")} Exit admin</button>`;
  else left = `<button class="btn-secondary" data-act="home">${icon("chevron-left")} Home</button>`;

  const title = TITLES[n]?.();
  const mid = title ? `<div class="title">${h(title)}</div>` : `<div class="spacer"></div>`;
  const p = S.profile;
  const account = p
    ? `<button class="account press" data-act="menu" aria-label="Signed in as ${h(p.firstName)}. Sign out">
        <span class="initial">${h(p.firstName[0])}</span>
        <span><div class="n">${h(p.firstName)}</div><div class="u">${p.isAdmin ? "Building staff" : "Apt " + h(p.unit)}</div></span>
      </button>`
    : `<button class="btn-secondary" data-act="signIn">${icon("circle-user-round")} Sign in</button>`;
  const help = ["help", "locker", "admin"].includes(n) ? "" :
    `<button class="circle-btn" data-act="go" data-to="help" aria-label="Help"><span style="font-size:1.75rem;font-weight:800">?</span></button>`;
  const a11y = `<button class="circle-btn ${customised() ? "on" : "accent"}" data-act="a11y" aria-label="Accessibility options">${icon("accessibility", 30)}</button>`;
  return `${left}${mid}${n === "home" ? clockHTML() : ""}${account}${help}${a11y}`;
}

// ---------- Home ----------

function greeting() {
  const hr = new Date().getHours();
  return hr >= 5 && hr < 12 ? "Good morning" : hr < 17 && hr >= 12 ? "Good afternoon" : "Good evening";
}

function actionTile(mode) {
  const borrow = mode === "borrow";
  return `<button class="action-tile ${borrow ? "filled" : "outline"}" data-act="go" data-to="scan" data-mode="${mode}"
      aria-label="${borrow ? "Borrow" : "Return"}. Scan your booking QR code.">
    <span class="icon">${icon(borrow ? "arrow-up-right" : "arrow-down-left", 34)}</span>
    <span class="t">${borrow ? "Borrow" : "Return"}</span>
    <span class="d">${borrow ? "Collect an item you've booked" : "Drop off an item you've borrowed"}</span>
    <span class="tag">${icon("scan-line", 18)} Scan QR code</span>
  </button>`;
}

function shortcut(title, sub, ic, act, to, locked) {
  return `<button class="card shortcut" data-act="${act}" data-to="${to}">
    ${badge(ic, 56)}
    <span class="grow"><div class="t">${h(title)}</div><div class="s">${h(sub)}</div></span>
    ${icon(locked ? "lock" : "chevron-right", 18)}
  </button>`;
}

const SCREENS = {};

SCREENS.home = () => {
  after(() => speak("Welcome to the Nook community hub. Tap Borrow to collect an item, or Return to bring one back."));
  return `<div class="home">
    <div class="main">
      <div>
        <div class="greeting">${greeting()}</div>
        <div class="h-xl">Borrow it.<br>Use it.<br>Bring it back.</div>
        <div class="hint">${icon("qr-code", 22)} Have your booking QR code ready in the Nook app.</div>
      </div>
      <div class="tiles">${actionTile("borrow")}${actionTile("return")}</div>
    </div>
    <div class="shortcuts">
      ${shortcut("What's available", `${availableCount()} items ready now`, "layout-grid", "go", "available", false)}
      ${shortcut("Schedule", "Pickups & returns", "calendar", "gated", "schedule", !S.profile)}
      ${shortcut("Requests", `${openRequests().length} up for grabs`, "hand", "gated", "requests", !S.profile)}
    </div>
  </div>`;
};

// ---------- Booking validation ----------

const PROBLEMS = {
  notFound: { title: "We couldn't find that booking", message: "Check the booking number in the Nook app and try again." },
  tooEarly: { title: "It's a little early", message: (b) => `Your pickup window opens at ${fmtTime(b.pickupStart)}. Come back then.` },
  expired: { title: "This pickup window has passed", message: "Rebook the item in the Nook app to get a new pickup window." },
  alreadyCollected: { title: "This item is already with you", message: "Looks like you want to return it. Use this same QR code to return.", suggest: "return" },
  notCollectedYet: { title: "This item hasn't been collected yet", message: "Looks like you want to borrow it. Use this same QR code to collect.", suggest: "borrow" },
  alreadyReturned: { title: "This booking is complete", message: "This item has already been returned. Thanks!" },
  cancelled: { title: "This booking was cancelled", message: "Make a new booking in the Nook app." },
};

function validate(code, mode) {
  const b = D.bookings.find((x) => x.code === code);
  if (!b) return { problem: "notFound" };
  if (b.status === "cancelled") return { problem: "cancelled" };
  if (b.status === "returned") return { problem: "alreadyReturned" };
  if (mode === "borrow" && b.status === "onLoan") return { problem: "alreadyCollected" };
  if (mode === "return" && b.status === "reserved") return { problem: "notCollectedYet" };
  if (mode === "borrow") {
    const now = Date.now();
    if (now < b.pickupStart.getTime() - 15 * 60000) return { problem: "tooEarly", booking: b };
    if (now > b.pickupEnd.getTime()) return { problem: "expired" };
  }
  return { booking: b };
}

// Pulls the 6-digit booking number out of e.g. "nook://booking/482193".
const parseCode = (payload) => String(payload).split(/\D+/).find((s) => s.length === 6) || null;

// ---------- Scan ----------

const CAM = { stream: null, raf: 0, canvas: null, last: 0, starting: false };

async function startCamera() {
  if (CAM.stream) return attachCamera();
  if (CAM.starting) return;
  if (!navigator.mediaDevices?.getUserMedia) { S.v.cam = "off"; return render(); }
  CAM.starting = true;
  try {
    CAM.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: { ideal: 1280 } }, audio: false });
    CAM.starting = false;
    if (S.screen.name !== "scan" || S.v.manual) return stopCamera();
    S.v.cam = "on";
    render();
  } catch {
    CAM.starting = false;
    if (S.screen.name !== "scan") return;
    S.v.cam = "off";
    render();
  }
}

function attachCamera() {
  const video = $("#cam");
  if (!video || !CAM.stream) return;
  video.srcObject = CAM.stream;
  video.play().catch(() => {});
  cancelAnimationFrame(CAM.raf);
  CAM.canvas ||= document.createElement("canvas");
  const ctx = CAM.canvas.getContext("2d", { willReadFrequently: true });
  const tick = (t) => {
    CAM.raf = requestAnimationFrame(tick);
    if (t - CAM.last < 150 || S.v.phase !== "scanning" || video.readyState < 2 || !window.jsQR) return;
    CAM.last = t;
    const w = 640, hgt = Math.round((video.videoHeight / video.videoWidth) * 640) || 480;
    CAM.canvas.width = w; CAM.canvas.height = hgt;
    ctx.drawImage(video, 0, 0, w, hgt);
    const found = jsQR(ctx.getImageData(0, 0, w, hgt).data, w, hgt, { inversionAttempts: "dontInvert" });
    if (found?.data) {
      const code = parseCode(found.data);
      if (code) submitCode(code);
      else { S.v.phase = "problem"; S.v.problem = "notFound"; render(); }
    }
  };
  CAM.raf = requestAnimationFrame(tick);
}

function stopCamera() {
  cancelAnimationFrame(CAM.raf);
  CAM.stream?.getTracks().forEach((t) => t.stop());
  CAM.stream = null;
}

async function submitCode(code) {
  if (S.v.phase === "checking") return;
  S.v.lastCode = code;
  S.v.phase = "checking";
  render();
  await sleep(450);
  const mode = S.screen.mode;
  const r = validate(code, mode);
  if (r.problem) {
    S.v.phase = "problem";
    S.v.problem = r.problem;
    S.v.problemBooking = r.booking;
    render();
    const p = PROBLEMS[r.problem];
    speak(`${p.title}. ${typeof p.message === "function" ? p.message(r.booking) : p.message}`);
  } else {
    go("confirm", { mode, code: r.booking.code });
  }
}

const DEMO = [["482193", "Collect"], ["715024", "Return"], ["920457", "Overdue"], ["306611", "Too early"]];

SCREENS.scan = () => {
  const v = S.v;
  v.phase ||= "scanning";
  v.digits ??= "";
  v.cam ||= "pending";
  const mode = S.screen.mode;
  if (!v.spoken) {
    v.spoken = true;
    after(() => speak(mode === "borrow"
      ? "Hold your booking QR code up to the camera, or enter your booking number."
      : "Scan the same QR code you used to borrow the item, or enter your booking number."));
  }
  const checking = v.phase === "checking" ? `<div class="checking"><div class="spinner"></div>Finding your booking…</div>` : "";

  let left;
  if (v.manual) {
    const cells = Array.from({ length: 6 }, (_, i) => `<span class="${i === v.digits.length ? "cur" : ""}">${h(v.digits[i] || "")}</span>`).join("");
    left = `<div class="keypad-panel">
      <div class="digits" aria-label="Booking number, ${v.digits.length} of 6 digits entered">${cells}</div>
      ${numpad("scanKey")}
      <button class="btn-primary" style="max-width:400px" data-act="findBooking" ${v.digits.length < 6 ? "disabled" : ""}>Find my booking</button>
      ${checking}
    </div>`;
  } else if (v.cam === "off") {
    left = `<div class="camera off"><div class="stack" style="align-items:center;gap:16px;text-align:center;padding:32px">
        <span class="muted">${icon("video-off", 44)}</span>
        <div class="h-s">Camera unavailable</div>
        <div class="lead">Enter your booking number instead, or try a demo booking.</div>
        <button class="btn-primary" style="max-width:360px;margin-top:8px" data-act="toggleManual">Enter booking number</button>
      </div>${checking}</div>`;
  } else {
    left = `<div class="camera">
      <video id="cam" playsinline muted autoplay></video>
      <div class="viewfinder"><i></i><i></i><i></i><i></i>${v.phase === "scanning" && v.cam === "on" ? `<div class="sweep"></div>` : ""}</div>
      ${v.cam === "pending" ? `<div style="position:absolute;color:#fff;font-weight:600;top:24px">Starting camera…</div>` : ""}
      <div class="caption">${icon("qr-code", 20)} Hold your QR code inside the frame</div>
      ${checking}
    </div>`;
    after(() => startCamera());
  }

  let side;
  if (v.phase === "problem") {
    const p = PROBLEMS[v.problem];
    const msg = typeof p.message === "function" ? p.message(v.problemBooking) : p.message;
    side = `<div class="card stack gap-18">
      ${badge("circle-alert", 64, "var(--warning)")}
      <div class="h-s" style="font-size:2rem">${h(p.title)}</div>
      <div class="lead">${h(msg)}</div>
      ${p.suggest ? `<button class="btn-primary" data-act="switchMode" data-mode="${p.suggest}">${p.suggest === "return" ? "Return" : "Borrow"} instead</button>
        <button class="btn-secondary" data-act="retry">Try again</button>`
        : `<button class="btn-primary" data-act="retry">Try again</button>`}
    </div>`;
  } else {
    side = `<div class="steps">
      <div class="stack gap-8">
        <div class="h-l">${mode === "borrow" ? "Scan to collect" : "Scan to return"}</div>
        <div class="lead">${mode === "borrow" ? "Your locker opens as soon as we find your booking." : "Use the same QR code you used to borrow the item."}</div>
      </div>
      <div class="step"><span class="n">1</span><span>Open the Nook app and tap <b>My bookings</b></span></div>
      <div class="step"><span class="n">2</span><span>${v.manual ? "Type the 6-digit <b>booking number</b>" : "Hold the <b>QR code</b> up to the camera"}</span></div>
      <div class="step"><span class="n">3</span><span>${mode === "borrow" ? "Take your item from the locker that opens" : "Place the item back in the locker that opens"}</span></div>
    </div>`;
  }

  return `<div class="split">
    <div class="grow" style="min-height:${v.manual ? "560px" : "320px"}">${left}</div>
    <div class="side gap-24">
      <div class="grow scroll">${side}</div>
      <button class="btn-secondary" style="width:100%" data-act="toggleManual">${icon(v.manual ? "scan-line" : "hash")} ${v.manual ? "Scan QR code instead" : "Enter booking number"}</button>
      <div class="demo">
        <div class="label">Demo bookings</div>
        <div class="codes">${DEMO.map(([c, l]) => `<button class="press" data-act="demo" data-code="${c}"><b>${c}</b><span>${l}</span></button>`).join("")}</div>
      </div>
    </div>
  </div>`;
};

function numpad(act) {
  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "clear", "0", "delete"];
  return `<div class="numpad">${keys.map((k) => `<button class="${k.length > 1 ? "fn" : ""}" data-act="${act}" data-k="${k}" aria-label="${k === "delete" ? "Delete" : k}">
    ${k === "delete" ? icon("delete", 30) : k === "clear" ? "Clear" : k}</button>`).join("")}</div>`;
}

// ---------- Locker wall ----------

function wall({ highlight = null, open = false, names = false, status = false, act = null, hidden = null } = {}) {
  return `<div class="wall">${D.lockers.map((l) => {
    const target = l.number === highlight;
    const dim = highlight && !target;
    const cls = `cell ${target ? "target" : ""} ${dim ? "dim" : ""} ${target && open ? "open" : ""} ${l.number === hidden ? "gap" : ""}`;
    const tag = act ? "button" : "div";
    const dots = (names && l.unlocked ? icon("lock-open", 14) : "") + (status ? `<span class="dot" style="--c:${STATUS[l.status].color}"></span>` : "");
    return `<${tag} class="${cls}" data-num="${l.number}" ${act ? `data-act="${act}" data-n="${l.number}"` : ""} aria-label="Locker ${l.number}${l.item ? ", " + h(l.item.name) : ""}">
      <div class="door">
        <span class="num">${label(l.number)}</span>
        <span class="dots">${dots}</span>
        <span class="handle"></span>
        ${names ? `<span class="item ${l.item ? "" : "empty"}">${h(l.item?.name || "Empty")}</span>` : ""}
      </div>
    </${tag}>`;
  }).join("")}</div>`;
}

const legend = (withUnlocked = false) => `<div class="legend">
  ${Object.values(STATUS).map((s) => `<span><i style="--c:${s.color}"></i>${s.label}</span>`).join("")}
  ${withUnlocked ? `<span style="color:var(--secondary)"><span style="color:var(--warning);display:inline-flex">${icon("lock-open", 13)}</span>Unlocked</span>` : ""}
</div>`;

// ---------- Confirm ----------

SCREENS.confirm = () => {
  const b = D.bookings.find((x) => x.code === S.screen.code);
  const mode = S.screen.mode;
  const v = S.v;
  const canGo = mode === "borrow" || v.condition;
  if (!v.spoken) {
    v.spoken = true;
    after(() => speak(mode === "borrow"
      ? `Hi ${b.firstName}. Your ${b.item.name} is in locker ${b.locker}. Tap Open locker when you're ready.`
      : `Thanks ${b.firstName}. Tell us how the ${b.item.name} is, then tap Open locker ${b.locker}.`));
  }
  const due = fmtDayTime(b.returnDue);
  const conditions = [["good", "All good", "thumbs-up"], ["clean", "Needs a clean", "sparkles"], ["damaged", "Damaged or missing parts", "triangle-alert"]];
  return `<div class="split">
    <div class="grow scroll stack gap-28 pb">
      <div class="stack gap-8">
        <div style="font-size:1.375rem;font-weight:600;color:var(--accent)">Hi ${h(b.firstName)} 👋</div>
        <div class="h-xl" style="font-size:3rem;letter-spacing:-1px">${mode === "borrow" ? "Ready to collect" : "Ready to return"}</div>
      </div>
      <div class="card stack gap-24">
        <div class="row" style="gap:20px;align-items:flex-start">
          ${badge(b.item.icon, 84)}
          <div class="stack gap-8"><div class="h-s" style="font-size:1.875rem">${h(b.item.name)}</div><div class="muted" style="font-size:1.0625rem">${h(b.item.blurb)}</div></div>
        </div>
        <div class="divider"></div>
        <div class="facts">
          <div class="fact"><div class="label">Locker</div><div class="v">${label(b.locker)}</div></div>
          <div class="fact"><div class="label">Booking</div><div class="v">${b.code}</div></div>
          <div class="fact"><div class="label">${mode === "borrow" ? "Return by" : isOverdue(b) ? "Was due" : "Due"}</div>
            <div class="v" style="${isOverdue(b) && mode === "return" ? "color:var(--danger)" : ""}">${due}</div></div>
        </div>
        ${isOverdue(b) ? `<div class="row" style="color:var(--danger);font-weight:500;font-size:1.0625rem">${icon("clock-alert")} This return is overdue. No stress, thanks for bringing it back.</div>` : ""}
      </div>
      ${mode === "return" ? `<div class="stack gap-16"><div class="h-s">How's the item?</div>
        <div class="conditions">${conditions.map(([k, t, ic]) => `<button class="condition press ${v.condition === k ? "on" : ""}" data-act="condition" data-k="${k}">${icon(ic, 30)}${t}</button>`).join("")}</div></div>` : ""}
    </div>
    <div class="side gap-24" style="align-items:center">
      ${wall({ highlight: b.locker })}
      <div class="lead"><span>Your item is in locker <b style="color:var(--ink)">${label(b.locker)}</b></span></div>
      <div class="grow"></div>
      <button class="btn-primary" data-act="openLocker" ${canGo ? "" : "disabled"}>${icon("lock-open")} Open locker ${label(b.locker)}</button>
      ${canGo ? "" : `<div class="muted">Let us know how the item is first</div>`}
    </div>
  </div>`;
};

// ---------- Locker open ----------

SCREENS.locker = () => {
  const b = D.bookings.find((x) => x.code === S.screen.code);
  const mode = S.screen.mode;
  const v = S.v;
  v.phase ||= "unlocking";
  if (v.phase === "unlocking" && !v.started) { v.started = true; after(() => unlock(b)); }
  const doorOpen = v.phase === "open" || v.phase === "finishing";
  // Render closed the first time, then open it a frame later so it swings.
  const alreadyOpen = doorOpen && v.doorShown;
  if (doorOpen && !v.doorShown) {
    v.doorShown = true;
    after(() => requestAnimationFrame(() => $(`.cell[data-num="${b.locker}"]`)?.classList.add("open")));
  }

  let right;
  if (v.phase === "unlocking") {
    right = `<div class="stack gap-20"><div class="spinner"></div><div class="h-l">Unlocking locker ${label(b.locker)}…</div><div class="lead">Stand clear of the door.</div></div>`;
  } else if (v.phase === "failed") {
    right = `<div class="stack gap-20">${badge("lock-keyhole", 76, "var(--danger)")}
      <div class="h-l">That locker needs attention</div>
      <div class="lead">The building manager has been notified. Please try again later.</div>
      <div class="row"><button class="btn-primary" data-act="retryUnlock">Try again</button><button class="btn-secondary" data-act="home">Back to start</button></div></div>`;
  } else {
    right = `<div class="stack gap-28" style="height:100%">
      ${pill(`Locker ${label(b.locker)} is open`, "var(--success)")}
      <div class="h-xl" style="font-size:3.25rem;letter-spacing:-1.5px">${mode === "borrow" ? `Grab your<br>${h(b.item.name)}` : `Pop the ${h(b.item.name)} back in`}</div>
      <div class="stack gap-16">
        <div class="instruction"><span class="ic">${icon("map-pin", 20)}</span><span>Door <b>${label(b.locker)}</b> is highlighted on the map</span></div>
        <div class="instruction"><span class="ic">${icon(mode === "borrow" ? "hand" : "package", 20)}</span><span>${mode === "borrow" ? "Check everything is there" : "Include all parts and chargers"}</span></div>
        <div class="instruction"><span class="ic">${icon("door-closed", 20)}</span><span>Close the door firmly until it clicks</span></div>
      </div>
      <div id="open-timer" class="muted mono" style="font-weight:500">Open for 0:00</div>
      <div class="grow"></div>
      <button class="btn-primary success" data-act="closedDoor" ${v.phase === "finishing" ? "disabled" : ""}>
        ${v.phase === "finishing" ? `<span class="spinner white"></span>` : `${icon("check")} I've closed the door`}</button>
      <button class="link-btn" data-act="lockerProblem">Something's wrong</button>
    </div>`;
  }
  return `<div class="split">
    <div class="side w45" style="justify-content:center">${wall({ highlight: b.locker, open: alreadyOpen })}</div>
    <div class="grow">${right}</div>
  </div>`;
};

async function unlock(b) {
  await sleep(1200);
  const l = locker(b.locker);
  if (S.screen.name !== "locker") return;
  if (l.status === "maintenance") {
    reportIssue("Locker failed to open", l.number);
    S.v.phase = "failed";
    speak("Sorry, that locker didn't open. The building manager has been notified.");
  } else {
    l.unlocked = true;
    S.v.phase = "open";
    S.v.openedAt = Date.now();
    speak(S.screen.mode === "borrow"
      ? `Locker ${b.locker} is open. Take your ${b.item.name}, then close the door and tap I've closed the door.`
      : `Locker ${b.locker} is open. Place the ${b.item.name} inside, close the door, and tap I've closed the door.`);
  }
  render();
}

function reportIssue(title, lockerNumber = null) {
  D.tickets.unshift({ id: "t" + Date.now(), locker: lockerNumber, title, details: "Reported at the kiosk.", reportedBy: "Kiosk", createdAt: new Date(), updatedAt: new Date(), status: "open" });
}

function completeBooking(b, mode, condition) {
  const l = locker(b.locker);
  l.unlocked = false;
  if (mode === "borrow") {
    b.status = "onLoan";
    l.status = "onLoan";
  } else {
    b.status = "returned";
    l.status = condition === "good" ? "available" : "maintenance";
    if (condition !== "good") {
      D.tickets.unshift({ id: "t" + Date.now(), locker: b.locker, title: `Returned: ${condition === "clean" ? "needs a clean" : "damaged or missing parts"}`,
        details: `${b.item.name} came back flagged by the resident.`, reportedBy: `${b.firstName} · Apt ${b.unit}`, createdAt: new Date(), updatedAt: new Date(), status: "open" });
    }
  }
}

// ---------- Done ----------

SCREENS.done = () => {
  const b = D.bookings.find((x) => x.code === S.screen.code);
  const mode = S.screen.mode;
  if (!S.v.started) {
    S.v.started = true;
    S.v.remaining = 12;
    after(() => speak(mode === "borrow"
      ? `All done. Enjoy the ${b.item.name}. Please return it using the same QR code.`
      : `All done. Thanks for returning the ${b.item.name}.`));
  }
  const msg = mode === "borrow"
    ? `Your ${h(b.item.name)} is all yours. We'll send a reminder to the Nook app before it's due.`
    : `The ${h(b.item.name)} is back in locker ${label(b.locker)}, ready for your next neighbour. Your booking is now closed.`;
  const c = 2 * Math.PI * 11.5;
  return `<div class="done">
    <div class="check-burst"><div class="core">${icon("check", 64)}</div></div>
    <div class="stack gap-12" style="align-items:center">
      <div class="h-xl" style="font-size:3.5rem;letter-spacing:-1.5px">${mode === "borrow" ? "Enjoy" : "Thanks"}, ${h(b.firstName)}!</div>
      <div class="lead" style="max-width:640px;font-size:1.375rem">${msg}</div>
    </div>
    ${mode === "borrow" ? `<div class="return-by">${icon("rotate-ccw", 20)} Return by ${fmtDayTime(b.returnDue, true)} · use the same QR code</div>` : ""}
    <button class="btn-primary" style="max-width:380px;margin-top:24px" data-act="finish">Done
      <svg class="ring" viewBox="0 0 26 26"><circle cx="13" cy="13" r="11.5" stroke="rgba(255,255,255,.3)"/>
      <circle id="ring" cx="13" cy="13" r="11.5" stroke="#fff" stroke-linecap="round" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - S.v.remaining / 12)}" style="transition:stroke-dashoffset 1s linear"/></svg>
    </button>
  </div>`;
};

function finishSession() {
  resetSettings();
  endSession();
  goHome();
}

// ---------- What's available ----------

SCREENS.available = () => {
  const v = S.v;
  if (!v.spoken) { v.spoken = true; after(() => speak(`${availableCount()} items are ready to borrow. Book them in the Nook app, or sign in here.`)); }
  const lockers = D.lockers.filter((l) => l.item && (!v.cat || l.item.category === v.cat));
  const catIcon = { Tools: "wrench", Kitchen: "utensils", Outdoors: "tent", Home: "sofa", Leisure: "gamepad-2" };
  return `<div class="stack gap-24" style="height:100%">
    <div class="row" style="align-items:flex-end;justify-content:space-between;flex-wrap:wrap">
      <div class="stack gap-8"><div class="h-m">${availableCount()} of ${D.lockers.length} ready to borrow</div>
        <div class="lead">Book any item in the Nook app, then scan here to collect.</div></div>
      ${legend()}
    </div>
    <div class="chips nowrap">
      <button class="chip ${!v.cat ? "on" : ""}" data-act="cat" data-k="">${icon("layout-grid", 20)} All</button>
      ${ITEM_CATEGORIES.map((c) => `<button class="chip ${v.cat === c ? "on" : ""}" data-act="cat" data-k="${c}">${icon(catIcon[c], 20)} ${c}</button>`).join("")}
    </div>
    <div class="grow scroll"><div class="grid-cards pb">
      ${lockers.map((l) => `<button class="card locker-card ${l.status === "available" ? "" : "faded"}" data-act="detail" data-n="${l.number}">
        <div class="row">${badge(l.item.icon, 60)}<span class="num">${label(l.number)}</span></div>
        <div><div class="nm">${h(l.item.name)}</div><div class="muted">${h(l.item.category)}</div></div>
        <div>${pill(STATUS[l.status].label, STATUS[l.status].color)}</div>
      </button>`).join("")}
    </div></div>
  </div>`;
};

function detailHTML() {
  const l = locker(S.detail);
  const it = l.item;
  const avail = l.status === "available";
  const sizes = { S: "Small", M: "Medium", L: "Large" };
  return `<div class="backdrop" data-act="closeDetail"><div class="modal detail" role="dialog" aria-modal="true">
    <div class="row" style="gap:20px">${badge(it.icon, 88)}
      <div class="grow"><div class="h-s" style="font-size:2.125rem">${h(it.name)}</div>
      <div class="muted" style="font-size:1.125rem">Locker ${label(l.number)} · ${sizes[l.size]} · ${h(it.category)}</div></div>
      ${pill(STATUS[l.status].label, STATUS[l.status].color)}</div>
    <div style="font-size:1.25rem">${h(it.blurb)}</div>
    <div class="row muted" style="font-size:1.125rem;font-weight:500">${icon("calendar-clock")} Borrow for up to ${it.days} days</div>
    <div class="row" style="font-size:1.125rem;font-weight:500;color:var(--accent)">${icon("smartphone")} ${avail ? "Book it here, or in the Nook app and scan your QR code." : "Not available right now. Check the Nook app for the next free slot."}</div>
    <div class="row" style="margin-top:12px"><button class="btn-secondary" data-act="closeDetail" data-force="1">Close</button>
      ${avail ? `<button class="btn-primary" data-act="bookNow" data-n="${l.number}">${icon("lock-open")} Book &amp; collect now</button>` : ""}</div>
  </div></div>`;
}

function bookNow(l, resident) {
  const due = new Date();
  due.setDate(due.getDate() + l.item.days);
  due.setHours(18, 0, 0, 0);
  const b = { code: String(Math.floor(100000 + Math.random() * 900000)), firstName: resident.firstName, unit: resident.unit,
    item: { ...l.item }, locker: l.number, pickupStart: new Date(), pickupEnd: new Date(Date.now() + D.hours.window * 60000), returnDue: due, status: "reserved" };
  D.bookings.push(b);
  l.status = "reserved";
  return b;
}

// ---------- Schedule ----------

SCREENS.schedule = () => {
  const v = S.v;
  v.day ??= 0;
  if (!v.spoken) { v.spoken = true; after(() => speak("Here's the locker schedule for the week.")); }
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const days = Array.from({ length: 7 }, (_, i) => { const d = new Date(start); d.setDate(d.getDate() + i); return d; });
  const eventsOn = (day) => {
    const out = [];
    for (const b of D.bookings) {
      if (b.status === "reserved" && sameDay(b.pickupStart, day)) out.push({ kind: "pickup", date: b.pickupStart, b });
      if ((b.status === "onLoan" || b.status === "reserved") && sameDay(b.returnDue, day)) out.push({ kind: "due", date: b.returnDue, b });
    }
    return out.sort((a, c) => a.date - c.date);
  };
  const day = days[v.day];
  const today = v.day === 0;
  const list = eventsOn(day);
  const carried = today ? D.bookings.filter((b) => isOverdue(b) && !isToday(b.returnDue)).map((b) => ({ kind: "due", date: b.returnDue, b })) : [];
  const pickups = list.filter((e) => e.kind === "pickup").length;
  const returns = list.length - pickups;
  const now = new Date();

  const row = (e, past) => {
    const b = e.b;
    const color = e.kind === "pickup" ? "var(--accent)" : isOverdue(b) ? "var(--danger)" : "var(--success)";
    const kind = e.kind === "pickup" ? "Pickup" : isOverdue(b) ? "Overdue" : "Return";
    const time = isToday(e.date) || !isOverdue(b) ? fmtTime(e.date) : fmtWeekday(e.date);
    return `<div class="timeline-row ${past ? "past" : ""}">
      <div class="time">${time}</div>
      <div class="rail"><i style="--c:${past ? "var(--hairline)" : color}"></i></div>
      <div class="event">${badge(b.item.icon, 52, past ? "var(--secondary)" : null)}
        <div class="grow"><div style="font-size:1.25rem;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${h(b.item.name)}</div>
        <div class="muted">Locker ${label(b.locker)}</div></div>
        <span class="kind" style="--c:${past ? "var(--secondary)" : color}">${kind}</span></div>
    </div>`;
  };
  const nowRow = `<div class="now-row"><div class="time">Now</div><div class="rail"><i></i></div><div class="line"></div></div>`;

  let body = carried.map((e) => row(e, false)).join("");
  if (!list.length && !carried.length) {
    body += `<div class="empty-state">${icon("calendar-check", 44)}<div class="h-s" style="font-size:1.5rem">Nothing scheduled</div><div class="lead">Every locker is free to book this day.</div></div>`;
  }
  list.forEach((e, i) => {
    if (today && e.date > now && (i === 0 || list[i - 1].date <= now)) body += nowRow;
    body += row(e, today && e.date < now && !isOverdue(e.b));
  });
  if (today && list.length && list[list.length - 1].date <= now) body += nowRow;

  const winLabel = D.hours.window % 60 === 0 ? `${D.hours.window / 60}-hour pickup windows` : `${D.hours.window}-minute pickup windows`;
  return `<div class="stack gap-28" style="height:100%">
    <div class="days">${days.map((d, i) => `<button class="day press ${i === v.day ? "on" : ""}" data-act="day" data-k="${i}">
      <span class="w">${i === 0 ? "Today" : fmtWeekday(d)}</span><span class="d">${d.getDate()}</span>
      <span class="p" style="background:${eventsOn(d).length ? (i === v.day ? "#fff" : "var(--accent)") : "transparent"}"></span></button>`).join("")}</div>
    <div class="row" style="align-items:baseline">
      <div class="h-s" style="font-size:2.25rem;letter-spacing:-1px">${today ? "Today" : fmtWeekday(day, true)}</div>
      <div class="muted" style="font-size:1.375rem;font-weight:500">${day.toLocaleDateString(LOCALE, { day: "numeric", month: "long" })}</div>
      <div class="grow"></div>
      <div class="muted" style="font-size:1.125rem;font-weight:500">${pickups} pickup${pickups === 1 ? "" : "s"} · ${returns} return${returns === 1 ? "" : "s"}</div>
    </div>
    <div class="grow scroll pb">${body}</div>
    <div class="info-chips">
      <div class="info-chip">${icon("clock", 18)} Open ${hourLabel(D.hours.open)} – ${hourLabel(D.hours.close)} daily</div>
      <div class="info-chip">${icon("hourglass", 18)} ${winLabel}</div>
      <div class="info-chip">${icon("sparkles", 18)} Restocked Mondays 10am – 12pm</div>
    </div>
  </div>`;
};

function hourLabel(hr) {
  if (hr === 0 || hr === 24) return "12am";
  if (hr === 12) return "12pm";
  return hr < 12 ? `${hr}am` : `${hr - 12}pm`;
}

// ---------- Help ----------

SCREENS.help = () => {
  const v = S.v;
  if (!v.spoken) { v.spoken = true; after(() => speak("Help. Tap the problem you're having and we'll let the building manager know.")); }
  return `<div class="split">
    <div class="grow stack gap-20">
      <div class="h-l">What's going on?</div>
      <div class="lead">Tap an issue and we'll let the building manager know straight away.</div>
      <div class="grow scroll stack gap-12 pb">
        ${HELP_ISSUES.map(([t, ic]) => `<button class="card arow press" style="text-align:left" data-act="report" data-k="${h(t)}">
          ${badge(ic, 52)}<span class="grow" style="font-size:1.25rem;font-weight:600">${h(t)}</span>
          <span style="color:${v.reported === t ? "var(--success)" : "var(--secondary)"}">${icon(v.reported === t ? "circle-check" : "chevron-right", v.reported === t ? 26 : 18)}</span></button>`).join("")}
      </div>
    </div>
    <div class="side w400 gap-20">
      ${v.reported ? `<div class="card stack gap-12">${pill("Reported", "var(--success)")}<div class="h-s">Thanks for letting us know</div>
        <div class="lead" style="font-size:1.125rem">“${h(v.reported)}” has been sent to the building manager. You don't need to do anything else.</div></div>` : ""}
      <div class="card stack gap-16">
        <div class="row" style="font-size:1.25rem;font-weight:700">${icon("circle-user-round")} Building manager</div>
        <div class="row" style="font-size:1.125rem;font-weight:500"><span style="color:var(--accent)">${icon("phone", 20)}</span>(02) 9000 1234</div>
        <div class="row" style="font-size:1.125rem;font-weight:500"><span style="color:var(--accent)">${icon("mail", 20)}</span>hub@thearden.com.au</div>
        <div class="row" style="font-size:1.125rem;font-weight:500"><span style="color:var(--accent)">${icon("clock", 20)}</span>Mon–Fri, 8am – 6pm</div>
        <div class="divider"></div>
        <div class="row muted" style="align-items:flex-start">${icon("shield-alert", 20)}<span>After hours emergencies: call building security on (02) 9000 5678.</span></div>
      </div>
    </div>
  </div>`;
};

// ---------- Requests ----------

const rewardLabel = (r) => ({ thanks: "A big thank you", coffee: "Coffee on me", treat: "Home-baked treat" }[r.kind] || `$${r.amount}`);
const rewardIcon = (r) => ({ thanks: "heart", coffee: "coffee", treat: "cake-slice", cash: "circle-dollar-sign" }[r.kind]);
const rewardBadge = (r) => `<span class="reward ${r.kind === "cash" ? "cash" : ""}" aria-label="Reward: ${h(rewardLabel(r))}">${icon(rewardIcon(r), 20)} ${h(rewardLabel(r))}</span>`;
const neededBy = (d) => isToday(d) ? `${fmtTime(d)} today` : isTomorrow(d) ? `${fmtTime(d)} tomorrow` : fmtDayTime(d, true);

SCREENS.requests = () => {
  const v = S.v;
  v.tab ||= "open";
  if (!S.profile && v.tab === "mine") v.tab = "open";
  if (!v.spoken) { v.spoken = true; after(() => speak(`${openRequests().length} requests are up for grabs. Accept one to help a neighbour and earn a reward.`)); }
  const p = S.profile;
  const inProgress = D.requests.filter((r) => r.helper);
  const mine = p ? D.requests.filter((r) => r.by.unit === p.unit || r.helper?.unit === p.unit) : [];
  const shown = v.tab === "open" ? openRequests() : v.tab === "active" ? inProgress : mine;
  const tab = (k, t, n) => `<button class="chip ${v.tab === k ? "on" : ""}" data-act="reqTab" data-k="${k}">${t} <span class="count">${n}</span></button>`;

  const card = (r) => {
    let footer;
    if (r.helper) {
      footer = `<div class="status-bar" style="color:var(--success);background:color-mix(in srgb, var(--success) 10%, transparent)">${icon("circle-check", 20)} ${p && r.helper.unit === p.unit ? "You're helping" : `${h(r.helper.firstName)} is on it`}</div>`;
    } else if (p && r.by.unit === p.unit) {
      footer = `<div class="status-bar muted" style="background:var(--surface)">Your request · waiting for a helper</div>`;
    } else {
      footer = `<div class="row"><button class="btn-secondary" data-act="decline" data-id="${r.id}">Decline</button>
        <button class="btn-primary" data-act="accept" data-id="${r.id}" ${v.working === r.id ? "disabled" : ""}>${v.working === r.id ? `<span class="spinner white"></span>` : "Accept"}</button></div>`;
    }
    return `<div class="card stack gap-18" style="padding:24px">
      <div class="row" style="justify-content:space-between;align-items:flex-start">${badge(r.icon, 56)}${rewardBadge(r.reward)}</div>
      <div class="stack gap-8"><div style="font-size:1.4375rem;font-weight:700">${h(r.title)}</div><div class="muted clamp2">${h(r.details)}</div></div>
      <div class="stack gap-8"><div class="meta">${icon("user", 16)} ${h(publicName(r.by))}</div><div class="meta">${icon("clock", 16)} Needed by ${neededBy(r.neededBy)}</div></div>
      ${footer}
    </div>`;
  };

  return `<div class="stack gap-24" style="height:100%">
    <div class="row" style="align-items:flex-end;justify-content:space-between">
      <div class="stack gap-8"><div class="h-m">Neighbours need a hand</div><div class="lead">Help out, earn a reward. Or ask the building for a favour.</div></div>
      <button class="btn-primary" style="width:auto" data-act="postRequest">${icon("plus")} Post a request</button>
    </div>
    <div class="chips">${tab("open", "Up for grabs", openRequests().length)}${tab("active", "In progress", inProgress.length)}${p ? tab("mine", "Mine", mine.length) : ""}</div>
    <div class="grow scroll">
      ${shown.length ? `<div class="grid-cards wide pb">${shown.map(card).join("")}</div>`
        : `<div class="empty-state">${icon("hand-heart", 48)}<div class="h-s" style="font-size:1.5rem">${v.tab === "open" ? "Nothing up for grabs right now" : "Nothing here yet"}</div>
          <div class="lead">New requests from the Nook app show up here straight away.</div></div>`}
    </div>
  </div>`;
};

const DEADLINES = [
  ["hour", "Within the hour", () => new Date(Date.now() + 3600000)],
  ["today", "Later today", () => { const d = new Date(); d.setHours(20, 0, 0, 0); return new Date(Math.max(d, Date.now() + 2 * 3600000)); }],
  ["tomorrow", "Tomorrow", () => { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(18, 0, 0, 0); return d; }],
  ["week", "This week", () => new Date(Date.now() + 6 * 86400000)],
];

SCREENS.newRequest = () => {
  const v = S.v;
  if (!S.profile) { after(() => go("requests")); return ""; }
  v.title ??= ""; v.details ??= ""; v.reward ??= 1; v.deadline ??= "today";
  if (!v.spoken) { v.spoken = true; after(() => speak("What do you need a hand with? Type your request, pick a reward, then tap Post request.")); }
  const r = REWARDS[v.reward];
  return `<div class="split">
    <div class="grow scroll stack gap-28 pb">
      <div class="stack gap-8"><div class="h-m">Ask for a favour</div>
        <div class="lead" style="font-size:1.125rem">Posting as ${h(publicName(S.profile))}. Neighbours won't see your apartment number.</div></div>
      <div class="stack gap-16"><div style="font-size:1.25rem;font-weight:700">What do you need?</div>
        <input class="field" data-input="title" placeholder="e.g. Water my plants" value="${h(v.title)}" maxlength="80">
        <div class="chips nowrap">${REQUEST_IDEAS.map((i) => `<button class="chip small accent ${v.title === i ? "on" : ""}" data-act="idea" data-k="${h(i)}">${h(i)}</button>`).join("")}</div></div>
      <div class="stack gap-16"><div style="font-size:1.25rem;font-weight:700">Any details? <span class="muted" style="font-weight:500">(optional)</span></div>
        <textarea class="field small" rows="3" data-input="details" placeholder="Where, when, anything helpful">${h(v.details)}</textarea></div>
      <div class="stack gap-16"><div style="font-size:1.25rem;font-weight:700">Reward</div>
        <div class="chips">${REWARDS.map((x, i) => `<button class="chip small accent ${v.reward === i ? "on" : ""}" data-act="pickReward" data-k="${i}">${icon(rewardIcon(x), 18)} ${h(rewardLabel(x))}</button>`).join("")}</div></div>
      <div class="stack gap-16"><div style="font-size:1.25rem;font-weight:700">Needed by</div>
        <div class="chips">${DEADLINES.map(([k, t]) => `<button class="chip small accent ${v.deadline === k ? "on" : ""}" data-act="pickDeadline" data-k="${k}">${t}</button>`).join("")}</div></div>
    </div>
    <div class="side w360 gap-20">
      <div class="label">Preview</div>
      <div class="card stack gap-12" style="padding:24px">
        <div>${rewardBadge(r)}</div>
        <div id="pv-title" style="font-size:1.5rem;font-weight:700;color:${v.title ? "var(--ink)" : "var(--secondary)"}">${h(v.title || "Your request")}</div>
        <div id="pv-details" class="muted">${h(v.details)}</div>
        <div class="meta">${icon("clock", 16)} ${DEADLINES.find((d) => d[0] === v.deadline)[1]}</div>
      </div>
      <div class="muted">Your request goes live on the kiosk and in the Nook app. We'll notify you when someone accepts.</div>
      <div class="grow"></div>
      <button class="btn-primary" id="post-btn" data-act="submitRequest" ${v.title.trim() ? "" : "disabled"}>${icon("send")} Post request</button>
    </div>
  </div>`;
};

// ---------- Overlays ----------

function overlayHTML() {
  if (S.idle) {
    const left = Math.max(0, Math.round((resetAfter() - (Date.now() - lastTouch) / 1000)));
    return `<div class="backdrop"><div class="modal idle">
      <div class="count" id="idle-count">${left}</div>
      <div class="h-s" style="font-size:2.125rem">Still there?</div>
      <div class="lead">We'll head back to the start soon to keep things private.</div>
      <button class="btn-primary" style="max-width:360px" data-act="stay">I'm still here</button></div></div>`;
  }
  if (S.login) return loginHTML();
  if (S.a11y) return a11yHTML();
  if (S.menu) {
    const p = S.profile;
    return `<div class="backdrop" data-act="closeMenu"><div class="modal stack gap-20" style="width:min(460px, calc(100vw - 48px))">
      <div class="row" style="gap:16px"><span class="account" style="padding:0;background:none"><span class="initial">${h(p.firstName[0])}</span></span>
        <div><div class="h-s">${h(p.firstName)}</div><div class="muted">${p.isAdmin ? "Building staff" : "Apartment " + h(p.unit)}</div></div></div>
      <div class="row"><button class="btn-secondary" data-act="closeMenu" data-force="1">Cancel</button>
        <button class="btn-primary dark" data-act="signOut">${icon("log-out")} Sign out</button></div></div></div>`;
  }
  if (S.detail) return detailHTML();
  return "";
}

function loginHTML() {
  const L = S.login;
  const unitV = L.unit || "e.g. 1204";
  const pinV = L.pin ? "●".repeat(L.pin.length) : "4 digits";
  const can = L.field === "unit" ? !!L.unit : L.pin.length === 4;
  return `<div class="backdrop" data-act="cancelLogin"><div class="modal" role="dialog" aria-modal="true"><div class="login">
    <div class="form">
      <div class="row" style="gap:18px;align-items:center">${badge("circle-user-round", 72)}
        <div class="stack gap-8"><div class="h-m">Sign in</div><div class="muted" style="font-size:1.125rem">${h(L.reason)}</div></div></div>
      <button class="field-box ${L.field === "unit" ? "on" : ""}" data-act="loginField" data-k="unit">
        <div class="label ${L.field === "unit" ? "on" : ""}">Apartment</div><div class="v ${L.unit ? "" : "ph"}">${h(unitV)}</div></button>
      <button class="field-box ${L.field === "pin" ? "on" : ""}" data-act="loginField" data-k="pin">
        <div class="label ${L.field === "pin" ? "on" : ""}">PIN</div><div class="v ${L.pin ? "pin" : "ph"}">${pinV}</div></button>
      ${L.failed ? `<div class="row" style="color:var(--danger);font-weight:600">${icon("circle-alert", 20)} That apartment number and PIN don't match.</div>` : ""}
      <div class="muted small">Forgot your PIN? Reset it in the Nook app.</div>
      <div class="muted small" style="font-family:ui-monospace,Menlo,monospace">Demo: apartment 1204, PIN 1234 · Admin: 0000, PIN 2468</div>
      <div class="row" style="margin-top:8px"><button class="btn-secondary" data-act="cancelLogin" data-force="1">Cancel</button>
        <button class="btn-primary" data-act="loginNext" ${can && !L.checking ? "" : "disabled"}>${L.checking ? `<span class="spinner white"></span>` : L.field === "unit" ? "Next" : "Sign in"}</button></div>
    </div>
    ${numpad("loginKey")}
  </div></div></div>`;
}

function a11yHTML() {
  const opt = (k, t, d, ic) => `<button class="option press ${S.set[k] ? "on" : ""}" data-act="toggleSet" data-k="${k}" aria-pressed="${S.set[k]}">
    <div class="top"><span class="ic">${icon(ic, 28)}</span><span class="switch ${S.set[k] ? "on" : ""}"></span></div>
    <div><div class="t">${t}</div><div class="d">${d}</div></div></button>`;
  return `<div class="backdrop" data-act="closeA11y"><div class="modal a11y" role="dialog" aria-modal="true">
    <div class="row" style="align-items:flex-start;justify-content:space-between">
      <div class="stack gap-8"><div class="h-m">Accessibility</div><div class="lead" style="font-size:1.125rem">These settings reset when you're finished, ready for the next person.</div></div>
      <button class="circle-btn" data-act="closeA11y" data-force="1" aria-label="Close">${icon("x", 26)}</button></div>
    <div class="grid">
      ${opt("large", "Larger text", "Make everything easier to read", "a-large-small")}
      ${opt("hc", "High contrast", "Bolder colours and outlines", "contrast")}
      ${opt("voice", "Voice guidance", "Read each step out loud", "volume-2")}
      ${opt("reach", "Lower the screen", "Move controls within easy reach", "accessibility")}
      ${opt("rm", "Reduce motion", "Turn off animations", "circle-pause")}
    </div>
    <div class="row">${customised() ? `<button class="btn-secondary" data-act="resetSet">Reset</button>` : ""}
      <button class="btn-primary" data-act="closeA11y" data-force="1">Done</button></div>
  </div></div>`;
}

// ---------- Admin ----------

const ZOOM_MS = 550;

SCREENS.admin = () => {
  if (!isAdmin()) { after(goHome); return ""; }
  const v = S.v;
  v.tab ||= "lockers";
  v.filter ||= "open";
  if (!v.spoken) { v.spoken = true; after(() => speak("Admin. Tap a locker to inspect it.")); }
  return v.selected ? inspectorHTML() : adminOverview();
};

function adminOverview() {
  const v = S.v;
  const openJobs = D.tickets.filter((t) => t.status !== "resolved").length;
  const activeBookings = D.bookings.filter((b) => b.status === "reserved" || b.status === "onLoan").length;
  const tab = (k, t, n) => `<button class="chip ${v.tab === k ? "on" : ""}" data-act="adminTab" data-k="${k}">${t}${n ? ` <span class="count">${n}</span>` : ""}</button>`;
  const panel = v.tab === "lockers" ? lockersPanel() : v.tab === "service" ? servicePanel() : bookingsPanel();
  return `<div class="admin">
    <div class="wall-col">
      <div class="row" style="justify-content:space-between;align-items:baseline"><div class="h-s" style="font-size:2.25rem;letter-spacing:-1px">Locker wall</div>${pill("Staff mode", "var(--warning)")}</div>
      <div class="lead" style="font-size:1.125rem">Tap a locker to look inside, edit it or unlock it.</div>
      ${wall({ names: true, status: true, act: "inspect" })}
      ${legend(true)}
    </div>
    <div class="panel">
      <div class="chips">${tab("lockers", "Lockers")}${tab("service", "Service", openJobs)}${tab("bookings", "Bookings", activeBookings)}</div>
      <div class="grow scroll stack gap-18 pb">${panel}</div>
    </div>
  </div>`;
}

const arow = (ic, color, title, sub, action = "") => `<div class="card arow">${badge(ic, 52, color)}
  <div class="grow"><div class="t">${h(title)}</div><div class="s">${h(sub)}</div></div>${action}</div>`;

function lockersPanel() {
  const count = (s) => D.lockers.filter((l) => l.status === s && l.item).length;
  const unlocked = D.lockers.filter((l) => l.unlocked);
  const empty = D.lockers.filter((l) => !l.item);
  const jobs = D.tickets.filter((t) => t.status !== "resolved").length;
  const stat = (n, t, c) => `<div class="card stat" style="padding:20px;--c:${c}"><div class="v">${n}</div><div class="muted" style="font-weight:500">${t}</div></div>`;
  return `<div class="stats">
      ${stat(count("available"), "Available", "var(--success)")}${stat(count("reserved"), "Reserved", "var(--accent)")}
      ${stat(count("onLoan"), "On loan", "var(--secondary)")}${stat(D.lockers.filter((l) => l.status === "maintenance").length, "Out of service", "var(--warning)")}
    </div>
    ${arow(unlocked.length ? "lock-open" : "lock", unlocked.length ? "var(--warning)" : "var(--success)",
      unlocked.length ? `${unlocked.length} door${unlocked.length === 1 ? "" : "s"} unlocked` : "All doors locked",
      unlocked.length ? unlocked.map((l) => `Locker ${label(l.number)}`).join(", ") : "Every locker is secure.",
      unlocked.length ? `<button class="btn-secondary" data-act="lockAll">Lock all</button>` : "")}
    ${arow("wrench", jobs ? "var(--warning)" : "var(--success)", jobs ? `${jobs} open service job${jobs === 1 ? "" : "s"}` : "No open service jobs",
      "Repairs and reports from the kiosk.", `<button class="btn-secondary" data-act="adminTab" data-k="service">View</button>`)}
    ${empty.map((l) => arow("inbox", "var(--accent)", `Locker ${label(l.number)} is empty`, "Add an item so residents can borrow it.",
      `<button class="btn-secondary" data-act="inspect" data-n="${l.number}">Add item</button>`)).join("")}`;
}

function servicePanel() {
  const v = S.v;
  const tabs = [["open", "Open"], ["inProgress", "In progress"], ["resolved", "Resolved"]];
  const shown = D.tickets.filter((t) => t.status === v.filter);
  return `<div class="row" style="flex-wrap:wrap">
      ${tabs.map(([k, t]) => `<button class="chip ${v.filter === k ? "on" : ""}" data-act="ticketFilter" data-k="${k}">${t} <span class="count">${D.tickets.filter((x) => x.status === k).length}</span></button>`).join("")}
      <div class="grow"></div>
      <button class="btn-secondary" data-act="toggleComposer">${icon(v.composing ? "x" : "plus")} Log repair</button>
    </div>
    ${v.composing ? composerHTML(null) : ""}
    ${shown.length ? shown.map((t) => ticketHTML(t, true)).join("")
      : `<div class="empty-state" style="padding:50px 0"><span style="color:var(--success)">${icon("badge-check", 40)}</span><div style="font-size:1.375rem;font-weight:600">Nothing ${tabs.find((x) => x[0] === v.filter)[1].toLowerCase()}</div></div>`}`;
}

function ticketHTML(t, linkLocker) {
  const color = { open: "var(--danger)", inProgress: "var(--accent)", resolved: "var(--success)" }[t.status];
  const ic = { open: "circle-alert", inProgress: "wrench", resolved: "circle-check" }[t.status];
  const btn = (k, text, primary) => `<button class="${primary ? "btn-primary success" : "btn-secondary"}" data-act="ticketStatus" data-id="${t.id}" data-k="${k}">${text}</button>`;
  const actions = t.status === "open" ? btn("inProgress", "Start work") + btn("resolved", "Resolve", true)
    : t.status === "inProgress" ? btn("open", "Back to open") + btn("resolved", "Resolve", true)
    : btn("open", "Reopen");
  return `<div class="card ticket">
    <div class="row" style="align-items:flex-start;gap:16px">${badge(ic, 52, color)}
      <div class="grow stack gap-8"><div style="font-size:1.25rem;font-weight:600">${h(t.title)}</div>
        <div class="muted">${h(t.details)}</div>
        <div class="muted small" style="font-weight:500">${h(t.reportedBy)} · ${relative(t.createdAt)}</div></div>
      ${t.locker ? (linkLocker ? `<button class="pill press" style="--c:var(--accent)" data-act="inspect" data-n="${t.locker}">Locker ${label(t.locker)}</button>`
        : pill(`Locker ${label(t.locker)}`, "var(--accent)")) : ""}
    </div>
    <div class="row">${actions}</div>
  </div>`;
}

function composerHTML(fixed) {
  const v = S.v;
  const target = fixed ?? v.pick;
  const ok = v.reason && target;
  return `<div class="card stack gap-16" style="padding:22px">
    <div style="font-size:1.25rem;font-weight:700">Log a repair</div>
    ${fixed ? "" : `<div class="muted" style="font-weight:600">Locker</div>
      <div class="chips nowrap">${D.lockers.map((l) => `<button class="chip small accent ${v.pick === l.number ? "on" : ""}" data-act="pickLocker" data-k="${l.number}">${label(l.number)}</button>`).join("")}</div>`}
    <div class="muted" style="font-weight:600">What's wrong?</div>
    <div class="chips">${REPAIR_REASONS.map((r) => `<button class="chip small accent ${v.reason === r ? "on" : ""}" data-act="pickReason" data-k="${h(r)}">${h(r)}</button>`).join("")}</div>
    <button class="toggle-row" data-act="toggleOos"><span class="switch ${v.oos !== false ? "on" : ""}"></span>Take the locker out of service until it's fixed</button>
    <button class="btn-primary" data-act="logRepair" data-n="${target || ""}" ${ok ? "" : "disabled"}>${icon("wrench")} Log repair</button>
  </div>`;
}

function bookingsPanel() {
  const active = D.bookings.filter((b) => b.status === "reserved" || b.status === "onLoan")
    .sort((a, b) => (a.status === "reserved" ? a.pickupStart : a.returnDue) - (b.status === "reserved" ? b.pickupStart : b.returnDue));
  const hrs = D.hours;
  const stepper = (k, labelText, val, min, max) => `<div class="stepper">
    <div class="stack" style="margin-right:auto"><div class="label">${labelText}</div><div class="v">${hourLabel(val)}</div></div>
    <button data-act="hour" data-k="${k}" data-d="-1" ${val <= min ? "disabled" : ""} aria-label="Earlier">${icon("minus", 18)}</button>
    <button data-act="hour" data-k="${k}" data-d="1" ${val >= max ? "disabled" : ""} aria-label="Later">${icon("plus", 18)}</button></div>`;
  return `<div class="card stack gap-16" style="padding:22px">
      <div class="row" style="font-size:1.25rem;font-weight:700">${icon("clock")} Hub hours</div>
      <div class="hours">${stepper("open", "Opens", hrs.open, 0, hrs.close - 1)}${stepper("close", "Closes", hrs.close, hrs.open + 1, 24)}</div>
      <div class="muted" style="font-weight:600">Pickup window</div>
      <div class="chips">${[30, 60, 90, 120].map((m) => `<button class="chip small accent ${hrs.window === m ? "on" : ""}" data-act="window" data-k="${m}">${m < 60 ? m + " min" : m / 60 + " hr"}</button>`).join("")}</div>
      <div class="muted small">Shown on the kiosk schedule and used for new bookings.</div>
    </div>
    <div class="section-title">Active bookings</div>
    ${active.map((b) => bookingCardHTML(b, true)).join("")}`;
}

function bookingCardHTML(b, linkLocker) {
  const overdue = isOverdue(b);
  const status = overdue ? ["Overdue", "var(--danger)"] : b.status === "reserved" ? ["Awaiting pickup", "var(--accent)"] : ["On loan", "var(--success)"];
  const when = b.status === "reserved" ? `Pickup ${fmtDayTime(b.pickupStart)} – ${fmtTime(b.pickupEnd)}` : `Due ${fmtDayTime(b.returnDue)}`;
  const actions = b.status === "reserved"
    ? `<button class="btn-secondary" data-act="cancelBooking" data-code="${b.code}">Cancel booking</button>`
    : `<button class="btn-secondary" data-act="extend" data-code="${b.code}">+1 day</button><button class="btn-primary" data-act="adminReturned" data-code="${b.code}">Mark returned</button>`;
  return `<div class="card ticket">
    <div class="row" style="align-items:flex-start;gap:16px">${badge(b.item.icon, 52)}
      <div class="grow stack gap-8"><div style="font-size:1.25rem;font-weight:600">${h(b.item.name)}</div>
        <div class="muted">${h(b.firstName)} · Apt ${h(b.unit)} · #${b.code}</div>
        <div style="font-weight:500;${overdue ? "color:var(--danger)" : ""}">${when}</div></div>
      <div class="stack gap-8" style="align-items:flex-end">${pill(...status)}
        ${linkLocker ? `<button class="press" style="color:var(--accent);font-weight:700" data-act="inspect" data-n="${b.locker}">Locker ${label(b.locker)}</button>` : ""}</div>
    </div>
    <div class="row">${actions}</div>
  </div>`;
}

function inspectorHTML() {
  const v = S.v;
  const l = locker(v.selected);
  const booked = l.status === "reserved" || l.status === "onLoan";
  const sizes = { S: "Small", M: "Medium", L: "Large" };
  const b = activeBooking(l);
  const tickets = D.tickets.filter((t) => t.locker === l.number);

  const door = `<div class="card arow" style="padding:20px">${badge(l.unlocked ? "lock-open" : "lock", 56, l.unlocked ? "var(--warning)" : "var(--success)")}
    <div class="grow"><div class="t" style="font-size:1.25rem">${l.unlocked ? "Door unlocked" : "Door locked"}</div>
      <div class="s">${l.unlocked ? "Anyone can open it. Lock it when you're done." : "Unlock to restock or check the item."}</div></div>
    <button class="btn-primary ${l.unlocked ? "dark" : ""}" style="width:180px" data-act="door" ${v.doorBusy ? "disabled" : ""}>
      ${v.doorBusy ? `<span class="spinner white"></span>` : `${icon(l.unlocked ? "lock" : "lock-open")} ${l.unlocked ? "Lock" : "Unlock"}`}</button></div>`;

  let contents;
  if (v.editing) contents = editorHTML(l);
  else if (l.item) {
    contents = `<div class="card stack gap-16" style="padding:22px"><div class="label">Contents</div>
      <div class="row" style="align-items:flex-start;gap:16px">${badge(l.item.icon, 64)}
        <div class="stack gap-8"><div class="h-s">${h(l.item.name)}</div>
          <div class="muted" style="font-weight:500">${h(l.item.category)} · Loan up to ${l.item.days} day${l.item.days === 1 ? "" : "s"}</div>
          <div style="font-size:1.0625rem">${h(l.item.blurb)}</div></div></div>
      <div class="row"><button class="btn-primary" data-act="editItem">${icon("pencil")} Edit item</button>
        <button class="btn-secondary" data-act="removeItem" ${booked ? "disabled" : ""}>${icon("trash-2")} Remove</button></div>
      ${booked ? `<div class="muted small">This item is booked, so it can't be removed until the booking ends.</div>` : ""}</div>`;
  } else {
    contents = `<div class="card stack gap-16" style="padding:22px"><div class="label">Contents</div>
      <div class="row" style="gap:16px">${badge("inbox", 64, "var(--secondary)")}<div><div class="h-s">Empty</div><div class="muted">Add an item so residents can borrow it.</div></div></div>
      <button class="btn-primary" data-act="editItem">${icon("plus")} Add an item</button></div>`;
  }

  const service = `<div class="card stack gap-12" style="padding:22px"><div class="label">Service status</div>
    ${booked ? `<div class="muted">${STATUS[l.status].label}. This updates automatically when the booking ends.</div>`
      : `<div class="chips"><button class="chip small accent ${l.status === "available" ? "on" : ""}" data-act="lockerStatus" data-k="available">In service</button>
        <button class="chip small accent ${l.status === "maintenance" ? "on" : ""}" data-act="lockerStatus" data-k="maintenance">Out of service</button></div>
        <div class="muted small">${l.status === "maintenance" ? "Residents can't book this locker right now." : "Residents can book this item."}</div>`}</div>`;

  if (!v.zoomed) {
    v.zoomed = true;
    after(zoomIn);
  }

  return `<div class="inspector">
    <div class="cab-col">
      <div class="cabinet ${v.cabOpen ? "open" : ""}" id="cabinet">
        <div class="inside"><div class="contents">${l.item ? `${icon(l.item.icon, 96)}<div class="nm">${h(l.item.name)}</div><div class="muted" style="font-size:1.125rem;font-weight:500">${h(l.item.category)}</div>`
          : `<span class="muted">${icon("inbox", 80)}</span><div class="nm muted">Empty</div>`}</div></div>
        <div class="big-door"><span class="num">${label(l.number)}</span><span class="dot" style="--c:${STATUS[l.status].color}"></span><span class="handle"></span></div>
      </div>
      <div class="muted small" style="font-weight:500;min-height:1.2em">${v.cabOpen ? "Showing what's inside" : ""}</div>
    </div>
    <div class="details grow scroll stack gap-18 pb" style="animation:fade .4s .15s both">
      <div class="row" style="align-items:center">
        <div class="stack gap-8 grow"><div class="h-m">Locker ${label(l.number)}</div>
          <div class="row" style="gap:8px">${pill(STATUS[l.status].label, STATUS[l.status].color)}${pill(sizes[l.size], "var(--secondary)")}</div></div>
        <button class="circle-btn" data-act="closeInspector" aria-label="Back to locker wall">${icon("x", 26)}</button>
      </div>
      ${door}${contents}${service}
      ${b ? `<div class="section-title">Booking</div>${bookingCardHTML(b, false)}` : ""}
      <div class="row" style="justify-content:space-between;margin-top:4px"><div class="section-title" style="margin:0">Repairs</div>
        <button class="btn-secondary" data-act="toggleRepair">${icon(v.repair ? "x" : "plus")} ${v.repair ? "Cancel" : "Log repair"}</button></div>
      ${v.repair ? composerHTML(l.number) : ""}
      ${!tickets.length && !v.repair ? `<div class="muted" style="font-size:1.0625rem">No repairs logged for this locker.</div>` : ""}
      ${tickets.map((t) => ticketHTML(t, false)).join("")}
    </div>
  </div>`;
}

function editorHTML(l) {
  const e = S.v.edit;
  return `<div class="card stack gap-18" style="padding:22px">
    <div class="h-s" style="font-size:1.5rem">${l.item ? "Edit item" : "Add an item"}</div>
    <div class="stack gap-12"><div class="muted" style="font-weight:600">Name</div>
      <input class="field" data-input="edit.name" placeholder="e.g. Cordless Drill" value="${h(e.name)}" maxlength="40"></div>
    <div class="stack gap-12"><div class="muted" style="font-weight:600">Details</div>
      <textarea class="field small" rows="3" data-input="edit.blurb" placeholder="What's included, how to use it">${h(e.blurb)}</textarea></div>
    <div class="stack gap-12"><div class="muted" style="font-weight:600">Category</div>
      <div class="chips">${ITEM_CATEGORIES.map((c) => `<button class="chip small accent ${e.category === c ? "on" : ""}" data-act="editCat" data-k="${c}">${c}</button>`).join("")}</div></div>
    <div class="stack gap-12"><div class="muted" style="font-weight:600">Icon</div>
      <div class="icon-grid">${ADMIN_ICONS.map((i) => `<button class="press ${e.icon === i ? "on" : ""}" data-act="editIcon" data-k="${i}" aria-label="${i}">${icon(i, 22)}</button>`).join("")}</div></div>
    <div class="stack gap-12"><div class="muted" style="font-weight:600">Loan length</div>
      <div class="stepper"><div class="v">${e.days} day${e.days === 1 ? "" : "s"}</div>
        <button data-act="editDays" data-d="-1" ${e.days <= 1 ? "disabled" : ""}>${icon("minus", 18)}</button>
        <button data-act="editDays" data-d="1" ${e.days >= 14 ? "disabled" : ""}>${icon("plus", 18)}</button></div></div>
    <div class="row"><button class="btn-secondary" data-act="cancelEdit">Cancel</button>
      <button class="btn-primary" id="save-item" data-act="saveItem" ${e.name.trim() ? "" : "disabled"}>${icon("check")} Save</button></div>
  </div>`;
}

// Zoom the locker from its spot on the wall up to the big cabinet (FLIP).
function zoomIn() {
  const cab = $("#cabinet");
  const from = S.v.fromRect;
  const finish = () => setTimeout(() => { S.v.cabOpen = true; cab.classList.add("open"); $(".cab-col .small").textContent = "Showing what's inside"; }, S.set.rm ? 0 : 380);
  if (!cab || !from || S.set.rm) return finish();
  const to = cab.getBoundingClientRect();
  const sx = from.width / to.width, sy = from.height / to.height;
  cab.animate([
    { transformOrigin: "top left", transform: `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${sx}, ${sy})` },
    { transformOrigin: "top left", transform: "none" },
  ], { duration: ZOOM_MS, easing: "cubic-bezier(.2,.8,.2,1)" });
  finish();
}

async function zoomOut() {
  const v = S.v;
  const n = v.selected;
  const cab = $("#cabinet");
  if (cab && !S.set.rm) {
    cab.classList.remove("open");
    await sleep(260);
  }
  const from = $("#cabinet")?.getBoundingClientRect();
  v.selected = null; v.zoomed = false; v.cabOpen = false; v.editing = false; v.repair = false; v.fromRect = null;
  render();
  const cell = $(`.cell[data-num="${n}"]`);
  if (cell && from && !S.set.rm) {
    const to = cell.getBoundingClientRect();
    cell.animate([
      { transformOrigin: "top left", transform: `translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width}, ${from.height / to.height})`, zIndex: 5 },
      { transformOrigin: "top left", transform: "none", zIndex: 5 },
    ], { duration: ZOOM_MS, easing: "cubic-bezier(.2,.8,.2,1)" });
  }
}

function setTicketStatus(t, status) {
  t.status = status;
  t.updatedAt = new Date();
  const l = t.locker && locker(t.locker);
  if (status === "resolved" && l && l.status === "maintenance" && !D.tickets.some((x) => x !== t && x.locker === l.number && x.status !== "resolved")) {
    l.status = "available";
    toast(`Resolved. Locker ${label(l.number)} is back in service`);
  } else {
    toast(status === "resolved" ? "Ticket resolved" : `Ticket marked ${status === "open" ? "open" : "in progress"}`);
  }
}

// ---------- Actions ----------

const ACT = {
  home: () => goHome(),
  go: (d) => go(d.to, d.mode ? { mode: d.mode } : {}),
  gated: (d) => requireLogin(d.to === "schedule" ? "Sign in to see the locker schedule." : "Sign in to see and help with community requests.", () => go(d.to)),
  signIn: () => requireLogin("Sign in to book items and post requests from your apartment.", () => {}),
  menu: () => { S.menu = true; renderOverlay(); },
  closeMenu: (d, el, e) => { if (d.force || e.target === el) { S.menu = false; renderOverlay(); } },
  signOut: () => {
    const wasGated = REQUIRES_SIGN_IN.includes(S.screen.name);
    endSession();
    toast("Signed out");
    wasGated ? goHome() : render();
  },
  exitAdmin: () => { endSession(); toast("Signed out of admin"); goHome(); },
  a11y: () => { S.a11y = true; renderOverlay(); },
  closeA11y: (d, el, e) => { if (d.force || e.target === el) { S.a11y = false; render(); } },
  toggleSet: (d) => {
    S.set[d.k] = !S.set[d.k];
    if (d.k === "voice") S.set.voice ? speak("Voice guidance is on. I'll read out each step.") : speechSynthesis?.cancel();
    render();
  },
  resetSet: () => { resetSettings(); render(); },
  stay: () => poke(),

  // Login
  cancelLogin: (d, el, e) => { if (d.force || e.target === el) { S.login = null; renderOverlay(); } },
  loginField: (d) => { if (d.k === "pin" && !S.login.unit) return; S.login.field = d.k; renderOverlay(); },
  loginKey: (d) => {
    const L = S.login;
    L.failed = false;
    const f = L.field;
    if (d.k === "delete") { if (f === "pin" && !L.pin) L.field = "unit"; else L[f] = L[f].slice(0, -1); }
    else if (d.k === "clear") L[f] = "";
    else if (L[f].length < 4) {
      L[f] += d.k;
      if (f === "pin" && L.pin.length === 4) return ACT.loginNext();
    }
    renderOverlay();
  },
  loginNext: async () => {
    const L = S.login;
    if (L.field === "unit") { if (L.unit) { L.field = "pin"; renderOverlay(); } return; }
    if (L.pin.length < 4 || L.checking) return;
    L.checking = true;
    renderOverlay();
    await sleep(450);
    const match = D.residents[L.unit];
    if (!match || match.pin !== L.pin) {
      Object.assign(L, { checking: false, failed: true, pin: "" });
      renderOverlay();
      const m = $(".modal");
      m.style.animation = "";
      m.classList.remove("shake"); void m.offsetWidth; m.classList.add("shake");
      speak("That apartment number and PIN don't match. Please try again.");
      return;
    }
    S.profile = match.resident;
    S.login = null;
    if (S.profile.isAdmin) { toast("Admin mode"); go("admin"); return; }
    toast(`Welcome back, ${S.profile.firstName}`);
    speak(`Welcome back, ${S.profile.firstName}.`);
    render();
    L.onSuccess(S.profile);
  },

  // Scan
  toggleManual: () => {
    S.v.manual = !S.v.manual;
    S.v.phase = "scanning";
    if (S.v.manual) stopCamera(); else S.v.cam = "pending";
    render();
  },
  scanKey: (d) => {
    const v = S.v;
    if (d.k === "delete") v.digits = v.digits.slice(0, -1);
    else if (d.k === "clear") v.digits = "";
    else if (v.digits.length < 6) v.digits += d.k;
    render();
  },
  findBooking: () => submitCode(S.v.digits),
  demo: (d) => submitCode(d.code),
  retry: () => { S.v.phase = "scanning"; render(); },
  switchMode: async (d) => {
    const code = S.v.lastCode;
    const r = validate(code, d.mode);
    if (r.booking && !r.problem) go("confirm", { mode: d.mode, code });
    else go("scan", { mode: d.mode });
  },

  // Booking flow
  condition: (d) => { S.v.condition = d.k; render(); },
  openLocker: () => go("locker", { mode: S.screen.mode, code: S.screen.code, condition: S.v.condition }),
  retryUnlock: () => { S.v.phase = "unlocking"; S.v.started = false; render(); },
  closedDoor: async () => {
    S.v.phase = "finishing";
    render();
    await sleep(500);
    const b = D.bookings.find((x) => x.code === S.screen.code);
    completeBooking(b, S.screen.mode, S.screen.condition);
    go("done", { mode: S.screen.mode, code: b.code });
  },
  lockerProblem: () => { reportIssue("Problem at open locker", D.bookings.find((x) => x.code === S.screen.code)?.locker); go("help"); },
  finish: () => finishSession(),

  // Available
  cat: (d) => { S.v.cat = d.k || null; render(); },
  detail: (d) => { S.detail = +d.n; renderOverlay(); },
  closeDetail: (d, el, e) => { if (d.force || e.target === el) { S.detail = null; renderOverlay(); } },
  bookNow: (d) => {
    const l = locker(+d.n);
    S.detail = null;
    renderOverlay();
    requireLogin(`Sign in to book the ${l.item.name} to your apartment.`, (resident) => {
      if (l.status !== "available") return toast("Sorry, that item was just booked by someone else");
      const b = bookNow(l, resident);
      go("confirm", { mode: "borrow", code: b.code });
    });
  },

  // Schedule / help
  day: (d) => { S.v.day = +d.k; render(); },
  report: (d) => {
    reportIssue(d.k);
    S.v.reported = d.k;
    render();
    speak("Thanks. We've let the building manager know.");
  },

  // Requests
  reqTab: (d) => { S.v.tab = d.k; render(); },
  decline: (d) => { S.declined.add(d.id); render(); },
  accept: (d) => {
    const r = D.requests.find((x) => x.id === d.id);
    requireLogin(`Sign in so ${r.by.firstName} knows who's helping.`, async (resident) => {
      if (resident.unit === r.by.unit) return toast("That's your own request");
      S.v.working = r.id;
      render();
      await sleep(450);
      if (r.helper) toast("Someone else just grabbed that one");
      else {
        r.helper = resident;
        toast(`You're on it! ${r.by.firstName} has been notified in the Nook app.`);
        speak(`You're on it. ${r.by.firstName} has been notified.`);
      }
      S.v.working = null;
      render();
    });
  },
  postRequest: () => requireLogin("Sign in to post a request from your apartment.", () => go("newRequest")),
  idea: (d) => { S.v.title = d.k; render(); },
  pickReward: (d) => { S.v.reward = +d.k; render(); },
  pickDeadline: (d) => { S.v.deadline = d.k; render(); },
  submitRequest: async () => {
    const v = S.v;
    if (!v.title.trim() || !S.profile) return;
    const p = S.profile;
    D.requests.unshift({ id: "r" + Date.now(), title: v.title.trim(), details: v.details.trim(), icon: "hand", by: p,
      reward: REWARDS[v.reward], postedAt: new Date(), neededBy: DEADLINES.find((x) => x[0] === v.deadline)[2](), helper: null });
    toast("Request posted. We'll let you know when someone accepts.");
    go("requests");
  },

  // Admin
  adminTab: (d) => { S.v.tab = d.k; render(); },
  inspect: (d, el) => {
    const cell = $(`.cell[data-num="${d.n}"]`);
    S.v.fromRect = cell?.getBoundingClientRect();
    S.v.selected = +d.n;
    S.v.zoomed = false;
    S.v.cabOpen = false;
    render();
  },
  closeInspector: () => zoomOut(),
  door: async () => {
    const l = locker(S.v.selected);
    S.v.doorBusy = true;
    render();
    await sleep(600);
    l.unlocked = !l.unlocked;
    S.v.doorBusy = false;
    toast(`Locker ${label(l.number)} ${l.unlocked ? "unlocked" : "locked"}`);
    render();
  },
  lockAll: () => { D.lockers.forEach((l) => (l.unlocked = false)); toast("All doors locked"); render(); },
  editItem: () => {
    const it = locker(S.v.selected).item;
    S.v.edit = { name: it?.name || "", blurb: it?.blurb || "", category: it?.category || "Tools", icon: it?.icon || ADMIN_ICONS[0], days: it?.days || 3 };
    S.v.editing = true;
    render();
  },
  cancelEdit: () => { S.v.editing = false; render(); },
  editCat: (d) => { S.v.edit.category = d.k; render(); },
  editIcon: (d) => { S.v.edit.icon = d.k; render(); },
  editDays: (d) => { S.v.edit.days = Math.min(14, Math.max(1, S.v.edit.days + +d.d)); render(); },
  saveItem: () => {
    const l = locker(S.v.selected);
    const e = S.v.edit;
    const name = e.name.trim();
    if (!name) return;
    const added = !l.item;
    l.item = { id: l.item?.id || "i" + Date.now(), name, category: e.category, icon: e.icon, blurb: e.blurb.trim(), days: e.days };
    S.v.editing = false;
    toast(added ? `${name} added to locker ${label(l.number)}` : `${name} updated`);
    render();
  },
  removeItem: () => {
    const l = locker(S.v.selected);
    toast(`${l.item.name} removed from locker ${label(l.number)}`);
    l.item = null;
    render();
  },
  lockerStatus: (d) => {
    const l = locker(S.v.selected);
    l.status = d.k;
    toast(d.k === "available" ? `Locker ${label(l.number)} is back in service` : `Locker ${label(l.number)} taken out of service`);
    render();
  },
  toggleRepair: () => { S.v.repair = !S.v.repair; S.v.reason = null; S.v.oos = true; render(); },
  toggleComposer: () => { S.v.composing = !S.v.composing; S.v.reason = null; S.v.pick = null; S.v.oos = true; render(); },
  pickLocker: (d) => { S.v.pick = +d.k; render(); },
  pickReason: (d) => { S.v.reason = d.k; render(); },
  toggleOos: () => { S.v.oos = S.v.oos === false; render(); },
  logRepair: (d) => {
    const n = +d.n;
    const l = locker(n);
    if (!S.v.reason || !l) return;
    D.tickets.unshift({ id: "t" + Date.now(), locker: n, title: S.v.reason, details: "Logged by building staff.", reportedBy: "Building staff",
      createdAt: new Date(), updatedAt: new Date(), status: "open" });
    if (S.v.oos !== false && l.status === "available") l.status = "maintenance";
    toast(`Repair logged for locker ${label(n)}`);
    S.v.repair = false; S.v.composing = false; S.v.reason = null; S.v.pick = null;
    render();
  },
  ticketFilter: (d) => { S.v.filter = d.k; render(); },
  ticketStatus: (d) => { setTicketStatus(D.tickets.find((t) => t.id === d.id), d.k); render(); },
  cancelBooking: (d) => {
    const b = D.bookings.find((x) => x.code === d.code);
    b.status = "cancelled";
    const l = locker(b.locker);
    if (l.status === "reserved") l.status = "available";
    toast(`Booking #${b.code} cancelled`);
    render();
  },
  extend: (d) => {
    const b = D.bookings.find((x) => x.code === d.code);
    const base = new Date(Math.max(b.returnDue, Date.now()));
    base.setDate(base.getDate() + 1);
    b.returnDue = base;
    toast(`Extended to ${fmtDayTime(base, true)}`);
    render();
  },
  adminReturned: (d) => {
    const b = D.bookings.find((x) => x.code === d.code);
    completeBooking(b, "return", "good");
    toast(`${b.item.name} marked as returned`);
    render();
  },
  hour: (d) => {
    const hrs = D.hours;
    if (d.k === "open") hrs.open = Math.min(hrs.close - 1, Math.max(0, hrs.open + +d.d));
    else hrs.close = Math.min(24, Math.max(hrs.open + 1, hrs.close + +d.d));
    render();
  },
  window: (d) => { D.hours.window = +d.k; render(); },
};

document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-act]");
  if (!el || el.disabled) return;
  ACT[el.dataset.act]?.(el.dataset, el, e);
});

// Text fields update state without re-rendering, so the keyboard stays up.
document.addEventListener("input", (e) => {
  const el = e.target.closest("[data-input]");
  if (!el) return;
  const key = el.dataset.input;
  if (key.startsWith("edit.")) {
    S.v.edit[key.slice(5)] = el.value;
    const save = $("#save-item");
    if (save) save.disabled = !S.v.edit.name.trim();
    return;
  }
  S.v[key] = el.value;
  if (S.screen.name === "newRequest") {
    const t = $("#pv-title");
    t.textContent = S.v.title || "Your request";
    t.style.color = S.v.title ? "var(--ink)" : "var(--secondary)";
    $("#pv-details").textContent = S.v.details;
    $("#post-btn").disabled = !S.v.title.trim();
  }
});

// Physical keyboard works on the keypads too (handy on a laptop).
document.addEventListener("keydown", (e) => {
  if (e.target.matches("input, textarea")) return;
  const k = /^\d$/.test(e.key) ? e.key : e.key === "Backspace" ? "delete" : e.key === "Enter" ? "enter" : null;
  if (!k) return;
  if (S.login) {
    if (k === "enter") ACT.loginNext(); else ACT.loginKey({ k });
  } else if (S.screen.name === "scan" && S.v.manual) {
    if (k === "enter") { if (S.v.digits.length === 6) ACT.findBooking(); } else ACT.scanKey({ k });
  }
});

// ---------- Idle timeout ----------

let lastTouch = Date.now();
const resetAfter = () => (isAdmin() ? 180 : 60);

function poke() {
  lastTouch = Date.now();
  if (S.idle) { S.idle = false; renderOverlay(); }
}
["pointerdown", "keydown", "wheel", "touchstart"].forEach((ev) => document.addEventListener(ev, poke, { capture: true, passive: true }));

setInterval(() => {
  const idle = (Date.now() - lastTouch) / 1000;
  if (S.screen.name === "locker") return; // never time out with a door open
  const atRest = S.screen.name === "home" && !customised() && !S.a11y && !S.profile && !S.login && !S.detail && !S.menu;
  if (idle >= resetAfter()) {
    S.idle = false; S.a11y = false; S.detail = null;
    resetSettings();
    endSession();
    lastTouch = Date.now();
    goHome();
  } else if (idle >= resetAfter() - 15 && !atRest) {
    if (!S.idle) {
      S.idle = true;
      renderOverlay();
      speak("Are you still there? Tap the screen to keep going.");
    } else {
      const c = $("#idle-count");
      if (c) c.textContent = Math.max(0, Math.round(resetAfter() - idle));
    }
  }

  // Live bits that tick without a full re-render.
  const timer = $("#open-timer");
  if (timer && S.v.openedAt) {
    const s = Math.floor((Date.now() - S.v.openedAt) / 1000);
    timer.textContent = `Open for ${Math.floor(s / 60)}:${pad2(s % 60)}`;
    timer.style.color = s > 120 ? "var(--warning)" : "";
  }
  if (S.screen.name === "done" && S.v.remaining > 0) {
    S.v.remaining -= 1;
    const ring = $("#ring");
    if (ring) ring.style.strokeDashoffset = 2 * Math.PI * 11.5 * (1 - S.v.remaining / 12);
    if (S.v.remaining === 0) finishSession();
  }
}, 1000);

setInterval(() => {
  if (S.screen.name !== "home") return;
  const clock = $(".clock");
  if (clock) clock.outerHTML = clockHTML();
}, 15000);

render();
