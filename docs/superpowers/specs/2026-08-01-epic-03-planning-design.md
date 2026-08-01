# Epic 3 teljes tervcsomag — design

**Dátum:** 2026-08-01

**Státusz:** jóváhagyott design

**Planning branch:** `codex/epic-03-planning`

**Tervezési baseline:** `main` @ `eeb4f6d` (E02-R18 pipeline-adminisztráció kész)

**Normatív Epic-forrás:** `docs/sdd/04-epic-03-song-trainer.md`

## 1. Cél

Az Epic 3 — Song Trainer teljes, előkészített végrehajtási csomagja készüljön
el úgy, hogy az Epic 2 lezárása után mind a 22 kör egyenként pre-flightolható,
review-zható és végrehajtható legyen.

A csomag nem ír production kódot, nem indít Epic 3 kört, és nem állítja, hogy
a még futó Epic 2 contractjai már véglegesek. Az előre elkészített briefek
`PREPARED` státuszú tervezési szerződések; csak az adott elődkör merge-je, a
friss `main` auditja és a brief dokumentált pre-flight revíziója után válhatnak
`PLANNING` státuszú végrehajtási szerződéssé.

## 2. Források és elsőbbség

A tervek az alábbi sorrendben vezetik le a követelményeket:

1. aktuális explicit felhasználói döntés;
2. `docs/sdd/04-epic-03-song-trainer.md` adott köre és közös Epic-szabályai;
3. `docs/sdd/03-epic-02-practice-engine.md` ténylegesen szállított contractjai;
4. `docs/sdd/01-architecture-engineering-principles.md` és `AGENTS.md`;
5. elfogadott ADR-ek;
6. aktuális `HANDOFF.md`;
7. `docs/LESSONS.md` mért tanulságai;
8. történeti vagy tájékoztató dokumentumok.

Az SDD-ből nem találunk ki új termékscope-ot. A terv pontosítja a fájlhatárokat,
az ellenőrizhető mércéket, a függőségeket és a végrehajtási sorrendet.

## 3. Kimeneti artefaktumok

### 3.1 Epic-szintű főterv

`docs/superpowers/plans/2026-08-01-epic-03-song-trainer.md`

A főterv tartalmazza:

- az öt fázist és a 22 kör függőségi gráfját;
- a cross-feature contract- és döntési kapukat;
- a teljes fájlfelelősségi térképet;
- a körönkénti kimeneteket, tesztcsaládokat és gate-eket;
- az Epic 3 végső Definition of Done traceability-mátrixát;
- az indítás és az Epic-zárás feltételeit.

### 3.2 Huszonkét kör-brief

| Kör | Brief |
|---|---|
| E03-R01 | `docs/rounds/e03-r01-baseline-and-boundaries.md` |
| E03-R02 | `docs/rounds/e03-r02-song-document-identity-metadata.md` |
| E03-R03 | `docs/rounds/e03-r03-song-structure-and-time-map.md` |
| E03-R04 | `docs/rounds/e03-r04-tracks-events-monophonic-analysis.md` |
| E03-R05 | `docs/rounds/e03-r05-validator-normalizer-capabilities.md` |
| E03-R06 | `docs/rounds/e03-r06-legacy-song-setlist-adapters.md` |
| E03-R07 | `docs/rounds/e03-r07-song-repository-asset-store.md` |
| E03-R08 | `docs/rounds/e03-r08-persistent-v2-migration.md` |
| E03-R09 | `docs/rounds/e03-r09-native-json-import-export.md` |
| E03-R10 | `docs/rounds/e03-r10-import-flow-security-boundary.md` |
| E03-R11 | `docs/rounds/e03-r11-musicxml-mxl-importer.md` |
| E03-R12 | `docs/rounds/e03-r12-midi-importer.md` |
| E03-R13 | `docs/rounds/e03-r13-guitar-pro-feasibility.md` |
| E03-R14 | `docs/rounds/e03-r14-guitar-pro-path.md` |
| E03-R15 | `docs/rounds/e03-r15-song-library-import-ui.md` |
| E03-R16 | `docs/rounds/e03-r16-song-editor-v2.md` |
| E03-R17 | `docs/rounds/e03-r17-overview-track-range-setup.md` |
| E03-R18 | `docs/rounds/e03-r18-transport-backing-playback.md` |
| E03-R19 | `docs/rounds/e03-r19-practice-compiler-chord-rhythm.md` |
| E03-R20 | `docs/rounds/e03-r20-pitch-observation-note-scoring.md` |
| E03-R21 | `docs/rounds/e03-r21-trainer-ui-loop-speed-results.md` |
| E03-R22 | `docs/rounds/e03-r22-setlist-progress-epic-closure.md` |

