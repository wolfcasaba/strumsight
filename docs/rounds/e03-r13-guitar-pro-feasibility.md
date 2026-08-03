# E03-R13 — Guitar Pro feasibility és stratégiai döntés

- **Státusz:** **PLANNING** (2026-08-03, pre-flight baseline: `origin/main` @ `315b2b7`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 13; §17
- **Branch:** `codex/e03-r13-guitar-pro-feasibility`
- **Előfeltétel:** E03-R12 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/research/epic-03-guitar-pro-feasibility.md",
  "tool/guitar_pro_feasibility/pubspec.yaml",
  "tool/guitar_pro_feasibility/bin/run_spike.dart",
  "tool/guitar_pro_feasibility/lib/gp_spike.dart",
  "tool/guitar_pro_feasibility/test/gp_spike_test.dart",
  "test/fixtures/song_trainer/guitar_pro/README.md",
  "test/fixtures/song_trainer/guitar_pro/minimal_gp3.gp3",
  "test/fixtures/song_trainer/guitar_pro/minimal_gp5.gp5",
  "test/fixtures/song_trainer/guitar_pro/minimal_gpx.gpx",
  "docs/rounds/e03-r13-guitar-pro-feasibility.md",
]
gate_tests = [
  "test/features/song_trainer/data/importers",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, symbol, producer, resource owner, dependency/licence
> és numerikus cella mai állapotát. Drift esetén dokumentáld §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract/licence,
ellentmondó acceptance, hiányzó fixture vagy nem reprodukálható mérce esetén
`stopped`; nincs néma scope-tágítás vagy acceptance-gyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- Nincs jóváhagyott GP parser vagy aktív GP registry extension.
- MusicXML/MXL és MIDI biztonságos alternatív utak rendelkezésre állnak.
- Az ADR exact sorszáma az aktív ADR-katalógus pre-flight auditjában dől el.

**2026-08-03 pre-flight revízió (baseline `46e2a3d`):** `songImporterRegistryProvider`
(`lib/features/song_trainer/application/song_trainer_providers.dart:141`) ma
`NativeJsonImporter`, `MusicXmlImporter`, `MxlImporter` és `MidiImporter`
példányokat ad az egyetlen production `ImporterRegistry`-nek; Guitar Pro
importer nem létezik. A `SongSourceType.guitarPro` enum-tag előre lefoglalt
provenance-kód, nem aktív importképesség. A tényleges owner-mérés ezért nem
igényel production registry- vagy domain-változást. A következő szabad
ADR-sorszám az `0122`; a pre-flight az exact
`docs/adr/0122-guitar-pro-import-strategy.md` utat a §4 emberi táblájához
adta, de az implementer `ai-router.allowed_paths` listájából kikerült: az ADR
pre-flight-artefaktum, nem modell-írható fájl. Az R13/H6 nested-Dart-cache
heal (`46e2a3d`) a router scope-auditját kifejezetten erre az izolált tool
cache-re javította; a meglévő, jelzett modelldiff ugyanazzal a task state-tel
folytatható. Az izolált spike kizárólag saját, minimális, provenance-olt
technikai fixtureket használhat; nem adhat hozzá production dependencyt vagy
adaptert.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Bizonyíték-alapú, licence- és platformtudatos A/B/C Guitar Pro stratégia elfogadása production parserkód előtt.

## 2. Jelenlegi állapot

- Nincs jóváhagyott GP parser vagy aktív GP registry extension.
- MusicXML/MXL és MIDI biztonságos alternatív utak rendelkezésre állnak.
- Az ADR exact sorszáma az aktív ADR-katalógus pre-flight auditjában dől el.

## 3. Scope

**Benne:**

- legalább három reális opció kutatása vagy bizonyított hiánya
- izolált tool-spike jogtiszta technikai fixturekkel
- fidelity/platform/security/build-size mérések
- egy A/B/C döntés és elutasított utak indoklása

**Kívül — ebben a körben TILOS:**

- `lib/features/song_trainer/**` production GP parser
- aktív GP registry extension
- jogsértő converter/content source
- UI implementáció az R14 előtt

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `docs/research/epic-03-guitar-pro-feasibility.md` | ÚJ | összehasonlítás és mérések |
| `tool/guitar_pro_feasibility/pubspec.yaml` | ÚJ | izolált spike dependency |
| `tool/guitar_pro_feasibility/bin/run_spike.dart` | ÚJ | reprodukálható CLI |
| `tool/guitar_pro_feasibility/lib/gp_spike.dart` | ÚJ | adapter/probe |
| `tool/guitar_pro_feasibility/test/gp_spike_test.dart` | ÚJ | fixture assertion |
| `test/fixtures/song_trainer/guitar_pro/README.md` | ÚJ | provenance és expected values |
| `test/fixtures/song_trainer/guitar_pro/minimal_gp3.gp3` | ÚJ | technikai fixture |
| `test/fixtures/song_trainer/guitar_pro/minimal_gp5.gp5` | ÚJ | technikai fixture |
| `test/fixtures/song_trainer/guitar_pro/minimal_gpx.gpx` | ÚJ | technikai fixture |
| `docs/adr/0122-guitar-pro-import-strategy.md` | ÚJ | a §5 által előírt stratégiai ADR |
| `docs/rounds/e03-r13-guitar-pro-feasibility.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Production parser ADR nélkül tilos; ez a kör csak research/tool artefaktum.
2. ADR-téma kötött: Guitar Pro parser feasibility és A/B/C path. Exact ADR path pre-flightban kerül §4-be.
3. A/B/C: jóváhagyott Dart parser, jóváhagyott natív adapter, vagy konverziós workflow.
4. Fixture saját/jogtiszta, minimális és provenance-dokumentált.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Opciók licence, GP verzió, Android/iOS, offline, build size, fidelity, security, maintenance és effort szerint összevetve.
- [ ] Spike output reprodukálható; track/tuning/measure/note/string-fret/tempo/meter expected értékekkel összevetett.
- [ ] Az ADR egyetlen A/B/C döntést ad, rejection rationale és R14 activation contracttal.
- [ ] Nincs production feature vagy registry módosítás; licence bizonytalanság esetén A/B nem választható.

### Kötelező megkülönböztető mátrix

| Mért dimenzió | Kötelező evidencia |
|---|---|
| parse success/verzió | fixture×candidate táblázat |
| track/tuning/measure/note | expected vs actual delta |
| string/fret/tempo/meter | megőrzött/veszett/warning |
| mobile/offline/build size | reprodukálható build vagy dokumentált blocker |
| licence/maintenance/security | elsődleges forrás és dátum |
| crash/malformed | izolációs viselkedés |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/importers
```

A brief pre-flightja a feltételes szöveget egyetlen futtatható
`tools/round-gate.sh ...` parancsra cseréli, ha a kör döntési ágas. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. A pre-flight ossza ki az ADR exact pathját és adja a §4-hez.
2. Készítsd el a provenance-olt fixtureket és candidate összehasonlítást.
3. Írd meg és futtasd az izolált spike tesztet minden reális opción.
4. Dokumentáld a méréseket, majd fogadd el az egyetlen A/B/C döntést.
5. Futtasd az érintetlenségi round gate-et és töltsd ki a handoffot.

Javasolt commit: `research(song-import): decide Guitar Pro import strategy`.

## 9. Kockázatok

- Dependency licence vagy maintenance gyorsan változhat; R14 pre-flight újraellenőrzi.
- Natív spike lokális sikere nem bizonyít Android+iOS release buildet.
- Három reális opció hiányát keresési evidenciával kell igazolni, nem állítani.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r13-guitar-pro-feasibility-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
