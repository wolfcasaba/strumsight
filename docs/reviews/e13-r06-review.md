# E13-R06 review — Motion rendszer és reduced motion

- **Kör:** `E13-R06` · **Branch:** `sonnet-impl/e13-r06-motion-and-reduced-motion`
- **Reviewed HEAD:** `9f47f2e0` → javító kör 1: `0ceb213b` → javító kör 2: **`580440a4`**
  (implementer: `sonnet-impl` / Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5), orchestrátor — read-only, production kódot nem írtam
- **Dátum:** 2026-08-23
- **Verdikt (1. kör):** CHANGES REQUESTED — 1 MAJOR, 3 MINOR, 2 NOTE
- **Verdikt (2. kör):** CHANGES REQUESTED — 1 új MAJOR (regresszió, lásd §7)
- **VÉGSŐ VERDIKT (3. kör, HEAD `580440a4`):** ✅ **APPROVED** — lásd §8

---

## 1. Amit magam mértem (nem bemondásra)

### 1.1 Gate — izolált `/tmp` klónban, saját kézzel újrafuttatva

```
git clone --branch sonnet-impl/e13-r06-motion-and-reduced-motion \
  /home/ubuntu/ss-sonnet-impl-e13-r06 /tmp/review-e13-r06
bash tools/prepare-flutter-generated.sh
tools/round-gate.sh test/core/design_system/motion/ss_motion_scope_test.dart \
                    test/core/design_system/motion/ss_beat_pulse_test.dart
```

Mind a hét lépés **ZÖLD** (17 cella: 7 + 10):

| lépés | eredmény |
|---|---|
| format | zöld — 1890 fájl, 0 changed |
| analyze | zöld — `No issues found! (ran in 23.4s)` |
| test `ss_motion_scope_test.dart` | zöld — 7/7 |
| test `ss_beat_pulse_test.dart` | zöld — 10/10 |
| architecture | zöld — 12 allowlisted deviation |
| secrets | zöld — 3487 fájl, 0 finding |
| l10n | zöld — parity en→hu, 1755 üzenet |

### 1.2 Scope-audit — a hiteles eszközzel

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r06 \
  --brief docs/rounds/e13-r06-motion-and-reduced-motion.md --base 467ef3ea