Minden brief a `docs/execution/08-round-brief.md` szerződését követi, és saját
`codex/e03-rYY-<slug>` branchnevet ad meg.

### 3.3 Brief-index

A `docs/rounds/README.md` egy Epic 3 szekcióval bővül. A szekció rögzíti a
planning baseline-t, az öt fázist, a `PREPARED` jelentését és azt, hogy az
előre megírt fájlok indítás előtt kötelezően újraauditálandók.

Az aktív Epic 2 pipeline által kezelt `HANDOFF.md`, RTM és pipeline queue nem
része a planning commitnak.

## 4. Fázisok és döntési kapuk

### Fázis I — Domainalapok (E03-R01–R05)

- baseline, rollout-határok és ADR-témák;
- SongDocument V2 identity és metadata;
- section, measure, tempo, meter és determinisztikus SongTimeMap;
- track- és eventmodell, monophonic alkalmasság;
- validator, normalizer és capability resolver.

**Kilépési kapu:** a domain Flutter-, parser- és platformfüggetlen; a
normalizálás idempotens; a capability nem állít nem bizonyított scoringot.

### Fázis II — Migráció, storage és natív import (E03-R06–R10)

- legacy Song/Setlist adapterek és parity;
- atomikus fájlrendszeres repository és asset store;
- újraindítható, adatvesztésmentes tartós migráció;
- natív StrumSight JSON round-trip;
- parserfüggetlen import state machine és biztonsági workspace.

**Kilépési kapu:** nincs SharedPreferences-alapú SongDocument-tárolás, nincs
félkész library rekord, és a legacy fallback kontrolláltan visszakapcsolható.

### Fázis III — Külső formátumok (E03-R11–R14)

- MusicXML/MXL subset és archívumbiztonság;
- Standard MIDI subset;
- Guitar Pro feasibility ADR;
- kizárólag az ADR által jóváhagyott parseres vagy konverziós út.

**Kilépési kapu:** minden támogatási állításhoz jogtiszta fixture és capability
report tartozik; GP production kód nem előzheti meg a feasibility döntést.
E03-R13 döntést szállít, nem parserkódot. E03-R14 briefje két teljes, egymást
kizáró végrehajtási ágat ír le (jóváhagyott adapter vagy konverziós UX); az
R13 ADR-je alapján a pre-flight pontosan egy ágat aktivál, a másikat explicit
scope-on kívülivé teszi.

### Fázis IV — Felhasználói tartalomkezelés és transport (E03-R15–R18)

- indexalapú Library és import UI;
- strukturált editor, determinisztikus undo/redo és revision conflict;
- overview, track/range kiválasztás és trainer setup;
- determinisztikus transport és cserélhető backing player.

**Kilépési kapu:** a felhasználó érti a capability-korlátokat; az editor nem
veszít draftot; a transport lifecycle erőforrásszivárgás nélkül zár.

### Fázis V — Trainer, progress és Epic-zárás (E03-R19–R22)

- SongDocument → PracticeDefinition compiler és chord/rhythm session;
- monophonic pitch observation és note scoring;
- trainer UI, loop, Speed Builder, result és resume;
- Setlist V2, revision-aware progress, quality gate és completion report.

**Kilépési kapu:** az Epic 3 DoD minden tétele bizonyítékkal teljesül vagy
név szerint nyitott leletként szerepel; a valódi eszközös checklistet nem
helyettesíti szintetikus teszt.

## 5. Kör-brief szerződés

Minden `PREPARED` brief kötelező elemei:

1. baseline dátum és commit;
2. SDD-kör és kapcsolódó közös szakaszok;
3. közvetlen előfeltétel és fáziskapu;
4. cél, benne-scope és explicit kívül-scope;
5. tételes engedélyezett fájlok, az új fájlokat külön jelölve;
6. tiltott zóna és cross-feature határ;
7. kötött döntések és az ADR-téma;
8. mérhető acceptance-kritériumok;
9. minden lényegi invariáns tiltott gyengítése;
10. paraméteres és határérték-mátrixok konkrét cellákkal;
11. egyetlen lokális `tools/round-gate.sh ...` záró artefaktum;
12. CI full-suite/property/APK elvárás exact `headSha` ellenőrzéssel;
13. implementációs sorrend;
14. kockázatok, STOP-klauzula, handoff- és review-hely.

Az implementer számára a brief §7/§8 sorrendje a terv. A brief nem írhat elő
olyan viselkedést, amelyhez a szükséges production vagy tesztfájl tiltott.

## 6. Kötelező pre-flight minden kör előtt

A `PREPARED → PLANNING` átmenet feltétele:

1. az `origin/main` és a közvetlen elődkör merge-jének ellenőrzése;
2. az aktuális `AGENTS.md`, Chapter 1, Chapter 3/4, `HANDOFF.md`, releváns ADR
   és `docs/LESSONS.md` elolvasása;
3. minden briefben megnevezett útvonal, típus, enum, mező, metódus és provider
   grep-alapú ellenőrzése;
4. minden cél-state tényleges producerének megkeresése;
5. minden lease, lock, stream, player, mic és temporary workspace tényleges
   tulajdonosi hívási láncának kimérése;
6. minden új recorder/repository kötelező bemenetének visszakövetése a
   production provider-wiringig;
7. minden numerikus és származtatott határpont újraszámítása;
8. az engedélyezett fájllista összevetése az acceptance-kritériumokkal és a
   ma ellentétes viselkedést rögzítő production/teszt fájlokkal;
9. a kör ADR-számának ütközésmentes kiosztása, ha a döntés valóban szükséges;
10. drift esetén `§0.0` revízió: mért eltérés, választott feloldás és indok;
11. a státusz, dátum és baseline SHA frissítése, majd a brief commitolása a
    kör branchére az implementer indítása előtt.

Az ADR-számokat a planning batch nem foglalja le az aktív Epic 2 mellett. A
brief az ADR tárgyát és döntési kérdését rögzíti; a tényleges számot a
pre-flight osztja ki a friss ADR-katalógus alapján.

## 7. Architektúra és komponenshatárok

```text
Presentation
     ↓
Application
     ↓
Domain
     ↑
Data implementations
```

- A Song Trainer domain nem függ Fluttertől, Riverpodtól, parser- vagy
  platformcsomagtól.
- A data réteg felel a codecért, importerekért, file repositoryért, asset
  store-ért és migrációért.
- Az application réteg felel az import-, library-, editor-, transport- és
  trainer-orchestrációért.
- A presentation kizárólag application contracton keresztül dolgozik.
- Más feature csak `public.dart` vagy közös core contracton keresztül érhető
  el.

A jelenlegi `lib/features/practice/public.dart` a planning baseline-on nem
exportálja a Song Trainer compilerhez és result mappinghez szükséges teljes
domain/application contractot. E03-R01 pre-flight hard gate ellenőrzi az Epic
2 lezárása utáni állapotot. Hiány esetén dokumentált bridge-kör vagy R01
revízió szükséges; Practice-belső import nem megengedett.

## 8. Adatáramlás

### Import és tárolás

```text
ImportSourceFile
  → probe és formátumválasztás
  → korlátozott temporary workspace
  → parser/importer
  → SongNormalizer
  → SongValidator + capability report
  → atomikus document/asset commit
  → indexfrissítés
  → Library/Editor/Trainer
```

Warning és fatal error külön csatorna. Cancellation, parserhiba vagy commit
hiba után a workspace kitakarít, és nem marad látható félkész rekord.

### Gyakorlás és progress

