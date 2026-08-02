# ADR 0093 — Song Trainer local time-model primitives (no Practice Engine reuse)

**Státusz:** elfogadva (E03-R03 pre-flight, 2026-08-02, orchestrátor: Claude
Sonnet 5). Formalizálja a
[`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) §10
(Zenei időmodell) tervezetének egy mért implementációs korlátozását. Előfeltétele
[ADR 0089](0089-song-document-v2.md) (SongDocument V2) és
[ADR 0092](0092-song-trainer-practice-engine-integration.md) (Song Trainer ×
Practice Engine határ).

## Kontextus

A §10.1 kimondja: „Az Epic 3 a Chapter 3 `BeatPosition`, `Tempo` és `Meter`
értékobjektumaira épít" — ahol „Chapter 3" a
[`docs/sdd/03-epic-02-practice-engine.md`](../sdd/03-epic-02-practice-engine.md)
(Practice Engine) fejezet, és a hivatkozott típusok ténylegesen a
`lib/features/practice/domain/model/beat_position.dart` / `tempo.dart` /
`meter.dart` fájlokban élnek (ADR 0066/0072, E02-R02).

Az E03-R03 pre-flightja megmérte, hogy ez a szó szerinti típusmegosztás **nem
elérhető** a jelenlegi, gate-kikényszerített szerződések mellett:

1. `test/features/song_trainer/domain/song_document_test.dart` „Domain
   purity" scannere (`_forbiddenPatterns['cross-feature import']`) tételesen
   tiltja a `package:strumsight/features/practice/` import mintát bármely
   `lib/features/song_trainer/domain/**` fájlban — **kivétel nélkül**, tehát a
   `practice/public.dart`-on keresztüli import is bukik. Ez a teszt **nem**
   szerepel az E03-R03 `allowed_paths` listáján, tehát ebben a körben nem
   módosítható; a teljes CI-suite futtatja, így a gate ténylegesen
   kikényszeríti.
2. Az architektúra-őr (`tool/check_architecture.dart`) `_isSharedDomain`
   allowlistje NEM tartalmazza a `lib/features/song_trainer/domain/`-t (csak
   `lib/core/music/`, `lib/core/audio/codec/`, `lib/features/practice/domain/`
   — R02 pre-flight mérése, lásd `song_trainer/domain/public.dart` komment),
   így ez a guard önmagában megengedné a `practice/public.dart` importot — de
   az (1) pontban mért, szigorúbb, ehhez a körhöz nem tartozó teszt ettől
   függetlenül buktatja.
3. [ADR 0092](0092-song-trainer-practice-engine-integration.md) §1/§4
   független forrásból is megerősíti: a Song Trainer ↔ Practice Engine
   kapcsolat kizárólag egy jövőbeli, application-szintű
   `SongPracticeCompiler` határon (E03-R19) él majd, nem domain-szintű
   típusmegosztáson — és annak Practice-oldali export-auditja is egy
   **külön, E03-R19-hez tartozó** pre-flight feladata.
4. Az architekturálisan tisztább megoldás — a `BeatPosition`/`Tempo`/`Meter`
   áthelyezése egy valódi megosztott `lib/core/music/` otthonba — ehhez a
   körhöz **nincs** hozzáférés: `lib/core/music/**` egyetlen fájlja sincs az
   E03-R03 `allowed_paths` listáján, és egy ilyen áthelyezés messze túlmutat
   a kör §3 scope-ján (section/measure/tempo/meter-map/SongTimeMap).

## Döntés

1. **A Song Trainer domain saját, lokális idő-primitíveket definiál**, nem
   importálja és nem terjeszti tovább a Practice Engine `BeatPosition` /
   `Tempo` / `Meter` típusait — sem közvetlenül, sem a `practice/public.dart`
   határon át. Ez a tiltás **véglegesen fennáll**, amíg a `song_document_test.dart`
   purity scannere vagy egy dedikált, jövőbeli ADR ezt kifejezetten fel nem
   oldja.
2. **A lokális idő-primitívek az E03-R03 már engedélyezett fájljain belül
   élnek** — nincs szükség új fájlra vagy `allowed_paths` bővítésre. Egész
   (nem lebegőpontos) tick-alapú pozíció- és BPM-alapú tempó-reprezentáció a
   `tempo_map.dart`/`song_time_map.dart` alá kerül; a `MeterChange` az SDD
   §10.3 szerint measure-index kulcsú (`atMeasure: int`), így a meter maphez
   **nem** kell pozíció-típus.
3. **A tervezési elvek — nem a típusok — öröklődnek a Chapter 3-ból.** Az
   implementáció ugyanazt a mintát követi, mint a Practice Engine
   precedense: egész/racionális köztes aritmetika (ADR 0066 480-PPQ
   precedens elve — a konkrét granularitást az implementáció méri és
   dokumentálja), egyetlen kerekítési pont a mikroszekundum-pontos
   szegmensenkénti konverzióban (ADR 0072 `BeatTimeConverter` precedens
   elve — szegmensenkénti egész-mikroszekundum összegzés, nem
   measure-enkénti lebegőpontos akkumuláció).
4. **A tényleges round-trip tolerancia és kerekítési szabály az
   implementáció mért kimenete**, nem ez az ADR rögzíti előre — a brief §5.4
   ezt kötelezi ("konkrétan mérve és dokumentálva"), a kör handoffja és a
   property teszt bizonyítja.
5. **Nem ehhez a körhöz tartozó follow-up:** egy jövőbeli kör dönthet úgy,
   hogy a Song Trainer és a Practice Engine idő-primitíveit egy közös
   `lib/core/music/` típusra konszolidálja — ez explicit, külön ADR-t és
   saját `allowed_paths`-ot igényel mindkét feature-ben; ez az ADR nem dönt
   e mellett vagy ellene, csak rögzíti, hogy E03-R03 nem az a kör.

## Alternatívák

- **`practice/public.dart` import a Song Trainer domainbe:** elvetve — a
  mért (1) pont szerint a teljes CI-suite buktatja, a purity teszt ehhez a
  körhöz nem módosítható; a zöld kapu enélkül elérhetetlen.
- **A purity teszt lazítása egy kivétellel a `practice` mintára:** elvetve —
  a teszt fájlja nincs az `allowed_paths` listán (tilos zóna, §4), a
  lazítás pontosan az a „mércegyengítés zöldre javítással" minta, amit a
  brief §5 kifejezetten tilt.
- **`BeatPosition`/`Tempo`/`Meter` áthelyezése `core/music`-ba ebben a
  körben:** elvetve — nincs a scope-ban, és egy ilyen refaktor önmagában
  megérne egy külön, célzott kört a Practice Engine oldali migrációval
  együtt.

## Következmények

- A Song Trainer és a Practice Engine idő-reprezentációja **tudatosan
  duplikált** marad E03-R03 után is — ez mért, dokumentált döntés, nem
  felügyelet nélküli drift.
- Az E03-R19 (Practice compiler) pre-flightjának explicit fel kell mérnie,
  hogyan alakul át a Song Trainer lokális pozíció-/tempó-reprezentációja
  Practice `BeatPosition`/`Tempo`/`Meter`-ré a `SongPracticeCompiler`
  határán (ADR 0092 §2) — ez már ismert munka, nem új felfedezés.
- Ha egy jövőbeli kör a konszolidáció mellett dönt, mindkét feature oldalán
  migrációs kört igényel; ez az ADR nem előlegezi meg azt a döntést.
