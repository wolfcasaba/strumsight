# E13-R26 review — Analyze Home, Recording és Processing UI

- **Kör:** `E13-R26` (Chapter 13, Kör 26)
- **Branch:** `sonnet-impl/e13-r26-analyze-recording-and-processing`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor), read-only, izolált `/tmp` klón
- **Review-elt diff:** `5b6fa961..0243c26e` — 19 fájl, +2330 / −1
- **Dátum:** 2026-08-26

## VÉGSŐ DÖNTÉS: **APPROVED**

**0 BLOCKER · 0 MAJOR · 0 MINOR · 3 NOTE.** A kör merge-elhető.

---

## 1. Amit a review MÉRT (nem bemondásra fogadott el)

### 1.1 Scope-audit — a jelzésfájlból HIÁNYZOTT, kézzel pótolva

Az implementer jelzésfájljában **nem volt `scope_audit=` kulcs**, tehát a
scope bizonyítatlan volt. Kézi mérés (ADR 0138 kifutó ága):

```
$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r26 \
    --brief docs/rounds/e13-r26-analyze-recording-and-processing.md --base 5b6fa961
Legacy scope audit OK (5b6fa9610800..0243c26e65fe, 19 changed path(s), 0 generated/ignored)
```

Az első futás EGY sértést jelzett — `.round-prompt-e13-r26.md` —, ami az
**orchestrátor saját, sosem commitolt** prompt-fájlja a munkapéldány
gyökerében, nem implementer-termék. A repóból kimozgatva az audit tiszta.
`dirty_files=2` a jelzésben ugyanerre a fájlra (+ a jelzésfájlra) vezethető
vissza — **elveszett munka nincs**, minden termék commitolva.

### 1.2 A gate FÜGGETLEN újrafuttatása izolált klónban

A `/tmp/ss-review-e13-r26` friss klónban, a kör teljes gate-sorával:
**mind a 18 lépés ZÖLD** (format, analyze, 13 teszt-útvonal külön processzben,
architecture, secrets, l10n). Ez független megerősítése az implementer
állításának, nem az ő kimenetének átvétele.

### 1.3 Exact-SHA CI a `0243c26e` head SHA-n