→ Legacy scope audit OK (467ef3ea5544..9f47f2e0f190, 8 changed path(s), 0 generated/ignored)
```

A jelzésfájlban **nem volt** `scope_audit=` kulcs, ezért a fenti kézi futtatás
az egyetlen scope-bizonyíték (prompt §1.1). Eredmény: **OK**, nincs listán
kívüli fájl.

### 1.3 A6 / A7 / ADR 0274 §4 — közvetlenül mérve

```
git diff --stat 467ef3ea..HEAD -- lib/features/        → üres  (A6 ✅)
grep -n "Duration(" lib/core/design_system/motion/*.dart
  → ss_beat_pulse.dart:57: syncTolerance = Duration(milliseconds: 100)  (A7 ✅ — küszöb, nem animáció-hossz)
grep -rn "package:strumsight/features" lib/core/design_system/  → üres  (ADR 0274 §4 ✅)
```

---

## 2. Leletek

### 🔴 MAJOR-1 — a §6.1 KÖTELEZŐ óra-szinkron hármas tautologikus: zöld marad a tiltott implementáción is

**Hol:** `test/core/design_system/motion/ss_beat_pulse_test.dart:22-46`
(a `SsBeatPulse.isWithinSyncTolerance — A3, the three threshold cells` group),
a mért felület `lib/core/design_system/motion/ss_beat_pulse.dart:57-66`.

**Mit ír elő a brief §6.1:** *„Az óra-szinkron három kötelező cellája (a küszöb:
a megengedett vizuális lag, **100 ms**): a küszöb alatt | **60 ms eltérés az
órától** | elfogadva …"* — a cella bemenete tehát a **renderelt pulzus tényleges
eltérése az órától**, nem egy predikátumnak átadott szám.

**Mi valósult meg:** a három cella kizárólag a tiszta, statikus
`SsBeatPulse.isWithinSyncTolerance(Duration)` függvényt hívja, amely
`lag <= syncTolerance` alakú, ahol `syncTolerance` egy 100 ms-os konstans
UGYANABBAN a fájlban. A cellák **soha nem építik fel a widgetet**, és nem
mérnek renderelt fázist. Így azt bizonyítják, hogy `60 <= 100`, `100 <= 100`,
`140 > 100` — vagyis önmagukat.

**Mérés (valódi-sértés próba, reviewer-oldali, `/tmp/review-e13-r06`):**
átírtam a `_onTick`-et, hogy a `widget.clock.position` HELYETT a ticker saját
`elapsed`-jéből számoljon fázist — pontosan a szabadon futó időzítő, amit az
ADR 0274 tilt:

```
final position = elapsed;  // PROBE: free-running, ignores the clock
```

Majd lefuttattam a három kötelező cellát:

```
00:00 +0: … 60ms lag is under the threshold: accepted
00:00 +1: … 100ms lag sits on the threshold: accepted (inclusive bound)
00:00 +2: … 140ms lag is over the threshold: rejected
00:00 +3: All tests passed!
```

**A tiltott implementáció mellett mind a három ZÖLD.** A teljes fájl ugyanezen
a rontáson **6/10 cellát** visz pirosra (A1 ×1, A2 ×2, A3 ×2, „no live
timeline" ×1) — tehát az *óra-vezéreltség* szabálya jól őrzött, de a **100
ms-os küszöb maga sehol nincs renderelt lag ellen mérve**. A brief által
kötelezővé tett numerikus mérce az egyetlen, ami nem tud elbukni. Ez pontosan
az „a zöld gate nem bizonyíték" hibaosztály (`docs/LESSONS.md` L21). A próba
után a fájlt visszaállítottam (`git diff` üres).

**Javasolt irány (nem kész patch):** a három cella hajtsa a WIDGETET egy olyan
fake órával, amelynek pozíciója a „valódi" pozíciótól 60 / 100 / 140 ms-mal
tér el, és mérje a renderelt fázisból visszaszámolt eltérést a
`syncTolerance`-hoz. A `isWithinSyncTolerance` maradhat, de önmagában nem
acceptance-bizonyíték.

---

### 🟡 MINOR-1 — reduced motion mellett az ütem MÁSODIK FELE pixelre azonos a „nincs élő idővonal" állapottal

**Hol:** `lib/core/design_system/motion/ss_beat_pulse.dart:113-121` vs `110-112`.

Csökkentett mozgásnál `_phase >= 0.5` → `colors.surfaceSunken`; a „nincs élő
idővonal" ág **ugyanazt** a `colors.surfaceSunken`-t rajzolja.

**Mérés (PROBE A):**

```
PROBE_A off-beat : BoxDecoration(color: Color(… 0.1333, 0.1255, 0.1216 …), shape: circle)
PROBE_A stopped  : BoxDecoration(color: Color(… 0.1333, 0.1255, 0.1216 …), shape: circle)
PROBE_A IDENTICAL: true
```

A csökkentett mozgást kérő felhasználó tehát minden ütem felében pontosan azt
látja, mint amikor a lejátszás ÁLL. Az A1 cellája ettől zöld marad (az
on-beat/off-beat különbözik), de a brief §5.1 garanciája — a visszajelzés
*állapotváltásként* marad meg — félig sérül. Nem blokkoló: egy ütemnyi
megfigyeléssel a váltakozás megkülönbözteti a két állapotot.

**Javasolt irány:** az off-beat kapjon a `surfaceSunken`-től MEGKÜLÖNBÖZTETHETŐ
értéket (pl. tompított `brand`), vagy a nem-élő állapot kapjon saját, harmadik
megjelenést.

---

### 🟡 MINOR-2 — `beatDuration == Duration.zero` csak `assert`-tel őrzött → release-ben `IntegerDivisionByZeroException`

**Hol:** `lib/core/design_system/motion/ss_beat_pulse.dart:36-39` (az `assert`)
és `:98-99` (a `%` művelet).

Az `assert` release buildben **eltűnik**, a `_onTick` viszont
`position.inMicroseconds % beatMicros`-t számol.

**Mérés (PROBE B) — ugyanaz az aritmetika, assert nélkül:**

```
PROBE_B release-mode arithmetic throws: IntegerDivisionByZeroException
```

Publikus design-system widget, amelynek `beatDuration`-jét a hívó BPM-ből
számolja: hiányzó/0 tempónál a release build az első frame-en dobja.

**Javasolt irány:** valódi futásidejű őr (a nem-pozitív `beatDuration` a
nem-élő ággal ekvivalens, azaz statikus pont), vagy a `beatDuration` típusát
tegyük szerkezetileg pozitívvá.

---

### 🟡 MINOR-3 — a `Ticker` élő idővonal NÉLKÜL is fut, szemben az ADR 0274 §1-gyel

**Hol:** `lib/core/design_system/motion/ss_beat_pulse.dart:80-84` (`..start()`
az `initState`-ben, sosem `stop()`).

Az ADR 0274 §1 szó szerint: *„Ha nincs élő idővonal, a komponens **nem animál**,
nem pedig »szabadon fut«."* A jelenlegi kód `position == null` esetén statikus
pontot RAJZOL (a vizuális előírás teljesül), de a `Ticker` **továbbra is minden
frame-en fut** — vagyis a widget folyamatosan frame-et kér akkor is, amikor
semmi nem szól. Egy mobil zene-appban ez fölösleges frame- és
akkumulátor-terhelés, és ez az, ami a katalógus-demót is megbuktatta.

**Mérés (PROBE C):**

```
PROBE_C pumpAndSettle FAILED: FlutterError   (timeout, élő órával)
```

**Javasolt irány:** `position == null` esetén `_ticker.stop()`, és élővé váláskor
`start()`. Így a nem-élő állapotban a `pumpAndSettle` is leülepszik, és a
katalógus-demó (a §4 engedélyezett deliverable-je) visszahozhatóvá válik.

---

### ⚪ NOTE-1 — `public.dart` export-sorrend

`lib/core/design_system/public.dart:11-13` — a három `motion/*` export a
`foundations/ss_radius.dart` és a `foundations/ss_semantics.dart` KÖZÉ került,
megtörve a fájl eddigi csoportosítását. Nincs rá gépi mérce, nem blokkol.

### ⚪ NOTE-2 — a katalógus-demó elhagyása elfogadva

A `documentation/component_catalog_screen.dart` (engedélyezett fájl) demója
visszavonva, mert a listán KÍVÜLI `component_catalog_test.dart`-ot pirosra
vitte (`pumpAndSettle timed out`). Az implementer a helyes utat választotta: a
tiltott teszt módosítása helyett az engedélyezett fájlt állította vissza, és
ezt a §10-ben dokumentálta. Egyetlen A1–A7 cella sem függ tőle, tehát ez
scope-**szűkítés**, nem hiány. A gyökérokot a MINOR-3 fedi.

---

## 3. Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| A1 | Reduced motion mellett a visszajelzés MEGMARAD | `ss_beat_pulse_test.dart:150-196`; a rontás-próbán pirosra vált | ✅ (de lásd MINOR-1) |
| A2 | A beat-pulzus az audio órából vezetett | `:48-92`; a szabadon futó időzítőn mindkét cella piros | ✅ |
| A3 | Az óra megállása/ugrása után szinkronban marad | `:94-148` (seek + stop cellák) pirosra váltak a rontáson | ✅ a *viselkedésre* |
| A3 | …a **100 ms-os küszöb** mérve | — | ❌ **MAJOR-1**: tautologikus |
| A4 | `dispose` után nincs élő controller / `setState` | `:198-224`; a `flutter_test` „Ticker was still active" őre + explicit `takeException` | ✅ |
| A5 | Az app-szintű felülbírálás felülírja a rendszert | `ss_motion_scope_test.dart` 7/7, mindkét irány + `null` | ✅ |
| A6 | Nem módosít `lib/features/audio_analysis/**`-t | `git diff --stat … -- lib/features/` üres | ✅ |
| A7 | Nincs nyers `Duration` literál az átmenetekben | `grep` → csak `syncTolerance` (küszöb, §6.2 szerint megengedett) | ✅ |

---

## 4. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `core ↛ feature`: `grep -rn "package:strumsight/features" lib/core/design_system/` **üres** — az `SsBeatClock` port a design systemben van definiálva, ahogy az ADR 0274 „Következmények" előírja. ✅
- `public.dart` contract: a három új fájl exportálva. ✅
- Lifecycle: a `Ticker` a `State`-ben születik és ott `dispose`-olódik; a
  reviewer-próba a `dispose` utáni óra-léptetésen sem kapott kivételt. ✅
  (A nem-élő állapotban futó ticker MINOR-3, nem szivárgás.)
- **Kockázatos-kör dimenziók (`risk = "high"`, brief §0 indoklás):** a diff
  nem érint hálózatot, tárolást, engedélyt, hitelesítést, AI-provider hívást,
  importált fájlt vagy felhasználói adatot — a `secrets` gate 3487 fájlon 0
  leletet adott. A `high` besorolás két tényleges tengelye az
  **akadálymentesség** (A1 → MINOR-1) és az **erőforrás-életciklus**
  (A4 → MINOR-3); mindkettőt valódi widget-fát mozgató próbával mértem
  (`docs/LESSONS.md` L244 mintája), nem flag-olvasással.

---

## 5. Próbatesztek — eldobhatók, merge előtt törölve

Mind a `/tmp/review-e13-r06` izolált klónban futott, a közös munkafát nem
érintette. A `zz_review_probe_test.dart` törölve
(`git status --short` → 0 dirty file), a `_onTick` rontása visszaállítva
(`git diff` üres).

| Próba | Mit mért | Eredmény |
|---|---|---|
| valódi-sértés (`_onTick` → `elapsed`) | fogja-e a §6.1 hármas a tiltott implementációt | **NEM** → MAJOR-1; a többi cella 6/10-et pirosra visz |
| PROBE A | reduced-motion off-beat vs nem-élő állapot | `IDENTICAL: true` → MINOR-1 |
| PROBE B | `Duration.zero` release-viselkedés | `IntegerDivisionByZeroException` → MINOR-2 |
| PROBE C | `pumpAndSettle` élő órával | `FlutterError` (timeout) → MINOR-3 |

---

## 6. Merge-döntés

**A MAJOR-1 nyitva → merge TILOS.** A javító kör ugyanezzel a motorral
(`sonnet-impl`) megy, a fenti leletlistával. A MINOR-1..3 ugyanabban a körben
olcsón javítható és nem hizlalja érdemben a diffet, ezért velük együtt megy
vissza; a NOTE-ok nem blokkolnak.

A javítás után: friss `/tmp` klón + gate újrafuttatás, leletenkénti zárás-
ellenőrzés, és **új exact-SHA CI-dispatch** (a jelenlegi `32654826904` /
`32654820364` futás a javítással elavul).

---

## 7. Második review-kör — javító kör 1 (`0ceb213b`), friss `/tmp` klón

### Lezárt leletek

| Lelet | Zárás | Mért bizonyíték |
|---|---|---|
| **MAJOR-1** | ✅ | A három cella most a WIDGETET hajtja: a fake óra a „valódi" pozíciótól 60/100/140 ms-mal lemaradva jelent, a renderelt pont méretéből `_phaseFromDiameter` visszaszámolja a fázist, abból a pozíciót, és AZT méri a `syncTolerance`-hoz. Ugyanaz a rontás (`_onTick` → `elapsed`), ami előtte **0/3** cellát vitt pirosra, most **2/3**-at visz (`+0 -2` a 60 ms és a 100 ms cellán). Valódi őr. |
| **MINOR-1** | ✅ | `Color.lerp(surfaceSunken, brand, .45)` az off-beat tónus; új cella méri, hogy az off-beat dekoráció ≠ a nem-élő dekoráció. |
| **MINOR-2** | ✅ | Az `assert` helyett futásidejű őr: `beatMicros <= 0` a nem-élő ággal ekvivalens. Új cella: `Duration.zero` mellett statikus 16×16 pont, `takeException()` null. |

### 🔴 MAJOR-2 (ÚJ) — a MINOR-3 javítása néma regressziót okozott

**Ezt a leletet a saját 1. köri lelet-irányom okozta**, nem az implementer:
a `_ticker.stop()`-ot kértem anélkül, hogy végiggondoltam volna, mi ébreszti
fel egy PULL-alapú portnál. Az `SsBeatClock` szerződése az, hogy a widget
**minden frame-en lekérdezi** a `position`-t; ha a ticker leáll, semmi nem
kérdezi meg többé, és a `didUpdateWidget` csak a HÍVÓ újraépítésekor fut —
amit egy per-frame pollozott óra nem garantál.

**Mérés (`/tmp/review2-e13-r06`, HEAD `0ceb213b`):**

```
PROBE_D  (az óra élővé válik, rebuild NÉLKÜL)
  dead=Size(16.0, 16.0)  afterGoingLive=Size(16.0, 16.0)   RESUMED: false
PROBE_E  (pause → resume lejátszás közben, rebuild nélkül)
  live=Size(20.3, 20.3)  afterResume=Size(16.0, 16.0)
  → a 16.0 a HALOTT statikus méret: a resume után is halott marad
```

Néma no-op: a komponens lényegi funkciója az első szünet után csendben
megszűnik, zöld gate mellett.

**A MINOR-3-at ezzel NOTE-tá minősítem vissza.** Az ADR 0274 §1 („nincs élő
idővonal → nem animál") **vizuális** előírás, amit a statikus pont ága
teljesít; a folyamatosan futó `Ticker` bevett Flutter-idióma folyamatos
animációra (a `CircularProgressIndicator` pontosan így viselkedik, és ugyanígy
fogja meg a `pumpAndSettle`-t). A helyes viselkedés fontosabb, mint a
frame-takarékosság.

---

## 8. Harmadik review-kör — javító kör 2 (`580440a4`) — ✅ APPROVED

### MAJOR-2 zárása — mérve, friss `/tmp/review3-e13-r06` klónban

A `_ticker.stop()` és a `didUpdateWidget` ébresztő eltávolítva; a ticker
folyamatosan fut és minden frame-en pollozza az órát. Ugyanaz a két próba:

```
PROBE_D dead=Size(16.0, 16.0) afterGoingLive=Size(20.3, 20.3)  RESUMED=true
PROBE_E live=Size(20.3, 20.3) paused=Size(16.0, 16.0) resumed=Size(16.5, 16.5)
        BACK_TO_LIVE=true
```

A `16.5` nem tetszőleges: a 900 ms-os pozíció fázisa 0.9, és
`16 * (1 + (1 - 0.9) * 0.3) = 16.48` — a renderelt méret tehát a helyes
fázist tükrözi, nem csak „valami mozgást". ✅

Az implementer a regressziót **gépi őrré** is tette: két új cella
(`PROBE_D` / `PROBE_E` néven) rebuild nélkül méri az újraindulást, és a §10.2
szerint a hibás (`stop()`-os) kóddal pirosra váltak. A leletnek van tehát
tesztje, ami a hibát elkapta volna.

Változatlanul zöld: az A3 „stopping the clock freezes the pulse" és a „no live
timeline renders a static, non-animating state" cella — a leállás továbbra is
fagyaszt, csak már nem zárja ki az újraindulást.

### Gate — saját kézzel, izolált klónban, a VÉGLEGES HEAD-en

```
tools/round-gate.sh test/core/design_system/motion/ss_motion_scope_test.dart \
                    test/core/design_system/motion/ss_beat_pulse_test.dart
```

Mind a hét lépés **ZÖLD**, összesen **21 cella** (7 + 14):
format · analyze (`No issues found!`) · scope-teszt 7/7 · pulse-teszt 14/14 ·
architecture (12 allowlisted) · secrets (3488 fájl, 0 finding) · l10n (en→hu,
1755 üzenet).

### Scope-audit a végleges HEAD-en

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r06 \
  --brief docs/rounds/e13-r06-motion-and-reduced-motion.md --base 467ef3ea
→ Legacy scope audit OK (467ef3ea5544..580440a42ead, 9 changed path(s), 1 generated/ignored)
```

A `1 generated/ignored` maga ez a review-jelentés — állandó, kód szintű
mentesség (`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`), nem
sértés.

### Nyitott leletek

**Nincs nyitott BLOCKER vagy MAJOR.** A megmaradt NOTE-ok (NOTE-1 export-sorrend,
NOTE-2 katalógus-demó, NOTE-3 = a visszaminősített MINOR-3) nem blokkolnak.

### Próbatesztek takarítása

Mindhárom reviewer-klón (`/tmp/review-e13-r06`, `/tmp/review2-`, `/tmp/review3-`)
izolált volt; a közös munkafát egyik sem érintette. Minden próbafájl törölve és
minden ideiglenes rontás visszaállítva — a három klónban `git status --short`
0 piszkos fájlt adott.

**Merge-döntés: ENGEDVE**, a zöld kapu (ADR 0052) többi eleme — teljes CI-suite,
randomizált property gate, exact-SHA Router CI — a PR-en igazolva.
