# E03-R05 — Validator, normalizer és capability resolver

- **Státusz:** **PLANNING** (2026-08-02, pre-flight: orchestrátor Claude
  Sonnet 5, tervezési baseline: `main` @ `d37aa1c`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 5; §7, §12
- **Branch:** `codex/e03-r05-validator-normalizer-capabilities`
- **Előfeltétel:** E03-R04 merge
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent
- **ADR:** [0114](../adr/0114-song-validator-normalizer-capability-boundary.md)
  (a pre-flight írta, ld. §0.0)

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/song_trainer/domain/services/song_validator.dart",
  "lib/features/song_trainer/domain/services/song_normalizer.dart",
  "lib/features/song_trainer/domain/services/song_capability_resolver.dart",
  "lib/features/song_trainer/domain/models/song_validation_report.dart",
  "lib/features/song_trainer/domain/models/song_capability.dart",
  "lib/features/song_trainer/domain/models/import_warning.dart",
  "lib/features/song_trainer/domain/public.dart",
  "test/features/song_trainer/domain/song_validator_test.dart",
  "test/features/song_trainer/domain/song_normalizer_test.dart",
  "test/features/song_trainer/domain/song_capability_resolver_test.dart",
  "test/property/song_normalizer_property_test.dart",
  "docs/rounds/e03-r05-validator-normalizer-capabilities.md",
]
gate_tests = [
  "test/features/song_trainer/domain/song_validator_test.dart",
  "test/features/song_trainer/domain/song_normalizer_test.dart",
  "test/features/song_trainer/domain/song_capability_resolver_test.dart",
  "test/property/song_normalizer_property_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold a brief minden útvonalát, symbolját, state producerét, resource
> ownerét és numerikus celláját. Drift esetén dokumentáld lent §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer indítása előtt. A `PREPARED` brief önmagában
> nem végrehajtási engedély.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract, ellentmondó
acceptance, hiányzó fixture/licence, vagy nem reprodukálható mérce esetén:
`stopped` és pontos jelentés; nincs néma scope-tágítás vagy mércegyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- R04 után a teljes domain reprezentálható, de invalid dokumentum is konstruálható.
- A SongDocument még nem rendelkezik profile-alapú validation/capability gate-tel.
- A normalizer nem találhat ki bizonytalan zenei jelentést.

A pre-flight az itt leírt tényeket újraméri. Ha bármelyik eltér, ebben a
szekcióban rögzíti a mért állapotot, a választott feloldást és annak indokát.
Üres vagy implicit revízióval a státusz nem válhat `PLANNING`-re.

**Pre-flight mérés (2026-08-02, baseline `main` @ `d37aa1c`):** a fenti három
állítás a tényleges kóddal egyezik — nincs drift, a scope/fájllista
változatlan marad. A két kötelező mérési szabály (elérhetetlen cél-státusz,
erőforrás-tulajdonlás) eredménye:

1. **Cél-státuszok, INPUT-tal igazolva:**
   - `NoteTrack` „polyphonic" — `NoteTrackAnalyzer.analyze` (E03-R04,
     `lib/features/song_trainer/domain/services/note_track_analyzer.dart:182`)
     `isMonophonic = overlapCount == 0`; az inputot egy sweep-line állítja
     elő két különböző pitch-ű, időben átfedő `SongNoteEvent`-ből — VALÓDI,
     mért producer, a kör capability resolvere ezt közvetlenül fogyaszthatja.
   - „fatal range/map" — `SongSection` (`song_section.dart:30-36`) ÉS
     `SongDocument` (`song_document.dart:98-129`) ma **csak önmagát**
     validálja (pl. `startMeasure < endMeasureExclusive`), **nem** a
     testvér kollekciók ellen (egy `SongSection.endMeasureExclusive` a
     dokumentum tényleges `measures.length`-én túlra mutathat úgy, hogy
     egyik konstruktor sem bukik el ma) — ez egy VALÓS, elérhető, ma
     detektálatlan input, tehát a dokumentum-szintű validátornak van mit
     ellenőriznie (nem üres célállapot).
   - „unknown chord" — a `Chord` (`core/music/chord.dart`) validálatlan
     `label`-wrapper, tehát a „support" fogalmat ennek a körnek KELL
     bevezetnie; nincs előzetes producer, mert nincs előzetes definíció —
     ld. ADR 0114 Döntés 1.