| Kapu | Run | Eredmény |
|---|---|---|
| Full Gate (`full-gate.yml`) | [33015979355](https://github.com/wolfcasaba/strumsight/actions/runs/33015979355) | **success** |
| Router CI (`router-ci.yml`) | [33015973741](https://github.com/wolfcasaba/strumsight/actions/runs/33015973741) | **success** |

A CI-tervező (`tools/round-ci-plan.py`) `full-gate.yml`-t írt elő
(`apk_required: false`, tisztán Dart/dokumentum-diff) és Router CI-t várt
(`docs/rounds/**` trigger-találat) — mindkettő lefutott és zöld.

---

## 2. Eldobható próbatesztek — a MÉRT ellenőrzés

### 2.1 Érintési cél (ADR 0280 §5, ≥ 48 dp) — a gyanú MEGDŐLT

Ez a sáv **kétszer** bukott ezen (E13-R20/MAJOR-1: 40 dp; E13-R21/MAJOR:
32 dp — mindkettő ZÖLD gate mögött), ezért célzottan mértem. A statikus
olvasat gyanús volt: a három képernyő **egyetlen** `minimumSize`-t sem állít
be, a téma pedig nem ad button-szintű override-ot
(`grep -rn "minimumSize\|MaterialTapTargetSize" lib/core/theme lib/core/design_system`
→ 0 találat), miközben a merge-elt E13-R22 precedens explicit
`FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))`-t használ
(`practice_result_screen.dart:360`).

**Eldobható próbateszt (mérés, nem következtetés):**

```
PROBE FilledButton[0] height=48.0 width=768.0     (recording Stage, idle)
PROBE InkWell[0] height=100.0 width=760.0         (home — felvétel kártya)
PROBE InkWell[1] height=80.0  width=760.0         (home — import kártya)
```

A Flutter alapértelmezett `MaterialTapTargetSize.padded`-je a Material
gombok érintési célját 48 dp-re tölti ki, az `InkWell`-kártyák pedig
tartalmi méretüknél fogva jóval fölötte vannak. **A szerződés teljesül;
lelet nincs.** A gyanút a mérés zárta le — ezt a bekezdést azért hagyom
benne, hogy a következő kör ne induljon újra a téves statikus olvasatból.

### 2.2 Az A3 valódi-sértés próbája — az implementer állítása HIHETŐ

A §10 dokumentálja az időzítőből animált százalék visszaültetését és a
mért piros cellát (`Expected: no matching candidates / Actual: Found 1
widget with text containing %: [Text("0%")]`). A cella maga
falszifikálható és nem tautologikus (lásd 3.2), a hibaüzenet alakja
pontosan az `expect(find.textContaining('%'), findsNothing)` állításé —
az állítás konzisztens a kóddal.

---

## 3. A kötött döntések (ADR 0285) tételes ellenőrzése

### 3.1 A2 — a megőrzés-jelzés a MÉRT policy-ból jön, nem kitalált kapcsolóból

`_RetentionNotice` (`analysis_recording_screen.dart:313-340`) a
`retentionPolicy.keepOriginal`-on **ténylegesen ágazik** — külön ikon
(`privacy_tip_outlined` / `save_outlined`) és külön lokalizált szöveg. Nem
beégetett egyetlen string. A default `AudioRetentionPolicy.defaultPolicy`
(`keepOriginal: false`, ADR 0217 §1) — a felület tehát alapesetben a
„csak a származtatott elemzés marad meg" igazságot mondja ki. **A §0.0/B6
tiltása (kitalált megőrzés-kapcsoló) betartva.**

### 3.2 A3 — nincs hamis százalék, és a három cella VALÓDI

| Cella | Bemenet | MÉRT elvárás a tesztben |
|---|---|---|
| alatta | `AnalysisAnalyzing(runId)` — nincs fázis | `bar.value` **`isNull`** + `find.textContaining('%')` **`findsNothing`** |
| rajta | `+ phase: estimatingHarmony` | szakasz-szintű szöveg (`5/9`), `bar.value` **`isNull`**, `%` továbbra sincs |
| fölötte | `+ completedUnits: 3, totalUnits: 5` | `bar.value` **`closeTo(0.6)`** — a TÉNYLEGES hányados |

A fán **nincs** `Timer`, `Random`, `AnimationController` vagy `Ticker`
(`grep` a három képernyőn → 0 találat), tehát álhaladás szerkezetileg sem
keletkezhet.

### 3.3 A4 — a megszakítás idempotens, és nem „örökre tiltó"

`_handleCancel` (`analysis_processing_screen.dart:48-52`) `_cancelledForRunId`
per-run őrrel dolgozik: azonos `runId`-ra a második koppintás no-op, **ÚJ
`runId` viszont újra engedélyezi**. Ez a helyes olvasat — egy globális
`_cancelled` bool „cancel forever"-t csinálna a következő futásból is.

### 3.4 A5 — nincs árva mikrofon egyetlen kilépési úton sem

`dispose()` (`:72-79`) minden útvonalon lemondja a level-subscriptiont és
hívja `widget.recorder.dispose()`-t. `AnalysisRecorder.dispose()` (`:218-226`)
**valóban idempotens** (`if (_disposed) return;`), és `try/finally`-ben
`stop()`-ol (mic-lease elengedés) majd zárja a stream-controllert. A
doc-comment állítása („idempotens, biztonságos duplán is") tehát **kódban
bizonyított**, nem díszítés — megfelel a doc-comment fegyelemnek.

### 3.5 A8 — a degradált ok MÉRT, nem kitalált

`_DegradedBody` (`:218-233`) a `document.capabilities` halmazból KIZÁRÓLAG
azokat gyűjti, ahol `status == CapabilityStatus.unavailable && reason != null`,
és a MEGLÉVŐ `AppLocalizationsOverviewLabels.unavailableReason` adaptert
használja. **Kitalált hő-/akku-indok nincs a kódban** — a §0.0/B6 tiltása
betartva.

### 3.6 Scope-fegyelem

- `analysis_progress_view.dart` **bájtra változatlan** (`git diff 22ef4b1e..HEAD`
  a fájlra → **0 sor**) — a kör befogadta, nem írta újra (§0.0/B2).
- `test/ui/ui_inventory_test.dart` diffje **egyetlen sor**: `hasLength(86)` →
  `hasLength(89)`. Más állítás érintetlen (§0.0/R4 jogosultság pontosan ez).
- **Route nem került be** (§0.0/B3) — a `route_literal_guard_test` zöld.
- **ADR nem íródott** — a `0285` merge-elt (§0.0/B0), H1 elkerülve.
- l10n: 39 új `analysis*` kulcs, **mind a négy** fájlban azonos darabszámmal
  (base forrás + generált aggregátum, en + hu); a gate `l10n` lépése
  „aggregate freshness OK" + „parity OK (2033 message)".

---

## 4. NOTE-ok (follow-up, NEM merge-blokkoló)

**NOTE-1 — az A3 „fölötte" cellája a sáv értékét méri, a szöveget nem.**
`expect(bar.value, closeTo(0.6))` bizonyítja, hogy a szám VALÓDI, de nem
állítja, hogy a felhasználó százalékot LÁT. A §6.1 „a tényleges százalék"
elvárását a sáv hordozza; ha egy későbbi kör szöveges százalékot is kiír, a
cellát érdemes kiegészíteni.

**NOTE-2 — `silenceThresholdDbfs = -45.0` kalibrálatlan prezentációs
konstans.** Az implementer helyesen jelölte: konstruktor-paraméter,
doc-commentje kimondja, hogy „the engine never reads this value", és a mérés
ezt megerősíti (kizárólag a `_RecordingBody`-nak adódik át). Nem DSP-paraméter
(AGENTS.md §9 nem sérül), de a küszöb nincs valós felvételen hitelesítve — egy
halkan játszó felhasználó „túl csendes" jelzést kaphat. Kalibráció egy
DSP/valós-hang körre való.

**NOTE-3 — a három képernyő nincs huzalozva** (route, providerek, egymás
közti navigáció). Ez **szándékos** és a §0.0/B3-ban előre rögzített: a
merge-elt E13-R22 precedens (`practice_history_screen`, `speed_builder_screen`
szintén route nélkül merge-elt) és az [L409](../LESSONS.md#l409) ugyanezt
mondja. A route-élesítés külön kör dolga; addig a képernyők a
`ui_inventory`-ban szerepelnek, de a felhasználó nem éri el őket.

---

## 5. Merge-ajánlás

Minden előfeltétel teljesül: scope-audit OK, független gate-újrafuttatás
18/18 zöld, exact-SHA Full Gate + Router CI zöld, a hét kötött ADR 0285
döntés tételesen ellenőrizve, és a sáv kétszer visszatérő érintési-cél
hibaosztálya MÉRÉSSEL kizárva. **Squash-merge az ADR 0052 zöld kapuja alatt.**
