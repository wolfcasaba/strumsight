# E05-R09 — Review

Brief: `docs/rounds/e05-r09-frame-quality-assessor.md`
Diff: `git diff main...codex/e05-r09-frame-quality-assessor` (implementer commit `3671358`, on top of the orchestrátor pre-flight commit `ac03c1f`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-06
Verdikt: **APPROVED** (2 javító kör után — ld. a jelentés végén)

## Összegzés (eredeti, első pass)

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 4

Mindkét MAJOR **teszt-hiányosság**, nem termelt kódhiba: a tényleges
implementáció mindkét esetben helyesen viselkedik (kézzel elolvasva és
mutáció-próbával igazolva), de a jelenlegi teszt-készlet nem bizonyítja
falszifikálhatóan a brief §6 két kritériumát. Mindkettő kis, célzott
teszt-only javítással zárható, produkciós kód módosítása nélkül.

## Módszer

Független, izolált `/tmp/review-e05-r09` klónban (nem a megosztott
munkapéldányban). `tools/prepare-flutter-generated.sh` (friss klón → hiányzó
`flutter pub get`/l10n) után `tools/round-gate.sh test/features/vision`
saját kézzel újrafuttatva — ld. Gate-bizonyíték. Két saját, eldobható
mutáció-próba (a §10-ben dokumentált implementer-próbán felül) a
prioritás-sorrendre és a degenerált-bemenet ágra — ld. F1/F2.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Fixture-készlet (sötét, kiégett, motion-blur, éles/stabil, részleges ROI), szintetikus, nincs személyes adat | ✅ | `frame_quality_assessor_test.dart:20-79` (dark/clipped/blurred/blurredWide/sharpStable), `test/fixtures/vision/quality/README.md` — 5 típus dokumentálva, két blur-felbontás (8×8, 16×12) |
| 2 | Küszöb-mátrix minden metrikára, mindhárom cella (alatta/rajta/fölötte) | ✅ | `frame_quality_assessor_test.dart:81-130` — luminance 39/40/41, overexposed 214/215/216, sharpness 9.9/10/10.1, motion 11.9/12/12.1, coverage 0.10/0.20/0.30, mind közvetlenül a `QualityThresholds` predikátumokon |
| 3 | Prioritás-teszt: egyszerre több hiba → pontosan egy cue, §5.3 sorrend; két azonos súlyú hiba is determinisztikus | ⚠️ **RÉSZLEGES — ld. F1** | `vision_quality_summary_test.dart:6-61` bizonyítja: framing nyer mind a négy másik ellen egyszerre (teszt #1), és mindegyik dimenzió ÖNMAGÁBAN helyes cue-t ad (teszt #3). **Nem bizonyítja** a köztes párokat (pl. blur↔stability, lighting↔roiCoverage) egyszerre-rossz esetben — mért mutáció-próbával igazolva (F1) |
| 4 | NaN/Infinity guard: degenerált bemenetre (0 méret, konstans kép) → `notObservable`, egyetlen mező sem NaN | ⚠️ **RÉSZLEGES — ld. F2** | `frame_quality_assessor_test.dart:132-148` bizonyítja a 0×0 esetet + `measurements` végig finite. A **konstans kép** ág lefut (`vision_quality_summary_test.dart` — helyesen `does not compare motion across an unobservable frame`), de a konstans-frame SAJÁT visszatérési értékére (overall/lighting/blur stb.) nincs közvetlen assert — mért mutáció-próbával igazolva (F2) |
| 5 | Költség-mérés: 640×480 mért átlagidő §10-ben, budget alatt | ✅ | `test/fixtures/vision/quality/frame_quality_benchmark.dart`; §10 önjelentés 691.33 µs/frame; **saját, független újrafuttatás:** 622.82 µs/frame — mindkettő << 16.67 ms (60 FPS budget) |
| 6 | Valódi-sértés próba §10-ben dokumentálva | ✅ | Terra saját próbája (§10: lighting-elé-tolt framing-csere → piros → visszaállítás) **plusz** e review két saját mutáció-próbája (ld. F1/F2 — ezek pont a hiányosságot fedték fel) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

`git diff --stat main...codex/e05-r09-frame-quality-assessor` (saját klónban futtatva) pontosan a brief §4 tíz bejegyzését adja: 4 új domain fájl,
`public.dart` (additív, 5 új export sor, semmi törölve/módosítva — ellenőrizve
soronként), 2 teszt fájl, 2 fixture fájl, a round brief maga. Az implementer
saját `Legacy scope audit` (a logban) és a wrapper záró `.codex-round-status`
egyaránt `scope_audit=ok`, `scope_audit_changed=10`,
`scope_audit_base=ac03c1f` (a pre-flight commit, nem `origin/main` — helyesen,
az orchestrátor §0.0 commitja nem számít az implementer scope-jába).

## Architektúra és termékhatárok

- **Framework-mentes domain** (§5.1): a négy új fájl importjai —
  `dart:typed_data`, három relatív sibling-import, `core/camera/…` (core→feature
  irány, megengedett). Nincs `package:flutter/…`, nincs modellhívás, nincs I/O. ✅
- **`public.dart` additív-only**: 5 új export sor, 0 törölt/módosított. ✅
- Architecture gate (`tool/check_architecture.dart`) zöld, 12 allowlistelt
  eltérés — mind pre-existing, a diff nem érint allowlist-fájlt. ✅
- Fixture-adatok kizárólag szöveges (`README.md`, `.dart` generátor) —
  nincs bináris/kép fixture, nincs személyes/kamera-adat. ✅
- **`dirty_files=1`** volt az ELSŐ (`codex-signal.sh done` pillanatában írt)
  jelzésben. Kivizsgálva: az implementer saját `git status --short` a jelzés
  ELŐTT ÉS UTÁN is tiszta fát mutatott; a `.tmp.$$` → `mv` atomikus csere
  (`codex-signal.sh` §65-77) önmagát látja egy pillanatra untracked fájlként a
  `git status --porcelain` hívás közben — jóindulatú self-race, nem elveszett
  munka. A friss `.codex-round-status` (a wrapper post-exit lépése után) és a
  saját klónom is 0 dirty file-t mutat.

## Megállapítások

### F1 — MAJOR — a cue-prioritás teljes rendezése csak részben bizonyított

- **Fájl:** `test/features/vision/domain/vision_quality_summary_test.dart`
- **Probléma:** a §6 3. kritériuma a §5.3 **teljes rendezését** követeli meg
  ("egyszerre több hiba → pontosan egy cue, a sorrend szerint"). A jelenlegi
  tesztek bizonyítják, hogy *framing* nyer a másik négy ellen (test #1), és
  hogy minden dimenzió ELSZIGETELVE helyes cue-t ad (test #3) — de **egyetlen
  teszt sem** állít két, framing/lighting alatti dimenziót EGYSZERRE rosszra
  (pl. blur+stability, vagy lighting+roiCoverage), hogy a köztes párok
  sorrendje bizonyított legyen.
- **Mért bizonyíték:** saját mutáció-próba (`lib/features/vision/domain/quality/vision_quality_summary.dart`,
  `_cue()` metódus) — felcseréltem a `blur`- és `stability`-ág sorrendjét
  (stability előbb, blur utóbb). `flutter test test/features/vision/domain/vision_quality_summary_test.dart`
  → **mind a 4 teszt zöld maradt** a hibás sorrenddel is. A mutáció
  visszaállítva, a fájl a `3671358` commit tartalmára állítva.
- **Hatás:** ha egy jövőbeli, scope-on belüli módosítás felcseréli két
  köztes prioritás-szint sorrendjét (pl. refaktorálásnál), a gate zöld marad,
  és a felhasználó rossz sorrendű setup-cue-t kap (pl. "stabilizáld a
  kamerát", miközben a §5.3 szerint a blur-hibának kellene elsőbbséget
  élveznie) — csendes, gate által nem fogott termékhatár-sértés.
- **Kötelező javítás:** legalább egy teszt-eset, amely a §5.3 teljes láncát
  PÁRONKÉNT bizonyítja — pl. egy paraméterezett/láncolt teszt, ahol
  `{lighting jó, blur+stability+roiCoverage mind rossz}` → `reduceBlur`;
  `{lighting+blur jó, stability+roiCoverage rossz}` → `stabilizeCamera`;
  `{lighting+blur+stability jó, roiCoverage rossz}` → `increaseRoiCoverage`
  (ez utóbbi már közvetve bizonyított az egyedi teszttel, de a lánc többi tagja
  nem). Produkciós kód módosítása NEM szükséges — a `_cue()` már helyesen a
  §5.3 sorrendet követi.
- **Ellenőrzés:** az új teszt(ek) a fenti mutáció (blur/stability csere)
  mellett PIROSRA váltanak, az eredeti sorrenddel ZÖLDEK.
- **Státusz:** OPEN

### F2 — MAJOR — a konstans-kép degenerált ág saját kimenete nincs közvetlenül bizonyítva

- **Fájl:** `test/features/vision/domain/frame_quality_assessor_test.dart`
- **Probléma:** a §6 4. kritériuma két degenerált esetet nevesít: "0 méret,
  **konstans kép**" → `notObservable`. A `returns notObservable with finite
  measurements for degenerate input` teszt kizárólag a 0×0 esetet fedi. A
  konstans-kép ág máshol (`does not compare motion across an unobservable
  frame`, `vision_quality_summary_test.dart` egyik segédfüggvénye) csak
  MELLÉKHATÁSKÉNT fut le (a `_previousSamples` reset hatását nézi a
  KÖVETKEZŐ frame-en) — a konstans frame SAJÁT `overall`/`lighting`/`blur`
  mezőire nincs közvetlen assert.
- **Mért bizonyíték:** saját mutáció-próba
  (`lib/features/vision/domain/quality/frame_quality_assessor.dart`,
  `assess()`) — a konstans-kép ágat úgy módosítottam, hogy `_previousSamples`
  helyesen null-ra áll ÉS korán visszatér (a §10 kontinuitás-tesztet nem
  érinti), de egy KITALÁLT, `overall: good` értékű `VisionFrameQuality`-t ad
  vissza `notObservable` helyett. `flutter test test/features/vision/domain/frame_quality_assessor_test.dart
  test/features/vision/domain/vision_quality_summary_test.dart` → **mind a 10
  teszt zöld maradt.** A mutáció visszaállítva.
- **Hatás:** ADR 0179 fő garanciája ("hiányzó megfigyelhetőség ⇒
  `notObservable`, nem gyengébb ítélet") pont erre az ágra vonatkozik — egy
  csendes regresszió itt a §5.2 kötött döntést sértené (technikai
  visszajelzést adna ott, ahol a mérés nem megbízható), és a gate ezt ma NEM
  fogná meg.
- **Kötelező javítás:** egy közvetlen assert a konstans-kép `assess()`
  visszatérési értékén (pl. nem-nulla méretű, egyenletes luminance-fixture →
  `expect(quality.overall, VisionMetricState.notObservable)` +
  `quality.measurements` finite-guard, hasonlóan a 0×0 esethez).
- **Ellenőrzés:** az új teszt a fenti mutáció mellett PIROSRA vált, az
  eredeti kóddal ZÖLD.
- **Státusz:** OPEN

### N1 — NOTE — `minimumFramingCoverageFor` csak 2 a 4 profilból tesztelve

- **Fájl:** `lib/features/vision/domain/quality/quality_thresholds.dart:84-90`
- A négy `VisionSetupProfile` közül csak `practiceBalanced` és
  `leftHandFocus` szerepel tesztben; `rightHandFocus` (0.01) és
  `fullUpperBody` (0.12) értéke sosem kerül assertált útvonalra. A
  leképezés egy egyszerű `switch`, alacsony kockázatú — nem blokkoló,
  de egy jövőbeli körben (profilonkénti valós ROI-integráció) érdemes
  mind a négyet lefedni.

### N2 — NOTE — `framing` és `roiCoverage` ugyanazt a `roiCoverageRatio`-t méri két küszöbön

- **Fájl:** `lib/features/vision/domain/quality/frame_quality_assessor.dart:80-97`
- Szándékos, és a `partial ROI is a separate frame-quality concern` teszt
  igazolja, hogy a két dimenzió ténylegesen szét tud válni (a profilfüggő
  laza küszöb vs. a fix, szigorúbb `minimumRoiCoverage`). Egy doc-comment a
  `framing`/`roiCoverage` mezők fölött, ami kimondja, hogy mindkettő a
  `roi` paraméter területéből származik két különböző küszöbön, segítene a
  következő olvasónak — nem blokkoló.

### N3 — NOTE — §5.3 cue-sorrend a pre-flight §0.0-R2 szerint a brief saját döntése

- A `docs/rounds/e05-r09-frame-quality-assessor.md` §0.0-R2 (pre-flight,
  orchestrátor) már dokumentálta, hogy a §5.3 sorrend (framing → lighting →
  blur → motion → ROI-lefedettség) NEM az SDD §14.3 hét tételes listájának
  mechanikus szűkítése, hanem e kör saját, kötött döntése a modell nélküli
  altér felett. A termék-UX szempontú mérlegelés emberi/jövőbeli kör dolga —
  ez a review a KÓDOT a §5.3-hoz méri (annak, amit implementál, helyesen
  megfelel), nem az SDD-hez.

### N4 — NOTE — a low-tier device-mátrix PENDING marad

- A §6 5. kritériuma és a §7 megjegyzése szerint ez elvárt ezen a körön —
  a lokális Dart-benchmark (622-691 µs, dev-box) nem helyettesíti, csak a
  nagyságrendet rögzíti. Nem e kör hatásköre.

## Gate-bizonyíték ellenőrzése

Mind a hat lépés SAJÁT KÉZZEL, izolált `/tmp/review-e05-r09` klónban,
`tools/prepare-flutter-generated.sh` után, `tools/round-gate.sh test/features/vision` egyetlen artefaktum-hívással:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (1068 fájl, 0 változás) | ✅ saját futtatás |
| analyze | zöld (0 issue) | ✅ saját futtatás |
| test test/features/vision | zöld (23/23) | ✅ saját futtatás |
| architecture | zöld (12 allowlistelt, pre-existing) | ✅ saját futtatás |
| secrets | zöld (1846 fájl, 0 lelet) | ✅ saját futtatás |
| l10n parity | zöld (942 üzenet, en↔hu) | ✅ saját futtatás |
| CI (teljes suite + property + APK) | — | **még nem dispatch-elve — F1/F2 zárása után** |

## Security review

Külön `security-reviewer` ágens dolgozik a brief `risk = "high"` jelölése
miatt (`docs/reviews/e05-r09-frame-quality-assessor-security.md`) —
folyamatban, ennek a jelentésnek a lezárásakor még nem érkezett vissza.

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge. **Jelenleg 2 nyitott MAJOR (F1, F2) → merge TILOS.** Javító kör
szükséges: ugyanaz a motor (Terra), a fenti két lelet listájával, kizárólag
a két érintett teszt fájlra szűkítve — produkciós domain-kód módosítása nem
várt.

---

## Javító kör #1 után — 2026-08-06

Fix commit: `29347c1` (+ a Terra saját, ugyanabban a fordulóban zárt security S1/S2 javítás). Gate újra futtatva SAJÁT kézzel, friss `/tmp/review2-e05-r09` klónban (`tools/prepare-flutter-generated.sh` → `tools/round-gate.sh test/features/vision`): **mind a hat lépés zöld**, 25/25 vision teszt (23→25, +2 új eset).

### F2 — ZÁRVA

Új teszt: `frame_quality_assessor_test.dart` — `returns notObservable with finite measurements for a constant frame`. Közvetlenül asserttál a konstans-kép SAJÁT `overall`/`measurements` mezőire. **Saját mutáció-visszaellenőrzés:** a korábbi (F2-t felfedő) próba a javított kódon már nem alkalmazható változtatás nélkül — az új teszt önmagában PIROSRA vált, ha a konstans-ág korán visszatér, de nem `_notObservable()`-t ad. **Státusz: FIXED (`29347c1`).**

### S1, S2 — ZÁRVA

`frame_quality_assessor.dart` diffje pontosan a kért guardokat adja hozzá:
- `downsampleFactor <= 0` → `assess()` elején explicit `ArgumentError.value` dobás (assert-mentes, release buildben is fut).
- Egy új `hasObservableRoiCoverage = roi != null && roiCoverageRatio.isFinite` mindkét `framing` ÉS `roiCoverage` állapotot erre szűkíti a korábbi puszta `roi == null` helyett — a NaN-eset immár mindkét mezőn `notObservable`, nem csak a `framing`-en. Tiszta, minimális, a §5 kötött döntéseket nem érinti. **Státusz: FIXED (`29347c1`).**

### F1 — RÉSZBEN ZÁRVA, egy lánc-elem még nyitva

Új teszt: `vision_quality_summary_test.dart` — `prioritizes each cue over every lower-priority concern`, három al-esettel: `{blur+stability+roiCoverage rossz, lighting jó}` → `reduceBlur`; `{stability+roiCoverage rossz, lighting+blur jó}` → `stabilizeCamera`; `{roiCoverage rossz}` → `increaseRoiCoverage`. Ez **ténylegesen lezárja** a blur↔stability és stability↔roiCoverage párokat (a review eredeti mutáció-próbája — blur/stability csere — most PIROSRA vált, ellenőrizve).

**Egy pár még nyitva: lighting↔blur.** A meglévő tesztek egyike sem állítja
`lighting`-et rosszra EGYSZERRE bármelyik alacsonyabb dimenzióval (a lánc új
teszt-ága `lighting`-et mindenhol a default `good`-on hagyja). **Saját mért
bizonyíték:** a `_cue()`-ban a lighting/blur ág-sorrend felcserélve → a teljes
`vision_quality_summary_test.dart` (mind az 5 teszt, a javított kóddal együtt)
**ZÖLD maradt** a hibás sorrenddel is. Mutáció visszaállítva.

**Kötelező javítás (javító kör #2, szűken szigetelve):** egy negyedik al-eset
a `prioritizes each cue over every lower-priority concern` teszthez:
`{lighting: tooDark VAGY overexposed, blur/stability/roiCoverage mind rossz,
framing jó}` → `improveLighting`. Ez zárja a lánc utolsó nyitott elemét
(framing↔lighting már az 1. teszttel bizonyított).

**Verdikt marad CHANGES REQUIRED** — 1 nyitott MAJOR (F1, szűkítve).

---

## Javító kör #2 után — 2026-08-06 — APPROVED

Fix commit: `a7f446b` — pontosan a kért egy al-eset
(`lighting: tooDark, blur/stability/roiCoverage mind rossz → improveLighting`).

Gate újra futtatva SAJÁT kézzel, harmadik friss klónban
(`/tmp/review3-e05-r09`): mind a hat lépés zöld, 25/25 vision teszt.

**Végső mutáció-visszaellenőrzés:** a `_cue()`-ban a lighting/blur ág-sorrend
felcserélve (utoljára, ezen a végleges kódon) → `prioritizes each cue over
every lower-priority concern` PIROSRA váltott, minden más teszt zöld maradt.
Visszaállítva.

A §5.3 teljes lánca (framing→lighting→blur→stability→roiCoverage) mind a
négy szomszédos párja immár külön-külön, mért mutációval bizonyítva:
framing↔{lighting,blur,stability,roiCoverage} (1. teszt), lighting↔blur
(új), blur↔stability (kör #1), stability↔roiCoverage (kör #1).

**Nyitott BLOCKER/MAJOR: 0.** A security review (2 MINOR, S1/S2) is zárva
(kör #1). Nincs több nyitott lelet.

**VÉGSŐ VERDIKT: APPROVED.** Mehet a CI-dispatch és a merge.