2. **Erőforrás-tulajdonlás:** ennek a körnek nincs lease/lock/handle/
   subscription jellegű erőforrása (tiszta value-in/value-out domain
   szolgáltatások) — a szabály nem alkalmazható, nincs mit mérni.

**ADR 0114 felvéve** (`docs/adr/0114-song-validator-normalizer-capability-boundary.md`,
a §4 emberi táblájába bekötve, az `ai-router` TOML `allowed_paths`-ából
szándékosan kihagyva) két mért, a briefben implicit hagyott döntés
formalizálására:

- **Chord-support határ:** az egyetlen ma létező maj/min szótár
  (`lib/features/practice/data/adapters/legacy_chord_label.dart`,
  `legacyPracticeChordLabel`) a `practice` feature alatt él, és a
  domain-purity scanner (`test/features/song_trainer/domain/song_document_test.dart`
  `_forbiddenPatterns['cross-feature import']`) a `practice` importot
  explicit tiltja — ráadásul nincs is az `allowed_paths` listán (H3). A
  capability resolver „támogatott akkord" fogalma tehát **önálló,
  domain-lokális grammatika**, nem a practice-dictionary importja vagy
  másolata (ADR 0114 Döntés 1).
- **Severity → capability szerződés:** `fatal` ⇒ `persist = false`;
  capability (display/scoring, dimenziónkénti) önálló tengely, sosem vonható
  össze a severity-vel — a §6 „Kötelező megkülönböztető mátrix" négy
  kombinációja (pl. unknown chord: persistálható ÉS scoring-tiltott) csak
  így fejezhető ki (ADR 0114 Döntés 2/3).

Nincs más eltérés; a scope, az engedélyezett fájllista (az ADR-en kívül) és
az acceptance criteria változatlan.

## 1. Cél

A persistálhatóság, importpreview és trainer alkalmasság stabil reportjai, idempotens normalizálás és őszinte display/scoring capability szállítása.

## 2. Jelenlegi állapot

- R04 után a teljes domain reprezentálható, de invalid dokumentum is konstruálható.
- A SongDocument még nem rendelkezik profile-alapú validation/capability gate-tel.
- A normalizer nem találhat ki bizonytalan zenei jelentést.

## 3. Scope

**Benne:**

- validation severity/code/profile/report
- sorting és bizonyítható normalizálások
- document/track capability és import warning contract
- lokalizációs message-key boundary

**Kívül — ebben a körben TILOS:**

- UI szöveg és badge
- repository persist végrehajtás
- formátumspecifikus parser warning mapping

## 4. Engedélyezett fájlok

