/* Motorsport Kalender – Web-App (kein Build-Schritt nötig) */
(function () {
  'use strict';

  const TZ = 'Europe/Vienna';
  const SERIES = {
    F1:   { name: 'Formel 1', short: 'F1', color: 'var(--f1)', logo: 'assets/logos/f1.svg', bg: 'dark' },
    DTM:  { name: 'DTM', short: 'DTM', color: 'var(--dtm)', logo: 'assets/logos/dtm.png', bg: 'cover' },
    IMSA: { name: 'IMSA WeatherTech', short: 'IMSA', color: 'var(--imsa)', logo: 'assets/logos/imsa.png', bg: 'dark' },
    GTWC: { name: 'GT World Challenge Europe', short: 'GTWC', color: 'var(--gtwc)', logo: 'assets/logos/gtwc.svg', bg: 'dark' },
    WEC: { name: 'FIA WEC', short: 'WEC', color: 'var(--wec)', logo: 'assets/logos/wec.png', bg: 'dark' },
    WRC: { name: 'Rallye-WM (WRC)', short: 'WRC', color: 'var(--wrc)', logo: 'assets/logos/wrc.png', bg: 'light' },
    INDYCAR: { name: 'IndyCar', short: 'IndyCar', color: 'var(--indycar)', logo: 'assets/logos/indycar.png', bg: 'light' },
    NASCAR: { name: 'NASCAR Cup Series', short: 'NASCAR', color: 'var(--nascar)', logo: 'assets/logos/nascar.png', bg: 'light' },
    MOTOGP: { name: 'MotoGP', short: 'MotoGP', color: 'var(--motogp)', logo: 'assets/logos/motogp.png', bg: 'light' }
  };
  const ORDER = Object.keys(SERIES);

  const COLS = {
    pos: 'Pos', pic: 'Kl.', no: '#', cls: 'Klasse', driver: 'Fahrer', team: 'Team', car: 'Fahrzeug',
    laps: 'Runden', time: 'Zeit', gap: 'Abstand', best: 'Schnellste Rd.', q1: 'Q1', q2: 'Q2', q3: 'Q3',
    grid: 'Start', pts: 'Punkte', status: 'Status'
  };

  const state = {
    events: [], meta: null, standings: null, results: {},
    enabled: load('mk.series', ORDER.slice()),
    view: load('mk.view', 'list'),
    target: load('mk.target', 'session'),
    month: null, selDay: null,
    resSeries: null, resEvent: null, resSession: 0, resClass: '',
    stSeries: null, stTable: 0
  };

  // Neu hinzugekommene Serien automatisch einblenden (auch bei gespeicherter Auswahl)
  (function () {
    const known = load('mk.known', ['F1', 'DTM', 'IMSA', 'GTWC']);
    ORDER.forEach(k => { if (!known.includes(k) && !state.enabled.includes(k)) state.enabled.push(k); });
    state.enabled = state.enabled.filter(k => SERIES[k]);
    save('mk.known', ORDER); save('mk.series', state.enabled);
  })();

  // ------------------------------------------------------------ Helpers
  function load(k, def) { try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : def; } catch (e) { return def; } }
  function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* privat */ } }
  const $ = (s, el) => (el || document).querySelector(s);
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }

  const fmt = (o) => new Intl.DateTimeFormat('de-AT', Object.assign({ timeZone: TZ }, o));
  const fDay = fmt({ weekday: 'short', day: '2-digit', month: '2-digit' });
  const fTime = fmt({ hour: '2-digit', minute: '2-digit' });
  const fFull = fmt({ weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  const fKey = fmt({ year: 'numeric', month: '2-digit', day: '2-digit' });
  const fMonth = new Intl.DateTimeFormat('de-AT', { month: 'long', year: 'numeric', timeZone: 'UTC' });
  const fDateUtc = new Intl.DateTimeFormat('de-AT', { weekday: 'short', day: '2-digit', month: '2-digit', timeZone: 'UTC' });
  const fDateLong = new Intl.DateTimeFormat('de-AT', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });

  function viennaKey(d) {
    const p = {}; fKey.formatToParts(d).forEach(x => { p[x.type] = x.value; });
    return `${p.year}-${p.month}-${p.day}`;
  }
  const dateOnly = (s) => new Date(s + 'T00:00:00Z');
  function addDays(key, n) { const d = dateOnly(key); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
  // Mitternacht Wiener Zeit für ein Datum (für Countdown zu Wochenenden ohne Zeitplan)
  function viennaMidnight(key) {
    const guess = new Date(key + 'T00:00:00Z');
    const h = Number(fmt({ hour: '2-digit', hourCycle: 'h23' }).format(guess));
    return new Date(guess.getTime() - (h >= 12 ? h - 24 : h) * 3600e3);
  }

  function logo(series, cls) {
    const s = SERIES[series];
    return `<span class="logo ${s.bg === 'dark' ? 'logo--dark' : ''} ${cls || ''}" style="${s.bg === 'cover' ? 'background:#f5c400' : ''}"><img src="${s.logo}" alt="${esc(s.name)}" loading="lazy"></span>`;
  }

  function dateRange(ev) {
    const a = dateOnly(ev.start), b = dateOnly(ev.end);
    const d1 = a.getUTCDate(), d2 = b.getUTCDate();
    const m = (d) => new Intl.DateTimeFormat('de-AT', { month: 'short', timeZone: 'UTC' }).format(d);
    if (ev.start === ev.end) return `${d2}. ${m(b)}`;
    if (a.getUTCMonth() === b.getUTCMonth()) return `${d1}.–${d2}. ${m(b)}`;
    return `${d1}. ${m(a)} – ${d2}. ${m(b)}`;
  }

  // ------------------------------------------------------------ Daten
  async function getJson(url) {
    const r = await fetch(url + (url.includes('?') ? '&' : '?') + 'v=' + Math.floor(Date.now() / 6e5), { cache: 'no-cache' });
    if (!r.ok) throw new Error(url + ': ' + r.status);
    return r.json();
  }

  async function init() {
    bindStatic();
    try {
      const [ev, meta, st] = await Promise.all([getJson('data/events.json'), getJson('data/meta.json').catch(() => null), getJson('data/standings.json').catch(() => ({}))]);
      state.events = ev.events || [];
      state.meta = meta;
      state.standings = st || {};
      const u = new Date(ev.updated);
      $('#updated').textContent = 'Aktualisiert: ' + fDay.format(u) + ', ' + fTime.format(u) + ' Uhr';
    } catch (e) {
      $('#updated').textContent = 'Daten konnten nicht geladen werden.';
      console.error(e);
    }
    renderFilters();
    renderFooter();
    setView(state.view);
    tick();
    setInterval(tick, 1000);
  }

  function visibleEvents() { return state.events.filter(e => state.enabled.includes(e.series)); }

  // Alle Termine als Einzel-Einträge (Sessions bzw. Wochenende ohne Zeitplan)
  function slots(events) {
    const out = [];
    for (const ev of events) {
      if (ev.sessions && ev.sessions.length) {
        for (const s of ev.sessions) {
          if (s.allDay) out.push({ ev, s, start: viennaMidnight(s.start), end: viennaMidnight(addDays(s.end, 1)), allDay: true });
          else out.push({ ev, s, start: new Date(s.start), end: new Date(s.end), allDay: false });
        }
      } else {
        out.push({ ev, s: { name: 'Rennwochenende', type: 'weekend' }, start: viennaMidnight(ev.start), end: viennaMidnight(addDays(ev.end, 1)), allDay: true });
      }
    }
    return out.sort((a, b) => a.start - b.start);
  }

  // ------------------------------------------------------------ Filter
  function renderFilters() {
    const el = $('#filters');
    el.innerHTML = ORDER.map(k => {
      const on = state.enabled.includes(k);
      return `<button class="chip ${on ? 'is-on' : 'is-off'}" data-series="${k}" style="--c:${SERIES[k].color}" aria-pressed="${on}">${logo(k)}${esc(SERIES[k].short)}</button>`;
    }).join('');
    el.querySelectorAll('.chip').forEach(b => b.addEventListener('click', () => {
      const k = b.dataset.series;
      const i = state.enabled.indexOf(k);
      if (i >= 0) { if (state.enabled.length > 1) state.enabled.splice(i, 1); } else state.enabled.push(k);
      save('mk.series', state.enabled);
      renderFilters();
      lastHeroKey = '';
      tick();
      renderView();
    }));
  }

  // ------------------------------------------------------------ Countdown
  let lastHeroKey = '';
  function nextSlot() {
    const now = Date.now();
    let list = slots(visibleEvents()).filter(x => x.end > now);
    if (state.target === 'race') list = list.filter(x => x.s.type === 'race' || x.s.type === 'weekend');
    return list[0] || null;
  }

  function tick() {
    const body = $('#heroBody');
    const n = nextSlot();
    const hero = $('#hero');
    if (!n) {
      if (lastHeroKey !== 'none') { body.innerHTML = '<p class="empty">Keine kommenden Termine für die gewählten Serien.</p>'; lastHeroKey = 'none'; }
      return;
    }
    const key = (n.s.id || n.ev.id) + state.target;
    const now = Date.now();
    const live = n.start <= now && now < n.end;
    if (key !== lastHeroKey) {
      lastHeroKey = key;
      hero.style.setProperty('--c', SERIES[n.ev.series].color);
      const when = n.allDay
        ? `${dateRange(n.ev)} · Zeitplan folgt`
        : `${fFull.format(n.start)} Uhr`;
      body.innerHTML = `
        ${logo(n.ev.series, 'hero__logo')}
        <div style="--c:${SERIES[n.ev.series].color}">
          <div class="hero__series">${esc(SERIES[n.ev.series].name)}${n.ev.cup ? ' · ' + esc(n.ev.cup) : ''}</div>
          <div class="hero__event">${esc(n.ev.name)}</div>
          <div class="hero__meta"><strong>${esc(n.s.name)}</strong> · ${esc(when)}${n.ev.circuit && n.ev.circuit !== n.ev.name ? ' · ' + esc(n.ev.circuit) : ''}</div>
        </div>
        <div class="countdown" id="cd"></div>`;
    }
    const cd = $('#cd');
    if (live) { cd.innerHTML = '<span class="live">Live</span>'; return; }
    let t = Math.max(0, Math.floor((n.start - now) / 1000));
    const d = Math.floor(t / 86400); t %= 86400;
    const h = Math.floor(t / 3600); t %= 3600;
    const m = Math.floor(t / 60); const s = t % 60;
    const p = (x) => String(x).padStart(2, '0');
    cd.innerHTML = [[d, 'Tage'], [p(h), 'Std'], [p(m), 'Min'], [p(s), 'Sek']]
      .map(([v, l]) => `<div class="cd"><div class="cd__n">${v}</div><div class="cd__l">${l}</div></div>`).join('');
  }

  // ------------------------------------------------------------ Views
  function setView(v) {
    state.view = v; save('mk.view', v);
    document.querySelectorAll('.tab').forEach(t => t.classList.toggle('is-on', t.dataset.view === v));
    document.querySelectorAll('.view').forEach(s => { s.hidden = s.id !== 'view-' + v; });
    renderView();
  }
  function renderView() {
    ({ list: renderList, month: renderMonth, results: renderResults, standings: renderStandings, sync: renderSync })[state.view]();
  }

  // ---------- Termine
  function eventCard(ev) {
    const now = Date.now();
    const c = SERIES[ev.series].color;
    let rows = '';
    if (ev.sessions && ev.sessions.length) {
      rows = '<ul class="sessions">' + ev.sessions.map(s => {
        if (s.allDay) {
          return `<li><span class="when">${fDateUtc.format(dateOnly(s.start))}</span><span>${esc(s.name)}</span><span class="time">–</span></li>`;
        }
        const st = new Date(s.start), en = new Date(s.end);
        const past = en < now, live = st <= now && now < en;
        return `<li class="${past ? 'is-past' : ''}"><span class="when">${fDay.format(st)}</span><span class="${s.type === 'race' ? 'type-race' : ''}">${esc(s.name)} ${live ? '<span class="live">Live</span>' : ''}</span><span class="time">${fTime.format(st)}</span></li>`;
      }).join('') + '</ul>';
    } else {
      rows = '<p class="note">Zeitplan folgt – die Session-Zeiten werden eingetragen, sobald sie veröffentlicht sind.</p>';
    }
    const first = slots([ev])[0];
    const days = Math.ceil((first.start - now) / 864e5);
    const badge = days > 1 ? `in <b>${days} Tagen</b>` : days === 1 ? '<b>morgen</b>' : (slots([ev]).some(x => x.end > now) ? '<b>läuft</b>' : '<b>vorbei</b>');
    return `<article class="card" style="--c:${c}">
      <div class="card__head">${logo(ev.series)}
        <div><h3 class="card__title">${esc(ev.name)}${ev.cup ? `<span class="cup">${esc(ev.cup)}</span>` : ''}</h3>
        <div class="card__sub">${esc(dateRange(ev))}${ev.circuit && ev.circuit !== ev.name ? ' · ' + esc(ev.circuit) : ''}${ev.location ? ' · ' + esc(ev.location) : ''}</div></div>
        <div class="card__badge">${badge}</div>
      </div>${rows}</article>`;
  }

  function renderList() {
    const el = $('#view-list');
    const evs = visibleEvents().filter(e => slots([e]).some(x => x.end > Date.now() - 864e5));
    if (!evs.length) { el.innerHTML = '<p class="empty">Keine Termine.</p>'; return; }
    let html = '', cur = '';
    let buf = [];
    const flush = () => { if (buf.length) html += `<div class="events">${buf.join('')}</div>`; buf = []; };
    for (const ev of evs) {
      const m = fMonth.format(dateOnly(ev.start));
      if (m !== cur) { flush(); html += `<h2 class="month-label">${esc(m)}</h2>`; cur = m; }
      buf.push(eventCard(ev));
    }
    flush();
    el.innerHTML = html;
  }

  // ---------- Monatskalender
  function renderMonth() {
    const el = $('#view-month');
    const todayKey = viennaKey(new Date());
    if (!state.month) state.month = todayKey.slice(0, 7);
    const [y, m] = state.month.split('-').map(Number);
    const first = new Date(Date.UTC(y, m - 1, 1));
    const offset = (first.getUTCDay() + 6) % 7;
    const start = new Date(Date.UTC(y, m - 1, 1 - offset));

    const byDay = {};
    for (const x of slots(visibleEvents())) {
      if (x.allDay) {
        const a = x.s.start || x.ev.start, b = x.s.end || x.ev.end;
        for (let k = a; k <= b; k = addDays(k, 1)) (byDay[k] = byDay[k] || []).push(x);
      } else {
        const k = viennaKey(x.start); (byDay[k] = byDay[k] || []).push(x);
      }
    }

    let cells = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'].map(d => `<div class="dow">${d}</div>`).join('');
    for (let i = 0; i < 42; i++) {
      const d = new Date(start.getTime() + i * 864e5);
      const k = d.toISOString().slice(0, 10);
      const items = byDay[k] || [];
      const other = d.getUTCMonth() !== m - 1;
      if (i === 35 && other) break; // 6. Zeile nur, wenn der Monat sie braucht
      const pills = items.slice(0, 4).map(x => `<div class="pill" style="--c:${SERIES[x.ev.series].color}" title="${esc(x.ev.name + ' · ' + x.s.name)}">${esc(SERIES[x.ev.series].short)} ${x.allDay ? esc(x.ev.name) : fTime.format(x.start) + ' ' + esc(x.s.name)}</div>`).join('')
        + (items.length > 4 ? `<div class="pill" style="--c:#555">+${items.length - 4} weitere</div>` : '');
      const series = [...new Set(items.map(x => x.ev.series))];
      const dots = series.map(s => `<span class="dot" style="--c:${SERIES[s].color}"></span>`).join('');
      cells += `<button class="day ${other ? 'is-other' : ''} ${k === todayKey ? 'is-today' : ''} ${k === state.selDay ? 'is-sel' : ''}" data-day="${k}">
        <span class="day__n">${d.getUTCDate()}</span>${pills}<span class="dots">${dots}</span></button>`;
    }

    const sel = state.selDay && byDay[state.selDay];
    let detail = '';
    if (state.selDay) {
      const evIds = [...new Set((sel || []).map(x => x.ev.id))];
      const evs = evIds.map(id => state.events.find(e => e.id === id));
      detail = `<div class="day-detail"><h2 class="month-label">${esc(fDateLong.format(dateOnly(state.selDay)))}</h2>${evs.length ? `<div class="events">${evs.map(eventCard).join('')}</div>` : '<p class="empty">Keine Termine an diesem Tag.</p>'}</div>`;
    }

    el.innerHTML = `<div class="cal-head"><h2 class="cal-title">${esc(fMonth.format(first))}</h2>
      <div class="cal-nav"><button class="btn btn--icon" data-nav="-1" aria-label="Vorheriger Monat">‹</button><button class="btn" data-nav="0">Heute</button><button class="btn btn--icon" data-nav="1" aria-label="Nächster Monat">›</button></div></div>
      <div class="grid">${cells}</div>${detail}`;

    el.querySelectorAll('[data-nav]').forEach(b => b.addEventListener('click', () => {
      const n = Number(b.dataset.nav);
      if (n === 0) { state.month = todayKey.slice(0, 7); state.selDay = todayKey; }
      else { const d = new Date(Date.UTC(y, m - 1 + n, 1)); state.month = d.toISOString().slice(0, 7); state.selDay = null; }
      renderMonth();
    }));
    el.querySelectorAll('.day').forEach(b => b.addEventListener('click', () => {
      state.selDay = state.selDay === b.dataset.day ? null : b.dataset.day; renderMonth();
    }));
  }

  // ---------- Ergebnisse
  async function renderResults() {
    const el = $('#view-results');
    const list = ORDER.filter(k => state.enabled.includes(k));
    if (!state.resSeries || !list.includes(state.resSeries)) state.resSeries = list[0];
    const sk = state.resSeries;
    if (!state.results[sk]) {
      el.innerHTML = '<p class="empty">Lade Ergebnisse …</p>';
      try { state.results[sk] = await getJson(`data/results/${sk.toLowerCase()}.json`); }
      catch (e) { el.innerHTML = '<p class="empty">Ergebnisse konnten nicht geladen werden.</p>'; return; }
      if (state.view !== 'results' || state.resSeries !== sk) return;
    }
    const evs = (state.results[sk].events || []).slice().sort((a, b) => String(b.date).localeCompare(String(a.date)));
    const seriesBtns = `<div class="pills">${list.map(k => `<button class="pillbtn ${k === sk ? 'is-on' : ''}" data-rs="${k}">${esc(SERIES[k].short)}</button>`).join('')}</div>`;
    if (!evs.length) { el.innerHTML = `<div class="toolbar">${seriesBtns}</div><p class="empty">Noch keine Ergebnisse.</p>`; bindRes(el); return; }
    if (!state.resEvent || !evs.find(e => e.id === state.resEvent)) { state.resEvent = evs[0].id; state.resSession = -1; }
    const ev = evs.find(e => e.id === state.resEvent);
    if (state.resSession < 0 || state.resSession >= ev.sessions.length) {
      const lastRace = ev.sessions.map(s => s.type).lastIndexOf('race');
      state.resSession = lastRace >= 0 ? lastRace : ev.sessions.length - 1;
    }
    const sess = ev.sessions[state.resSession];
    const classes = [...new Set(sess.rows.map(r => r.cls).filter(Boolean))];
    if (state.resClass && !classes.includes(state.resClass)) state.resClass = '';
    const rows = state.resClass ? sess.rows.filter(r => r.cls === state.resClass) : sess.rows;
    const keys = ['pos'].concat((state.resClass ? [] : ['pic']), ['no', 'cls', 'driver', 'team', 'car', 'q1', 'q2', 'q3', 'grid', 'laps', 'time', 'gap', 'best', 'pts', 'status'])
      .filter(k => rows.some(r => r[k] != null && r[k] !== ''));

    const thead = keys.map(k => `<th class="${k === 'pts' ? 'pts' : ''}">${COLS[k]}</th>`).join('');
    const tbody = rows.map(r => {
      const pos = state.resClass ? (r.pic || r.pos) : r.pos;
      const cls = pos === '1' ? 'p1' : pos === '2' ? 'p2' : pos === '3' ? 'p3' : '';
      return `<tr class="${cls}">` + keys.map(k => {
        const v = k === 'pos' ? (pos || r.status || '–') : r[k];
        if (k === 'pos') return `<td class="pos">${esc(v)}</td>`;
        if (k === 'no') return `<td><span class="no">${esc(v || '')}</span></td>`;
        if (k === 'cls') return `<td>${v ? `<span class="clsb">${esc(v)}</span>` : ''}</td>`;
        if (k === 'driver') return `<td class="drv">${esc(v || '')}</td>`;
        if (k === 'pts') return `<td class="pts">${esc(v || '')}</td>`;
        if (k === 'team' || k === 'car') return `<td class="muted">${esc(v || '')}</td>`;
        return `<td class="nowrap">${esc(v || '')}</td>`;
      }).join('') + '</tr>';
    }).join('');

    el.innerHTML = `<div class="toolbar">${seriesBtns}
        <select class="select" id="resEvent" aria-label="Rennen wählen">${evs.map(e => `<option value="${esc(e.id)}" ${e.id === ev.id ? 'selected' : ''}>${esc((e.date ? fDateUtc.format(dateOnly(e.date)) + ' · ' : '') + e.name)}</option>`).join('')}</select></div>
      <div class="res-head" style="--c:${SERIES[sk].color}">${logo(sk)}<div><h2>${esc(ev.name)}${ev.cup ? `<span class="cup">${esc(ev.cup)}</span>` : ''}</h2><p>${esc(SERIES[sk].name)} · Saison ${esc(ev.season)}${ev.date ? ' · ' + esc(fDateLong.format(dateOnly(ev.date))) : ''}${ev.note ? '<br>' + esc(ev.note) : ''}</p></div></div>
      <div class="toolbar"><div class="pills">${ev.sessions.map((s, i) => `<button class="pillbtn ${i === state.resSession ? 'is-on' : ''}" data-sess="${i}">${esc(s.name)}</button>`).join('')}</div>
      ${classes.length > 1 ? `<select class="select" id="resClass" aria-label="Klasse"><option value="">Alle Klassen</option>${classes.map(c => `<option ${c === state.resClass ? 'selected' : ''}>${esc(c)}</option>`).join('')}</select>` : ''}</div>
      <div class="tablebox"><table class="res"><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table></div>`;
    bindRes(el);
  }
  function bindRes(el) {
    el.querySelectorAll('[data-rs]').forEach(b => b.addEventListener('click', () => { state.resSeries = b.dataset.rs; state.resEvent = null; state.resClass = ''; renderResults(); }));
    el.querySelectorAll('[data-sess]').forEach(b => b.addEventListener('click', () => { state.resSession = Number(b.dataset.sess); renderResults(); }));
    const se = $('#resEvent', el); if (se) se.addEventListener('change', () => { state.resEvent = se.value; state.resSession = -1; renderResults(); });
    const sc = $('#resClass', el); if (sc) sc.addEventListener('change', () => { state.resClass = sc.value; renderResults(); });
  }

  // ---------- Meisterschaft
  function renderStandings() {
    const el = $('#view-standings');
    const list = ORDER.filter(k => state.enabled.includes(k));
    if (!state.stSeries || !list.includes(state.stSeries)) { state.stSeries = list[0]; state.stTable = 0; }
    const sk = state.stSeries;
    const data = state.standings && state.standings[sk];
    const seriesBtns = `<div class="pills">${list.map(k => `<button class="pillbtn ${k === sk ? 'is-on' : ''}" data-ss="${k}">${esc(SERIES[k].short)}</button>`).join('')}</div>`;
    if (!data || !data.tables || !data.tables.length) {
      el.innerHTML = `<div class="toolbar">${seriesBtns}</div><p class="empty">Kein Meisterschaftsstand verfügbar.</p>`;
    } else {
      if (state.stTable >= data.tables.length) state.stTable = 0;
      const t = data.tables[state.stTable];
      const hasTeam = t.rows.some(r => r.team);
      const hasWins = t.rows.some(r => r.wins != null);
      el.innerHTML = `<div class="toolbar">${seriesBtns}</div>
        <div class="res-head" style="--c:${SERIES[sk].color}">${logo(sk)}<div><h2>Meisterschaft ${esc(data.season || '')}</h2><p>${esc(SERIES[sk].name)}${data.round ? ' · nach Runde ' + esc(data.round) : ''}</p></div></div>
        <div class="toolbar">${data.tables.length > 1 ? `<select class="select" id="stTable" aria-label="Wertung">${data.tables.map((x, i) => `<option value="${i}" ${i === state.stTable ? 'selected' : ''}>${esc(x.title)}</option>`).join('')}</select>` : ''}</div>
        <div class="tablebox"><table class="res"><thead><tr><th>Pos</th><th>${esc(t.title.split('·').pop().trim())}</th>${hasTeam ? '<th>Team</th>' : ''}${hasWins ? '<th>Siege</th>' : ''}<th class="pts">Punkte</th></tr></thead><tbody>
        ${t.rows.map(r => `<tr class="${r.pos === '1' ? 'p1' : r.pos === '2' ? 'p2' : r.pos === '3' ? 'p3' : ''}"><td class="pos">${esc(r.pos)}</td><td class="drv">${esc(r.name)}</td>${hasTeam ? `<td class="muted">${esc(r.team || '')}</td>` : ''}${hasWins ? `<td class="nowrap">${esc(r.wins || '0')}</td>` : ''}<td class="pts">${esc(r.pts)}</td></tr>`).join('')}
        </tbody></table></div>`;
    }
    el.querySelectorAll('[data-ss]').forEach(b => b.addEventListener('click', () => { state.stSeries = b.dataset.ss; state.stTable = 0; renderStandings(); }));
    const s = $('#stTable', el); if (s) s.addEventListener('change', () => { state.stTable = Number(s.value); renderStandings(); });
  }

  // ---------- Abo & Widget
  function renderSync() {
    const el = $('#view-sync');
    const base = location.href.replace(/[#?].*$/, '').replace(/index\.html$/, '');
    const http = (f) => base + 'calendar/' + f;
    const webcal = (f) => http(f).replace(/^https?:/, 'webcal:');
    const row = (code, label, file) => `<div class="subrow">${code ? logo(code) : '<span class="logo logo--dark" style="width:44px;height:32px">🏁</span>'}<span>${esc(label)}</span>
      <a class="btn btn--primary" href="${esc(webcal(file))}">Abonnieren</a><button class="btn" data-copy="${esc(http(file))}" title="Link kopieren">⧉</button></div>`;
    el.innerHTML = `<div class="panels">
      <section class="panel carbon-soft"><h2>Kalender-Abo</h2>
        <p>Alle Termine automatisch im iPhone-Kalender. Das Abo aktualisiert sich selbst, neue Termine und Zeitänderungen kommen von allein.</p>
        <div class="sublist">${row('', 'Alle Serien', 'alle.ics')}${ORDER.map(k => row(k, SERIES[k].name, k.toLowerCase() + '.ics')).join('')}</div>
        <p style="margin-top:12px;font-size:13px">Auf dem iPhone „Abonnieren“ antippen und bestätigen. Danach in der Kalender-App unter <b>Kalender</b> ein- und ausblenden. Ein Kalender-Widget dafür bietet Apple direkt an.</p>
      </section>
      <section class="panel carbon-soft"><h2>iPhone-Widget</h2>
        <p>Race-Countdown mit Serien-Logo im Carbon-Look, als mittleres Widget und für den Sperrbildschirm.</p>
        <ol class="steps">
          <li>Die kostenlose App <b>Scriptable</b> aus dem App Store laden.</li>
          <li><button class="btn btn--primary" id="copyWidget">Widget-Skript kopieren</button><br>Die Adresse dieser Seite ist darin schon eingetragen.</li>
          <li>In Scriptable mit <b>+</b> ein neues Skript anlegen, alles einfügen und als „Motorsport“ speichern.</li>
          <li>Home-Bildschirm lange drücken → <b>+</b> → Scriptable → <b>mittleres Widget</b>. Widget antippen und halten → Bearbeiten → Skript wählen.</li>
          <li>Unter <b>Parameter</b> optional Serien eintragen, z. B. <code>F1</code> oder <code>F1,DTM</code>. Mit <code>race</code> zählt der Countdown nur bis zum nächsten Rennen, z. B. <code>F1,race</code>. Leer = alle Serien.</li>
          <li>Sperrbildschirm: lange drücken → Anpassen → Widgets → Scriptable (rechteckig oder rund) → gleiches Skript.</li>
        </ol>
      </section></div>`;
    const cw = $('#copyWidget', el);
    cw.addEventListener('click', async () => {
      try {
        const src = await (await fetch('widget/motorsport-widget.js', { cache: 'no-cache' })).text();
        const code = src.replace(/const BASE_URL = '[^']*';/, `const BASE_URL = '${base}';`);
        await navigator.clipboard.writeText(code);
        cw.textContent = '✓ Kopiert';
      } catch (e) {
        cw.textContent = 'Kopieren nicht möglich – Skript öffnen';
        location.href = 'widget/motorsport-widget.js';
      }
      setTimeout(() => { cw.textContent = 'Widget-Skript kopieren'; }, 2500);
    });
    el.querySelectorAll('[data-copy]').forEach(b => b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy); b.textContent = '✓'; setTimeout(() => { b.textContent = '⧉'; }, 1500); }
      catch (e) { prompt('Link kopieren:', b.dataset.copy); }
    }));
  }

  function renderFooter() {
    const m = state.meta && state.meta.series || {};
    const st = ORDER.map(k => {
      const x = m[k];
      if (!x) return '';
      const when = x.updated ? fDay.format(new Date(x.updated)) + ' ' + fTime.format(new Date(x.updated)) : '–';
      return `<span class="status ${x.ok ? '' : 'is-bad'}" title="${esc(x.error || '')}">${esc(SERIES[k].short)} ${x.ok ? '' : '(Quelle nicht erreichbar, Stand ' + esc(when) + ')'}</span>`;
    }).join('');
    $('#footer').innerHTML = `<p>${st}</p>
      <p>Alle Zeiten in Wiener Zeit (MEZ/MESZ). Angaben ohne Gewähr.</p>
      <p>Quellen: Jolpica F1 API, dtm.com, IMSA Results (Al Kamel Systems), gt-world-challenge-europe.com, fiawec.com, motogp.com, nascar.com, indycar.com, Wikipedia (WRC, IndyCar-Ergebnisse). Logos sind Marken der jeweiligen Rechteinhaber. Privates Projekt ohne Verbindung zu den Serien.</p>`;
  }

  function bindStatic() {
    document.querySelectorAll('.tab').forEach(t => t.addEventListener('click', () => setView(t.dataset.view)));
    document.querySelectorAll('.seg__btn').forEach(b => {
      b.classList.toggle('is-on', b.dataset.target === state.target);
      b.addEventListener('click', () => {
        state.target = b.dataset.target; save('mk.target', state.target);
        document.querySelectorAll('.seg__btn').forEach(x => x.classList.toggle('is-on', x === b));
        lastHeroKey = ''; tick();
      });
    });
  }

  init();
})();
