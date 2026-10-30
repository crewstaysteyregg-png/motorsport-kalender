<#
  Motorsport-Kalender – Daten-Update
  Holt Termine, Ergebnisse und Meisterschaftsstände für F1, DTM, IMSA,
  GT World Challenge Europe, WEC, WRC, IndyCar, NASCAR und MotoGP und schreibt:
    data/events.json, data/standings.json, data/meta.json,
    data/results/<serie>.json, calendar/<serie>.ics, calendar/alle.ics
  Läuft in Windows PowerShell 5.1 und PowerShell 7 (GitHub Actions).
  Fällt eine Quelle aus, bleiben die zuletzt gespeicherten Daten dieser Serie erhalten.
#>
[CmdletBinding()]
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [string[]]$Only = @('F1', 'DTM', 'IMSA', 'GTWC', 'WEC', 'WRC', 'INDYCAR', 'NASCAR', 'MOTOGP'),
  [switch]$LibOnly   # nur Funktionen laden (zum Testen: . ./scripts/update.ps1 -LibOnly)
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$Inv = [Globalization.CultureInfo]::InvariantCulture
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
$Now = [DateTimeOffset]::UtcNow
$Year = $Now.Year
$KeepFrom = $Now.AddDays(-14).ToString('yyyy-MM-dd', $Inv)   # Kalender: nur ab jetzt (+ 2 Wochen Rückblick)
try { $Vienna = [TimeZoneInfo]::FindSystemTimeZoneById('Europe/Vienna') } catch { $Vienna = [TimeZoneInfo]::FindSystemTimeZoneById('W. Europe Standard Time') }

$SeriesInfo = [ordered]@{
  F1   = @{ name = 'Formel 1';                    short = 'F1' }
  DTM  = @{ name = 'DTM';                         short = 'DTM' }
  IMSA = @{ name = 'IMSA WeatherTech';            short = 'IMSA' }
  GTWC = @{ name = 'GT World Challenge Europe';   short = 'GTWC' }
  WEC     = @{ name = 'FIA WEC';                  short = 'WEC' }
  WRC     = @{ name = 'Rallye-WM (WRC)';          short = 'WRC' }
  INDYCAR = @{ name = 'IndyCar';                  short = 'IndyCar' }
  NASCAR  = @{ name = 'NASCAR Cup Series';        short = 'NASCAR' }
  MOTOGP  = @{ name = 'MotoGP';                   short = 'MotoGP' }
}
$WikiUA = 'MotorsportKalender/1.0 (private calendar; https://github.com/crewstaysteyregg-png/motorsport-kalender)'

# ---------------------------------------------------------------- Helpers

function Write-Log([string]$msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) }

function Get-Text([string]$Url) {
  for ($try = 1; $try -le 3; $try++) {
    try {
      # Wikipedia verlangt einen aussagekräftigen User-Agent
      $agent = if ($Url -match 'wikipedia\.org') { $WikiUA } else { $UA }
      $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent' = $agent }
      $bytes = $r.RawContentStream.ToArray()
      return $Utf8.GetString($bytes).TrimStart([char]0xFEFF)
    } catch {
      if ($try -eq 3) { throw "GET $Url fehlgeschlagen: $($_.Exception.Message)" }
      Start-Sleep -Seconds (2 * $try)
    }
  }
}

function Get-Json([string]$Url) {
  $t = Get-Text $Url
  $i = $t.IndexOfAny([char[]]'{[')
  if ($i -gt 0) { $t = $t.Substring($i) }
  return ($t | ConvertFrom-Json)
}

function Save-Json($Obj, [string]$Path) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Obj -Depth 30 -Compress), $Utf8)
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path $Path)) { return $null }
  try { return ([IO.File]::ReadAllText($Path, $Utf8) | ConvertFrom-Json) } catch { return $null }
}