| Útvonal | Állapot a kör elején | Miért |
|---|---|---|
| `lib/features/song_trainer/domain/services/song_validator.dart` | ÚJ | profile validáció |
| `lib/features/song_trainer/domain/services/song_normalizer.dart` | ÚJ | idempotens canonicalizálás |
| `lib/features/song_trainer/domain/services/song_capability_resolver.dart` | ÚJ | display/scoring capability |
| `lib/features/song_trainer/domain/models/song_validation_report.dart` | ÚJ | stabil report/code |
| `lib/features/song_trainer/domain/models/song_capability.dart` | ÚJ | capability model |
| `lib/features/song_trainer/domain/models/import_warning.dart` | ÚJ | warning model |
| `lib/features/song_trainer/domain/public.dart` | R04-ből | exportok |
| `test/features/song_trainer/domain/song_validator_test.dart` | ÚJ | profile×severity |
| `test/features/song_trainer/domain/song_normalizer_test.dart` | ÚJ | canonical cellák |
| `test/features/song_trainer/domain/song_capability_resolver_test.dart` | ÚJ | display/scoring mátrix |
| `test/property/song_normalizer_property_test.dart` | ÚJ | idempotencia/property |
| `docs/rounds/e03-r05-validator-normalizer-capabilities.md` | meglévő | §10 handoff |
| `docs/adr/0114-song-validator-normalizer-capability-boundary.md` | ÚJ, pre-flight írta | chord-support határ + severity→capability szerződés (§0.0) |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, az RTM,
`.github/**`, nem felsorolt `lib/features/**`, más kör briefje és
`docs/adr/**`. ADR-fájl csak akkor kivétel, ha a pre-flight ütközésmentes
exact pathként hozzáadta ehhez a táblához, még a `PLANNING` commit előtt.
Új tesztfixture vagy helper is fájl: ha nincs tételesen a táblában, `stopped`.
**A pre-flight `docs/adr/0114-song-validator-normalizer-capability-boundary.md`-t
kivételként felvette a §4 táblába (ld. fent és §0.0) — ez az EGYETLEN
`docs/adr/**` alatti pre-flight dokumentum ebben a körben; az implementer
gépi `allowed_paths` listáján nincs és tartalmilag nem módosítja.**

## 5. Kötött architekturális döntések

1. Profile-ok: importPreview, persist, trainer, export; fatal persist capabilityt mindig tilt.
2. Capability külön dimenzió display és scoring; polyphonic track pitch scoringja mindig false.
3. Automatikus javítás stabil code-dal reportolódik; UI mondat nem kerül domainbe.
4. ID csak hiányzó import ID-nél generálható; meglévő ID átírása normalizálás címén tilos.

E döntések enyhítése nem elfogadható „zöldre javítás”. Valódi ellentmondásnál
brief-revízió vagy ADR szükséges.

## 6. Acceptance criteria

- [ ] `normalize(normalize(x)) == normalize(x)` és canonical event ordering stabil.
- [ ] Validator ismeretlen/rossz inputnál reportot ad, nem nyers exceptiont.
- [ ] Fatal dokumentum nem persistálható; warningos dokumentum preview-zhető.
- [ ] Unsupported chord vagy technique esetén display és scoring őszintén eltér; polyphonic pitch false.

### Kötelező megkülönböztető mátrix

