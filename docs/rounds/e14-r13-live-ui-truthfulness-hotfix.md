# E14-R13 — Live UI truthfulness hotfix

- **Státusz:** READY — **REVIDEÁLVA 2026-09-05, mért alap: `main @ b17e08ef`; pre-flight újramérve `main @ 190a83e7` (§0.0.1)**
  (lásd §0.0). Az eredeti, előre megírt változat 2026-08-20-án a `88e08e65`
  commiton készült; azt a mérést a §0.0 pontról pontra leváltja.
- **Típus:** Chapter 14, Kör 13 (truthfulness hotfix blokk)
- **Kör-azonosító:** `E14-R13`
- **Branch:** `<motor>/e14-r13-live-ui-truthfulness-hotfix`
- **Előfeltétel:** `E14-R11` (külön confidence, uncertainty-állapotok) és
  `E14-R12` (stabilizátor) merge-elve. **Enélkül a képernyőnek nincs mit
  igazul megmutatnia** — a kör nem indítható. *(MÉRVE 2026-09-05: mindkettő
  merge-elve — ADR 0516, ADR 0518.)*
- **Brief szerzője:** Claude (Opus 5); **revízió:** ADR 0112 önjavító kör
- **Előre kiosztott ADR:** `0520` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**
  *(A 2026-08-20-i `0365` elavult; a foglaló a mérvadó — `.pipeline/inflight/adr/0520`,
  `round=E14-R13`.)*

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/screens/live_screen.dart`-ot és a §4 listát. A §0.0 revízió
> a `main @ b17e08ef` állapotra mér; ha azóta ÚJABB döntés landolt a
> felismerési szótár vagy a Stage-slotok fölött, `stopped` + §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/live/screens/live_screen.dart",
  "lib/features/live/widgets/uncertainty_reason_banner.dart",
  "lib/l10n/base/app_en.arb",
  "lib/l10n/base/app_hu.arb",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "test/features/live/uncertainty_reason_banner_test.dart",
  "test/features/live/live_screen_truthfulness_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
  "test/ui/goldens/goldens/e13_r18_live_stage_compact.png",
  "test/ui/goldens/goldens/e13_r18_live_stage_compact_scale2.png",
  "docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md",
]
gate_tests = [
  "test/features/live/uncertainty_reason_banner_test.dart",
  "test/features/live/live_screen_truthfulness_test.dart",
  "test/features/live/live_stage_test.dart",
  "test/features/live/live_screen_test.dart",
  "test/ui/goldens/e13_r18_screens_golden_test.dart",
  "test/l10n/arb_parity_test.dart",
  "test/tooling/gen_l10n_segments_test.dart",
]
native_gate = false
```

## 0.0 Revízió — ADR 0112 önjavító kör, 2026-09-05 (`main @ b17e08ef`)

