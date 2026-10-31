// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-gray; icon-glyph: flag-checkered;

/* ==========================================================
   Motorsport Kalender – Race-Countdown-Widget für Scriptable
   Größen: mittel (Home-Bildschirm), Sperrbildschirm (rechteckig, rund, Zeile)
   Einstellungen kommen aus der Web-App („Abo & Widget“ → „Ans Widget senden“):
   gewählte Serien, Countdown-Ziel und Push-Erinnerungen mit eigenem Vorlauf.
   Das Skript muss dafür in Scriptable „Motorsport“ heißen.

   Parameter (optional, im Widget unter „Parameter“) überschreibt die Serien-Auswahl,
   z. B. für ein zweites Widget nur für eine Serie:
     F1          -> nur Formel 1
     F1,DTM      -> mehrere Serien
                    Kürzel: F1, DTM, IMSA, GTWC, WEC, WRC, INDYCAR, NASCAR, MOTOGP
     race        -> Countdown nur bis zum nächsten Rennen (kombinierbar: F1,race)
     session     -> Countdown bis zur nächsten Session
   ========================================================== */

// >>> Hier die Adresse deiner GitHub-Pages-Seite eintragen (mit / am Ende):
const BASE_URL = 'https://DEIN-NAME.github.io/motorsport-kalender/';

const SERIES = {
  F1:      { name: 'Formel 1', short: 'F1', color: '#e10600', logo: 'f1.png' },
  DTM:     { name: 'DTM', short: 'DTM', color: '#f5c400', logo: 'dtm.png' },
  IMSA:    { name: 'IMSA', short: 'IMSA', color: '#2f7fff', logo: 'imsa.png' },
  GTWC:    { name: 'GTWC Europe', short: 'GTWC', color: '#ff9900', logo: 'gtwc.png' },
  WEC:     { name: 'FIA WEC', short: 'WEC', color: '#14b8a6', logo: 'wec.png', dark: true },
  WRC:     { name: 'Rallye-WM', short: 'WRC', color: '#a35cff', logo: 'wrc.png' },
  INDYCAR: { name: 'IndyCar', short: 'IndyCar', color: '#22d3ee', logo: 'indycar.png' },
  NASCAR:  { name: 'NASCAR Cup', short: 'NASCAR', color: '#8bd400', logo: 'nascar.png' },
  MOTOGP:  { name: 'MotoGP', short: 'MotoGP', color: '#ff5aa5', logo: 'motogp.png' }
};

const fm = FileManager.local();
const CACHE = fm.joinPath(fm.cacheDirectory(), 'motorsport-kalender');
if (!fm.fileExists(CACHE)) fm.createDirectory(CACHE, true);

// ---------- Einstellungen
// Standardwerte; die Web-App setzt hier beim Kopieren deine aktuelle Auswahl ein.
const DEFAULT_SETTINGS = { series: [], target: 'session', notify: { on: false, minutes: [15], types: 'all' } };
const SETTINGS_FILE = fm.joinPath(fm.documentsDirectory(), 'motorsport-kalender-settings.json');

function normalizeSettings(s) {
  s = s || {};
  const n = s.notify || {};
  return {
    series: (Array.isArray(s.series) ? s.series : []).map(x => String(x).toUpperCase()).filter(x => SERIES[x]),
    target: s.target === 'race' ? 'race' : 'session',
    notify: {
      on: !!n.on,
      minutes: (Array.isArray(n.minutes) ? n.minutes : [15]).map(Number).filter(m => m >= 0 && m <= 10080).slice(0, 6),
      types: ['all', 'quali_race', 'race'].includes(n.types) ? n.types : 'all'
    }
  };
}

let settings = normalizeSettings(DEFAULT_SETTINGS);
try { if (fm.fileExists(SETTINGS_FILE)) settings = normalizeSettings(JSON.parse(fm.readString(SETTINGS_FILE))); } catch (e) { /* Standard */ }