| Dokumentum | preview | persist | chord display/score | pitch display/score |
|---|---|---|---|---|
| valid chord | igen | igen | igen/igen | n.a. |
| unknown chord | igen+warning | policy szerint | igen/nem | n.a. |
| monophonic note | igen | igen | n.a. | igen/igen |
| polyphonic note | igen+warning | igen | n.a. | igen/nem |
| fatal range/map | nem | nem | nem/nem | nem/nem |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással tesz pirossá; bemásolt zöld kimenet önmagában nem evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/domain/song_validator_test.dart test/features/song_trainer/domain/song_normalizer_test.dart test/features/song_trainer/domain/song_capability_resolver_test.dart test/property/song_normalizer_property_test.dart
```

Ez az egyetlen lokális záró gate; külön processzben futó format → analyze →
célzott testek → architecture lépéseit nem szabad `&&`-del, pipe-pal,
`tail`-lel vagy csonkítással helyettesíteni. A full suite + randomizált
property + APK CI-t az orchestrátor indítja, és exact branch `headSha`-t
ellenőriz.

## 8. Implementációs sorrend

1. Írd meg a profile/severity és capability RED mátrixot.
2. Írd meg az idempotencia és stable-order property teszteket.
3. Implementáld a report/model típusokat és validatort.
4. Implementáld a normalizert, majd a capability resolvert.
5. Futtasd a gate-et több property seeddel és rögzítsd a mutációs próbát.

Javasolt körcommit: `feat(song-domain): validate normalize and classify trainer capabilities`.

## 9. Kockázatok

- A normalizer túlterjeszkedhet szemantikai javításba; csak bizonyított canonical művelet engedett.
- Capability warning és fatal összekeverése hamis támogatásjelzést adhat.

**STOP:** ha a kockázat csak listán kívüli módosítással, bizonyítatlan fallbackkel
vagy acceptance-gyengítéssel oldható fel, állj meg és kérj brief-revíziót.

## 10. Implementation handoff — az implementer tölti ki

**Státusz:** `DONE` (2026-08-02, implementer: Codex MiniMax M3, branch
`codex/e03-r05-validator-normalizer-capabilities-r2` @ `f98a027`+1).

### 10.1 Fájlonkénti összefoglaló

| Útvonal | Változás |
|---|---|
| `lib/features/song_trainer/domain/models/import_warning.dart` | ÚJ — `ImportWarning` immutable record + `ImportWarningCode` zárt készlet (`chordUnsupported`, `notePolyphonic`, `techniqueUnknown`, `strumDirectionUnknown`). Locale-független, `library;` dokumentáció, nincs framework import. |
| `lib/features/song_trainer/domain/models/song_capability.dart` | ÚJ — `SongCapabilityProfile` (4 profil: importPreview/persist/trainer/export), `SongCapability` (display + scoring önálló tengely), `SongChordCapability`, `SongPitchCapability`, `SongCapabilityReport`. A `songCapabilityProfileFromCode` fail-closed helper. |
| `lib/features/song_trainer/domain/models/song_validation_report.dart` | ÚJ — `SongValidationSeverity` (fatal/warning), `SongValidationCode` zárt készlet, `SongValidationIssue` immutable record, `SongValidationReport` immutable report + `empty` konstans, `hasFatalIssue` / `isPersistable` getterek. Deterministic ordering: severity asc, code asc. |
| `lib/features/song_trainer/domain/services/song_validator.dart` | ÚJ — `SongValidator` + top-level `songTrainerChordRootIsSupported`. Soha nem dob (acceptance: "Validator ismeretlen/rossz inputnál reportot ad, nem nyers exceptiont"). Cross-collection konzisztenciát nézi: section range vs. `measures.length`, section átfedés, `targetChordId` validáció, polyphonic note track detection (`NoteTrackAnalyzer` collaborator), chord support grammar (ADR 0114 §Döntés 1: önálló, domain-lokális, `Root[m?]` zárt grammatika, sosem a `practice/legacyPracticeChordLabel` szótár), unknown technique, ismeretlen strum direction. |
| `lib/features/song_trainer/domain/services/song_normalizer.dart` | ÚJ — `SongNormalizer` stateless pure service. Canonical ordering: track-ok `(kind, track.id)`, chord/note események `(start, id)`, strum/lyric/marker `(at, id)`, sections `(startMeasure, id)`, measures `(index)`, markers `(measureIndex, id)`, assets `(id)`. ID-ket soha nem írja újra (acceptance §5 kötött döntés 4). Short-circuit: ha minden kollekció már canonical, a bemeneti `SongDocument` referenciát adja vissza (megfigyelhető a `normalize(x) == x` szerződés). |
| `lib/features/song_trainer/domain/services/song_capability_resolver.dart` | ÚJ — `SongCapabilityResolver`. Tiszta függvény `(report, profile) → report`. A severity → capability szerződés: `hasFatal` ⇒ minden `canPersist/canImportPreview/canTrain/canExport = false`, a chord/pitch axis-ok `display`/`scoring` mezői is `false`. A warning szintű leletek csak a releváns axis `scoring` mezőjét downgradelik, a `display` és a `canPersist` tengelyek érintetlenek maradnak (acceptance §6 mátrix 4 kombinációja megmarad). |
| `lib/features/song_trainer/domain/public.dart` | MÓDOSÍTÁS — 6 új export (3 model + 3 service); minden meglévő export változatlan. |
| `test/features/song_trainer/domain/song_validator_test.dart` | ÚJ — 15 teszt, 4 csoport: empty/well-formed baseline, §6 mátrix (profile × severity), determinism, chord-root grammar. Minden mátrix-sor explicit. |
| `test/features/song_trainer/domain/song_normalizer_test.dart` | ÚJ — 10 teszt, 3 csoport: idempotencia (a §6 acceptance explicit tesztje), canonical ordering (minden track subtype + minden kollekció), determinism. |
| `test/features/song_trainer/domain/song_capability_resolver_test.dart` | ÚJ — 9 teszt, 4 csoport: §6 mátrix, per-profile függetlenség (fatal minden profilra kihat, warning egyikre sem), determinism, profile code round-trip. |
| `test/property/song_normalizer_property_test.dart` | ÚJ — 4 property teszt: idempotencia, track-ID megőrzés, event-identity megőrzés (multiset equality track-azonosítóra szűrve), canonical event ordering monotonitás. `PROPERTY_SEED` env, default 42, CI átadja a run id-t (a többi property gate-tel azonos séma). |

### 10.2 Futtatott parancsok és tényleges eredmények

- `tools/round-gate.sh test/features/song_trainer/domain/song_validator_test.dart test/features/song_trainer/domain/song_normalizer_test.dart test/features/song_trainer/domain/song_capability_resolver_test.dart test/property/song_normalizer_property_test.dart`
  → kimenet vége:

  ```
  ═══ Gate-összegzés
      format                                                     zöld
      analyze                                                    zöld
      test test/features/song_trainer/domain/song_validator_test.dart zöld
      test test/features/song_trainer/domain/song_normalizer_test.dart zöld
      test test/features/song_trainer/domain/song_capability_resolver_test.dart zöld
      test test/property/song_normalizer_property_test.dart      zöld
      architecture                                               zöld

  MINDEN GATE ZÖLD. …
  ```

- `$HOME/flutter/bin/flutter test test/features/song_trainer/` → `00:13 +177: All tests passed!` (az új 38 teszt + az E01–E03-R01–R04 meglévő 139; a domain purity szkenner ismét zöld).
- PROPERTY_SEED=1/42/1337/99999 négy seed-del a property tesztek rendre zöldek.

### 10.3 Terv szerinti eltérések

Nincs; a §4 fájllistája, a §5 kötött döntések, a §6 mátrix és a §0.0-ban mért
pre-flight revízió változatlan. Az implementáció tartalmilag NEM módosítja a
`docs/adr/0114-…` fájlt (az implementer scope-ján kívül esett, ahogy a §4
megjegyzése előrevetítette).

### 10.4 Nem futtatott ellenőrzések és ok

- A CI-ban futó teljes `flutter test` suite + release APK build: az
  outer router / orchestrátor indítja, a lokális boxon nincs Android
  SDK (AGENTS.md §12); a futás a PR nyitásakor dispatch-elve lesz.
- A `flutter build apk`: szándékosan nem futtatva lokálisan (ADR 0052
  + AGENTS.md §12 — "a fejlesztői boxon nincs Android SDK").

### 10.5 Következő kör

- **E03-R06** (szerző: pre-flight a `docs/rounds/e03-r06-…` placeholder
  alapján). Az importernek a `SongCapabilityReport` UI-oldali
  leképezését és a persist-gated write path-ot kell megvalósítania —
  ez a kör a `canPersist` zászló első fogyasztója.

## 11. Review — a független reviewer tölti ki

Tervezett review-fájl:
`docs/reviews/e03-r05-validator-normalizer-capabilities-review.md`.

Merge csak akkor engedett, ha az exact-SHA CI zöld, a diff a §4 listáján belül
marad, és nincs OPEN BLOCKER vagy MAJOR.
