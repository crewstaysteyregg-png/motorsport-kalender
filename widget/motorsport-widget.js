// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-gray; icon-glyph: flag-checkered;

/* ==========================================================
   Motorsport Kalender – Race-Countdown-Widget für Scriptable
   Größen: mittel (Home-Bildschirm), Sperrbildschirm (rechteckig, rund, Zeile)
   Parameter (optional, im Widget unter „Parameter“):
     leer        -> alle Serien, nächste Session
     F1          -> nur Formel 1
     F1,DTM      -> mehrere Serien
                    Kürzel: F1, DTM, IMSA, GTWC, WEC, WRC, INDYCAR, NASCAR, MOTOGP
     race        -> Countdown nur bis zum nächsten Rennen (kombinierbar: F1,race)
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

// ---------- Parameter
const param = String(args.widgetParameter || '').toUpperCase().split(/[,; ]+/).filter(Boolean);
const onlyRace = param.includes('RACE') || param.includes('RENNEN');
let enabled = param.filter(p => SERIES[p]);
if (!enabled.length) enabled = Object.keys(SERIES);

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

function slots(events) {
  const out = [];
  for (const ev of events) {
    if (!enabled.includes(ev.series)) continue;
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

// ---------- Widgets
async function mediumWidget(data) {
  const w = new ListWidget();
  w.url = BASE_URL;
  w.setPadding(12, 16, 12, 12);
  const list = slots(data.events);
  const main = (onlyRace ? list.filter(x => x.s.type === 'race' || x.s.type === 'weekend') : list)[0];
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
  const now = new Date();
  if (main.start <= now && now < main.end) {
    const live = left.addText('● LIVE'); live.font = Font.heavySystemFont(26); live.textColor = new Color('#ff2d55');
  } else if (main.start - now < 864e5 && !main.allDay) {
    const d = left.addDate(main.start); d.applyTimerStyle(); d.font = Font.heavyMonospacedSystemFont(30); d.textColor = Color.white();
  } else {
    const d = left.addText(countdownText(main.start)); d.font = Font.heavySystemFont(28); d.textColor = Color.white(); d.minimumScaleFactor = 0.7; d.lineLimit = 1;
  }

  // --- rechte Spalte: nächste Sessions
  row.addSpacer(8);
  const right = row.addStack(); right.layoutVertically();
  const nt = right.addText('DANACH'); nt.font = Font.boldSystemFont(8); nt.textColor = new Color('#9a9aa3');
  right.addSpacer(4);
  const next = list.filter(x => x !== main).slice(0, 4);
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
  w.refreshAfterDate = new Date(Date.now() + 15 * 60e3);
  return w;
}

async function lockWidget(data, family) {
  const w = new ListWidget();
  w.url = BASE_URL;
  const list = slots(data.events);
  const main = (onlyRace ? list.filter(x => x.s.type === 'race' || x.s.type === 'weekend') : list)[0];
  if (!main) { w.addText('Keine Termine'); return w; }
  const now = new Date();
  const live = main.start <= now && now < main.end;
  const days = Math.floor((main.start - now) / 864e5);

  if (family === 'accessoryCircular') {
    w.addAccessoryWidgetBackground = true;
    const s = w.addText(SERIES[main.ev.series].short); s.font = Font.heavySystemFont(11); s.centerAlignText();
    if (live) { const t = w.addText('LIVE'); t.font = Font.heavySystemFont(14); t.centerAlignText(); }
    else if (days >= 1) { const t = w.addText(String(days)); t.font = Font.heavySystemFont(20); t.centerAlignText(); const u = w.addText(days === 1 ? 'Tag' : 'Tage'); u.font = Font.systemFont(9); u.centerAlignText(); }
    else { const t = w.addDate(main.start); t.applyTimerStyle(); t.font = Font.heavySystemFont(11); t.centerAlignText(); }
  } else if (family === 'accessoryInline') {
    const t = w.addText(live ? `${SERIES[main.ev.series].short} ${main.s.name}: LIVE` : `${SERIES[main.ev.series].short} ${main.s.name} in ${countdownText(main.start)}`);
    t.lineLimit = 1;
  } else {
    const a = w.addText(`${SERIES[main.ev.series].short} · ${shortName(main.ev.name)}`); a.font = Font.heavySystemFont(13); a.lineLimit = 1;
    const b = w.addText(`${main.s.name} · ${fmtShort(main)}`); b.font = Font.systemFont(11); b.lineLimit = 1;
    if (live) { const c = w.addText('● LIVE'); c.font = Font.heavySystemFont(16); }
    else if (days >= 1) { const c = w.addText(countdownText(main.start)); c.font = Font.heavySystemFont(16); }
    else { const c = w.addDate(main.start); c.applyTimerStyle(); c.font = Font.heavyMonospacedSystemFont(16); }
  }
  w.refreshAfterDate = new Date(Date.now() + 15 * 60e3);
  return w;
}

// ---------- Start
const data = await loadData();
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