// Aufruf aus der Web-App: scriptable:///run/Motorsport?cfg={...}
const query = args.queryParameters || {};
let justSaved = false;
if (query.cfg) {
  try {
    settings = normalizeSettings(JSON.parse(query.cfg));
    fm.writeString(SETTINGS_FILE, JSON.stringify(settings));
    justSaved = true;
  } catch (e) { /* ungültig, alte Einstellungen bleiben */ }
}

// Widget-Parameter hat Vorrang vor der Auswahl aus der App
const param = String(args.widgetParameter || '').toUpperCase().split(/[,; ]+/).filter(Boolean);
const paramSeries = param.filter(p => SERIES[p]);
let enabled = paramSeries.length ? paramSeries : settings.series;
if (!enabled.length) enabled = Object.keys(SERIES);
const onlyRace = param.includes('RACE') || param.includes('RENNEN') || (settings.target === 'race' && !param.includes('SESSION'));

// ---------- Daten laden (mit Offline-Cache)
async function loadData() {
  const file = fm.joinPath(CACHE, 'events.json');
  try {
    const req = new Request(BASE_URL + 'data/events.json?t=' + Date.now());
    req.timeoutInterval = 15;
    const json = await req.loadJSON();
    if (!json || !json.events) throw new Error('leer');
    fm.writeString(file, JSON.stringify(json));
    return json;
  } catch (e) {
    if (fm.fileExists(file)) return JSON.parse(fm.readString(file));
    return null;
  }
}

async function loadLogo(series) {
  const file = fm.joinPath(CACHE, SERIES[series].logo);
  if (fm.fileExists(file) && (Date.now() - fm.modificationDate(file).getTime()) < 7 * 864e5) return fm.readImage(file);
  try {
    const img = await new Request(BASE_URL + 'assets/logos/' + SERIES[series].logo).loadImage();
    fm.writeImage(file, img);
    return img;
  } catch (e) {
    return fm.fileExists(file) ? fm.readImage(file) : null;
  }
}

function localMidnight(key) { const [y, m, d] = key.split('-').map(Number); return new Date(y, m - 1, d); }

function slots(events, series = enabled) {
  const out = [];
  for (const ev of events) {
    if (!series.includes(ev.series)) continue;
    if (ev.sessions && ev.sessions.length) {
      for (const s of ev.sessions) {
        if (s.allDay) {
          const end = localMidnight(s.end); end.setDate(end.getDate() + 1);
          out.push({ ev, s, start: localMidnight(s.start), end, allDay: true });
        } else {
          out.push({ ev, s, start: new Date(s.start), end: new Date(s.end), allDay: false });
        }
      }
    } else {
      const end = localMidnight(ev.end); end.setDate(end.getDate() + 1);
      out.push({ ev, s: { name: 'Rennwochenende', type: 'weekend' }, start: localMidnight(ev.start), end, allDay: true });
    }
  }
  const now = new Date();
  return out.filter(x => x.end > now).sort((a, b) => a.start - b.start);
}

// ---------- Formatierung
const df = new DateFormatter(); df.locale = 'de_AT';
function fmtWhen(x) {
  if (x.allDay) { df.dateFormat = 'EE dd.MM.'; return df.string(x.start) + ' · Zeitplan folgt'; }
  df.dateFormat = 'EE dd.MM. HH:mm'; return df.string(x.start) + ' Uhr';
}
function fmtShort(x) {
  if (x.allDay) { df.dateFormat = 'dd.MM.'; return df.string(x.start); }
  df.dateFormat = 'EE HH:mm'; return df.string(x.start);
}
function countdownText(target) {
  let t = Math.max(0, Math.floor((target - new Date()) / 1000));
  const d = Math.floor(t / 86400); t %= 86400;
  const h = Math.floor(t / 3600); t %= 3600;
  const m = Math.floor(t / 60);
  if (d > 0) return `${d} T ${String(h).padStart(2, '0')} Std`;
  return `${h} Std ${String(m).padStart(2, '0')} Min`;
}
function shortName(n) { return n.replace(/Grand Prix/i, 'GP').replace(/^\d+(st|nd|rd|th) Annual /i, ''); }