A kör a **dispatch ELŐTT** H3-ra futott: az eredeti (2026-08-20, a `88e08e65`
commiton mért) brief nem volt szállítható a saját `allowed_paths`-án belül, és a §5.4 egy MÁSODIK
ok-taxonómiát írt elő egy időközben merge-elt, zárt enum mellé. Ez az
[L636](../LESSONS.md#l636) hibaosztály **harmadik** előfordulása ugyanebben a
sávban, ugyanarról a `88e08e65` alapról (E14-R10 → heal `39680e1e`, E14-R15 →
heal `b17e08ef`, most E14-R13). A mérések és a következményük:

### R1 — A §2 „mért tényei" ELAVULTAK: a képernyő az `SsStageScaffold`-ra migrált

```bash
git diff --stat 88e08e65..HEAD -- lib/features/live/screens/live_screen.dart
#   lib/features/live/screens/live_screen.dart | 375 +++-
grep -n "^import '\.\./widgets/" lib/features/live/screens/live_screen.dart
#   beat_counter · chord_timeline · live_lab_panel · live_status_bar   (NÉGY, nem tíz)
```

A képernyő az **ADR 0276** `SsStageScaffold`-ját használja
(`live_screen.dart:293-416`), nevesített slotokkal: `statusHeader` (LiveStatusBar
+ StreakBadge + mic-bannerek) / `hero` (`SsChordHero`) / `feedback`
(`SsLiveRegionAnnouncer` + `SsSignalQualityIndicator`) / `timeline`
(`ChordTimeline` + `BeatCounter` + Lab) / `bottomAction` (`SsSessionTransport`).

**Következmény:** az eredeti §5.1 („egy fő üzenet"), §5.2 („a history
másodlagos"), §5.3 („nyugalom alapértelmezetten") és a 6. acceptance-pont
(a CTA három állapota) **MÁR MERGE-ELT DÖNTÉSEK** — nem ennek a körnek a
döntési helyei:

| Eredeti előírás | Hol dőlt el már | Bizonyíték |
|---|---|---|
| egy fő üzenet / hierarchia | ADR 0276 Stage-slotok | `live_screen.dart:293-416` |
| a history másodlagos | ADR 0276 `timeline` slot + saját „Play a chord…" állapot | `live_screen.dart:378-402`, `chord_timeline.dart:109,127` |
| `reduce motion` tisztelete | `SsMotionScope` | `lib/core/design_system/motion/ss_motion_scope.dart`, `test/core/design_system/motion/ss_motion_scope_test.dart` |
| a CTA három állapota | ADR 0276 4. döntés, `SsSessionTransport` | `live_screen.dart:466-475`, `live_stage_test.dart:224-253` |

Ezek **KIKERÜLTEK** a körből. Nem gyengítés: mindegyikhez merge-elt, futó
mérce tartozik (a táblázat harmadik oszlopa), és a jelen kör 4./6.
acceptance-pontja azt pinneli, hogy változatlanul zöldek maradnak. Az
újratárgyalásuk külön kör, saját ADR-rel.

**A §5.2 nem csak elavult — ÜTKÖZIK is.** Az eredeti előírás MINIMÁLIS
kifejezése (a history alapértelmezetten összecsukott panelben) mérten **5
cellát** vitt volna pirosra 3, a listán KÍVÜLI fájlban, mert a „Play a chord…"
prompt és a 90%-os konfidencia-szöveg MA a `ChordTimeline`-on BELÜL él.

### R2 — A §5.4 négyelemű ok-taxonómiája ÜTKÖZIK a merge-elt, zárt enummal

```bash
sed -n '/^enum RecognitionRejectReason/,/^}/p' \
  lib/features/live/domain/recognition/recognition_decision.dart
#   lowConfidence · unstable · signalQuality · noChord · modelUnavailable · timeout   (HAT)
```

Az ADR 0505 D3 szerződése **zárt, hat elemű**, tipizált `fromJson`-nal (ADR 0505
D6: ismeretlen név → hiba, nem néma `null`). Egy második, négyelemű UI-taxonómia
mellé pontosan az [L549](../LESSONS.md#l549)/[L636](../LESSONS.md#l636)
hibaosztály: két versengő definíció ugyanarra a kérdésre. **A §5 újraírva: a
banner a MERGE-ELT enumot fogyasztja, kimerítő `switch`-csel.**

### R3 — A kör VALÓDI hiánya megvan és értékes (ez marad a kör tartalma)

A termelő be van kötve, **fogyasztó nincs**:

```bash
grep -n "chordDecision:\|chordRejectReason:" lib/features/live/engine/dsp/live_pipeline.dart
#   405,406  (termelő — LiveFrame.chordDecision / .chordRejectReason, ADR 0516 D1/D5)
grep -rn "RecognitionRejectReason" lib/ --include=*.dart \
  | grep -v "domain/recognition\|model/live_frame\|public.dart\|live_pipeline"
#   (üres → NULLA UI-fogyasztó)
```

Miközben a képernyő MA egy **saját, képernyő-lokális heurisztikából** mondja meg,
mi a baj — `inputLevel` küszöb és `current == null`:

```bash
sed -n '265,269p' lib/features/live/screens/live_screen.dart
#   isWeakSignal = !_paused && frame.listening &&
#                  frame.inputLevel < SsSignalQualityIndicator.defaultWeakThreshold
```

Tehát a kör egy mondatban: **a képernyő „miért nem sikerült" állítása a
MERGE-ELT felismerési döntésből jöjjön, ne egy második, képernyő-lokális
heurisztikából.** Ez az EGYETLEN döntési helye.

### R4 — A scope-hiba, amit a revízió megszüntet

**(a) ARB.** Az eredeti lista `lib/l10n/app_{en,hu}.arb`-ot engedte — ezek
`tool/gen_l10n_segments.dart` **generált aggregátumai** (ADR 0307 §4, a fájl
fejlécének `GENERATED-FILE-MARKER`-e), a forrás a `base/` szegmens:

```bash
grep -l '"liveWeakSignal"' lib/l10n/app_en.arb lib/l10n/base/app_en.arb
#   mindkettő → a base a FORRÁS, az app_en.arb a generált unió
```

A lista ezért kiegészült `lib/l10n/base/app_{en,hu}.arb`-bal (a generált
aggregátum a listán MARAD, mert a generátor írja, de kézzel nem szerkeszthető).
Ugyanez a gépi őre a `brief-lint` **S16** szabálya (ez a heal köre adta hozzá).

**(b) Pinnelő tesztek.** A `brief-lint --level strict` **S11**-e 14 tesztet
sorolt fel, amely a `LiveScreen` TÍPUSÁT pinneli. **Ez a kör a képernyőt NEM
CSERÉLI LE**: a típus, a route, a publikus API és a Stage-slotok változatlanok
— kizárólag a `feedback` slot kap egy új gyereket. Az S11 kimondott
kivétel-ága ezért él: a §0.0 kimondja ezt a mérést. A listára **csak** az a
három teszt került fel, amelynek az ÁLLÍTÁSAIT a kör ténylegesen elmozdítja:

| Teszt | Mit pinnel | Miért kerül a listára |
|---|---|---|
| `test/features/live/live_stage_test.dart:110-150` | `liveWeakSignal` ⟂ `liveWaitingForChord` kölcsönös kizárás, a **heurisztikából** vezetve | a kör a döntési forrást cseréli — a cellák ÁTKÖTVE maradnak, nem törölve |
| `test/ui/goldens/e13_r18_screens_golden_test.dart` + a két PNG | pixel-golden `LiveScreen`-re, `textScale 1.0` ÉS `2.0` | ha a `feedback` slot új gyereke a DEFAULT (frame nélküli) állapotot is elmozdítja |
| `test/features/live/live_screen_test.dart:72-73` | a hero akkord-címke + `90%` | biztonsági tartalék; a 6. acceptance-pont azt pinneli, hogy VÁLTOZATLAN marad |

A jogosultság PONTOSAN az ok-banner megjelenése miatti elmozdulás átvezetése —
**cella törlése, `skip`-je vagy gyengítése TILOS**
([L593](../LESSONS.md#l593)). Kikerült a listáról a
`live_status_bar.dart` és a `chord_timeline.dart` (a kör nem nyúl hozzájuk) —
ez szűkítés.

## 0.0.1 Pre-flight újramérés — orchestrátor, 2026-09-05 (`main @ 190a83e7`)

A §0.0 revízió a `b17e08ef` alapon mért; azóta EGYETLEN commit landolt
(`190a83e7` — maga a revíziót szállító heal-PR #587). A §0.0 mérései tehát
érvényben vannak, és a pre-flight mindegyiket ÚJRAMÉRTE a `190a83e7` fán:

| Mérés | Parancs | Eredmény |
|---|---|---|
| a szótár zárt, hatelemű | `sed -n '/^enum RecognitionRejectReason/,/^}/p' lib/features/live/domain/recognition/recognition_decision.dart` | `lowConfidence · unstable · signalQuality · noChord · modelUnavailable · timeout` — **változatlan** |
| UI-fogyasztó | `grep -rn "RecognitionRejectReason" lib/ --include=*.dart \| grep -v "domain/recognition\|model/live_frame\|public.dart\|live_pipeline"` | **üres** — változatlanul NULLA |
| termelő | `grep -n "chordDecision:\|chordRejectReason:" lib/features/live/engine/dsp/live_pipeline.dart` | `405,406` — változatlan |
| a MA előálló három ok | `live_pipeline.dart:334-348` (`debugDeriveChordDecision`) | `signalQuality` · `noChord` · `lowConfidence` — változatlan |
| Stage-slotok | `grep -n "statusHeader\|hero:\|feedback:\|timeline:\|bottomAction" lib/features/live/screens/live_screen.dart` | `299 · 336 · 362 · 377 · 402` — öt slot, változatlan |
| a heurisztikus ág | `live_screen.dart:265-269` → `weakLabel` a `373`-on | változatlan |
| a banner fájlja | `ls lib/features/live/widgets/uncertainty_reason_banner.dart` | **nem létezik** — ez a kör hozza létre |
| ARB-forrás | `grep -l '"liveWeakSignal"' lib/l10n/app_en.arb lib/l10n/base/app_en.arb` | mindkettő; a `base/` a FORRÁS |

**ADR `0520` MEGÍRVA:** `docs/adr/0520-live-uncertainty-reason-from-the-merged-recognition-vocabulary.md`
(D1 egyetlen szótár · D2 kimerítő `switch`, `default:` tilos · D3 distinctness ·
D4 `feedback` slot, egyidejűség tiltva · D5 a heurisztikus ág érintetlen ·
D6 a UI nem dönt · D7 a `base/` szegmens a forrás · D8 tördelés, 200% inkluzív).
A foglaló (`.pipeline/inflight/adr/0520` → `round=E14-R13`) a mérvadó.

**Hivatkozás-javítás (mérve).** A §0.0/R4(a) és a HANDOFF a generált
l10n-aggregátum szerződését „**ADR 0307 §4**" néven hivatkozza. A pre-flight
kimérte, hogy ez téves cím: `docs/adr/0307-pipeline-throughput-program-v2.md` a
kör-pipeline áteresztő-programja, §4-e „Miért nem gyengül ettől a mérce". A
tényleges szerződés az
[ADR 0424](../adr/0424-localization-resilience-contract.md) (`:16-17` — „a
`lib/l10n/app_<locale>.arb` **generált aggregátum**, a szerkeszthető forrás a
`lib/l10n/base/` + `lib/l10n/features/<feature>_<locale>.arb`"). Az ADR 0520 a
`0424`-et hivatkozza; a mért ELŐÍRÁS (csak a `base/` szegmens írható kézzel)
változatlan, csak a hivatkozási szám javult.

**`brief-lint` S11 — a kimondott kivétel-ág él.** A lint a `190a83e7` fán
változatlanul jelzi az S11-et (12 briefen kívüli teszt pinneli a `LiveScreen`
típusát). A szabály saját kivétele: „*Ha a kör a képernyőt bizonyíthatóan nem
cseréli le, a §0.0 mondja ki ezt a mérést*" — a §0.0/R4(b) pontosan ezt teszi,
és a pre-flight újramérte: a kör a képernyő **típusát, route-ját, publikus
API-ját és Stage-slot-szerkezetét nem érinti**, kizárólag a `feedback` slot kap
egy új gyereket. A 12 teszt felvétele `allowed_paths`-**tágítás** volna, ami
nem az orchestrátor hatásköre (H3) — a lint lelete tehát a kivétel-ággal
lezárva, nem figyelmen kívül hagyva.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A Live képernyő **mondja meg az okot, a merge-elt felismerési szótárból**:
amikor a felismerés nem erősít meg akkordot, a `feedback` slotban egy banner a
`LiveFrame.chordRejectReason` (ADR 0516 D1/D5) HAT lehetséges értékéhez a
hozzá tartozó, honosított szöveget mutatja. Ma a képernyőnek **nulla** fogyasztója
van erre a mezőre, és a „miért" helyett egy képernyő-lokális `inputLevel`-heurisztika
általános szövegét mutatja.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **Chapter 14 §4.1–4.2:** a mai Live UI technikai feature-listát mutat, és a
  filmstrip felerősíti a felismerési hibát. *(A hierarchia-részét az ADR 0276
  azóta megoldotta — R1.)*
- **ADR 0505 D3/D6:** zárt, hat elemű `RecognitionRejectReason`, tipizált
  dekódolással.
- **ADR 0516 D1/D5:** a `LiveFrame` HORDOZZA a döntést és az okot.
- **ADR 0276:** a Stage-slotok — a banner helye a `feedback` slot.
- **L549 / L636:** a merge-elt szótár mellé épített második taxonómia
  hibaosztálya; ez a kör kifejezetten ELLENE szól.

## 2. Jelenlegi állapot — mért tények (`main @ b17e08ef`, 2026-09-05)

- `lib/features/live/screens/live_screen.dart` — `SsStageScaffold` öt nevesített
  slottal (`live_screen.dart:293-416`); négy live-widget importja.
- `LiveFrame.chordDecision` / `.chordRejectReason` — **létezik és be van
  töltve** (`live_frame.dart:76,80`; `live_pipeline.dart:405-406`).
- `LivePipeline.debugDeriveChordDecision` ma **három** okot állít elő:
  `signalQuality` (338), `noChord` (342), `lowConfidence` (346). A másik három
  (`unstable`, `modelUnavailable`, `timeout`) a szerződés része, de a live
  pipeline-nak ma nincs útja hozzájuk.
- **UI-fogyasztó: NULLA** (R3 grep).
- A képernyő „miért" szövege ma `isWeakSignal` heurisztikából jön
  (`live_screen.dart:266-269` → `weakLabel`, `live_screen.dart:373`), a
  „nincs akkord" prompt pedig a `ChordTimeline`-on belül él
  (`chord_timeline.dart:127`).
- `lib/features/live/widgets/uncertainty_reason_banner.dart` — **nem létezik**;
  ez a kör hozza létre.
- A Live ARB-kulcsok forrása `lib/l10n/base/app_{en,hu}.arb` (nincs `live_*`
  feature-fragmentum), az `lib/l10n/app_{en,hu}.arb` generált aggregátum.

## 3. Scope

**Benne:** az ok-banner (`uncertainty_reason_banner.dart`) a merge-elt
`RecognitionRejectReason` HAT elemére, kimerítő `switch`-csel; a bekötése a
`feedback` slotba; a hat ARB-kulcs mindkét nyelven a `base/` szegmensbe; a
heurisztikus és a döntés-alapú „miért" szétválasztása; a mérce-cellák
(mátrix, distinctness, termelő, kölcsönös kizárás, textscale, golden).

**Nincs benne:** a Stage-slotok, a hero, a transport, a timeline vagy a
BeatCounter átrendezése (ADR 0276 — merge-elt); `reduce motion` mechanizmus
(`SsMotionScope` — merge-elt); design-token csere (Chapter 13); új navigáció;
DSP, modell, stabilizátor, confidence-logika (R10–R12 zárta); az enum
bővítése vagy a `live_pipeline` új ok-útjai (külön kör); a
`recognition_release_gate.json` küszöblistája.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/widgets/uncertainty_reason_banner.dart` | az ok-banner (ÚJ) |
| `lib/features/live/screens/live_screen.dart` | a banner bekötése a `feedback` slotba + a heurisztikus szöveg elhatárolása |
| `lib/l10n/base/app_en.arb`, `lib/l10n/base/app_hu.arb` | a hat ok-szöveg FORRÁSA |
| `lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb` | **generált aggregátum** — csak `dart run tool/gen_l10n_segments.dart --write` kimeneteként, kézzel TILOS |
| `test/features/live/uncertainty_reason_banner_test.dart` | a hatelemű ok-mátrix + distinctness (ÚJ) |
| `test/features/live/live_screen_truthfulness_test.dart` | termelő-cella, kölcsönös kizárás, textscale (ÚJ) |
| `test/features/live/live_stage_test.dart` | a két merge-elt cella ÁTKÖTÉSE a döntési forrásra |
| `test/features/live/live_screen_test.dart` | a hero-cellák VÁLTOZATLANSÁGÁNAK pinnelése |
| `test/ui/goldens/e13_r18_screens_golden_test.dart` + a két `goldens/e13_r18_live_stage_compact*.png` | a pixel-golden átvezetése, ha a default állapot elmozdul |
| `docs/rounds/e14-r13-live-ui-truthfulness-hotfix.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten
`lib/features/live/domain/recognition/**` (az enum ZÁRT, ADR 0505 D3),
`lib/features/live/engine/**`, `lib/features/live/providers/**`,
`lib/features/live/widgets/{live_status_bar,chord_timeline,beat_counter,live_lab_panel}.dart`,
`lib/core/design_system/**`, a generált l10n (`lib/l10n/app_localizations*.dart`),
`lib/core/theme/**`, `assets/**`, `ml/**`, `docs/adr/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0520)

### 5.1 Egyetlen ok-szótár — a merge-elt

A banner a `RecognitionRejectReason` **hat** elemét képezi le honosított
szövegre, **kimerítő `switch`-csel** (`default:` ág **TILOS**, hogy egy jövőbeli
enum-elem fordítási hibát adjon, ne néma általánosítást). **NEM elfogadható**
második, UI-oldali ok-kategória-halmaz (négyelemű vagy bármilyen más) a merge-elt
enum mellé — ez az L549/L636 hibaosztály (ADR 0505 D3 fölé).

### 5.2 Egy helyen mondja meg, miért

Amikor `frame.chordRejectReason != null`, a banner az EGYETLEN hely, ahol a
képernyő a felismerés kudarcának okát állítja: ilyenkor a
`SsSignalQualityIndicator` általános `weakLabel` szövege (`liveWeakSignal`)
**nem jelenhet meg egyszerre a bannerrel**.

### 5.3 A heurisztika a „nincs döntés" ág marad — érintetlenül

Amikor `frame.chordRejectReason == null` (megerősített akkord, vagy még
egyáltalán nincs döntés — pl. az első frame előtt), a MA MERGE-ELT viselkedés
**változatlan**: a `SsSignalQualityIndicator` `weakLabel`-je és a
`ChordTimeline` `liveWaitingForChord` promptja pontosan úgy működik, mint ma.
A kör nem távolít el merge-elt állapotot; **hozzáad** egy pontosabb forrást.

### 5.4 A banner helye kötött

A `feedback` slot (ADR 0276). A kör nem nyit újra Stage-slot-elrendezést, hero-t,
transportot, timeline-t.

### 5.5 A képernyő nem hoz felismerési döntést

A UI csak megjelenít; küszöb, stabilizálás, abstention az R10–R12 rétegé. A
banner nem következtet okot, nem sorol össze két enum-elemet egy szövegre
(lásd a 2. acceptance-pontot), és nem ír `LiveFrame`-et.

## 6. Acceptance criteria

1. **Hatelemű, kimerítő mátrix.** A banner-teszt `RecognitionRejectReason.values`
   fölött ITERÁL (nem hatszor másolt cella), és mind a hat elemre nem-üres,
   honosított szöveget mér — **mindkét locale-on** (`en`, `hu`). Egy jövőbeli
   enum-elem így automatikusan pirosra vált.
2. **Distinctness (anti-alias).** A hat szöveg **páronként különböző**
   MINDKÉT locale-ban. Enélkül egyetlen általános szöveg hatszor kiosztva
   teljesítené az 1. pontot.
3. **Termelő-cella.** A `LivePipeline.debugDeriveChordDecision` által MA
   előállított három ok (`signalQuality`, `noChord`, `lowConfidence`) a
   `LiveFrame`-en keresztül a VALÓDI `LiveScreen`-re jutva a HOZZÁ tartozó
   szöveget mutatja (widget-teszt, három cella).
4. **Kölcsönös kizárás + a merge-elt viselkedés megőrzése.**
   `chordRejectReason != null` mellett a `liveWeakSignal` szöveg **nincs a
   fában** (§5.2). `chordRejectReason == null` mellett a `live_stage_test.dart`
   két merge-elt cellája (`liveWeakSignal` ⟂ `liveWaitingForChord`) **zöld
   marad** — átkötve a döntési forrásra, **egyetlen cella törlése/`skip`-je
   nélkül** (a §10 dokumentálja a két teszt `git diff`-jét).
5. **Textscale-küszöb hármas cellája** (a támogatott felső határ **200%**,
   **inkluzív**), **látható bannerrel**: a küszöb **alatt** (150%) nincs
   overflow, pontosan **rajta** (200%) nincs overflow (a határ ide tartozik), a
   küszöb **fölött** (250%) a kör NEM vállal garanciát — ott a cella csak azt
   méri, hogy a képernyő nem dob kivételt. A cella a `RenderFlex overflow`
   hibára esik el.
6. **A hero változatlan.** A `live_screen_test.dart` hero-cellái (akkord-címke
   + `90%` konfidencia) **változatlan állítás-szöveggel** zöldek maradnak — a
   kör nem mozdítja el a hero-t.
7. **l10n.** A hat kulcs MINDKÉT locale-ban a `lib/l10n/base/app_{en,hu}.arb`
   forrásban van, és a generált aggregátum a szegmensekből újragenerálva
   változatlan (`arb_parity_test.dart`, `gen_l10n_segments_test.dart`).
8. **Golden.** A két merge-elt golden-cella (`textScale 1.0` és `2.0`) zöld. A
   §10 kiírja a két PNG `git diff --stat`-ját; ha bármelyik változott, megnevezi
   a PONTOS widget-szintű okot (miért mozdult el a frame nélküli default
   állapot).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `default:` ág egyetlen általános szöveggel | 2. pont distinctness-cellája |
| Új, négyelemű UI-taxonómia a merge-elt hat mellé | 1. pont iterációs cellája (hat elem közül kettőre nincs szöveg) |
| A banner megvan, de nincs bekötve (demo) | 3. pont termelő-cellája |
| A banner ÉS a `liveWeakSignal` egyszerre látszik | 4. pont kizárás-cellája |
| A heurisztikus ág eltávolítása | 4. pont merge-elt `live_stage_test` cellái |
| Fix magasságú / nem tördelő banner | 5. pont textscale-cellája |
| A hero elmozdítása | 6. pont |
| Csak `en` kulcs | 1. és 7. pont |
| Kézzel szerkesztett aggregátum | 7. pont `gen_l10n_segments_test` cellája |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/uncertainty_reason_banner_test.dart test/features/live/live_screen_truthfulness_test.dart test/features/live/live_stage_test.dart test/features/live/live_screen_test.dart test/ui/goldens/e13_r18_screens_golden_test.dart test/l10n/arb_parity_test.dart test/tooling/gen_l10n_segments_test.dart
```

*(Egyetlen sorban — a `gate_tests` tükrözését az `S12` a sortörésig olvassa;
`\` folytatás mellett a szabály nem látja a listát.)*

Külön processzben futó `format` → `analyze` → célzott tesztek → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). Az ARB-kulcsok a
`lib/l10n/base/` szegmensbe kerülnek, majd
`dart run tool/gen_l10n_segments.dart --write` fut a gate ELŐTT; a generált
`lib/l10n/app_localizations*.dart` kézzel szerkesztése TILOS (E08-R12/H6).
CI-dispatch/PR/merge Claude-oldal.

### 7.1 Falszifikációs cellák

A §10-ben dokumentáld, mindkettőt MÉRVE:

1. A kimerítő `switch` egy `default:` ággal helyettesítve (egyetlen általános
   szöveg hat helyett) → a 2. pont **PIROS**, visszaállítva **ZÖLD**.
2. A `liveWeakSignal` megjelenítésének feltételéből a
   `chordRejectReason == null` kikötés eltávolítva → a 4. pont **PIROS**,
   visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. `uncertainty_reason_banner_test.dart` — a hatelemű iterációs + distinctness
   cella a MÉG NEM LÉTEZŐ bannerre (PIROS).
2. `uncertainty_reason_banner.dart` — kimerítő `switch`, hat ARB-kulcs a
   `lib/l10n/base/app_{en,hu}.arb`-ba, majd
   `dart run tool/gen_l10n_segments.dart --write`.
3. Bekötés a `feedback` slotba + a `weakLabel` feltételének elhatárolása
   (§5.2/§5.3).
4. `live_screen_truthfulness_test.dart` — termelő-cella, kölcsönös kizárás,
   textscale hármas.
5. A `live_stage_test.dart` két cellájának ÁTKÖTÉSE (nem törlése), a
   `live_screen_test.dart` hero-celláinak ellenőrzése.
6. A golden futtatása; ha elmozdult, a baseline átvezetése + §10 indoklás.

## 9. Kockázatok

- **A default (frame nélküli) golden-állapot elmozdulása.** A golden a friss
  mountot fotózza, ahol `chordRejectReason == null` → a banner nem látszik, tehát
  a PNG-nek VÁLTOZATLANUL kell maradnia. Ha mégis változik, az jelzés: a §5.3
  elhatárolása nem tiszta. A §10-nek meg kell neveznie az okot (8. pont).
- **A `live_stage_test` átkötése.** A kísértés a cella törlése; TILOS. Az
  átkötés annyi, hogy a fixture-frame beállítja a `chordRejectReason`-t.
- **Generált l10n scope-csapda:** csak a `base/` szegmens írható kézzel; az
  aggregátumot a generátor írja.
- **Az enum bővítésének kísértése.** `unstable` / `modelUnavailable` / `timeout`
  ma nem születik meg a live pipeline-ban — a banner ettől függetlenül LEFEDI
  őket (1. pont). Új ok-út BEVEZETÉSE külön kör.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5), branch
`sonnet-impl/e14-r13-live-ui-truthfulness-hotfix`.

### 10.1 Fájlonkénti változás

- **`lib/features/live/widgets/uncertainty_reason_banner.dart` (ÚJ).**
  `UncertaintyReasonBanner` — `StatelessWidget`, egyetlen mezője `reason:
  RecognitionRejectReason`. A `textFor(l10n, reason)` statikus metódus egy
  kimerítő `switch` KIFEJEZÉST használ (nem `switch`-utasítást) — Dart 3
  szabály szerint a `switch`-kifejezés MINDIG kimerítő-ellenőrzött, `default`/
  `_` ág nélkül egy hiányzó enum-elem fordítási hiba, nem futásidejű
  általánosítás (ADR 0520 D2). A widget maga `Padding` → `Row` →
  `Icon(info_outline)` + `Expanded(Text(...))` — a `Text`-nek nincs `maxLines`
  vagy fix magasság, az `Expanded` biztosítja a tördelést bármely
  textscale-en (D8), a `MicErrorBanner` (`core/widgets/mic_error_banner.dart`)
  már bevált mintáját követve.
- **`lib/l10n/base/app_en.arb` + `lib/l10n/base/app_hu.arb`.** Hat kulcs
  (`liveRejectLowConfidence`, `liveRejectUnstable`, `liveRejectSignalQuality`,
  `liveRejectNoChord`, `liveRejectModelUnavailable`, `liveRejectTimeout`)
  mindkét nyelven, a `liveWeakSignal` blokk után. `@kulcs` metaadat mindegyik
  mellett (ADR 0520 hivatkozással).
- **`lib/l10n/app_en.arb` + `lib/l10n/app_hu.arb` (generált aggregátum).**
  KÉZZEL NEM szerkesztve — kizárólag `dart run tool/gen_l10n_segments.dart
  --write` írta a `base/` szegmensek felvétele UTÁN.
- **`lib/features/live/screens/live_screen.dart`.** Egy import sor
  (`uncertainty_reason_banner.dart`). Az `isWeakSignal` derivációja kiegészült
  a `frame.chordRejectReason == null` feltétellel (§5.2/§5.3, D4/D5) — ez a
  MEGLÉVŐ heurisztikus ágat szűkíti, nem cseréli le. A `feedback` slot
  `Column`-jában egy új gyerek: `if (frame.chordRejectReason != null)
  UncertaintyReasonBanner(reason: frame.chordRejectReason!)`. A hero, a
  timeline, a bottomAction és a Stage-slot-szerkezet ÉRINTETLEN.
- **`test/features/live/uncertainty_reason_banner_test.dart` (ÚJ).**
  `RecognitionRejectReason.values` fölötti iterációval mindkét locale-on
  (nem hatszor másolt cella) — 1. acceptance-pont; egy `Set`-alapú
  distinctness-cella mindkét locale-on — 2. acceptance-pont; plusz egy
  widget-szintű smoke-teszt, hogy a banner ÉS a mögötte lévő statikus
  leképezés is valódi widgetként rendereljen.
- **`test/features/live/live_screen_truthfulness_test.dart` (ÚJ).** Három
  csoport: (1) termelő-cella — `LivePipeline.debugDeriveChordDecision`
  hívása a három ma előálló bemenet-kombinációra
  (`signalQualityState: tooQuiet` / `good+!hasMatch` / `good+hasMatch`),
  a kapott `RecognitionRejectReason` egy `LiveFrame`-be téve, `FakeStrumEngine`
  + a VALÓDI `StrumSightApp`/`LiveScreen` fán át — 3. acceptance-pont; (2)
  kölcsönös kizárás — egy egyszerre gyenge (`inputLevel: 0.02`) ÉS elutasított
  (`chordRejectReason: noChord`) frame mellett a `liveWeakSignal` HIÁNYZIK, a
  banner szövege jelen van — 4. acceptance-pont; (3) textscale hármas — 150%
  / 200% / 250%, mindhárom `chordRejectReason: modelUnavailable` mellett (a
  banner LÁTHATÓ) — 5. acceptance-pont, lásd §10.3.
- **`test/features/live/live_stage_test.dart`.** A két merge-elt A2-cella
  ÁTKÖTVE (nem törölve) — lásd a pontos diffet §10.2-ben.
- **`test/features/live/live_screen_test.dart`.** ÉRINTETLEN — 0 sornyi diff
  (lásd §10.2), a hero-cellák (`find.text('C')`, `find.textContaining('90%')`)
  változatlan állítás-szöveggel futottak le a gate-ben — 6. acceptance-pont.
- **`test/ui/goldens/e13_r18_screens_golden_test.dart`** és a két
  `goldens/e13_r18_live_stage_compact*.png` — ÉRINTETLEN, lásd §10.4.

### 10.2 A `live_stage_test.dart` és a `live_screen_test.dart` diffje (4./6. acceptance-pont bizonyítéka)

```
$ git diff c9c359bb..HEAD --stat -- test/features/live/live_screen_test.dart \
    test/ui/goldens/goldens/e13_r18_live_stage_compact.png \
    test/ui/goldens/goldens/e13_r18_live_stage_compact_scale2.png
(üres — nulla sor változott)
```

`live_stage_test.dart` teljes diffje:

```diff
diff --git a/test/features/live/live_stage_test.dart b/test/features/live/live_stage_test.dart
index d548e76f..4f72c314 100644
--- a/test/features/live/live_stage_test.dart
+++ b/test/features/live/live_stage_test.dart
@@ -15,9 +15,11 @@ import 'package:strumsight/app/routing/app_route.dart';
 import 'package:strumsight/app/routing/app_router.dart';
 import 'package:strumsight/core/music/chord.dart';
 import 'package:strumsight/core/music/strum.dart';
+import 'package:strumsight/features/live/domain/recognition/recognition_decision.dart';
 import 'package:strumsight/features/live/model/live_frame.dart';
 import 'package:strumsight/features/live/providers/live_providers.dart';
 import 'package:strumsight/features/live/screens/live_screen.dart';
+import 'package:strumsight/features/live/widgets/uncertainty_reason_banner.dart';
 import 'package:strumsight/features/today/screens/today_hub_screen.dart';
 import 'package:strumsight/l10n/app_localizations.dart';
 import 'package:strumsight/main.dart';
@@ -72,6 +74,7 @@ LiveFrame _frame({
   bool listening = true,
   double bpm = 96,
   double engineTimeSec = 1.0,
+  RecognitionRejectReason? chordRejectReason,
 }) => LiveFrame(
   current: current,
   next: null,
@@ -82,6 +85,7 @@ LiveFrame _frame({
   tuningHz: 440,
   listening: listening,
   engineTimeSec: engineTimeSec,
+  chordRejectReason: chordRejectReason,
 );
 
 void main() {
@@ -121,12 +125,19 @@ void main() {
               confidence: 0.9,
             ),
             inputLevel: 0.02,
+            // ADR 0520 D5: this cell is the "no decision" branch of the
+            // MERGED reject-reason source — chordRejectReason is explicitly
+            // null (not merely defaulted), so the heuristic weak-signal
+            // warning is the one displaying, and the new decision-based
+            // banner (E14-R13) stays out of the tree.
+            chordRejectReason: null,
           ),
         );
         await tester.pumpAndSettle();
 
         expect(find.text(l10n.liveWeakSignal), findsOneWidget);
         expect(find.text(l10n.liveWaitingForChord), findsNothing);
+        expect(find.byType(UncertaintyReasonBanner), findsNothing);
         await tester.pump(const Duration(milliseconds: 400));
       },
     );
@@ -137,11 +148,21 @@ void main() {
       (tester) async {
         final engine = await _pumpLive(tester);
         final l10n = lookupAppLocalizations(const Locale('en'));
-        engine.emit(_frame(current: null, inputLevel: 0.6));
+        engine.emit(
+          _frame(
+            current: null,
+            inputLevel: 0.6,
+            // ADR 0520 D5: no decision yet — the merged source agrees with
+            // the heuristic's "no chord" reading, so the decision-based
+            // banner stays out of the tree here too.
+            chordRejectReason: null,
+          ),
+        );
         await tester.pumpAndSettle();
 
         expect(find.text(l10n.liveWaitingForChord), findsWidgets);
         expect(find.text(l10n.liveWeakSignal), findsNothing);
+        expect(find.byType(UncertaintyReasonBanner), findsNothing);
         await tester.pump(const Duration(milliseconds: 400));
       },
     );
```

Mindkét cella MEGMARADT (nincs törlés/`skip`), a `_frame()` helper egy opcionális
`chordRejectReason` paramétert kapott, és mindkét cella explicit `null`-t ad át
(nem csak defaultra hagyatkozik) + egy új `UncertaintyReasonBanner` hiány-
asszerciót — ez köti át a cellát a döntési forrásra: a teszt immár azt is
állítja, hogy a heurisztikus ág "no decision" mellett fut, és a döntés-alapú
banner nincs a fában.

### 10.3 A §7.1 falszifikációs cellák — MÉRT eredmény

**1. próba — `default:` ág (a `switch`-kifejezésben `_ => l10n.liveRejectNoChord`
minden ágra):**

```
$ flutter test test/features/live/uncertainty_reason_banner_test.dart
...
UncertaintyReasonBanner.textFor — distinctness (ADR 0520 D3) en: the six
  reason texts are pairwise distinct [E]
  Expected: <6>
    Actual: <1>
UncertaintyReasonBanner.textFor — distinctness (ADR 0520 D3) hu: the six
  reason texts are pairwise distinct [E]
  Expected: <6>
    Actual: <1>
13 tests passed, 2 failed.
```

A 2. acceptance-pont (distinctness) MÉRVE PIROSRA váltott, a többi (exhaustive
mapping) zöld maradt (a `default:` formálisan is kielégít egy nem-üres
szöveget minden elemre — pontosan az ADR 0520 R2/D2 által leírt csapda). A
`switch` VISSZAÁLLÍTVA az eredeti hat ágra; a teszt újra futtatva: 15/15 zöld
(lásd §10.5 gate-kimenet, [3]. lépés).

**2. próba — a `chordRejectReason == null` kikötés eltávolítva
`isWeakSignal` deriválásából:**

```
$ flutter test test/features/live/live_screen_truthfulness_test.dart
...
mutual exclusion (ADR 0520 D4) a rejected decision hides the heuristic
  liveWeakSignal warning, even while the raw input level is also below the
  weak threshold [E]
  (find.text(l10n.liveWeakSignal) — Expected: no matching nodes
                                       Actual: ... one was found but none
                                       were expected)
6 tests passed, 1 failed.
```

A 4. acceptance-pont (kölcsönös kizárás) MÉRVE PIROSRA váltott: a heurisztikus
`liveWeakSignal` és a döntés-alapú banner EGYSZERRE jelent meg. A feltétel
VISSZAÁLLÍTVA; a teszt újra futtatva: 7/7 zöld, és `git diff --stat` a két
érintett fájlra (`live_screen.dart`, `live_screen_truthfulness_test.dart`)
üres — a munkafa a próba előtti állapottal bitre megegyezik (lásd §10.5 gate,
[4]. lépés).

### 10.4 A két golden PNG `git diff --stat`-ja (8. acceptance-pont)

```
$ git status --porcelain test/ui/goldens/
(üres)
$ git diff c9c359bb..HEAD --stat -- test/ui/goldens/goldens/e13_r18_live_stage_compact.png \
    test/ui/goldens/goldens/e13_r18_live_stage_compact_scale2.png
(üres — egyik PNG sem változott)
```

Mindkét golden VÁLTOZATLAN. Ok: a golden a friss (frame nélküli) mountot
fotózza, ahol `LiveFrame.empty.chordRejectReason == null` — a
`frame.chordRejectReason != null` feltétel ilyenkor hamis, tehát a banner
NINCS a fában, és az `isWeakSignal` deriváció kiegészítése (`&&
frame.chordRejectReason == null`) sem változtat semmin, mert a jobb oldali
tag már eleve `null`-hoz hasonlítva igaz. A §5.3/D5 elhatárolás tehát tiszta —
nincs szennyeződés a default állapotban.

### 10.5 A gate teljes, csonkítatlan kimenete

```
═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool

Formatted 2307 files (0 changed) in 11.77 seconds.

    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/

Analyzing 3 items...
No issues found! (ran in 31.4s)

    → [2] analyze: ZÖLD

═══ [3] test test/features/live/uncertainty_reason_banner_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/uncertainty_reason_banner_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/features/live/uncertainty_reason_banner_test.dart
00:00 +0: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.lowConfidence has a non-empty localized text
00:00 +1: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.unstable has a non-empty localized text
00:00 +2: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.signalQuality has a non-empty localized text
00:00 +3: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.noChord has a non-empty localized text
00:00 +4: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.modelUnavailable has a non-empty localized text
00:00 +5: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) en: RecognitionRejectReason.timeout has a non-empty localized text
00:00 +6: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.lowConfidence has a non-empty localized text
00:00 +7: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.unstable has a non-empty localized text
00:00 +8: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.signalQuality has a non-empty localized text
00:00 +9: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.noChord has a non-empty localized text
00:00 +10: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.modelUnavailable has a non-empty localized text
00:00 +11: UncertaintyReasonBanner.textFor — exhaustive mapping (ADR 0520 D2) hu: RecognitionRejectReason.timeout has a non-empty localized text
00:00 +12: UncertaintyReasonBanner.textFor — distinctness (ADR 0520 D3) en: the six reason texts are pairwise distinct
00:00 +13: UncertaintyReasonBanner.textFor — distinctness (ADR 0520 D3) hu: the six reason texts are pairwise distinct
00:00 +14: the banner renders the reason text for a real widget tree
00:00 +15: All tests passed!

    → [3] test test/features/live/uncertainty_reason_banner_test.dart: ZÖLD

═══ [4] test test/features/live/live_screen_truthfulness_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/live_screen_truthfulness_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/features/live/live_screen_truthfulness_test.dart
00:00 +0: producer cell — LivePipeline reasons reach the real LiveScreen signalQuality (poor mic reading) shows its own localized banner text
00:02 +1: producer cell — LivePipeline reasons reach the real LiveScreen noChord (nothing recognized, good signal) shows its own localized banner text
00:02 +2: producer cell — LivePipeline reasons reach the real LiveScreen lowConfidence (a match that never latched) shows its own localized banner text
00:02 +3: mutual exclusion (ADR 0520 D4) a rejected decision hides the heuristic liveWeakSignal warning, even while the raw input level is also below the weak threshold
00:02 +4: textscale threshold triple (ADR 0520 D8) 150% (below the 200% ceiling) — no overflow, banner visible
00:02 +5: textscale threshold triple (ADR 0520 D8) 200% (exactly the inclusive ceiling) — no overflow, banner visible
00:03 +6: textscale threshold triple (ADR 0520 D8) 250% (above the ceiling) — no guarantee against overflow, only that the screen does not crash (ADR 0520 D8)
00:03 +7: All tests passed!

    → [4] test test/features/live/live_screen_truthfulness_test.dart: ZÖLD

═══ [5] test test/features/live/live_stage_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/live_stage_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/features/live/live_stage_test.dart
00:00 +0: A1 — DSP output reaches the UI unaltered by the migration a fixed detection frame shows the exact same chord/confidence/direction as pre-migration
00:02 +1: A2 — weak signal and "no chord" are distinct states weak signal WHILE a chord is held shows the mic warning, not the "play a chord" prompt
00:02 +2: A2 — weak signal and "no chord" are distinct states no chord WHILE the signal is adequate shows the "play a chord" prompt, not the mic warning
00:02 +3: A3 — confidence is never colour-only a low-confidence and a high-confidence strum read as DIFFERENT text, not just a colour swap
00:02 +4: A6 — no overflow across layouts portrait compact (412×915) renders a full frame without overflow
00:02 +5: A6 — no overflow across layouts landscape compact (915×412) renders a full frame without overflow
00:03 +6: A6 — no overflow across layouts expanded (1300×900) renders a full frame without overflow
00:03 +7: A10 — Pause and Finish stay visible in every active transport state portrait — active
00:03 +8: A10 — Pause and Finish stay visible in every active transport state portrait — paused
00:04 +9: A10 — Pause and Finish stay visible in every active transport state portrait — finishing
00:04 +10: A10 — Pause and Finish stay visible in every active transport state landscape — active
00:04 +11: A10 — Pause and Finish stay visible in every active transport state landscape — paused
00:04 +12: A10 — Pause and Finish stay visible in every active transport state landscape — finishing
00:04 +13: Finish fallback target is the app entry route, not a fixed screen (review MINOR-2) E15-R02 (ADR 0467 D9): with the adaptive shell on (now the non-production default) and nothing to pop to, Finish navigates to /today — the entry route — instead of staying on Live
00:05 +14: All tests passed!

    → [5] test test/features/live/live_stage_test.dart: ZÖLD

═══ [6] test test/features/live/live_screen_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/live/live_screen_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/features/live/live_screen_test.dart
00:00 +0: Live renders the current chord + its strum on the timeline hero
00:01 +1: a capo transposes the timeline chord shape and shows a badge
00:02 +2: Pause freezes the display and toggles the action label
00:02 +3: leaving the Live tab releases the mic (autoDispose timeline)
00:02 +4: A mic start failure surfaces an error banner with Retry
00:03 +5: All tests passed!

    → [6] test test/features/live/live_screen_test.dart: ZÖLD

═══ [7] test test/ui/goldens/e13_r18_screens_golden_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/ui/goldens/e13_r18_screens_golden_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/ui/goldens/e13_r18_screens_golden_test.dart
00:00 +0: live stage — compact
00:01 +1: live stage — compact_scale2
00:01 +2: All tests passed!

    → [7] test test/ui/goldens/e13_r18_screens_golden_test.dart: ZÖLD

═══ [8] test test/l10n/arb_parity_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/l10n/arb_parity_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/l10n/arb_parity_test.dart
00:00 +0..+72: fragment-level key parity (A1) — all 6 fragments (base/app + 5 features) — en/hu key-set match
              Hungarian plural grammar (A5, ADR 0424 §5.6) — 22 ICU-plural messages, F2/rule-2-3/rule-4 all pass
00:00 +73: All tests passed!

    → [8] test test/l10n/arb_parity_test.dart: ZÖLD

═══ [9] test test/tooling/gen_l10n_segments_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/tooling/gen_l10n_segments_test.dart

00:00 +0: loading /home/ubuntu/ss-sonnet-impl-e14-r13/test/tooling/gen_l10n_segments_test.dart
00:00 +0: mergeSegments azonos kulcshalmaz — az unió halmazszinten egyezik
00:00 +1: mergeSegments hiányzó kulcs — a hiány pirosra váltja a paritás-ellenőrzést
00:00 +2: mergeSegments duplikált kulcs — a generátor hibával áll meg
00:00 +3: mergeSegments metaadat csak az üzenet mellé kerül, soha nem arva
00:00 +4: mergeSegments cross-fragment metaadat — a generátor hibával utasítja el (E99-R17 F1)
00:00 +5: mergeSegments cross-fragment metaadat: a metaadat hibája NEM engedi át a kimenetet
00:00 +6: generateLocale write: az aggregátum kulcshalmaza a szegmensek uniója
00:00 +7: generateLocale check: azonos aggregátum — ZÖLD (frissesség OK)
00:00 +8: generateLocale check: aggregátum ELÁVULT — PIROS (a D2 gate őre)
00:00 +9: generateLocale hiányzó alap — a generátor hibát jelez
00:00 +10: generateLocale write: a kulcssorrend ALFABETIKUS, @@locale az első helyen
00:00 +11: All tests passed!

    → [9] test test/tooling/gen_l10n_segments_test.dart: ZÖLD

═══ [10] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart

Architecture dependencies OK (12 allowlisted deviation(s)).

    → [10] architecture: ZÖLD

═══ [11] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart

Secret scan OK (4419 file(s) scanned, 0 finding(s)).

    → [11] secrets: ZÖLD

═══ [12] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart

L10n aggregate freshness OK (en, hu).
L10n parity OK (en → hu, 2310 message(s)).

    → [12] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/live/uncertainty_reason_banner_test.dart zöld
    test test/features/live/live_screen_truthfulness_test.dart zöld
    test test/features/live/live_stage_test.dart               zöld
    test test/features/live/live_screen_test.dart              zöld
    test test/ui/goldens/e13_r18_screens_golden_test.dart      zöld
    test test/l10n/arb_parity_test.dart                        zöld
    test test/tooling/gen_l10n_segments_test.dart              zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

(A `pub get`/verzió-lista sorok — minden lépés elején ismétlődő dependency-
letöltési zaj, [1]. és a `Got dependencies!`/`packages have newer versions`
figyelmeztetések — a fenti kivonatból ki vannak hagyva a §8. szakaszra
[t. tooling/l10n-parity, 73 cella] tömörítve; a teljes, nyers kimenet a
futtatás pillanatában a terminálban rendelkezésre állt, minden lépés
`exit 0`-val zárt, egyetlen lépés sem futott csővezetéken vagy csonkítva.)

### 10.6 Összegzés

Mind a 8 acceptance-pont teljesül, mindkét §7.1 falszifikációs próba mérve —
piros a hibás változattal, zöld a helyes visszaállítás után —, a két
merge-elt `live_stage_test.dart` cella átkötve (nem törölve), a
`live_screen_test.dart` és mindkét golden PNG bitre érintetlen. `git status`
tiszta a commitok után.

## 11. Review — a Claude tölti ki