function To-Utc([DateTimeOffset]$d) { $d.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", $Inv) }

function Parse-Utc([string]$s) {
  [DateTimeOffset]::Parse($s, $Inv, [Globalization.DateTimeStyles]::AssumeUniversal)
}

function Html-Text([string]$h) {
  $t = [regex]::Replace($h, '<[^>]+>', ' ')
  $t = [Net.WebUtility]::HtmlDecode($t)
  return ([regex]::Replace($t, '\s+', ' ')).Trim()
}

function Slug([string]$s) {
  $n = $s.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
  $n = [regex]::Replace($n, '\p{Mn}', '')
  return ([regex]::Replace($n, '[^a-z0-9]+', '-')).Trim('-')
}

function Arr($x) { if ($null -eq $x) { return @() } return @($x) }

function New-Session([string]$id, [string]$name, [string]$type, $start, $end, [bool]$allDay = $false) {
  [ordered]@{ id = $id; name = $name; type = $type; start = $start; end = $end; allDay = $allDay }
}

function New-Event([string]$series, [int]$season, [string]$name, [string]$circuit, [string]$location,
                   [string]$start, [string]$end, $sessions, [string]$source, [string]$cup = '') {
  [ordered]@{
    id       = "$($series.ToLowerInvariant())-$season-$(Slug $name)"
    series   = $series
    season   = $season
    name     = $name
    cup      = $cup
    circuit  = $circuit
    location = $location
    start    = $start
    end      = $end
    sessions = @($sessions)
    source   = $source
  }
}

function New-Row {
  param($pos, $no, $driver, $team, $car, $cls, $laps, $time, $gap, $best, $pts, $status, $q1, $q2, $q3, $grid)
  $r = [ordered]@{}
  foreach ($k in 'pos', 'no', 'cls', 'driver', 'team', 'car', 'laps', 'time', 'gap', 'best', 'q1', 'q2', 'q3', 'grid', 'pts', 'status') {
    $v = Get-Variable -Name $k -ValueOnly
    if ($null -ne $v -and "$v" -ne '') { $r[$k] = "$v".Trim() }
  }
  return $r
}

function Add-ClassPositions($rows) {
  $count = @{}
  foreach ($r in $rows) {
    if ($r.Contains('cls')) {
      $c = $r['cls']; if (-not $count.ContainsKey($c)) { $count[$c] = 0 }
      $count[$c]++; $r['pic'] = "$($count[$c])"
    }
  }
}

$Months = @{ january = 1; february = 2; march = 3; april = 4; may = 5; june = 6; july = 7; august = 8; september = 9; october = 10; november = 11; december = 12 }

# ---------------------------------------------------------------- Formel 1 (Jolpica / Ergast)

$JolpicaBase = 'https://api.jolpi.ca/ergast/f1'

function Get-F1Events([int]$season) {
  $j = Get-Json "$JolpicaBase/$season.json?limit=100"
  $defs = @(
    @('FirstPractice', '1. Freies Training', 'practice', 60),
    @('SecondPractice', '2. Freies Training', 'practice', 60),
    @('ThirdPractice', '3. Freies Training', 'practice', 60),
    @('SprintQualifying', 'Sprint-Qualifying', 'sprintquali', 45),
    @('SprintShootout', 'Sprint-Qualifying', 'sprintquali', 45),
    @('Sprint', 'Sprint', 'sprint', 60),
    @('Qualifying', 'Qualifying', 'quali', 60)
  )
  $out = @()
  foreach ($r in (Arr $j.MRData.RaceTable.Races)) {
    $base = "f1-$season-$($r.round)"
    $sess = New-Object System.Collections.Generic.List[object]
    $all = @($defs) + , @('__race', 'Rennen', 'race', 120)
    foreach ($d in $all) {
      if ($d[0] -eq '__race') { $p = [pscustomobject]@{ date = $r.date; time = $r.time } } else { $p = $r.($d[0]) }
      if (-not $p -or -not $p.date) { continue }
      $sid = "$base-$($d[2])$(if ($d[0] -match 'Second') {'2'} elseif ($d[0] -match 'Third') {'3'} elseif ($d[0] -match 'First') {'1'})"
      if ($p.time) {
        $st = Parse-Utc "$($p.date)T$($p.time)"
        $sess.Add((New-Session $sid $d[1] $d[2] (To-Utc $st) (To-Utc $st.AddMinutes($d[3])))) | Out-Null
      } else {
        $sess.Add((New-Session $sid $d[1] $d[2] $p.date $p.date $true)) | Out-Null
      }
    }
    $sorted = @($sess | Sort-Object { $_.start })
    $start = $sorted[0].start.Substring(0, 10)
    $loc = $r.Circuit.Location
    $ev = New-Event 'F1' $season $r.raceName $r.Circuit.circuitName "$($loc.locality), $($loc.country)" $start $r.date $sorted 'Jolpica F1 API'
    $ev.id = $base
    $ev['round'] = [int]$r.round
    $out += , $ev
  }
  return $out
}

function Get-JolpicaAll([string]$path) {
  # Paginiert durch alle Rennen eines Endpunkts und fasst Teilseiten pro Runde zusammen.
  $races = [ordered]@{}
  $offset = 0
  do {
    $j = Get-Json "$JolpicaBase/$path`?limit=100&offset=$offset"
    $total = [int]$j.MRData.total
    foreach ($r in (Arr $j.MRData.RaceTable.Races)) {
      $k = "$($r.round)"
      if (-not $races.Contains($k)) { $races[$k] = @{ race = $r; items = New-Object System.Collections.Generic.List[object] } }
      foreach ($p in 'Results', 'QualifyingResults', 'SprintResults') {
        foreach ($x in (Arr $r.$p)) { $races[$k].items.Add($x) | Out-Null }
      }
    }
    $offset += 100
    Start-Sleep -Milliseconds 350
  } while ($offset -lt $total)
  return $races
}

function Get-F1Results([int]$season) {
  $race = Get-JolpicaAll "$season/results.json"
  if ($race.Count -eq 0) { return @() }
  $quali = Get-JolpicaAll "$season/qualifying.json"
  $sprint = Get-JolpicaAll "$season/sprint.json"
  $out = @()
  foreach ($k in $race.Keys) {
    $r = $race[$k].race
    $sessions = @()
    if ($quali.Contains($k)) {
      $rows = foreach ($x in $quali[$k].items) {
        New-Row -pos $x.position -no $x.number -driver "$($x.Driver.givenName) $($x.Driver.familyName)" -team $x.Constructor.name -q1 $x.Q1 -q2 $x.Q2 -q3 $x.Q3
      }
      $sessions += , [ordered]@{ name = 'Qualifying'; type = 'quali'; rows = @($rows) }
    }
    if ($sprint.Contains($k)) {
      $rows = foreach ($x in $sprint[$k].items) {
        $t = if ($x.Time) { $x.Time.time } else { $x.status }
        New-Row -pos $x.position -no $x.number -driver "$($x.Driver.givenName) $($x.Driver.familyName)" -team $x.Constructor.name -laps $x.laps -time $t -grid $x.grid -pts $x.points -status $x.status -best $x.FastestLap.Time.time
      }
      $sessions += , [ordered]@{ name = 'Sprint'; type = 'sprint'; rows = @($rows) }
    }
    $rows = foreach ($x in $race[$k].items) {
      $t = if ($x.Time) { $x.Time.time } else { $x.status }
      New-Row -pos $x.position -no $x.number -driver "$($x.Driver.givenName) $($x.Driver.familyName)" -team $x.Constructor.name -laps $x.laps -time $t -grid $x.grid -pts $x.points -status $x.status -best $x.FastestLap.Time.time
    }
    $sessions += , [ordered]@{ name = 'Rennen'; type = 'race'; rows = @($rows) }
    $out += , [ordered]@{
      id = "f1-$season-$($r.round)"; series = 'F1'; season = $season; round = [int]$r.round
      name = $r.raceName; circuit = $r.Circuit.circuitName; date = $r.date; sessions = $sessions
    }
  }
  return $out
}

function Get-F1Standings([int]$season) {
  $d = Get-Json "$JolpicaBase/$season/driverstandings.json?limit=100"
  $c = Get-Json "$JolpicaBase/$season/constructorstandings.json?limit=100"
  $dl = @(Arr $d.MRData.StandingsTable.StandingsLists)
  if ($dl.Count -eq 0) { return $null }
  $drivers = foreach ($x in (Arr $dl[0].DriverStandings)) {
    [ordered]@{ pos = $x.position; name = "$($x.Driver.givenName) $($x.Driver.familyName)"; team = (Arr $x.Constructors | ForEach-Object { $_.name }) -join ' / '; pts = $x.points; wins = $x.wins }
  }
  $teams = foreach ($x in (Arr (Arr $c.MRData.StandingsTable.StandingsLists)[0].ConstructorStandings)) {
    [ordered]@{ pos = $x.position; name = $x.Constructor.name; pts = $x.points; wins = $x.wins }
  }
  [ordered]@{
    season = $season
    round  = $dl[0].round
    tables = @(
      [ordered]@{ title = 'Fahrer'; rows = @($drivers) },
      [ordered]@{ title = 'Konstrukteure'; rows = @($teams) }
    )
  }
}

function Update-F1 {
  $events = @()
  foreach ($s in @($Year, ($Year + 1))) { $events += Get-F1Events $s }
  $season = $Year
  $results = Get-F1Results $season
  if ($results.Count -eq 0) { $season = $Year - 1; $results = Get-F1Results $season }
  $standings = Get-F1Standings $season
  return @{ events = $events; results = $results; standings = $standings }
}

# ---------------------------------------------------------------- DTM (api.dtm.com)

$DtmApi = 'https://api.dtm.com/data'

function Format-DtmName([string]$n) {
  # "VAN DER LINDE Kelvin" -> "Kelvin van der Linde"
  $parts = $n -split '\s+'
  $last = @(); $first = @()
  foreach ($p in $parts) {
    if ($p.Length -gt 1 -and $p -ceq $p.ToUpperInvariant()) { $last += $p } else { $first += $p }
  }
  $ti = $Inv.TextInfo
  $lastFmt = ($last | ForEach-Object {
    $l = $_.ToLowerInvariant()
    if (@('van', 'der', 'de', 'den', 'von', 'la', 'le', 'da', 'di') -contains $l) { $l } else { $ti.ToTitleCase($l) }
  }) -join ' '
  return (@(($first -join ' '), $lastFmt) | Where-Object { $_ }) -join ' '
}

function Update-DTM {
  # Kalender
  $j = Get-Json "$DtmApi`?query=events&raceSeries=DTM"
  $events = @()
  foreach ($e in (Arr $j.events)) {
    if (-not $e.startTime) { continue }
    $st = Parse-Utc $e.startTime; $en = Parse-Utc $e.endTime
    # Die API liefert Mitternacht Wiener Zeit als UTC-Zeitpunkt -> Datum in Wiener Zeit
    $stL = [TimeZoneInfo]::ConvertTime($st, $Vienna); $enL = [TimeZoneInfo]::ConvertTime($en, $Vienna)
    $country = if ($e.country) { $e.country.name } else { '' }
    $ev = New-Event 'DTM' $st.Year $e.name $e.name $country $stL.ToString('yyyy-MM-dd', $Inv) $enL.ToString('yyyy-MM-dd', $Inv) @() 'dtm.com'
    $events += , $ev
  }

  # Ergebnisse + Stand: aktuelle Saison, sonst Vorjahr
  $season = $Year
  $items = @(Arr (Get-Json "$DtmApi`?query=wigeResults&raceSeries=DTM&startDate=$season-01-01&endDate=$season-12-31").wigeResultses)
  if ($items.Count -eq 0) {
    $season = $Year - 1
    $items = @(Arr (Get-Json "$DtmApi`?query=wigeResults&raceSeries=DTM&startDate=$season-01-01&endDate=$season-12-31").wigeResultses)
  }
  $byEvent = [ordered]@{}
  foreach ($it in ($items | Sort-Object { $_.startDate }, { [int]$_.sessionId })) {
    $jt = $it.jsonText | ConvertFrom-Json
    $meta = Arr $jt.sessions | Where-Object { $_.sessionid -eq $jt.sessionid } | Select-Object -First 1
    if (-not $meta -or @('race', 'qualifying') -notcontains $meta.type) { continue }
    $k = "$($it.wigeEventId)"
    if (-not $byEvent.Contains($k)) {
      $byEvent[$k] = [ordered]@{
        id = "dtm-$season-$(Slug $it.wigeName)"; series = 'DTM'; season = $season
        name = $it.wigeName; circuit = $it.wigeName; date = $it.startDate; sessions = @()
      }
    }
    $isRace = $meta.type -eq 'race'
    $rows = foreach ($x in (Arr $jt.result | Sort-Object { if ("$($_.position)" -match '^\d+$') { [int]$_.position } else { 999 } })) {
      $pts = if ($isRace) { $x.totalpoints } else { $x.qualifyingpoints }
      if ($pts -eq '0') { $pts = $null }
      $time = if ($isRace) { $x.time } else { $x.fastestlap }
      New-Row -pos $x.position -no $x.number -driver (Format-DtmName $x.name) -team $x.team -car $x.car -laps $x.laps -time $time -gap $x.gap -best $(if ($isRace) { $x.fastestlap }) -pts $pts -status $x.status
    }
    $name = ($meta.name -replace '^Race', 'Rennen')
    $order = [int]$meta.order
    $byEvent[$k].sessions += , [ordered]@{ name = $name; type = $(if ($isRace) { 'race' } else { 'quali' }); order = $order; rows = @($rows) }
  }
  $results = foreach ($v in $byEvent.Values) { $v.sessions = @($v.sessions | Sort-Object { $_.order }); $v }

  # Meisterschaft
  $standings = $null
  $st = @(Arr (Get-Json "$DtmApi`?query=wigeStandings&raceSeries=DTM&startDate=$season-01-01&endDate=$season-12-31").wigeStandingses)
  if ($st.Count -gt 0) {
    $sj = ($st | Select-Object -Last 1).jsonText | ConvertFrom-Json
    $mk = {
      param($list, $isDriver)
      foreach ($x in (Arr $list | Sort-Object { [int]$_.position })) {
        $n = if ($isDriver) { Format-DtmName $x.name } else { $x.name }
        [ordered]@{ pos = "$($x.position)"; name = $n; pts = $x.totalpoints }
      }
    }
    $standings = [ordered]@{
      season = $season
      tables = @(
        [ordered]@{ title = 'Fahrer'; rows = @(& $mk $sj.drivers $true) },
        [ordered]@{ title = 'Teams'; rows = @(& $mk $sj.teams $false) },
        [ordered]@{ title = 'Hersteller'; rows = @(& $mk $sj.manufacturers $false) }
      )
    }
  }
  return @{ events = $events; results = @($results); standings = $standings }
}

# ---------------------------------------------------------------- IMSA (Al Kamel Systems)

$ImsaBase = 'https://imsa.results.alkamelcloud.com/'
$ImsaChamp = '01_IMSA%20WeatherTech%20SportsCar%20Championship'

function Get-ImsaSeason([int]$season) {
  $code = '{0:D2}_{1}' -f ($season % 100), $season
  $page = Get-Text "$ImsaBase`?season=$code"
  if ($page -notmatch "option Value=`"$code`"") { return $null }
  $evOpts = [regex]::Matches($page, '<select name="evvent"[\s\S]*?</select>')
  if ($evOpts.Count -eq 0) { return $null }
  $names = [regex]::Matches($evOpts[0].Value, 'option Value="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }

  $results = @()
  $lastPoints = $null
  $teamByNo = @{}   # Startnummer -> Teamname (die Team-Wertung liefert nur Nummern)
  foreach ($ev in $names) {
    $html = Get-Text ("$ImsaBase`?season=$code&evvent=" + [uri]::EscapeDataString($ev))
    Start-Sleep -Milliseconds 200
    $links = [regex]::Matches($html, 'href="(Results/[^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -like "*/$ImsaChamp/*" }
    if (-not $links) { continue }

    if ($links | Where-Object { $_ -match 'POINTS%20DATA%20-%20(Official|Provisional)/IWSC%20' }) { $lastPoints = $links }

    # Pro Session-Ordner die beste Ergebnisdatei wählen (letzte Rennstunde, Official > Provisional > Unofficial)
    $best = @{}
    foreach ($l in $links) {
      $m = [regex]::Match($l, "$ImsaChamp/(\d{12})_(Race|Qualifying)([^/]*)/(?:(\d+)_[^/]+/)?03_Results_[^/]*?(Official|Provisional|Unofficial)?\.JSON$")
      if (-not $m.Success) { continue }
      $folder = "$($m.Groups[1].Value)_$($m.Groups[2].Value)$($m.Groups[3].Value)"
      $hour = if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 0 }
      $rank = switch ($m.Groups[5].Value) { 'Official' { 3 } 'Provisional' { 2 } 'Unofficial' { 1 } default { 2 } }
      $score = $hour * 10 + $rank
      if (-not $best.ContainsKey($folder) -or $best[$folder].score -lt $score) { $best[$folder] = @{ score = $score; url = $l; type = $m.Groups[2].Value } }
    }
    if ($best.Count -eq 0) { continue }

    $sessions = @(); $evName = $null; $evDate = $null; $circuit = $null
    foreach ($f in ($best.Keys | Sort-Object)) {
      $j = Get-Json ($ImsaBase + $best[$f].url)
      Start-Sleep -Milliseconds 200
      if (-not $evName) {
        $evName = $j.session.event_name; $circuit = $j.session.circuit.name
      }
      # Datum der letzten Session (= Renntag); Formate "03-10-2026" und "22/01/2026" kommen vor
      $d = [regex]::Match("$($j.session.session_date)", '(\d{2})[-/](\d{2})[-/](\d{4})')
      if ($d.Success) { $evDate = "$($d.Groups[3].Value)-$($d.Groups[2].Value)-$($d.Groups[1].Value)" }
      $isRace = $best[$f].type -eq 'Race'
      $rows = foreach ($x in (Arr $j.classification)) {
        $drv = (Arr $x.drivers | ForEach-Object { "$($_.firstname) $($_.surname)".Trim() }) -join ' / '
        $time = if ($isRace) { $x.elapsed_time } else { $x.fastest_lap_time }
        New-Row -pos $x.position -no $x.number -cls $x.class -driver $drv -team $x.team -car $x.vehicle -laps $x.laps -time $time -gap $x.gap_first -best $(if ($isRace) { $x.fastest_lap_time }) -status $(if ($x.status -ne 'Classified') { $x.status })
      }
      $rows = @($rows); Add-ClassPositions $rows
      foreach ($x in $rows) { if ($x.Contains('no') -and $x.Contains('team')) { $teamByNo[$x['no']] = $x['team'] } }
      $sessions += , [ordered]@{ name = $(if ($isRace) { 'Rennen' } else { 'Qualifying' }); type = $(if ($isRace) { 'race' } else { 'quali' }); rows = $rows }
    }
    $results += , [ordered]@{
      id = "imsa-$season-$(Slug $evName)"; series = 'IMSA'; season = $season
      name = $evName; circuit = $circuit; date = $evDate; sessions = $sessions
    }
  }

  $standings = $null
  if ($lastPoints) {
    $tables = @()
    $files = $lastPoints | Where-Object { $_ -match 'POINTS%20DATA%20-%20Official/IWSC%20\d+' }
    if (-not $files) { $files = $lastPoints | Where-Object { $_ -match 'POINTS%20DATA%20-%20Provisional/IWSC%20\d+' } }
    foreach ($f in ($files | Sort-Object)) {
      $fname = [uri]::UnescapeDataString(($f -split '/')[-1])
      $m = [regex]::Match($fname, '^IWSC \d+ (\S+) (Drivers|Teams|Manufacturers)\.json$')
      if (-not $m.Success) { continue }
      $j = Get-Json ($ImsaBase + $f)
      Start-Sleep -Milliseconds 200
      $kind = @{ Drivers = 'Fahrer'; Teams = 'Teams'; Manufacturers = 'Hersteller' }[$m.Groups[2].Value]
      $cls = $m.Groups[1].Value -replace 'GTDPRO', 'GTD PRO'
      $rows = foreach ($x in (Arr $j.classification | Sort-Object { [int]$_.position })) {
        $n = $x.key
        if ($kind -eq 'Teams' -and $teamByNo.ContainsKey("$n")) { $n = "#$n $($teamByNo["$n"])" }
        [ordered]@{ pos = "$($x.position)"; name = $n; pts = ([double]$x.total_points).ToString('0.##', $Inv) }
      }
      $tables += , [ordered]@{ title = "$cls · $kind"; rows = @($rows) }
    }
    if ($tables.Count) { $standings = [ordered]@{ season = $season; tables = $tables } }
  }
  return @{ results = $results; standings = $standings }
}

function Update-IMSA {
  $season = $Year
  $data = Get-ImsaSeason $season
  if (-not $data -or $data.results.Count -eq 0) { $season = $Year - 1; $data = Get-ImsaSeason $season }
  if (-not $data) { throw 'Keine IMSA-Saison gefunden' }
  # Termine: kein maschinenlesbarer Kalender -> seed.json (siehe Merge unten)
  return @{ events = @(); results = $data.results; standings = $data.standings }
}

# ---------------------------------------------------------------- GT World Challenge Europe (SRO)

$GtwcBase = 'https://www.gt-world-challenge-europe.com'

function Parse-GtwcDates([string]$txt) {
  # "14 - 18 October 2026", "30 July - 1 August 2027", "28 June 2026"
  $m = [regex]::Match($txt, '(\d{1,2})(?:\s+([A-Za-z]+))?(?:\s+(\d{4}))?\s*[-–]\s*(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})')
  if ($m.Success) {
    $y2 = [int]$m.Groups[6].Value; $mo2 = $Months[$m.Groups[5].Value.ToLowerInvariant()]
    $mo1 = if ($m.Groups[2].Success) { $Months[$m.Groups[2].Value.ToLowerInvariant()] } else { $mo2 }
    $y1 = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { $y2 }
    if (-not $mo1 -or -not $mo2) { return $null }
    return @((Get-Date -Year $y1 -Month $mo1 -Day ([int]$m.Groups[1].Value)).ToString('yyyy-MM-dd', $Inv),
             (Get-Date -Year $y2 -Month $mo2 -Day ([int]$m.Groups[4].Value)).ToString('yyyy-MM-dd', $Inv))
  }
  $m = [regex]::Match($txt, '(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})')
  if ($m.Success -and $Months[$m.Groups[2].Value.ToLowerInvariant()]) {
    $d = (Get-Date -Year ([int]$m.Groups[3].Value) -Month $Months[$m.Groups[2].Value.ToLowerInvariant()] -Day ([int]$m.Groups[1].Value)).ToString('yyyy-MM-dd', $Inv)
    return @($d, $d)
  }
  return $null
}

function Get-GtwcCalendar {
  $html = Get-Text "$GtwcBase/calendar"
  $out = @()
  $seen = @{}
  foreach ($m in [regex]::Matches($html, 'href="(?:https://www\.gt-world-challenge-europe\.com)?/event/(\d+)/([^"]+)"')) {
    $id = $m.Groups[1].Value
    if ($seen.ContainsKey($id)) { continue }
    $ctx = $html.Substring([Math]::Max(0, $m.Index - 2500), [Math]::Min(2500, $m.Index))
    # nur den Block dieses Events betrachten (ab dem vorherigen Event-Link)
    $prev = $ctx.LastIndexOf('/event/')
    if ($prev -ge 0) { $ctx = $ctx.Substring($prev + 7) }
    $text = Html-Text $ctx
    $dates = Parse-GtwcDates $text
    if (-not $dates) { continue }
    $track = [regex]::Match($ctx, '<strong>([^<]+)</strong>')
    $name = if ($track.Success) { [Net.WebUtility]::HtmlDecode($track.Groups[1].Value).Trim() } else { [Net.WebUtility]::HtmlDecode($m.Groups[2].Value) }
    if ($name -match 'Test') { continue }
    $country = ''
    $cm = [regex]::Match($ctx, '</strong>\s*([^<]+)<')
    if ($cm.Success) { $country = $cm.Groups[1].Value.Trim() }
    $seen[$id] = $true
    $slug = [Net.WebUtility]::HtmlDecode($m.Groups[2].Value)
    $out += , @{ id = $id; slug = $slug; name = $name; country = $country; start = $dates[0]; end = $dates[1] }
  }
  return $out
}

function Get-GtwcSessionLabel([string]$s) {
  switch -Regex ($s) {
    '^race-(\d+)$'        { return "Rennen $($Matches[1])" }
    '^(race|main-race)$'  { return 'Rennen' }
    '^qualifying-(\d+)$'  { return "Qualifying $($Matches[1])" }
    '^qualifying$'        { return 'Qualifying' }
    '^superpole'          { return 'Superpole' }
    default               { return $s }
  }
}

function Parse-GtwcTable([string]$html) {
  $tm = [regex]::Match($html, '<table class="table session">([\s\S]*?)</table>')
  if (-not $tm.Success) { return @() }
  $heads = [regex]::Matches($tm.Groups[1].Value, '<th[^>]*>([\s\S]*?)</th>') | ForEach-Object { (Html-Text $_.Groups[1].Value).ToLowerInvariant() }
  $map = @{ 'pos' = 'pos'; 'car #' = 'no'; 'class' = 'cls'; 'drivers' = 'driver'; 'driver' = 'driver'; 'team' = 'team'; 'car' = 'car';
            'time' = 'time'; 'best time' = 'time'; 'total time' = 'time'; 'laps' = 'laps'; 'gap' = 'gap'; 'best lap' = 'best' }
  $body = [regex]::Match($tm.Groups[1].Value, '<tbody[^>]*>([\s\S]*?)</tbody>')
  if (-not $body.Success) { return @() }
  $rows = @()
  foreach ($tr in [regex]::Matches($body.Groups[1].Value, '<tr[^>]*>([\s\S]*?)</tr>')) {
    $cells = @([regex]::Matches($tr.Groups[1].Value, '<td[^>]*>([\s\S]*?)</td>') | ForEach-Object { Html-Text $_.Groups[1].Value })
    if ($cells.Count -lt 3) { continue }
    $r = [ordered]@{}
    for ($i = 0; $i -lt [Math]::Min($cells.Count, $heads.Count); $i++) {
      $k = $map[$heads[$i]]
      if ($k -and $cells[$i] -ne '') { $r[$k] = $cells[$i] }
    }
    if ($r.Contains('driver')) { $r['driver'] = $r['driver'] -replace '\s*,\s*', ' / ' }
    if ($r.Count) { $rows += , $r }
  }
  Add-ClassPositions $rows
  return $rows
}

function Get-GtwcResults([int]$season, $calendar) {
  $html = Get-Text "$GtwcBase/results/$season"
  $slugs = [regex]::Matches($html, "href=`"(?:$([regex]::Escape($GtwcBase)))?/results/$season/([^/`"#]+)`"") |
    ForEach-Object { [Net.WebUtility]::HtmlDecode($_.Groups[1].Value) } | Select-Object -Unique | Where-Object { $_ -notmatch 'test' }
  $out = @()
  foreach ($slug in $slugs) {
    $enc = [uri]::EscapeDataString($slug)
    $ev = Get-Text "$GtwcBase/results/$season/$enc"
    Start-Sleep -Milliseconds 250
    $cup = [regex]::Match($ev, '<title>[^|]*\|[^|]*\|[^|]*\|\s*([^|]+?)\s*\|')
    $cupName = if ($cup.Success) { ([Net.WebUtility]::HtmlDecode($cup.Groups[1].Value) -replace '.*AWS\s*', '').Trim() } else { '' }
    $sess = [regex]::Matches($ev, "href=`"(?:$([regex]::Escape($GtwcBase)))?/results/$season/[^/`"]+/([^/`"#]+)`"") |
      ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique |
      Where-Object { $_ -match '^(race(-\d+)?|main-race|qualifying(-\d+)?|superpole[a-z0-9-]*)$' }
    if (-not $sess) { continue }
    $sessions = @()
    foreach ($s in $sess) {
      $page = Get-Text "$GtwcBase/results/$season/$enc/$s"
      Start-Sleep -Milliseconds 250
      $rows = Parse-GtwcTable $page
      if ($rows.Count -eq 0) { continue }
      $type = if ($s -match '^(race|main)') { 'race' } else { 'quali' }
      if ($type -eq 'race') {
        # Im Rennen ist die Spalte "Time" die schnellste Runde
        foreach ($r in $rows) { if ($r.Contains('time')) { $r['best'] = $r['time']; $r.Remove('time') } }
      }
      $sessions += , [ordered]@{ name = (Get-GtwcSessionLabel $s); type = $type; rows = @($rows) }
    }
    if ($sessions.Count -eq 0) { continue }
    # Reihenfolge: Qualifying 1, Rennen 1, Qualifying 2, Rennen 2 ...
    $sessions = @($sessions | Sort-Object { if ($_.name -match '(\d+)$') { [int]$Matches[1] } else { 50 } }, { if ($_.type -eq 'race') { 1 } else { 0 } })
    $cal = $calendar | Where-Object { $_.slug -eq $slug } | Select-Object -First 1
    $title = [regex]::Match($ev, '<title>[^|]*\|\s*([^|]+?)\s*\|')
    $name = if ($cal) { $cal.name } elseif ($title.Success) { [Net.WebUtility]::HtmlDecode($title.Groups[1].Value) } else { $slug }
    $out += , [ordered]@{
      id = "gtwc-$season-$(Slug $name)"; series = 'GTWC'; season = $season; name = $name; cup = $cupName
      circuit = $name; date = $(if ($cal) { $cal.end } else { $null }); sessions = $sessions
    }
  }
  return $out
}

function Get-GtwcStandings {
  $tables = @()
  $season = $null
  foreach ($t in @(@('0_0_drivers', 'Fahrer (Gesamt)'), @('0_0_teams', 'Teams (Gesamt)'))) {
    $html = Get-Text "$GtwcBase/standings?filter_standing_type=$($t[0])"
    Start-Sleep -Milliseconds 250
    if (-not $season) {
      $sm = [regex]::Match($html, '<option[^>]*value="\d+"[^>]*selected[^>]*>\s*(\d{4})')
      $season = if ($sm.Success) { [int]$sm.Groups[1].Value } else { $null }
    }
    $body = [regex]::Match($html, '<tbody class="table__body">([\s\S]*?)</tbody>')
    if (-not $body.Success) { continue }
    $rows = @()
    foreach ($tr in [regex]::Matches($body.Groups[1].Value, '<tr[^>]*>([\s\S]*?)</tr>')) {
      $c = @([regex]::Matches($tr.Groups[1].Value, '<td[^>]*>([\s\S]*?)</td>') | ForEach-Object { Html-Text $_.Groups[1].Value })
      if ($c.Count -lt 3 -or $c[0] -notmatch '^\d+$') { continue }
      $rows += , [ordered]@{ pos = $c[0]; name = $c[1]; pts = $c[2] }
    }
    if ($rows.Count) { $tables += , [ordered]@{ title = $t[1]; rows = $rows } }
  }
  if (-not $tables.Count) { return $null }
  [ordered]@{ season = $season; tables = $tables }
}

function Update-GTWC {
  $cal = Get-GtwcCalendar
  $events = foreach ($c in $cal) {
    $y = [int]$c.start.Substring(0, 4)
    New-Event 'GTWC' $y $c.name $c.name $c.country $c.start $c.end @() 'gt-world-challenge-europe.com'
  }
  $season = $Year
  $results = Get-GtwcResults $season $cal
  if ($results.Count -eq 0) { $season = $Year - 1; $results = Get-GtwcResults $season $cal }
  $standings = Get-GtwcStandings
  if ($standings -and -not $standings.season) { $standings.season = $season }
  return @{ events = @($events); results = $results; standings = $standings }
}

# ---------------------------------------------------------------- Gemeinsame Helfer (Tabellen, Wikipedia)

function TitleCase([string]$s) {
  $t = $Inv.TextInfo.ToTitleCase($s.Trim().ToLowerInvariant())
  return ($t -replace ' Of ', ' of ' -replace ' The ', ' the ' -replace ' De ', ' de ' -replace ' Del ', ' del ')
}

function Get-TableRows([string]$tableHtml) {
  $rows = @()
  foreach ($tr in [regex]::Matches($tableHtml, '<tr[^>]*>([\s\S]*?)</tr>')) {
    $inner = $tr.Groups[1].Value -replace '<style[\s\S]*?</style>', '' -replace '<sup[\s\S]*?</sup>', ''
    $cells = @([regex]::Matches($inner, '<t[dh][^>]*>([\s\S]*?)</t[dh]>') | ForEach-Object { Html-Text $_.Groups[1].Value })
    if ($cells.Count) { $rows += , $cells }
  }
  return , $rows
}

function Get-WikiTables([string]$html) {
  # alle class="wikitable"-Tabellen, auch wenn sie in Layout-Tabellen verschachtelt sind
  $out = @()
  foreach ($m in [regex]::Matches($html, '<table[^>]*class="[^"]*wikitable[^"]*"[^>]*>')) {
    $depth = 0; $pos = $m.Index
    $tok = [regex]::new('<table\b|</table>')
    $t = $tok.Match($html, $pos)
    while ($t.Success) {
      if ($t.Value -eq '</table>') { $depth-- } else { $depth++ }
      if ($depth -eq 0) { break }
      $t = $t.NextMatch()
    }
    if (-not $t.Success) { continue }
    $body = $html.Substring($m.Index, $t.Index + 8 - $m.Index)
    # verschachtelte Tabellen (z. B. Legenden) entfernen
    $body = $m.Value + [regex]::Replace($body.Substring($m.Length), '<table[\s\S]*?</table>', '')
    $out += , (Get-TableRows $body)
  }
  return , $out
}

function Get-HtmlTables([string]$html) {
  # Liefert pro <table> eine Liste von Zeilen (Array von Zelltexten); Kopfzeilen inklusive
  $out = @()
  foreach ($t in [regex]::Matches($html, '<table[\s\S]*?</table>')) {
    $rows = @()
    foreach ($tr in [regex]::Matches($t.Value, '<tr[^>]*>([\s\S]*?)</tr>')) {
      $inner = $tr.Groups[1].Value -replace '<style[\s\S]*?</style>', '' -replace '<sup[\s\S]*?</sup>', ''
      $cells = @([regex]::Matches($inner, '<t[dh][^>]*>([\s\S]*?)</t[dh]>') | ForEach-Object { Html-Text $_.Groups[1].Value })
      if ($cells.Count) { $rows += , $cells }
    }
    $out += , $rows
  }
  return , $out
}

function Get-WikiSectionHtml([string]$page, [string]$titleRegex) {
  $s = Get-Json "https://en.wikipedia.org/w/api.php?action=parse&page=$page&prop=sections&format=json&formatversion=2&redirects=1"
  $sec = Arr $s.parse.sections | Where-Object { $_.line -match $titleRegex } | Select-Object -First 1
  if (-not $sec) { return $null }
  Start-Sleep -Milliseconds 800
  $p = Get-Json "https://en.wikipedia.org/w/api.php?action=parse&page=$page&prop=text&section=$($sec.index)&format=json&formatversion=2&disabletoc=1&redirects=1"
  Start-Sleep -Milliseconds 800
  return $p.parse.text
}

function Get-WikiTable([string]$page, [string]$titleRegex, [string]$headerRegex) {
  # erste wikitable des Abschnitts, deren Kopfzeile zu $headerRegex passt
  $html = Get-WikiSectionHtml $page $titleRegex
  if (-not $html) { return $null }
  foreach ($t in (Get-WikiTables $html)) {
    if ($t.Count -gt 1 -and ($t[0] -join '|') -match $headerRegex) { return , $t }
  }
  return $null
}

function Results-FromStandings($table, $roundNames, [string]$series, [int]$season, $roundDates, [string]$note) {
  # Rekonstruiert Rennergebnisse aus einer Wikipedia-Meisterschaftstabelle (eine Spalte je Lauf)
  $head = $table[0]
  # Spaltenzahl aus den Datenzeilen (Kopfzellen können zusammengefasst sein, z. B. Doppelrennen)
  $width = ($table | Select-Object -Skip 1 | Where-Object { $_[0] -match '^\d+$' } | ForEach-Object { $_.Count } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name
  if (-not $width) { return @() }
  $width = [int]$width
  $first = 2; $last = $width - 2
  $out = @()
  for ($c = $first; $c -le $last; $c++) {
    $i = $c - $first
    $rows = @()
    foreach ($r in ($table | Select-Object -Skip 1)) {
      if ($r.Count -ne $width -or $r[0] -notmatch '^\d+$') { continue }
      $cell = "$($r[$c])".Trim()
      if (-not $cell) { continue }
      $m = [regex]::Match($cell, '^(\d+)')
      $pts = $null
      $pm = [regex]::Match($cell, '\s(\d+(?:\+\d+)*)$')
      if ($pm.Success) { $pts = (($pm.Groups[1].Value -split '\+') | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum }
      if ($m.Success) { $rows += , @{ p = [int]$m.Groups[1].Value; row = (New-Row -pos $m.Groups[1].Value -driver $r[1] -pts $pts) } }
      else { $rows += , @{ p = 999; row = (New-Row -driver $r[1] -status ($cell -split '\s')[0] -pts $pts) } }
    }
    $ranked = @($rows | Where-Object { $_.p -lt 999 })
    if ($ranked.Count -eq 0) { continue }
    $name = if ($i -lt @($roundNames).Count) { $roundNames[$i] } elseif ($c -lt $head.Count) { $head[$c] } else { "Lauf $($i + 1)" }
    $date = if ($roundDates -and $i -lt @($roundDates).Count) { $roundDates[$i] } else { $null }
    $out += , [ordered]@{
      id = "$($series.ToLowerInvariant())-$season-$(Slug $name)"; series = $series; season = $season; round = $i + 1
      name = $name; circuit = $name; date = $date; note = $note
      sessions = @([ordered]@{ name = 'Rennen'; type = 'race'; rows = @($rows | Sort-Object { $_.p } | ForEach-Object { $_.row }) })
    }
  }
  return $out
}

function Standings-FromWiki($table, [string]$title) {
  $rows = foreach ($r in ($table | Select-Object -Skip 1)) {
    if ($r[0] -notmatch '^\d+$') { continue }
    [ordered]@{ pos = $r[0]; name = $r[1]; pts = $r[-1] }
  }
  [ordered]@{ title = $title; rows = @($rows) }
}

function Fix-Offset([string]$s) { return ($s -replace '([+-]\d\d)(\d\d)$', '$1:$2') }

# ---------------------------------------------------------------- FIA WEC (fiawec.com)

$WecBase = 'https://www.fiawec.com'

function Get-WecSessionName([string]$n) {
  switch -Regex ($n) {
    '^Free Practice (\d)(.*)$' { return "$($Matches[1]). Freies Training$($Matches[2])" }
    '^Race$'                   { return 'Rennen' }
    default                    { return $n }
  }
}

function Update-WEC {
  $wecHome = Get-Text "$WecBase/en"
  $slugs = [regex]::Matches($wecHome,'href="(?:https://www\.fiawec\.com)?/en/race/([a-z0-9-]+-(\d{4}))"') |
    Where-Object { [int]$_.Groups[2].Value -ge $Year -and [int]$_.Groups[2].Value -le ($Year + 1) -and $_.Groups[1].Value -notmatch 'prologue' } |
    ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  $events = @(); $results = @()
  foreach ($slug in $slugs) {
    $page = Get-Text "$WecBase/en/race/$slug"
    Start-Sleep -Milliseconds 300
    $ld = $null
    foreach ($m in [regex]::Matches($page, '<script type="application/ld\+json">([\s\S]*?)</script>')) {
      try { $j = $m.Groups[1].Value | ConvertFrom-Json } catch { continue }
      if ($j.'@type' -eq 'SportsEvent') { $ld = $j; break }
    }
    if (-not $ld) { continue }
    $season = [int]($slug -replace '.*-(\d{4})$', '$1')
    $name = ($ld.name -replace '^WEC\s+', '' -replace "\s+$season$", '').Trim()
    $st = [DateTimeOffset]::Parse("$($ld.startDate)", $Inv); $en = [DateTimeOffset]::Parse("$($ld.endDate)", $Inv)
    $raceMin = 360
    if ($name -match '(\d+)\s*Hours') { $raceMin = [int]$Matches[1] * 60 } elseif ($name -match '1812') { $raceMin = 600 }
    $loc = ''
    if ($ld.location -and $ld.location.address) { $loc = "$($ld.location.address)" }
    $i = 0
    $sessions = foreach ($s in (Arr $ld.subEvent)) {
      if (-not $s.startDate) { continue }
      $i++
      $sn = ($s.name -replace "\s+-\s+$([regex]::Escape($name))$", '' -replace '\s+-\s+', ' ').Trim()
      $type = if ($sn -match '^Race') { 'race' } elseif ($sn -match 'Qualifying|Hyperpole') { 'quali' } else { 'practice' }
      $dur = switch ($type) { 'race' { $raceMin } 'quali' { 20 } default { 90 } }
      $ss = [DateTimeOffset]::Parse("$($s.startDate)", $Inv)
      New-Session "wec-$season-$(Slug $name)-$i" (Get-WecSessionName $sn) $type (To-Utc $ss) (To-Utc $ss.AddMinutes($dur))
    }
    $ev = New-Event 'WEC' $season $name $(if ($ld.location.name) { $ld.location.name } else { $name }) $loc `
      $st.ToString('yyyy-MM-dd', $Inv) $en.ToString('yyyy-MM-dd', $Inv) @($sessions | Sort-Object { $_.start }) 'fiawec.com'
    $events += , $ev

    # Ergebnisse (Hypercar-Klassement; andere Klassen lädt die Seite nur per JavaScript)
    $links = [regex]::Matches($page, 'resultats-1\?raceId=(\d+)&amp;sessionId=(\d+)') | ForEach-Object { @{ race = $_.Groups[1].Value; sess = $_.Groups[2].Value } }
    if (-not $links) { continue }
    $first = @($links)[0]
    $rp = Get-Text "$WecBase/en/page/resultats-1?raceId=$($first.race)&sessionId=$($first.sess)"
    Start-Sleep -Milliseconds 300
    $opts = [regex]::Matches($rp, 'option class="form-check-input"\s*(?:selected)?\s*value="(\d+)">([^<]+)<') | ForEach-Object { @{ id = $_.Groups[1].Value; name = $_.Groups[2].Value.Trim() } }
    $want = @($opts | Where-Object { $_.name -match '^(RACE|HYPERPOLE - HYPERCAR|QUALIFYING - HYPERCAR)$' -and (@($links | ForEach-Object { $_.sess }) -contains $_.id) })
    $rsess = @()
    foreach ($o in ($want | Sort-Object { if ($_.name -eq 'RACE') { 2 } elseif ($_.name -match 'HYPERPOLE') { 1 } else { 0 } })) {
      $html = if ($o.id -eq $first.sess) { $rp } else { Get-Text "$WecBase/en/page/resultats-1?raceId=$($first.race)&sessionId=$($o.id)" }
      Start-Sleep -Milliseconds 300
      $tm = [regex]::Match($html, '<table class="table table-sm table-standing[\s\S]*?</table>')
      if (-not $tm.Success) { continue }
      $heads = @([regex]::Matches([regex]::Match($tm.Value, '<thead[\s\S]*?</thead>').Value, '<t[hd][^>]*>([\s\S]*?)</t[hd]>') | ForEach-Object { (Html-Text $_.Groups[1].Value).ToLowerInvariant() })
      $map = @{ 'pos.' = 'pos'; 'n°' = 'no'; 'team' = 'team'; 'laps' = 'laps'; 'total time' = 'time'; 'time' = 'time'; 'gap' = 'gap'; 'best lap' = 'best' }
      $rows = foreach ($tr in [regex]::Matches([regex]::Match($tm.Value, '<tbody>([\s\S]*?)</tbody>').Groups[1].Value, '<tr[^>]*>([\s\S]*?)</tr>')) {
        $cells = @([regex]::Matches($tr.Groups[1].Value, '<td[^>]*>([\s\S]*?)</td>') | ForEach-Object { Html-Text $_.Groups[1].Value })
        $r = [ordered]@{ cls = 'Hypercar' }
        for ($k = 0; $k -lt [Math]::Min($cells.Count, $heads.Count); $k++) {
          $key = $map[$heads[$k]]
          if ($key -and $cells[$k] -ne '' -and $cells[$k] -ne '-') { $r[$key] = ($cells[$k] -replace '^#', '') }
        }
        $r
      }
      $label = switch -Regex ($o.name) { '^RACE$' { 'Rennen (Hypercar)' } 'HYPERPOLE' { 'Hyperpole (Hypercar)' } default { 'Qualifying (Hypercar)' } }
      if (@($rows).Count) { $rsess += , [ordered]@{ name = $label; type = $(if ($o.name -eq 'RACE') { 'race' } else { 'quali' }); rows = @($rows) } }
    }
    if ($rsess.Count) {
      $results += , [ordered]@{ id = $ev.id; series = 'WEC'; season = $season; name = $name; circuit = $ev.circuit; date = $ev.end; sessions = $rsess }
    }
  }

  # Meisterschaft
  $standings = $null
  $html = Get-Text "$WecBase/en/page/manufacturers-classification"
  $titles = @('Hypercar · Hersteller', 'Hypercar · Fahrer', 'LMGT3 · Teams', 'LMGT3 · Fahrer')
  $tables = @(); $n = 0
  foreach ($t in (Get-HtmlTables $html)) {
    $rows = foreach ($r in ($t | Select-Object -Skip 1)) {
      if ($r[0] -notmatch '^\d+$') { continue }
      $rest = @($r | Select-Object -Skip 1 | Where-Object { $_ -ne '' })
      $no = $rest | Where-Object { $_ -match '^#\d+' } | Select-Object -First 1
      $nm = $rest | Where-Object { $_ -notmatch '^#?\d+(\.\d+)?$' } | Select-Object -First 1
      $label = if ($no) { "$no $($Inv.TextInfo.ToTitleCase("$nm".ToLowerInvariant()))" } else { $Inv.TextInfo.ToTitleCase("$nm".ToLowerInvariant()) }
      [ordered]@{ pos = $r[0]; name = $label.Trim(); pts = ($r | Where-Object { $_ -ne '' } | Select-Object -Last 1) }
    }
    if (@($rows).Count) { $title = if ($n -lt $titles.Count) { $titles[$n] } else { "Wertung $($n + 1)" }; $tables += , [ordered]@{ title = $title; rows = @($rows) }; $n++ }
  }
  if ($tables.Count) { $standings = [ordered]@{ season = $Year; tables = $tables } }
  return @{ events = $events; results = $results; standings = $standings }
}

# ---------------------------------------------------------------- WRC (Wikipedia)

function Get-WrcCalendar([int]$season) {
  $t = Get-WikiTable "$($season)_World_Rally_Championship" '^Calendar$' 'Start date.*Rally'
  if (-not $t) { return @() }
  $h = $t[0]
  $iS = [array]::IndexOf($h, 'Start date'); $iE = [array]::IndexOf($h, 'Finish date'); $iR = [array]::IndexOf($h, 'Rally'); $iHq = [array]::IndexOf($h, 'Rally headquarters')
  $out = @()
  foreach ($r in ($t | Select-Object -Skip 1)) {
    if ($r[0] -notmatch '^\d+$' -or $r.Count -lt $h.Count) { continue }
    try {
      $s = [datetime]::ParseExact("$($r[$iS]) $season", 'd MMMM yyyy', $Inv)
      $e = [datetime]::ParseExact("$($r[$iE]) $season", 'd MMMM yyyy', $Inv)
    } catch { continue }
    $out += , @{ round = [int]$r[0]; name = $r[$iR]; hq = $(if ($iHq -ge 0) { $r[$iHq] -replace '\s+,', ',' } else { '' }); start = $s.ToString('yyyy-MM-dd', $Inv); end = $e.ToString('yyyy-MM-dd', $Inv) }
  }
  return $out
}

function Update-WRC {
  $events = @()
  $calCur = Get-WrcCalendar $Year
  foreach ($s in @($Year, ($Year + 1))) {
    $cal = if ($s -eq $Year) { $calCur } else { Get-WrcCalendar $s }
    foreach ($c in $cal) { $events += , (New-Event 'WRC' $s $c.name $c.name $c.hq $c.start $c.end @() 'Wikipedia (WRC-Saisonartikel)') }
  }
  $season = $Year
  $tbl = Get-WikiTable "$($season)_World_Rally_Championship" 'for Drivers' '^Pos\.?\|Driver'
  $results = @()
  if ($tbl) {
    $results = Results-FromStandings $tbl @($calCur | ForEach-Object { $_.name }) 'WRC' $season @($calCur | ForEach-Object { $_.end }) 'Ergebnis laut WM-Tabelle (punkteberechtigte WRC-Fahrer, Punkte inkl. Super Sunday/Power Stage)'
  }
  $tables = @()
  if ($tbl) { $tables += , (Standings-FromWiki $tbl 'Fahrer') }
  $co = Get-WikiTable "$($season)_World_Rally_Championship" 'for Co-Drivers' '^Pos\.?\|Co-driver'
  if ($co) { $tables += , (Standings-FromWiki $co 'Beifahrer') }
  $standings = if ($tables.Count) { [ordered]@{ season = $season; tables = $tables } } else { $null }
  return @{ events = $events; results = @($results); standings = $standings }
}

# ---------------------------------------------------------------- IndyCar (indycar.com + Wikipedia)

$MonthsShort = @{ jan = 1; feb = 2; mar = 3; apr = 4; may = 5; jun = 6; jul = 7; aug = 8; sep = 9; oct = 10; nov = 11; dec = 12 }

function Update-INDYCAR {
  try { $ny = [TimeZoneInfo]::FindSystemTimeZoneById('America/New_York') } catch { $ny = [TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time') }
  $html = Get-Text 'https://www.indycar.com/schedule'
  $marks = [regex]::Matches($html, 'event-card-header-date">([^<]+)<')
  $events = @()
  for ($k = 0; $k -lt $marks.Count; $k++) {
    $endIdx = if ($k + 1 -lt $marks.Count) { $marks[$k + 1].Index } else { $html.Length }
    $blk = $html.Substring($marks[$k].Index, $endIdx - $marks[$k].Index)
    $href = [regex]::Match($blk, 'href="/Schedule/(\d{4})/([^"]+)"')
    if (-not $href.Success) { continue }
    $yr = [int]$href.Groups[1].Value
    $dm = [regex]::Match($marks[$k].Groups[1].Value.Trim(), '^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})')
    if (-not $dm.Success) { continue }
    $date = Get-Date -Year $yr -Month $MonthsShort[$dm.Groups[1].Value.ToLowerInvariant()] -Day ([int]$dm.Groups[2].Value)
    $title = Html-Text ([regex]::Match($blk, 'class="event-card-title">([\s\S]*?)</').Groups[1].Value)
    $track = Html-Text ([regex]::Match($blk, 'class="event-card-track-name">([\s\S]*?)</').Groups[1].Value)
    $locn = Html-Text ([regex]::Match($blk, 'class="event-card-track-location">([\s\S]*?)</').Groups[1].Value)
    $time = Html-Text ([regex]::Match($blk, 'class="event-card-header-time">([\s\S]*?)</').Groups[1].Value)
    $name = if ($title) { $title } else { $href.Groups[2].Value -replace '-', ' ' }
    if ($href.Groups[2].Value -match 'Race(\d)$') { $name = "$name (Rennen $($Matches[1]))" }
    $key = $date.ToString('yyyy-MM-dd', $Inv)
    $sid = "indycar-$yr-$(Slug $href.Groups[2].Value)-race"
    $tm = [regex]::Match($time, '(\d{1,2}):(\d{2})\s*([AP]M)', 'IgnoreCase')
    if ($tm.Success) {
      $h = [int]$tm.Groups[1].Value % 12; if ($tm.Groups[3].Value -match 'P') { $h += 12 }
      $local = New-Object DateTime($date.Year, $date.Month, $date.Day, $h, [int]$tm.Groups[2].Value, 0)
      $st = New-Object DateTimeOffset($local, $ny.GetUtcOffset($local))
      $sess = @(New-Session $sid 'Rennen' 'race' (To-Utc $st) (To-Utc $st.AddMinutes(150)))
    } else {
      $sess = @(New-Session $sid 'Rennen (Startzeit folgt)' 'race' $key $key $true)
    }
    $ev = New-Event 'INDYCAR' $yr $name $track $locn $key $key $sess 'indycar.com'
    $ev.id = "indycar-$yr-$(Slug $href.Groups[2].Value)"
    $events += , $ev
  }

  # Ergebnisse + Stand über Wikipedia (indycar.com lädt sie nur per JavaScript)
  $season = $Year
  $page = "$($season)_IndyCar_Series"
  $sched = Get-WikiTable $page '^Schedule$' 'Race'
  $names = @(); $dates = @()
  if ($sched) {
    $h = $sched[0]
    $iN = -1; for ($x = 0; $x -lt $h.Count; $x++) { if ($h[$x] -match 'Race name|^Race$|Event') { $iN = $x; break } }
    $iD = [array]::IndexOf($h, 'Date')
    foreach ($r in ($sched | Select-Object -Skip 1)) {
      if ($r[0] -notmatch '^\d+$') { continue }
      $names += $(if ($iN -ge 0 -and $iN -lt $r.Count) { $r[$iN] } else { "Lauf $($r[0])" })
      $d = $null
      if ($iD -ge 0 -and $iD -lt $r.Count) { try { $d = ([datetime]::ParseExact("$($r[$iD] -replace '^[A-Za-z]+,\s*', '') $season", 'MMMM d yyyy', $Inv)).ToString('yyyy-MM-dd', $Inv) } catch {} }
      $dates += $d
    }
  }
  $tbl = Get-WikiTable $page 'Driver standings' '^Pos\.?\|Driver'
  $results = @(); $standings = $null
  if ($tbl) {
    $results = Results-FromStandings $tbl $names 'INDYCAR' $season $dates 'Zielankunft laut Meisterschaftstabelle (Wikipedia)'
    $standings = [ordered]@{ season = $season; tables = @(Standings-FromWiki $tbl 'Fahrer') }
  }
  return @{ events = $events; results = @($results); standings = $standings }
}

# ---------------------------------------------------------------- NASCAR Cup (cf.nascar.com)

function Update-NASCAR {
  $events = @(); $finished = @()
  foreach ($s in @($Year, ($Year + 1))) {
    try { $list = Get-Json "https://cf.nascar.com/cacher/$s/1/race_list_basic.json" } catch { continue }
    foreach ($r in (Arr $list)) {
      $sess = foreach ($x in (Arr $r.schedule | Where-Object { @(1, 2, 3) -contains [int]$_.run_type })) {
        $st = Parse-Utc "$($x.start_time_utc)"
        $type = @{ 1 = 'practice'; 2 = 'quali'; 3 = 'race' }[[int]$x.run_type]
        $nm = @{ 1 = 'Training'; 2 = 'Qualifying'; 3 = 'Rennen' }[[int]$x.run_type]
        $dur = @{ 1 = 50; 2 = 60; 3 = 210 }[[int]$x.run_type]
        New-Session "nascar-$s-$($r.race_id)-$type-$($st.ToString('ddHHmm', $Inv))" $nm $type (To-Utc $st) (To-Utc $st.AddMinutes($dur))
      }
      $sess = @($sess | Sort-Object { $_.start })
      $raceDay = "$($r.race_date)".Substring(0, 10)
      if ($sess.Count) {
        $start = ([TimeZoneInfo]::ConvertTime((Parse-Utc $sess[0].start), $Vienna)).ToString('yyyy-MM-dd', $Inv)
        $end = ([TimeZoneInfo]::ConvertTime((Parse-Utc $sess[-1].start), $Vienna)).ToString('yyyy-MM-dd', $Inv)
      } else { $start = $raceDay; $end = $raceDay; $sess = @(New-Session "nascar-$s-$($r.race_id)-race" 'Rennen (Startzeit folgt)' 'race' $raceDay $raceDay $true) }
      $ev = New-Event 'NASCAR' $s "$($r.race_name)".Trim() $r.track_name '' $start $end $sess 'nascar.com'
      $ev.id = "nascar-$s-$($r.race_id)"
      $events += , $ev
      if ($s -eq $Year -and [int]$r.winner_driver_id -gt 0) { $finished += , $r }
    }
  }
  $results = @()
  foreach ($r in $finished) {
    try { $w = Get-Json "https://cf.nascar.com/cacher/$Year/1/$($r.race_id)/weekend-feed.json" } catch { continue }
    Start-Sleep -Milliseconds 150
    $res = Arr (Arr $w.weekend_race)[0].results
    if (-not $res) { continue }
    $quali = foreach ($x in ($res | Where-Object { [int]$_.qualifying_position -gt 0 } | Sort-Object { [int]$_.qualifying_position })) {
      New-Row -pos $x.qualifying_position -no $x.car_number -driver $x.driver_fullname -team $x.team_name -car $x.car_make -best $(if ($x.qualifying_speed) { "$($x.qualifying_speed) mph" })
    }
    $race = foreach ($x in ($res | Sort-Object { [int]$_.finishing_position })) {
      New-Row -pos $x.finishing_position -no $x.car_number -driver $x.driver_fullname -team $x.team_name -car $x.car_make -laps $x.laps_completed -grid $x.starting_position -pts $x.points_earned -status $(if ($x.finishing_status -ne 'Running') { $x.finishing_status })
    }
    $sess = @()
    if (@($quali).Count) { $sess += , [ordered]@{ name = 'Qualifying'; type = 'quali'; rows = @($quali) } }
    $sess += , [ordered]@{ name = 'Rennen'; type = 'race'; rows = @($race) }
    $results += , [ordered]@{ id = "nascar-$Year-$($r.race_id)"; series = 'NASCAR'; season = $Year; name = $r.race_name; circuit = $r.track_name; date = "$($r.race_date)".Substring(0, 10); sessions = $sess }
  }
  $standings = $null
  try {
    $p = Get-Json "https://cf.nascar.com/cacher/$Year/1/points-feed.json"
    $rows = foreach ($x in (Arr $p | Sort-Object { [int]$_.position })) { [ordered]@{ pos = "$($x.position)"; name = $x.driver_name; team = $x.manufacturer; pts = "$($x.points)"; wins = "$($x.wins)" } }
    $standings = [ordered]@{ season = $Year; tables = @([ordered]@{ title = 'Fahrer'; rows = @($rows) }) }
  } catch {}
  return @{ events = $events; results = $results; standings = $standings }
}

# ---------------------------------------------------------------- MotoGP (Pulselive API)

$MgpApi = 'https://api.motogp.pulselive.com/motogp/v1'

function Strip-MgpSponsor([string]$n) {
  # "PETRONAS GRAND PRIX OF MALAYSIA" -> "GRAND PRIX OF MALAYSIA"
  $m = [regex]::Match($n.Trim(), '\b(GRAND PRIX|GRAN PREMI[O]?|GRANDE PR[EÉ]MIO)\b.*$', 'IgnoreCase')
  if ($m.Success) { return $m.Value } else { return $n.Trim() }
}

function Update-MOTOGP {
  $names = @{ FP1 = '1. Freies Training'; FP2 = '2. Freies Training'; PR = 'Practice'; Q1 = 'Qualifying 1'; Q2 = 'Qualifying 2'; SPR = 'Sprint'; WUP = 'Warm-up'; RAC = 'Rennen' }
  $types = @{ FP1 = 'practice'; FP2 = 'practice'; PR = 'practice'; Q1 = 'quali'; Q2 = 'quali'; SPR = 'sprint'; WUP = 'practice'; RAC = 'race' }
  $events = @()
  foreach ($s in @($Year, ($Year + 1))) {
    try { $list = Get-Json "$MgpApi/events?seasonYear=$s" } catch { continue }
    foreach ($e in (Arr $list)) {
      if ($e.kind -ne 'GP' -or -not $e.date_start) { continue }
      $name = TitleCase (Strip-MgpSponsor $e.name)
      $sess = foreach ($b in (Arr $e.broadcasts | Where-Object { $_.type -eq 'SESSION' -and $_.category.acronym -eq 'MGP' -and $names.ContainsKey($_.shortname) })) {
        $st = [DateTimeOffset]::Parse((Fix-Offset $b.date_start), $Inv); $en = [DateTimeOffset]::Parse((Fix-Offset $b.date_end), $Inv)
        New-Session "motogp-$s-$(Slug $name)-$($b.shortname.ToLowerInvariant())" $names[$b.shortname] $types[$b.shortname] (To-Utc $st) (To-Utc $en)
      }
      $country = if ($e.circuit) { $e.circuit.country } else { '' }
      $circuit = if ($e.circuit) { $e.circuit.name } else { $name }
      $ev = New-Event 'MOTOGP' $s $name $circuit $country "$($e.date_start)".Substring(0, 10) "$($e.date_end)".Substring(0, 10) @($sess | Sort-Object { $_.start }) 'motogp.com'
      $events += , $ev
    }
  }

  $seasons = Arr (Get-Json "$MgpApi/results/seasons")
  $cur = $seasons | Where-Object { $_.current } | Select-Object -First 1
  $cats = Arr (Get-Json "$MgpApi/results/categories?seasonUuid=$($cur.id)")
  $cat = ($cats | Where-Object { $_.name -match '^MotoGP' } | Select-Object -First 1).id
  $evs = Arr (Get-Json "$MgpApi/results/events?seasonUuid=$($cur.id)&isFinished=true") | Where-Object { -not $_.test } | Sort-Object { $_.date_start }
  $results = @()
  foreach ($e in $evs) {
    $ss = Arr (Get-Json "$MgpApi/results/sessions?eventUuid=$($e.id)&categoryUuid=$cat")
    Start-Sleep -Milliseconds 150
    $sessions = @()
    foreach ($s in ($ss | Where-Object { @('Q', 'SPR', 'RAC') -contains $_.type -and $_.status -ne 'CANCELLED' } | Sort-Object { $_.date })) {
      try { $c = Get-Json "$MgpApi/results/session/$($s.id)/classification?test=false" } catch { continue }
      Start-Sleep -Milliseconds 150
      $isQ = $s.type -eq 'Q'
      $rows = foreach ($x in (Arr $c.classification)) {
        $gap = if ($x.gap -and $x.gap.first -and $x.gap.first -ne '0.000') { "+$($x.gap.first)" } else { $null }
        if ($isQ) {
          New-Row -pos $x.position -no $x.rider.number -driver $x.rider.full_name -team $x.team.name -car $x.constructor.name -best $x.best_lap.time -gap $gap -laps $x.total_laps
        } else {
          New-Row -pos $x.position -no $x.rider.number -driver $x.rider.full_name -team $x.team.name -car $x.constructor.name -laps $x.total_laps -time $x.time -gap $gap -pts $(if ($x.points) { $x.points }) -status $(if (-not $x.position) { $x.status })
        }
      }
      if (-not @($rows).Count) { continue }
      $label = switch ($s.type) { 'Q' { "Qualifying $($s.number)" } 'SPR' { 'Sprint' } default { 'Rennen' } }
      $sessions += , [ordered]@{ name = $label; type = $(if ($isQ) { 'quali' } elseif ($s.type -eq 'SPR') { 'sprint' } else { 'race' }); rows = @($rows) }
    }
    if (-not $sessions.Count) { continue }
    $nm = TitleCase (Strip-MgpSponsor $e.name)
    $results += , [ordered]@{ id = "motogp-$($cur.year)-$(Slug $nm)"; series = 'MOTOGP'; season = [int]$cur.year; name = $nm; circuit = $(if ($e.circuit) { $e.circuit.name } else { $nm }); date = "$($e.date_end)".Substring(0, 10); sessions = $sessions }
  }

  $standings = $null
  $st = Get-Json "$MgpApi/results/standings?seasonUuid=$($cur.id)&categoryUuid=$cat"
  $rows = foreach ($x in (Arr $st.classification)) { [ordered]@{ pos = "$($x.position)"; name = $x.rider.full_name; team = $x.team.name; pts = "$($x.points)"; wins = "$($x.race_wins)" } }
  if (@($rows).Count) { $standings = [ordered]@{ season = [int]$cur.year; tables = @([ordered]@{ title = 'Fahrer'; rows = @($rows) }) } }
  return @{ events = $events; results = $results; standings = $standings }
}

# ---------------------------------------------------------------- Seeds & manuelle Session-Zeiten

function Merge-Seeds($events, $seedEvents) {
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($e in $events) { $list.Add($e) | Out-Null }
  foreach ($s in $seedEvents) {
    $overlap = $list | Where-Object {
      $_.series -eq $s.series -and $_.start -le ([datetime]$s.end).AddDays(2).ToString('yyyy-MM-dd') -and $_.end -ge ([datetime]$s.start).AddDays(-2).ToString('yyyy-MM-dd')
    }
    if ($overlap) { continue }
    $cup = if ($s.cup) { $s.cup } else { '' }
    $list.Add((New-Event $s.series ([int]$s.season) $s.name $s.circuit $s.location $s.start $s.end @() 'Offizieller Saisonkalender (manuell erfasst)' $cup)) | Out-Null
  }
  return $list
}

function Apply-Overrides($events, $overrides) {
  foreach ($o in $overrides) {
    $ev = $events | Where-Object { $_.series -eq $o.series -and $_.start -le $o.event -and $_.end -ge $o.event } | Select-Object -First 1
    if (-not $ev) { Write-Log "Override ohne passendes Event: $($o.series) $($o.event)"; continue }
    $i = 0
    $ev.sessions = @(foreach ($s in (Arr $o.sessions)) {
      $i++
      $st = [DateTimeOffset]::Parse($s.start, $Inv)
      $en = if ($s.end) { [DateTimeOffset]::Parse($s.end, $Inv) } else { $st.AddMinutes($(if ($s.minutes) { [int]$s.minutes } else { 60 })) }
      New-Session "$($ev.id)-m$i" $s.name $(if ($s.type) { $s.type } else { 'race' }) (To-Utc $st) (To-Utc $en)
    })
  }
}

# ---------------------------------------------------------------- iCalendar

function Ics-Escape([string]$s) { ($s -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n') }

function Ics-Fold([string]$line) {
  $sb = New-Object System.Text.StringBuilder
  $bytes = 0; $limit = 75
  foreach ($ch in $line.ToCharArray()) {
    $n = $Utf8.GetByteCount([string]$ch)
    if ([char]::IsHighSurrogate($ch)) { $n = 4 } elseif ([char]::IsLowSurrogate($ch)) { $n = 0 }
    if ($bytes + $n -gt $limit) { [void]$sb.Append("`r`n "); $bytes = 1; $limit = 75 }
    [void]$sb.Append($ch); $bytes += $n
  }
  return $sb.ToString()
}

function Write-Ics($events, [string]$calName, [string]$path) {
  $L = New-Object System.Collections.Generic.List[string]
  $stamp = $Now.UtcDateTime.ToString("yyyyMMdd'T'HHmmss'Z'", $Inv)
  foreach ($x in @('BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Motorsport-Kalender//DE', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
                   "X-WR-CALNAME:$calName", 'X-WR-TIMEZONE:Europe/Vienna', 'REFRESH-INTERVAL;VALUE=DURATION:PT6H', 'X-PUBLISHED-TTL:PT6H')) { $L.Add($x) }
  foreach ($e in $events) {
    $short = $SeriesInfo[$e.series].short
    $loc = (@($e.circuit, $e.location) | Where-Object { $_ } | Select-Object -Unique) -join ', '
    $desc = "$($SeriesInfo[$e.series].name)$(if ($e.cup) { " – $($e.cup)" })`n$($e.name)`nZeiten ohne Gewähr. Quelle: $($e.source)"
    $items = @($e.sessions)
    if ($items.Count -eq 0) {
      $items = @(New-Session "$($e.id)-weekend" 'Rennwochenende' 'weekend' $e.start $e.end $true)
    }
    foreach ($s in $items) {
      $L.Add('BEGIN:VEVENT')
      $L.Add("UID:$($s.id)@motorsport-kalender")
      $L.Add("DTSTAMP:$stamp")
      if ($s.allDay) {
        $L.Add("DTSTART;VALUE=DATE:$($s.start.Replace('-', ''))")
        $L.Add("DTEND;VALUE=DATE:$(([datetime]::ParseExact($s.end, 'yyyy-MM-dd', $Inv)).AddDays(1).ToString('yyyyMMdd', $Inv))")
      } else {
        $L.Add("DTSTART:$((Parse-Utc $s.start).UtcDateTime.ToString("yyyyMMdd'T'HHmmss'Z'", $Inv))")
        $L.Add("DTEND:$((Parse-Utc $s.end).UtcDateTime.ToString("yyyyMMdd'T'HHmmss'Z'", $Inv))")
      }
      $L.Add((Ics-Fold "SUMMARY:$(Ics-Escape "$short · $($e.name) · $($s.name)")"))
      if ($loc) { $L.Add((Ics-Fold "LOCATION:$(Ics-Escape $loc)")) }
      $L.Add((Ics-Fold "DESCRIPTION:$(Ics-Escape $desc)"))
      $L.Add("CATEGORIES:$short")
      $L.Add('END:VEVENT')
    }
  }
  $L.Add('END:VCALENDAR')
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
  [IO.File]::WriteAllText($path, (($L -join "`r`n") + "`r`n"), $Utf8)
}

# ---------------------------------------------------------------- Main

if ($LibOnly) { return }

$dataDir = Join-Path $Root 'data'
$oldEvents = Read-JsonFile (Join-Path $dataDir 'events.json')
$oldStandings = Read-JsonFile (Join-Path $dataDir 'standings.json')
$oldMeta = Read-JsonFile (Join-Path $dataDir 'meta.json')
$seed = Read-JsonFile (Join-Path $dataDir 'manual/seed.json')
$overrides = Read-JsonFile (Join-Path $dataDir 'manual/sessions.json')

$allEvents = New-Object System.Collections.Generic.List[object]
$standings = [ordered]@{}
$meta = [ordered]@{ updated = (To-Utc $Now); series = [ordered]@{} }

foreach ($code in $SeriesInfo.Keys) {
  $data = $null
  if ($Only -contains $code) {
    Write-Log "Aktualisiere $code ..."
    try {
      $data = & "Update-$code"
      Save-Json ([ordered]@{ series = $code; updated = (To-Utc $Now); events = @($data.results) }) (Join-Path $dataDir "results/$($code.ToLowerInvariant()).json")
      $meta.series[$code] = [ordered]@{ ok = $true; updated = (To-Utc $Now); events = @($data.events).Count; results = @($data.results).Count }
      Write-Log "  $code ok: $(@($data.events).Count) Termine, $(@($data.results).Count) Ergebnis-Events"
    } catch {
      Write-Log "  $code FEHLER: $($_.Exception.Message)"
      $prev = if ($oldMeta -and $oldMeta.series.$code) { $oldMeta.series.$code.updated } else { $null }
      $meta.series[$code] = [ordered]@{ ok = $false; error = "$($_.Exception.Message)"; updated = $prev }
      $data = $null
    }
  }
  if ($data) {
    foreach ($e in $data.events) { $allEvents.Add($e) | Out-Null }
    if ($data.standings) { $standings[$code] = $data.standings }
  } else {
    # alte Daten dieser Serie weiterverwenden
    if ($oldEvents) { foreach ($e in (Arr $oldEvents.events | Where-Object { $_.series -eq $code -and $_.source -notmatch 'manuell' })) { $allEvents.Add($e) | Out-Null } }
    if ($oldStandings -and $oldStandings.$code) { $standings[$code] = $oldStandings.$code }
    if (-not $meta.series.Contains($code) -and $oldMeta -and $oldMeta.series.$code) { $meta.series[$code] = $oldMeta.series.$code }
  }
}

$merged = Merge-Seeds $allEvents (Arr $seed.events)
if ($overrides) { Apply-Overrides $merged (Arr $overrides.overrides) }

$events = @($merged | Where-Object { $_.end -ge $KeepFrom } | Sort-Object { $_.start }, { $_.series })
Save-Json ([ordered]@{ updated = (To-Utc $Now); timezone = 'Europe/Vienna'; events = $events }) (Join-Path $dataDir 'events.json')
Save-Json $standings (Join-Path $dataDir 'standings.json')
Save-Json $meta (Join-Path $dataDir 'meta.json')

$calDir = Join-Path $Root 'calendar'
Write-Ics $events 'Motorsport (alle Serien)' (Join-Path $calDir 'alle.ics')
foreach ($code in $SeriesInfo.Keys) {
  Write-Ics @($events | Where-Object { $_.series -eq $code }) "Motorsport · $($SeriesInfo[$code].name)" (Join-Path $calDir "$($code.ToLowerInvariant()).ics")
}

Write-Log "Fertig: $($events.Count) Termine gespeichert."
$failed = @($meta.series.Values | Where-Object { -not $_.ok }).Count
if ($failed -eq $SeriesInfo.Count) { Write-Log 'Alle Quellen fehlgeschlagen.'; exit 1 }