// ---------- Carbon-Hintergrund
function carbon(w, h, accent) {
  const dc = new DrawContext();
  dc.size = new Size(w, h); dc.opaque = true; dc.respectScreenScale = true;
  dc.setFillColor(new Color('#111113')); dc.fillRect(new Rect(0, 0, w, h));
  const c = 8;
  const shades = ['#1d1d20', '#161618', '#242428', '#19191c'];
  for (let y = 0; y < h; y += c) {
    for (let x = 0; x < w; x += c) {
      const alt = ((x / c) + (y / c)) % 2 === 0;
      for (let i = 0; i < 4; i++) {
        dc.setFillColor(new Color(shades[(i + (alt ? 0 : 2)) % 4]));
        if (alt) dc.fillRect(new Rect(x, y + i * c / 4, c, c / 4));
        else dc.fillRect(new Rect(x + i * c / 4, y, c / 4, c));
      }
    }
  }
  // Glanz von links oben
  for (let i = 0; i < 24; i++) {
    dc.setFillColor(new Color('#ffffff', 0.012));
    dc.fillRect(new Rect(0, 0, w * (1 - i / 24), h * (1 - i / 24)));
  }
  dc.setFillColor(new Color(accent)); dc.fillRect(new Rect(0, 0, 5, h));
  return dc.getImage();
}

function logoBox(stack, img, w, h, dark) {
  const box = stack.addStack();
  box.size = new Size(w, h);
  box.backgroundColor = dark ? new Color('#0d0d0f') : Color.white();
  box.cornerRadius = 7;
  box.centerAlignContent();
  if (img) { const i = box.addImage(img); i.imageSize = new Size(w - 6, h - 6); i.applyFittingContentMode(); }
  return box;
}

// ---------- Countdown-Ziel
// Der Countdown läuft immer zum nächsten Event, das noch NICHT begonnen hat.
function pickTargets(list) {
  const now = new Date();
  const pool = onlyRace ? list.filter(x => x.s.type === 'race' || x.s.type === 'weekend') : list;
  return { next: pool.find(x => x.start > now) || null };
}

// Widget genau beim Start neu laden lassen, damit der iOS-Timer danach nicht hochzählt,
// sondern gleich zum nächsten Event wechselt.
function nextRefresh(next) {
  const now = Date.now();
  const marks = [now + 15 * 60e3];
  if (next) marks.push(next.start.getTime() + 15e3);
  return new Date(Math.max(now + 60e3, Math.min(...marks)));
}

function addCountdown(stack, target, size) {
  const diff = target.start - new Date();
  if (!target.allDay && diff < 864e5) {
    const d = stack.addDate(target.start); d.applyTimerStyle();
    d.font = Font.heavyMonospacedSystemFont(size); d.textColor = Color.white();
    return d;
  }
  const d = stack.addText(countdownText(target.start));
  d.font = Font.heavySystemFont(size - 2); d.textColor = Color.white(); d.minimumScaleFactor = 0.7; d.lineLimit = 1;
  return d;
}