```text
SongDocument + track + TrainerRange + config
  → SongPracticeCompiler
  → publikus PracticeDefinition
  → Practice Engine
  → publikus PracticeResult
  → SongEventReference visszamapping
  → measure/section metrics
  → idempotens, revision-aware progress commit
```

A backing transport és a scoring lifecycle összehangolt, de külön contract.
Playback-only mód nem kér mikrofont. Scoring csak capabilityvel támogatott
dimenzióra indul.

## 9. Hiba-, cancellation- és lifecycle-szabályok

- Várt hibák stabil code-dal rendelkező `AppFailure`/`AppResult` úton jutnak a
  UI-ba; nyers parser-, storage- vagy platformexception nem.
- Unsupported formátum vagy capability őszinte, lokalizálható eredmény, nem
  néma fallback.
- Import commit atomikus; recovery és retry idempotens.
- Perzisztenciateszt a production provider-wiringen ment és visszaolvas, a
  reális `StorageException` hibatípussal is.
- Audio interruption, app background és route leave safe pause/cleanupot
  okoz; nincs automatikus hangos resume.
- Mic, player, stream, isolate és temporary workspace minden terminal ágon
  felszabadul.
- Feature flag rollout-határ, nem két tartós domain/progress rendszer.

## 10. Tesztelés és bizonyíték

Körönként a kockázathoz illesztett tesztcsalád készül:

- domain és application unit teszt;
- normalizálási/idő-/state-machine property teszt;
- legacy és codec parity/round-trip fixture;
- repository crash, recovery és production-wiring teszt;
- importer security fixture (XXE, traversal, zip bomb, malformed input);
- widget teszt nagy szöveg, landscape, reduced motion, újrabelépés és
  kombinált státusz/effect cellákra;
- lifecycle/integration teszt mic, player, cancellation és idempotens commit
  határokra;
- valós eszközös gate audio, import, backing, Bluetooth és hosszú session
  esetére.

Minden brief megnevezi, melyik hibás implementációt fogja pirosra az adott
mérce. A reviewer legalább egy központi invariánsra eldobható mutációs vagy
reference-próbát futtat; a bemásolt zöld kimenet önmagában nem evidencia.

## 11. Koordináció és izoláció

- A tervezés külön teljes klónban és `codex/epic-03-planning` branchen fut.
- A primary `/home/ubuntu/music-theory` munkafát és az Epic 2 pipeline által
  kezelt fájlokat a planning munka nem módosítja.
- A planning branch kizárólag dokumentációs artefaktumokat tartalmaz.
- A 22 brief elkészítése nem indít implementert, CI-dispatchet, PR-merge-et
  vagy feature rolloutot.
- E02-R20 merge után a teljes csomag friss-main auditot kap, mielőtt E03-R01
  elindulhat.

## 12. A tervcsomag saját Definition of Done-ja

- [ ] A főterv és mind a 22 brief létezik.
- [ ] Minden brief `PREPARED`, baseline-os és elődkörhöz kötött.
- [ ] Minden Epic 3 SDD-kör pontosan egy briefhez mapel.
- [ ] Az Epic 3 végső DoD minden tétele körhöz és bizonyítéktípushoz mapel.
- [ ] Nincs `TBD`, kitöltetlen placeholder vagy az SDD által döntési körhöz
  nem rendelt, végrehajtásra hagyott tervezési döntés. Az E03-R13 feasibility
  döntése tervezett kimenet; a pre-flightkor kiosztandó ADR-szám explicit
  policy, nem kitöltetlen mező.
- [ ] Minden briefben van pontos scope, tiltott zóna, fájllista, acceptance,
  gate, sorrend, kockázat, STOP-klauzula, handoff és review.
- [ ] A hivatkozott mai fájlok és contractok auditáltak; a jövőbeli fájlok
  egyértelműen `ÚJ` jelölést kapnak.
- [ ] A Practice public-contract hiány hard gate-ként szerepel.
- [ ] A dependency-gráf ciklusmentes és az SDD sorrendjét tartja.
- [ ] A planning diff nem érinti a `HANDOFF.md`-t, RTM-et, pipeline queue-t,
  production kódot, tesztkódot vagy ADR-fájlokat.
