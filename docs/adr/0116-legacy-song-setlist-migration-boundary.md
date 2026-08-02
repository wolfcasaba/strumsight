# ADR 0116 — Legacy Song/Setlist migration adapter: report boundary, meter/section defaulting, timing method

**Státusz:** elfogadva (E03-R06 pre-flight, 2026-08-02, orchestrátor: Claude
Sonnet 5). Formalizálja a
[`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md)
Kör 6 tervezetének a briefben implicit hagyott döntéseit.
Előfeltétele [ADR 0089](0089-song-document-v2.md),
[ADR 0093](0093-song-trainer-local-time-primitives.md),
[ADR 0113](0113-song-track-event-model.md) és
[ADR 0114](0114-song-validator-normalizer-capability-boundary.md).

## Kontextus

Az E03-R06 brief (`docs/rounds/e03-r06-legacy-song-setlist-adapters.md`) egy
veszteségmentes, determinisztikus legacy `Song`/`Setlist` →
`SongDocument` V2 adaptert ír le. A pre-flight a domain modell TÉNYLEGES
konstruktorait mérte ki (nem a dokumentációt feltételezte) — négy pont
bizonyult olyan valódi döntésnek, amit a brief §5 nem, vagy csak
implicit módon rögzít, és amit az implementer szabadon, egymástól eltérő
módon is megoldhatna:

1. **Nincs meglévő „adaptációs hűség" report-típus.** `SongValidationReport`
   (ADR 0114) a dokumentum SZERKEZETI invariánsait ellenőrzi (section-range,
   strum→chord cél, ismeretlen technika/akkord) — sosem a forrás-hűséget
   (pl. „ez az akkordcímke csonkolva lett", „ez a setlist-hivatkozás nem
   oldható fel"). Az `ImportWarning`/`ImportWarningCode`
   (`import_warning.dart`) egy meglévő, tipizált, csak-warning projekció, de
   a doksija szerint import-preview UI-nak készült, nem migrációs
   provenienciának. A `SongSource.warningSummary` egy lapos string-lista,
   kifejezetten „codec round-tripping"-re (a doksi szerint).
2. **A `Meter` konstruktor kötelező denominatort vár** (`Meter(numerator,
   denominator)`, a denominator 2-hatvány kell legyen), de a legacy `Song`
   modellnek nincs denominator mezője — csak `beatsPerBar` (mindig
   negyedhang-alapú: a `pattern` hossza `beatsPerBar * 2`, azaz nyolcadonként
   egy szlot).
3. **A `SongChordEvent`/`SongStrumEvent` `start`/`duration`/`at` mezői
   `Duration` (valós idő, mikroszekundum), NEM tick-alapúak** — ellentétben a
   `TempoMap`/`MeterMap`/`KeyMap` tick-alapú (`BeatPosition`) primitíváival.
   A legacy `Song.toAnalyzeResult()` már ma is közvetlenül valós
   másodpercben számol (`spb = 60.0 / bpm`, `bar * beatsPerBar * spb`) —
   nincs tick-konverziós lépés a legacy oldalon.
4. **A `SongSectionKind` enumnak nincs „egész dal, tagolatlan" értéke**
   (`intro, verse, preChorus, chorus, bridge, solo, breakdown, outro,
   custom`) — a brief „Full song section létrejön" mondata nem mondja meg,
   melyik kind-ot használja az adapter.

## Döntés 1 — `LegacyMigrationReport` önálló, adapter-lokális típus

A `legacy_migration_report.dart` (a kör §4 engedélyezett fájllistáján ÚJ)
**nem** a `SongValidationReport` vagy az `ImportWarning` kiterjesztése vagy
újrafelhasználása, hanem egy harmadik, önálló report-típus, kizárólag a
forrás→cél adaptáció hűségének leírására (pl. `chordLabelTruncated`,
`patternLengthFitted`, `setlistDuplicateRetained`,
`setlistReferenceUnresolved` — stabil, additív string-kódokkal, a domain
meglévő konvencióját követve).

**Indoklás:** a `SongValidationReport` a dokumentum SAJÁT belső
konzisztenciáját méri (R05 boundary) — ha a migrációs hűségi jegyzeteket bele
kevernénk, a validator kódkészlete a migrációs adapter élettartamához
kötődne, holott a validator minden jövőbeli `SongDocument`-forrásra
(kézi szerkesztés, MusicXML-import stb.) egységesen kell hogy vonatkozzon.
Az `ImportWarning` megmarad az UI-célú, warning-only projekciónak; a
migrációs adapter — ha szükséges — ebből ÁLLÍTHAT ELŐ egy vetületet, de nem
ez a saját belső reprezentációja.

A `LegacyMigrationReport` tartalmát a `SongSource.warningSummary`-be
(lapos string-lista, codec round-trip) egy determinisztikus,
ember-olvasható vetítéssel kell átvinni, hogy a fidelity-jegyzet túlélje a
mentés/betöltés ciklust — de maga a gazdag, tipizált
`LegacyMigrationReport` az adapter visszatérési értéke, nem storage-mező.

## Döntés 2 — Meter denominator mindig 4

A legacy `Song` sosem hordoz explicit denominatort; a `pattern` hossza
(`beatsPerBar * 2`) mindig nyolcad-alapú alosztást fejez ki egy
negyedhang-nevezőjű ütem felett. Az adapter tehát mindig
`Meter(song.beatsPerBar, 4)`-et épít — más denominator kitalálása
dokumentálatlan, bizonyíthatatlan viselkedés lenne.

## Döntés 3 — Esemény-időzítés: közvetlen szorzás, nem kumulatív összegzés

A `SongChordEvent.start`/`.duration` és `SongStrumEvent.at` mezők
`Duration`-ök (mikroszekundum-pontosságúak), a `TempoMap` ticket-alapú
primitíváitól FÜGGETLENÜL. Az adapter minden esemény idejét egyetlen,
közvetlen szorzással számítja (`measureIndex * beatsPerBar * spb` majd egyszeri
mikroszekundum-kerekítés), NEM az előző esemény idejéhez való kumulatív
hozzáadással — ez ugyanaz az „egyetlen kerekítési pont" elv, amit ADR 0093
§1.1 a tick-alapú időmodellre mond ki, csak itt a wall-clock `Duration`
mezőkre alkalmazva. A közvetlen szorzás strukturálisan kizárja a
sok-ütemes drift-et, amit egy kumulatív összegzés kockáztatna.

## Döntés 4 — Section kind: `custom`, „Full Song" névvel

A `SongSectionKind` egyetlen értéke sem fejezi ki egy tagolatlan legacy dal
egészét — a `custom` a helyes választás, `name: 'Full Song'` (vagy a legacy
dal saját `name`-je, ha az adapter úgy dönt) címkével. Az öt tagolt kind
(`verse`/`chorus`/stb.) használata hamis szemantikai állítás lenne egy
olyan legacy rekordról, ami sosem hordozott section-információt.

## Következmény

- A `LegacyMigrationReport` kódkészlete additív és stabil, saját fájlban él
  — a validator/import-warning kódkészletek NEM bővülnek migrációs
  esetekkel.
- `Meter(beatsPerBar, 4)` minden migrált dokumentumon — nincs más
  denominator-ág, tesztelhető invariáns.
- Az időzítés-számítás közvetlen szorzással reprodukálható és a legacy
  `toAnalyzeResult()` képletével bitre összevethető (parity-teszt alapja).
- A section-kind döntés dokumentált, tesztelhető (`SongSectionKind.custom`)
  — a reviewer ellenőrizheti, hogy nincs kitalált tagolás.

Ezen döntések feloldása „zöldre javításként" nem elfogadható; valódi
ellentmondás esetén ez az ADR egy módosítási blokkal bővítendő, nem
csendben felülírandó.