// ---------- Widgets
async function mediumWidget(data) {
  const w = new ListWidget();
  w.url = BASE_URL;
  w.setPadding(12, 16, 12, 12);
  const list = slots(data.events);
  const { next: main } = pickTargets(list);
  w.refreshAfterDate = nextRefresh(main);
  if (!main) {
    w.backgroundImage = carbon(338, 158, '#555');
    const t = w.addText('Keine kommenden Termine'); t.textColor = Color.white(); t.font = Font.semiboldSystemFont(14);
    return w;
  }
  const col = new Color(SERIES[main.ev.series].color);
  w.backgroundImage = carbon(338, 158, SERIES[main.ev.series].color);

  const row = w.addStack(); row.layoutHorizontally();
  // --- linke Spalte
  const left = row.addStack(); left.layoutVertically(); left.size = new Size(186, 0);
  const head = left.addStack(); head.layoutHorizontally(); head.centerAlignContent();
  logoBox(head, await loadLogo(main.ev.series), 46, 30, SERIES[main.ev.series].dark);
  head.addSpacer(8);
  const hs = head.addStack(); hs.layoutVertically();
  const lab = hs.addText('RACE COUNTDOWN'); lab.font = Font.boldSystemFont(8); lab.textColor = new Color('#9a9aa3');
  const ser = hs.addText(SERIES[main.ev.series].name.toUpperCase() + (main.ev.cup ? ' · ' + main.ev.cup.toUpperCase() : ''));
  ser.font = Font.heavySystemFont(10); ser.textColor = col; ser.lineLimit = 1;
  left.addSpacer(6);
  const ev = left.addText(shortName(main.ev.name).toUpperCase()); ev.font = Font.heavySystemFont(15); ev.textColor = Color.white(); ev.lineLimit = 1; ev.minimumScaleFactor = 0.7;
  const se = left.addText(main.s.name + ' · ' + fmtWhen(main)); se.font = Font.mediumSystemFont(10); se.textColor = new Color('#c9ccd2'); se.lineLimit = 1; se.minimumScaleFactor = 0.8;
  left.addSpacer();
  addCountdown(left, main, 30);

  // --- rechte Spalte: die folgenden Sessions
  row.addSpacer(8);
  const right = row.addStack(); right.layoutVertically();
  const nt = right.addText('DANACH'); nt.font = Font.boldSystemFont(8); nt.textColor = new Color('#9a9aa3');
  right.addSpacer(4);
  const now = new Date();
  const next = list.filter(x => x !== main && x.start > now && x.start >= main.start).slice(0, 4);
  for (const x of next) {
    const r = right.addStack(); r.layoutHorizontally(); r.centerAlignContent();
    const bar = r.addStack(); bar.size = new Size(3, 22); bar.backgroundColor = new Color(SERIES[x.ev.series].color); bar.cornerRadius = 1.5;
    r.addSpacer(5);
    const tx = r.addStack(); tx.layoutVertically();
    const a = tx.addText(`${SERIES[x.ev.series].short} · ${x.s.name}`); a.font = Font.semiboldSystemFont(9); a.textColor = Color.white(); a.lineLimit = 1;
    const b = tx.addText(fmtShort(x)); b.font = Font.systemFont(9); b.textColor = new Color('#9a9aa3'); b.lineLimit = 1;
    right.addSpacer(4);
  }
  right.addSpacer();
  return w;
}

async function lockWidget(data, family) {
  const w = new ListWidget();
  w.url = BASE_URL;
  const list = slots(data.events);
  const { next: main } = pickTargets(list);
  w.refreshAfterDate = nextRefresh(main);
  if (!main) { w.addText('Keine Termine'); return w; }
  const now = new Date();
  const days = Math.floor((main.start - now) / 864e5);
  const short = SERIES[main.ev.series].short;

  if (family === 'accessoryCircular') {
    w.addAccessoryWidgetBackground = true;
    const s = w.addText(short); s.font = Font.heavySystemFont(11); s.centerAlignText();
    if (days >= 1) { const t = w.addText(String(days)); t.font = Font.heavySystemFont(20); t.centerAlignText(); const u = w.addText(days === 1 ? 'Tag' : 'Tage'); u.font = Font.systemFont(9); u.centerAlignText(); }
    else { const t = w.addDate(main.start); t.applyTimerStyle(); t.font = Font.heavySystemFont(11); t.centerAlignText(); }
  } else if (family === 'accessoryInline') {
    const t = w.addText(`${short} ${main.s.name} in ${countdownText(main.start)}`);
    t.lineLimit = 1;
  } else {
    const a = w.addText(`${short} · ${shortName(main.ev.name)}`); a.font = Font.heavySystemFont(13); a.lineLimit = 1;
    const b = w.addText(`${main.s.name} · ${fmtShort(main)}`); b.font = Font.systemFont(11); b.lineLimit = 1;
    addCountdown(w, main, 16);
  }
  return w;
}

// ---------- Push-Erinnerungen (lokal am iPhone geplant, kein Server nötig)
const THREAD = 'motorsport-kalender';

