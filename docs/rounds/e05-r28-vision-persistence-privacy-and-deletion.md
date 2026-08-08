# E05-R28 — Persistence, privacy control és törlés

- **Státusz:** PLANNING (pre-flight §0.0 lezárva 2026-08-08, kód olvasva: main @ `47fbaeb`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 28; §28
- **Branch:** `codex/e05-r28-vision-persistence-privacy-and-deletion`
- **Előfeltétel:** **E05-R10, E05-R22, E05-R24 merge** — mind a három megerősítve (§0.0)
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/data/persistence/vision_session_repository.dart",
  "lib/features/vision/data/persistence/vision_session_codec.dart",
  "lib/features/vision/data/persistence/vision_export.dart",
  "lib/features/vision/domain/vision_privacy_control.dart",
  "lib/features/vision/public.dart",
  "lib/core/storage/storage_keys.dart",
  "lib/features/settings/screens/vision_privacy_screen.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/vision/data/vision_session_repository_test.dart",
  "test/features/vision/data/vision_export_privacy_test.dart",
  "test/features/settings/vision_privacy_screen_test.dart",
  "test/app/offline_network_guard_test.dart",
  "docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md",
]
gate_tests = [
  "test/features/vision",
  "test/features/settings",
  "test/app/offline_network_guard_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight LEZÁRVA (§0.0, R1–R6):** `origin/main` @ `47fbaeb` (HEAD ==
> origin/main, nincs drift, nincs átfedő párhuzamos inflight kör) + E05-R10/
> R22/R24 merge megerősítve. Egy javítás (elavult ADR-hivatkozás — MÉRVE: NEM
> igényel ÚJ ADR-t) és öt precedens-pontosítás (persistence-konténer alakja,
> a migrációs mátrix elérhető cellái, a storage-kulcs mechanizmusa, a
> delete-all/confirm minta és a network-spy bővítés horgonya). Részletek
> §0.0. PLANNING→dispatch.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mérve `origin/main` @ `47fbaeb` (E05-R27 után), orchestrátor Claude Sonnet 5,
2026-08-08.** Előfeltétel (E05-R10 PR #181/`39d1c29`, E05-R22 PR #195/
`997e7be`, E05-R24 PR #197/`e9257f4`, mind squash-merged `main`-en)
megerősítve, working tree tiszta, a `.pipeline/inflight/` kizárólag ennek a
körnek a markerét tartalmazza. Hat mért tétel — egy javítás, öt
precedens-pontosítás —, egyik sem igényel ÚJ ADR-t.

**R1 — ADR-hivatkozás elavult (javítva, nincs ÚJ ADR).** A fejléc és a §5
pont 1 „ADR 0166"-ra, a §11 „Reviewer figyelem" sor „ADR 0161/0166"-ra
hivatkozott. `ls docs/adr | grep -E '^01(61|66)'` üres — az E05-R01
pre-flightja (`docs/rounds/e05-r01-vision-baseline-and-adrs.md` §0.0,
`docs/rounds/epic-05-batch-index.md` §3) a batch-tervezett `0161–0166`
blokkot egységesen `0178–0183`-ra tolta el (+17, dokumentálva:
`docs/LESSONS.md` L143/L147). A blokk-index (`epic-05-batch-index.md:100`)
szerint a pontos leképezés `0161 = "Vision privacy by default"` →
[`ADR 0178`](../adr/0178-vision-privacy-by-default.md), és a hatos blokk
utolsó tagja `0166` → [`ADR 0183`](../adr/0183-vision-no-raw-frame-persistence.md)
(„Vision no-raw-frame persistence"). Mindkét cél-ADR LÉTEZIK és tartalmilag
PONTOSAN fedi ezt a két brief-döntést (0183 Döntés 1 szó szerint: „raw kép
és teljes landmark-idősor alapértelmezetten nem tárolható" — ugyanaz, mint a
brief §5 pont 1/2). Ez tehát NEM az E05-R27 esete (ahol a „0161/0162" pár
egyetlen létező ADR-re sem mutatott, és a tartalom is genuinely új volt, ld.
ADR 0194) — itt a hivatkozott döntések MÁR léteznek, változatlanul
alkalmazhatók. A javítás így kizárólag hivatkozás-csere, ugyanaz a minta,
mint E05-R05/R08/R10/R11/R14/R24 saját pre-flightjában (mindegyik „nincs új
ADR, csak referenciajavítás" verdikttel zárt — pl. R10 §0.0 R1, a
legközelebbi analóg persistence-kör). Javítva: fejléc-callout, §5 pont 1
„(ADR 0166)" → „(ADR 0183)", §11 „(ADR 0161/0166)" → „(ADR 0178/0183)".

**R2 — Persistence-alak pontosítva: `JsonCollectionStore<T>`, nem az R10
single-bundle mintája.** A brief „az R10 mintája szerint" fogalmaz, de az
R10 `VisionCalibrationRepository` EGYETLEN bundle-t tart
(`VisionCalibrationRecord? read()` — nullable, nincs lista, nincs cap, nincs
egyedi rekord-törlés: `lib/features/vision/data/persistence/
vision_calibration_repository.dart:44-56`), miközben ez a kör történelmi
HISTORY-t igényel (§6: „egy-session törlés", „delete-all", implicit sok
rekord). A tényleges szerkezeti precedens `JsonCollectionStore<T>`
(`lib/core/storage/json_document_store.dart:175-251`) — ugyanaz a konténer,
mint a `practiceHistoryV2`/`librarySessions`/`songs` (`storage_keys.dart`),
KÉSZ `maxItems` cap-pel, `RecordOrder`-rel és per-rekord
`JsonRecordException`-alapú karanténnal (`read()` már ma eldobja+naplózza a
hibás rekordot, a többit megtartja — pontosan a brief §6 „Karantén-teszt"
AC-je). A `VisionSessionRepository` ezt a konténert wrapelje egy
`fromJson`/`toJson` codec felett (a `VisionSessionResult` mezőiből
MINIMALIZÁLT DTO-t kódolva, nem magát a domain-osztályt — a
`session`/`calibrationState` teljes objektum nem kerül a tárba, csak a §6
által engedélyezett mezőkészlet), nem egyetlen `JsonObjectStore`/bare
`JsonDocumentStore` bundle-t.

**R3 — „Migrációs mátrix (v0/vN-1/vN/vN+1)" AC-cella pontosítva: nincs
valódi legacy alak.** Az R10 migrációja egy TÉNYLEGESEN SZÁLLÍTOTT
pre-envelope flat alakot migrál (`vision_calibration_codec.dart:
_migrateFromLegacy`, `calibrationShapeLegacySchemaVersion = 0`). Ez a kör
viszont az ELSŐ, amely `VisionSessionResult`-ot perzisztál — production-ban
SOHA nem élt korábbi alak, tehát a brief §6 „v0 / vN-1 / vN / vN+1" négyes
cellája elérhetetlen cél-státusz (pipeline-prompt §1 R1 minta): nincs olyan
valódi input, ami egy „vN-1" rekordot termelne. Revízió: a codec EGYETLEN
aktuális alak-verzióval indul (`visionSessionShapeSchemaVersion = 1`, az R10
`calibrationShapeSchemaVersion`-nal analóg névvel), a mérhető mátrix két
valódi cellára szűkül — **vN round-trip** (byte-stabil encode→decode→encode)
és **vN+1 (jövőbeli, ismeretlen) verzió → karantén** ugyanazzal a fail-loud
`unknownEnum`/`JsonRecordException` mintával, mint az R10
`_migrateToCurrent` else-ága ÉS a `JsonDocumentStore._decodeEnvelope`
envelope-szintű „future_version" őre (`json_document_store.dart:140-144`,
generikus, ide is vonatkozik). A codec `_readShapeVersion`/dispatch
STRUKTÚRÁJA mindazonáltal kövesse az R10 verzió-switch mintáját (ne
hardkódolt egyetlen ág legyen), hogy egy jövőbeli valódi alakváltás
természetes bővítési pontot kapjon — csak a MOST tesztelhető mátrix szűkül
négyről kettőre, a kód nem. Ez nem scope-csökkentés: egy kitalált „legacy"
alak tesztelése hamis bizonyítékot adna.

**R4 — Storage-kulcs mechanizmus megerősítve: `StorageKeys`, NEM
`StorageMigrator`.** Az allowed_paths `storage_keys.dart`-ot „csak új
`ss.vision.*` kulcs"-ra korlátozza — ez összhangban van a mért ténnyel:
`appStorageMigrations` (`storage_migrator.dart:246-338`) kizárólag egy
MEGLÉVŐ pre-namespace kulcs átnevezésére való (`RenameKeyMigration`/
`WrapJsonDocumentMigration`, mind `from: LegacyStorageKeys....`), és
R28-nak (R10-hez hasonlóan, mely szintén NEM bővítette az
`appStorageMigrations` listát) nincs pre-namespace elődje. Az új kulcs
kizárólag `StorageKeys` osztálykonstansként és a `StorageKeys.all` listában
jelenik meg — a globális `StorageMigrator.migrations` lista ehhez a
körhöz NEM bővül.

**R5 — Delete-all + destruktív megerősítés precedense azonosítva: ai_tutor
(E04-R22).** A §6 „Privacy panel widget-teszt: … megerősítés nélkül nem hív
törlést (hívásszámláló 0)" AC pontosan a MEGLÉVŐ
`TutorDataScreen.confirmAndDeleteAll()` mintája
(`lib/features/ai_tutor/presentation/screens/tutor_data_screen.dart:82-126`):
`showDialog<bool>` cancel/confirm gombokkal, a repository törlés-hívása
KIZÁRÓLAG `confirmed == true` ágon. A repository-oldali „tényleges törlés,
nem soft-delete" AC ugyanígy megvan: `LocalTutorMemoryRepository.
deleteAllAiData()` (`local_tutor_memory_repository.dart:156-168`) nyers
`_keyValueStore.remove(key)`-t hív minden érintett kulcsra + a
karantén-árnyékra is. A `vision_privacy_screen.dart` és a
`VisionSessionRepository` törlés-útja ezt a KÉT meglévő mintát kövesse (a
Settings-tulajdonlás miatt új fájlban, nem az ai_tutor alá), nem új
tervezést igényel.

**R6 — Network-spy bővítés konkrét horgonya azonosítva.**
`AppRoutes.visionSession` MA is regisztrált, és KIZÁRÓLAG a `visionEnabled`
flaggel van gate-elve (`lib/app/routing/app_router.dart:244-247` — nincs
alflag, szemben `visionSetup`/`visionGuitarGeometry`-vel). A
`test/app/offline_network_guard_test.dart` alján élő `aiTutor` szcenárió
(`flags:` override + `harness.router.go(...)` + `_expectNoNetwork`) a KÉSZ
minta egy jelenleg-OFF flag bekapcsolására és hálózat-mentességének
bizonyítására — egy analóg `vision` szcenárió (`visionEnabled: true`
override, `AppRoutes.visionSession`-re navigálás) ugyanígy bővíthető. Ezen
felül: a `VisionSessionRepository`/`vision_export.dart` konstruktora (a
tervezett R2 alak szerint) kizárólag `KeyValueStore`-t vár — a „nulla
hálózat" e két osztályra STRUKTURÁLIS (nincs `Dio`/`HttpClient` paraméter,
amin keresztül egyáltalán kérést indíthatnának), a widget-szintű teszt ezt a
strukturális garanciát egészíti ki a teljes útvonalra (session→persistence→
export a UI-n át).

## 1. Cél

Verziózott `VisionSessionResult` tárolás **raw média nélkül**, és **teljes
felhasználói kontroll**: privacy panel, egy-session és teljes törlés, export.

## 2. Jelenlegi állapot (mért, `47fbaeb` + megelőző körök — §0.0 pre-flight
   megerősítette, tartalom változatlan `5d082dc` óta)

- Az R10 kalibrációs repository már ezt a mintát használja (verziózott envelope,
  idempotens migráció, record-szintű karantén) — ez a kör **ugyanazt** követi.
- Az R24 `VisionSessionResult`-ja létezik, de **nem** perzisztált.
- A `test/app/offline_network_guard_test.dart` a meglévő őre annak, hogy a
  detektálás nem generál hálózati forgalmat.
- A Settings ma `lib/features/settings/screens/` alatt tart képernyőket.

## 3. Scope

**Benne:** `VisionSessionRepository` + codec + schema migration, mentendő
adatkör (aggregátum, insight, capability, quality, model-verzió), **teljes
landmark-idősor NEM** mentődik alapból, Settings privacy panel (vision history,
kalibráció, Lab data), egy-session és **delete-all**, JSON export **kép nélkül**,
record-szintű karantén, és a nulla-hálózat bizonyítéka.

**Kívül — TILOS:** raw frame/kép mentése bármilyen formában, cloud-szinkron,
új hálózati útvonal, a tutor/analysis adapterek módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../data/persistence/vision_session_repository.dart` | ÚJ | verziózott tár |
| `.../data/persistence/vision_session_codec.dart` | ÚJ | JSON round-trip |
| `.../data/persistence/vision_export.dart` | ÚJ | export kép nélkül |
| `.../domain/vision_privacy_control.dart` | ÚJ | törlés/retenció szabályok |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `lib/core/storage/storage_keys.dart` | meglévő | **csak új** `ss.vision.*` kulcs |
| `lib/features/settings/screens/vision_privacy_screen.dart` | ÚJ | privacy panel |
| `lib/l10n/app_*.arb` | meglévő | **csak additív** kulcs |
| `test/features/*`, `test/app/offline_network_guard_test.dart` | ÚJ/meglévő | tesztek |
| `docs/rounds/e05-r28-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; meglévő storage-kulcs átírása; `backend/`.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Raw média soha nem perzisztálódik** (ADR 0183) — sem kép, sem videó, sem
   base64 blob, sem „debug dump". **NEM elfogadható** flag mögötti kivétel a
   consumer útvonalon; a Lab capture (explicit consent) **külön**,
   `visionLabCaptureEnabled` mögötti, és **nem e kör tárgya**.
2. **Teljes landmark-idősor alapból nincs mentve.** Ha egy jövőbeli kör
   opcionálisan engedélyezi, az külön flag + külön consent — **NEM elfogadható**
   itt bevezetni „csak a fejlesztéshez".
3. **A törlés tényleges:** a delete-all után a store-ban **nincs** vision
   rekord, és ezt a teszt a nyers store tartalmán ellenőrzi (nem a repository
   API-ján át). **NEM elfogadható:** „töröltnek jelölt" rekord.
4. **Record-szintű karantén:** egy sérült rekord nem teheti olvashatatlanná a
   historyt.
5. **Nulla hálózat:** a vision használata és a persistence **egyetlen** hálózati
   kérést sem generál (account/cloud kikapcsolt állapotban sem — és bekapcsolt
   account mellett sem küld vision adatot).
6. **Export = ugyanaz a minimalizált halmaz**, mint a tárolt adat, plusz a
   séma-verzió; a privacy-snapshot teszt mindkettőre fut.

## 6. Acceptance criteria

- [ ] **Round-trip + jövőbeli-verzió mátrix** (§0.0 R3 — két valódi cella,
      NEM az R10 négyes v0/vN-1/vN/vN+1 mátrixa, mert nincs szállított legacy
      alak): **vN round-trip** (encode→decode→encode byte-stabil) és **vN+1
      (ismeretlen jövőbeli verzió) → karantén**, fail-loud `unknownEnum`
      mintával (R10 `_migrateToCurrent` else-ága / `JsonDocumentStore`
      „future_version" őre). A codec dispatch-struktúrája verzió-switch
      formájú (bővíthető egy jövőbeli valódi migrációra), de a MOST
      tesztelt mátrix csak ezt a két cellát bizonyítja.
- [ ] **Privacy-snapshot teszt (a kör kulcsbizonyítéka):** a tárolt és az
      exportált JSON kulcskészlete rögzített halmazzal egyezik; kép/landmark/
      arc-gyanús kulcs esetén PIROS.
- [ ] **Delete-mátrix:** egy session törlése / delete-all / törlés sérült
      rekord mellett — mindhárom után a **nyers store** tartalma ellenőrizve.
- [ ] **Karantén-teszt:** csonka rekord → csak az érintett karanténba, a többi
      olvasható.
- [ ] **Network-spy teszt:** a teljes vision-út (session → persistence → export)
      **nulla** hálózati kérés; a meglévő offline-guard bővítve.
- [ ] **Privacy panel widget-teszt:** a törlés destruktív megerősítést kér, és
      a megerősítés nélkül **nem** hív törlést (hívásszámláló 0).
- [ ] **Lokalizációs paritás** zöld.
- [ ] **Valódi-sértés próba (§10):** egy landmark-idősor mező felvétele a
      codecbe → a privacy-snapshot teszt PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/features/settings test/app/offline_network_guard_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. RED: privacy-snapshot + delete-mátrix + network-spy.
2. Codec + repository + migráció + karantén.
3. Export.
4. Privacy panel + ARB; gate.

## 9. Kockázatok

- **A „csak fejlesztéshez" landmark-dump** — a legvalószínűbb privacy-szivárgás;
  a snapshot-teszt az egyetlen gépi őr.
- **A törlés csak logikai** (soft delete) — a nyers store ellenőrzése ezt fogja meg.

**STOP:** raw média mentése, soft delete vagy hálózati út bevezetése helyett
dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

### Módosítások

- `vision_session_codec.dart`: explicit, kanonikus kulcssorrendű DTO codec a
  `VisionSessionResult` allowlistjéből. A mentett mezők: `sessionId`,
  `startedAt`, `endedAt`, `endReason`, enum-alapú `quality`
  (`frameCount`, framing, lighting, blur, stability, roiCoverage, overall,
  setupCue), `calibrationState`, insightonként `code`, `policyVersion`,
  csak `evidenceIds`, `confidence`, `priority`, `direction`, `capability`,
  valamint `observedFrameCount`. Nincs kép, URI, pixel, koordináta vagy
  landmark-idősor. A shape-verzió dispatch future version esetén
  `unknownEnum`-mal fail-loud.
- `vision_session_repository.dart`: helyi `JsonCollectionStore`-wrapper;
  rekordhibánál a generikus per-record skip/karantén-mechanizmust használja.
  A `maxItems` cap **100**: ez korlátos helyi retentiont ad az
  aggregate-only előzményeknek, miközben elég a friss edzés-trendhez. Az
  egy-session törlés újraírt collectionből hagyja ki a rekordot; a
  `deleteAllVisionData` a historyt, kalibrációt és minden `.corrupt` shadowt
  nyers `KeyValueStore.remove`-val eltávolít.
- `vision_export.dart`: a tárolttal azonos DTO-t és a shape-verziót exportálja;
  constructora csak `KeyValueStore` + codec, hálózati dependency nélkül.
- `vision_privacy_control.dart`, `storage_keys.dart`, `vision/public.dart`:
  explicit retention policy, `ss.vision.session_history`, törölhető Vision
  kulcslista és additív public contract.
- `vision_privacy_screen.dart` + ARB: standalone privacy panel explicit
  key-scope listával, sessionenkénti törléssel, exporttal és confirmált
  delete-all-lal. Route/settings wiring szándékosan nincs ebben a körben.
- Tesztek: byte-stabil round-trip, future-version skip, record-hiba melletti
  olvashatóság, nyers-store delete-mátrix, store/export privacy snapshot,
  confirm-dialog és Vision route → session persistence → export network-spy.

### Futtatott ellenőrzések

- `flutter analyze lib/features/vision/data/persistence lib/features/vision/domain/vision_privacy_control.dart lib/core/storage/storage_keys.dart` — zöld, 0 issue.
- `flutter test test/features/vision/data/vision_session_repository_test.dart test/features/vision/data/vision_export_privacy_test.dart` — zöld, 6 teszt.
- `flutter test test/features/settings/vision_privacy_screen_test.dart` — zöld, 1 teszt.
- `flutter test test/app/offline_network_guard_test.dart` — zöld, 4 teszt; a
  Vision route után egy tényleges local `save` + JSON export is fut, továbbra
  is 0 hálózati factory/kérés mellett.
- `tools/round-gate.sh test/features/vision test/features/settings test/app/offline_network_guard_test.dart` — zöld (format, analyze, célzott Vision/Settings/offline-network tesztek és architecture). Az első két gate-kísérlet analyze-lépése redundáns `public.dart`-importokra jelzett; az importok eltávolítása után a kötelező gate sikeresen lefutott.
- Valódi-sértés próba: ideiglenesen `landmarkSeries` került a codec DTO-ba;
  `flutter test test/features/vision/data/vision_export_privacy_test.dart`
  elvárt módon piros lett (`Actual` kulcslistában `landmarkSeries`), majd a
  mező vissza lett állítva. A záró gate ezt már a helyreállított állapotban
  futtatja.

### Eltérések és nem futtatott ellenőrzések

- A briefhez nincs funkcionális eltérés. Valódi korábbi session-shape nem
  létezik, ezért nincs kitalált legacy migráció.
- CI-dispatch, PR és merge nem implementer-feladat; nem futtatva.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r28-vision-persistence-privacy-and-deletion-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.

> **Reviewer figyelem:** privacy-kritikus kör (ADR 0178/0183) — a
> `security-reviewer` ágens bevonása KÖTELEZŐ.
