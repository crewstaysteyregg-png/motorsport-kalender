# Motorsport Kalender

Web-App mit Terminen, Ergebnissen und Meisterschaftsständen für
**Formel 1, DTM, IMSA WeatherTech, GT World Challenge Europe, FIA WEC, WRC,
IndyCar, NASCAR Cup Series und MotoGP** – dazu
Kalender-Abos für das iPhone und ein Scriptable-Widget mit Race-Countdown.

Alles läuft kostenlos auf GitHub: Ein automatischer Job holt 4× täglich neue
Termine, Ergebnisse und Stände und veröffentlicht die Seite neu.

---

## 1. Einrichtung auf GitHub (einmalig, ca. 10 Minuten)

1. Auf <https://github.com/new> ein neues Repository anlegen
   - Name: `motorsport-kalender`
   - **Public** auswählen (GitHub Pages ist für private Repos nur im Bezahl-Abo verfügbar)
   - Ohne README erstellen
2. Auf der leeren Repository-Seite auf **„uploading an existing file“** klicken
   und **den gesamten Inhalt dieses Ordners** hineinziehen (alle Dateien und Ordner,
   auch `.github`). Dann **Commit changes**.
   > Tipp: Der Ordner `.github` ist unter Windows evtl. versteckt. Im Explorer unter
   > *Ansicht → Ausgeblendete Elemente* einblenden. Ohne diesen Ordner gibt es keine
   > automatische Aktualisierung.
3. **Settings → Pages**: Bei *Source* **„GitHub Actions“** auswählen.
4. **Actions**-Tab öffnen → Workflow **„Termine aktualisieren & veröffentlichen“** →
   **Run workflow**. Nach 2–3 Minuten ist die Seite online unter
   `https://DEIN-NAME.github.io/motorsport-kalender/`

Ab dann aktualisiert sich alles automatisch (06:15, 12:15, 18:15, 00:15 Uhr).

## 2. iPhone

Seite in Safari öffnen → Tab **„Abo & Widget“**.

- **Zum Home-Bildschirm:** Teilen-Symbol → *Zum Home-Bildschirm*, dann läuft die App im Vollbild.
- **Kalender-Abo:** Auf *Abonnieren* tippen (alle Serien oder einzeln). Die Termine erscheinen
  in der Kalender-App und aktualisieren sich selbst. Apples Kalender-Widget zeigt sie dann auch an.
- **Widget (Scriptable):**
  1. App **Scriptable** aus dem App Store installieren
  2. In der Web-App auf **„Widget-Skript kopieren“** tippen (Adresse ist schon eingetragen)
  3. In Scriptable **+** → einfügen → als „Motorsport“ speichern
  4. Home-Bildschirm lange drücken → **+** → Scriptable → **mittel** → Widget bearbeiten → Skript „Motorsport“
  5. **Parameter** (optional): `F1` · `F1,DTM` · `MOTOGP,WEC` · `race` (nur Rennen) · `F1,race`
     – Kürzel: `F1`, `DTM`, `IMSA`, `GTWC`, `WEC`, `WRC`, `INDYCAR`, `NASCAR`, `MOTOGP`
  6. Sperrbildschirm: lange drücken → *Anpassen* → *Widgets* → Scriptable (rechteckig/rund) → „Motorsport“

## 3. Datenquellen

| Serie | Termine | Ergebnisse & Stand |
|---|---|---|
| Formel 1 | Jolpica F1 API (inkl. aller Session-Zeiten) | Jolpica F1 API |
| DTM | api.dtm.com (offizielle DTM-Seite) | api.dtm.com |
| IMSA | `data/manual/seed.json` (offizieller Kalender 2027) | imsa.results.alkamelcloud.com (offizielle Zeitnahme) |
| GTWC Europe | gt-world-challenge-europe.com + `seed.json` | gt-world-challenge-europe.com |
| FIA WEC | fiawec.com (inkl. aller Session-Zeiten) | fiawec.com – Ergebnisse nur Hypercar-Klasse, Stand Hypercar + LMGT3 |
| WRC | Wikipedia-Saisonartikel (wrc.com sperrt Abrufe) | Wikipedia: Platzierungen + Punkte aus der WM-Tabelle |
| IndyCar | indycar.com (Renntag + Startzeit) | Wikipedia: Zielankunft aus der Meisterschaftstabelle |
| NASCAR Cup | nascar.com (Training, Qualifying, Rennen) | nascar.com, komplett |
| MotoGP | motogp.com (alle MotoGP-Sessions) | motogp.com, komplett (Qualifying, Sprint, Rennen) |

- Ergebnisse: Qualifying, Sprint und Rennen, bei F1/DTM/IMSA/GTWC/NASCAR/MotoGP **komplett** mit allen
  Platzierungen (bei IMSA/GTWC mit Klassen-Filter). Freie Trainings werden nicht gespeichert.
- WEC zeigt LMGT3-Ergebnisse nicht, weil fiawec.com sie nur per JavaScript nachlädt.
- WRC und IndyCar haben keine frei abrufbaren Zeitnahme-Daten; die Ergebnisse kommen aus den
  Meisterschaftstabellen bei Wikipedia (Gesamtplatzierungen der eingeschriebenen Fahrer, ohne Zeiten).
- Fällt eine Quelle aus, bleiben die zuletzt geladenen Daten dieser Serie erhalten.
  Unten auf der Seite steht, welche Quelle zuletzt nicht erreichbar war.

### Session-Zeiten für DTM, IMSA und GTWC

Für diese Serien gibt es vor dem Wochenende keinen maschinenlesbaren Zeitplan; sie stehen
zunächst als ganztägiges **„Rennwochenende“** im Kalender. Wer die genauen Zeiten möchte,
kann sie in `data/manual/sessions.json` eintragen (auf GitHub direkt im Browser bearbeitbar):

```json
{
  "overrides": [
    {
      "series": "DTM",
      "event": "2027-04-24",
      "sessions": [
        { "name": "Qualifying 1", "type": "quali", "start": "2027-04-24T10:00:00+02:00", "minutes": 20 },
        { "name": "Rennen 1",     "type": "race",  "start": "2027-04-24T13:30:00+02:00", "minutes": 60 }
      ]
    }
  ]
}
```

`event` ist ein beliebiges Datum innerhalb des Wochenendes. Beim nächsten Lauf erscheinen die
Sessions in App, Widget und Kalender-Abo.

### Neue Saison-Kalender

F1 und DTM kommen automatisch. Für IMSA und GTWC werden neue Kalender (z. B. 2028) in
`data/manual/seed.json` ergänzt – gleiche Struktur wie die vorhandenen Einträge.

## 4. Lokal testen (Windows)

```powershell
powershell -ExecutionPolicy Bypass -File scripts/update.ps1      # Daten holen
powershell -ExecutionPolicy Bypass -File scripts/serve-local.ps1 # http://localhost:8765/
```

---

Alle Zeiten in Wiener Zeit (MEZ/MESZ), Angaben ohne Gewähr. Logos sind Marken der jeweiligen
Rechteinhaber (IMSA-Logo via Wikimedia Commons). Privates Projekt ohne Verbindung zu den Serien.