function fmtLead(m) {
  if (m === 0) return 'jetzt';
  if (m % 1440 === 0) return m === 1440 ? '1 Tag' : `${m / 1440} Tagen`;
  if (m % 60 === 0) return m === 60 ? '1 Stunde' : `${m / 60} Stunden`;
  if (m > 60) return `${Math.floor(m / 60)} Std ${m % 60} Min`;
  return `${m} Minuten`;
}

function wantsType(type) {
  const t = settings.notify.types;
  if (t === 'race') return type === 'race';
  if (t === 'quali_race') return ['quali', 'sprintquali', 'sprint', 'race'].includes(type);
  return true;
}

async function scheduleNotifications(events) {
  // alte Erinnerungen dieses Kalenders entfernen und neu planen
  try {
    const pending = (await Notification.allPending()).filter(x => x.threadIdentifier === THREAD);
    if (pending.length) await Notification.removePending(pending.map(x => x.identifier));
  } catch (e) { /* nichts geplant */ }
  if (!settings.notify.on || !settings.notify.minutes.length) return 0;

  const now = Date.now();
  const horizon = now + 8 * 864e5;
  const items = [];
  // Erinnerungen immer für die Auswahl aus der App, nicht für den Parameter eines einzelnen Widgets
  const series = settings.series.length ? settings.series : Object.keys(SERIES);
  for (const x of slots(events, series)) {
    if (x.allDay || !wantsType(x.s.type)) continue;
    for (const m of settings.notify.minutes) {
      const t = x.start.getTime() - m * 60e3;
      if (t > now + 30e3 && t < horizon) items.push({ x, m, t });
    }
  }
  items.sort((a, b) => a.t - b.t);
  const dfT = new DateFormatter(); dfT.locale = 'de_AT'; dfT.dateFormat = 'HH:mm';
  let count = 0;
  for (const { x, m, t } of items.slice(0, 40)) {   // iOS erlaubt max. 64 geplante Mitteilungen
    const n = new Notification();
    n.identifier = `mk-${x.s.id || x.ev.id}-${m}`;
    n.threadIdentifier = THREAD;
    n.title = `🏁 ${SERIES[x.ev.series].short} · ${shortName(x.ev.name)}`;
    n.body = m === 0 ? `${x.s.name} startet jetzt.` : `${x.s.name} startet in ${fmtLead(m)} (${dfT.string(x.start)} Uhr).`;
    n.openURL = BASE_URL;
    n.sound = 'default';
    n.setTriggerDate(new Date(t));
    try { await n.schedule(); count++; } catch (e) { /* keine Berechtigung */ }
  }
  return count;
}

// ---------- Start
const data = await loadData();
let planned = 0;
if (data) planned = await scheduleNotifications(data.events);

if (justSaved && !config.runsInWidget && !config.runsInAccessoryWidget) {
  const a = new Alert();
  a.title = 'Einstellungen übernommen';
  const ser = settings.series.length ? settings.series.map(s => SERIES[s].short).join(', ') : 'alle';
  const push = settings.notify.on
    ? `${settings.notify.minutes.map(fmtLead).join(' + ')} vorher · ${planned} Erinnerungen für die nächsten Tage geplant`
    : 'aus';
  a.message = `Serien: ${ser}\nCountdown: ${settings.target === 'race' ? 'nächstes Rennen' : 'nächste Session'}\nPush: ${push}`;
  a.addAction('OK');
  await a.present();
}

let widget;
if (!data) {
  widget = new ListWidget();
  widget.backgroundColor = new Color('#111113');
  const t = widget.addText('Keine Daten – BASE_URL im Skript prüfen.');
  t.textColor = Color.white(); t.font = Font.mediumSystemFont(12);
} else {
  const fam = config.widgetFamily || 'medium';
  widget = fam.startsWith('accessory') ? await lockWidget(data, fam) : await mediumWidget(data);
}

if (config.runsInWidget || config.runsInAccessoryWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentMedium();
}
Script.complete();
