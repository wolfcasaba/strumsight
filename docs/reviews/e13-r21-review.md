# E13-R21 — Review (Practice setup és aktív session UI)

- **Kör:** `E13-R21` — `docs/rounds/e13-r21-practice-session-ui.md`
- **Branch:** `sonnet-impl/e13-r21-practice-session-ui`
- **Review-elt HEAD:** `ac33a8f593ab24d5f82d6f3f20adb5dc4ed60c86`
- **Induló HEAD (pre-flight):** `24b95acf83e702de9de5e2f777e840259d192af4`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude Opus 5 (orchestrátor-ülés), read-only, izolált
  `/tmp/review-e13-r21` klón
- **Dátum:** 2026-08-26

## 1. Verdikt

**VÉGSŐ: APPROVED** (a §8 javító kör után, `6167d5be` — 0 nyitott lelet).
Az első forduló verdiktje **CHANGES REQUESTED** volt — 2 MAJOR, 1 MINOR,
1 NOTE.

Mindkét MAJOR **teljesen ZÖLD kapu mögött** él: a kör 18/18 gate-lépése, a 173
presentation-teszt és a hat golden mind zöld, és a leletek egyikét sem fogja
egyetlen meglévő cella sem. Ez a sáv ismétlődő hibaosztálya (E13-R20/MAJOR-1
ugyanez volt) — a zöld gate itt sem bizonyíték.

## 2. Amit magam mértem (nem bemondás)

### 2.1 Gate-újrafuttatás — izolált klón

```
git clone --branch sonnet-impl/e13-r21-practice-session-ui \
  /home/ubuntu/ss-sonnet-impl-e13-r21 /tmp/review-e13-r21
tools/round-gate.sh <a brief §7 szerinti 13 útvonal>
```

**18/18 ZÖLD**, `GATE_EXIT=0` — a lépések: format, analyze, 13 teszt-útvonal,
architecture, secrets, l10n. A handoff §10.3 állítása **reprodukálva**.

### 2.2 Scope-audit (ADR 0138 §1)

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e13-r21 \
  --brief docs/rounds/e13-r21-practice-session-ui.md --base 24b95acf83e7
→ Legacy scope audit OK (24b95acf83e7..ac33a8f593ab, 22 changed path(s),
  0 generated/ignored)
```

**0 sértés.** (Az implementer-futás első jelzésében szereplő `VIOLATION` az
orchestrátor SAJÁT, a munkapéldányba tett prompt-fájlja volt — kivéve, a
diffbe nem került.)

### 2.3 Exact-SHA CI a merge SHA-n

| Workflow | Run | Head SHA | Eredmény |
|---|---|---|---|
| `router-ci.yml` | [32936422146](https://github.com/wolfcasaba/strumsight/actions/runs/32936422146) | `ac33a8f5` | **success** |
| `full-gate.yml` | [32936426618](https://github.com/wolfcasaba/strumsight/actions/runs/32936426618) | `ac33a8f5` | **success** |

Mindkét kapu zöld a `ac33a8f5` SHA-n — **de a merge így sem mehet**: a §3 két
MAJOR lelete nyitva van, és a javítás új HEAD-et képez, amire az exact-SHA
mérést (ADR 0086 §2) meg kell ismételni.

A CI-tervező (`tools/round-ci-plan.py`) `full-gate.yml`-t írt elő
(`apk_required=false`, natív/release-útvonal nincs a diffben),
`router_ci_expected=true` a `docs/rounds/**` érintése miatt.

### 2.4 Biztonsági review szükségessége — MÉRVE, nem feltételezve

A brief `risk = "high"`, de a **tényleges diff** a `.ai/router.toml`
`high_risk_path_fragments` listájából (`auth`, `camera`, `credential`,
`crypto`, `encryption`, `migration`, `payment`, `privacy`, `secret`, `share`,
`upload`, `vision`) **egyetlen töredéket sem érint**: a 22 útvonal kizárólag
presentation-widget, ARB, teszt és golden PNG. A brief kockázat-indoklása („a
gyakorló-session birtokolja a mikrofon-erőforrást") a §0.0/R8 pre-flight
mérése szerint **téves** — a lease a `lib/core/audio/`-é, és ezt a kör nem
érinti. Külön `-security.md` jelentés ezért nem készül; az indok itt, mérve,
rögzítve van.

### 2.5 Eldobható próbatesztek (merge előtt törölve)

`test/features/practice/session/zz_reviewer_probe_test.dart` (csak a
`/tmp` klónban; a kör branchére NEM került).

## 3. Leletek

### MAJOR-1 — a readiness-sor Tuner-belépője ŐRIZETLEN kijárat egy FUTÓ sessionből

**Hol:** `lib/features/practice/presentation/screens/practice_session_screen.dart:236`
(`onOpenTuner: () => context.go(AppRoutes.practiceTuner)`), a
`_buildFeedback` `isSessionActive` ágában (tehát `running` ÉS `paused`
állapotban látszik).

**Mit mértem** (`P1` próba, `running` állapot, a sor Tuner-belépőjének
koppintása):

```
PROBE P1: dialogs=0 sheets=0 alerts=0 commandsSent=() leftSession=true
```

Nulla megerősítő felület, **nulla** parancs a session felé, és a képernyő
elhagyva. Ráadásul `context.go` (**replace**, nem `push`), tehát a session
visszafelé sem érhető el.

**Miért MAJOR.** A kör MAGA építette meg a helyes kijáratot ugyanebben a
fájlban: `_requestExit` (`:255`) a `practiceExitNeedsConfirmation` táblát
nézi, `barrierDismissible: false` dialógust nyit, a szövege
következmény-központú (`practiceSessionConfirmExit` = „Exiting now discards
this session's progress. It will not be saved and this cannot be undone.") —
ez az **A5** és a §5.5 / [ADR 0279](../adr/0279-consequence-first-confirmations.md) §1.
A Tuner-belépő **megkerüli ezt a kaput**: egy koppintás a gyakorlás közben
elveszejti a session addigi munkáját, pontosan azt, amit az A5 véd. A §9
kockázat-szakasz ezt nevesíti is: „a gyakorlás közbeni véletlen kilépés a
leggyakoribb adatvesztési út".

**A mérce nem hogy nem fogta — PINNELI a hibát.** A kör saját A6 cellája
(`test/features/practice/session/session_transitions_test.dart:221`,
„tapping the tuning entry navigates to AppRoutes.practiceTuner") pontosan azt
állítja elvárásként, hogy a koppintás `running` állapotból KÖZVETLENÜL a
Tunerre visz (`expect(find.text('TUNER SENTINEL'), findsOneWidget)`), tehát a
jelenlegi cella a bypasst védi.

**Javasolt irány** (nem kész patch): a Tuner-belépő helye a **setup**
felület (SDD UI-18 „readiness checklist" + „A tuning warningból közvetlen
Tuner nyitható"), ahol az elhagyásnak nincs adatvesztési következménye — ez
egyben a MINOR-1-et is lezárja. Ha a belépő a futó session felületén is kell,
akkor **a `_requestExit` útján** kell mennie (megerősítés + `CancelPractice`),
vagy nem-destruktív módon (pl. `push` egy overlay/route fölé, a session
életben tartásával) — és az A6 cellát ennek megfelelően kell átírni: az
átírás a viselkedés JAVÍTÁSA, nem gyengítése, de a cellának ezután a
megerősítést kell bizonyítania, nem a közvetlen navigációt.

### MAJOR-2 — a Tuner-belépő érintési célja 32 dp, az ADR 0280 §Döntés 5 ≥ 48 dp-t ír elő

**Hol:** `lib/features/practice/presentation/widgets/practice_readiness_row.dart:127`
— `ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 32))`.

**Mit mértem** (`P2` próba, 412×915 compact portrait):

```
PROBE P2: tuning entry rendered size = Size(277.5, 32.0)
Expected: a value greater than or equal to <48.0>
  Actual: <32.0>
```

**Miért MAJOR.** [ADR 0280](../adr/0280-accessibility-contract-and-live-region-budget.md)
§Döntés 5: „A kritikus komponensek érintési célja **≥ 48 dp**." A belépő a
readiness-sor EGYETLEN interaktív eleme és a Tuner egyetlen belépője erről a
felületről — kritikus komponens. A magasság 16 dp-vel a szerződés alatt van.

**Ez a sáv ismétlődő hibaosztálya.** Az E13-R20/MAJOR-1 pontosan ugyanez volt
(40×40 dp cél a 48 dp-s szerződés alatt, végig ZÖLD gate mellett), és a
gyökérok is ugyanaz: a kör cellái a **szöveget és a navigációt** mérik, a
**célméretet** nem — a mérce nem teljesült, hanem **nincs jelen**.

**Javasolt irány:** a `minHeight` 48-ra emelése (és a `minWidth` legalább 48
megtartása) NEM elég önmagában — a javításhoz **őr-cella** tartozzon, ami a
`tester.getSize(...)`-szal a tényleges renderelt méretet állítja ≥ 48 dp-re,
és amit a 32 dp-s visszaállítás pirosra vált.

### MINOR-1 — a readiness-sor hiányzik a SETUP képernyőről (SDD UI-18)

**Hol:** `lib/features/practice/presentation/screens/practice_setup_screen.dart`
— a diff a beállító űrlapot migrálja (`SsValueSlider`, `SsSwitchRow`), de
`PracticeReadinessRow`-t nem renderel; a sor kizárólag a session képernyő
`_buildFeedback` slotjában él.

**Miért lelet.** Az SDD Ch13 **UI-18** állapotlistája kifejezetten tartalmazza
a `wrong tuning warning` és `device capability degraded` állapotokat, a
compact layoutja „readiness checklist"-et ír elő, az elfogadási feltétele
pedig: „**A tuning warningból közvetlen Tuner nyitható**" és „Indítás előtt a
szükséges engedélyek tiszták". A kör mind a hármat csak az UI-19-re tette,
ahol a Tuner-belépő ráadásul adatvesztési úttá válik (MAJOR-1).

**Javasolt irány:** a sort (vagy annak setup-változatát) a setup képernyőn is
rendereld; a MAJOR-1 javasolt javítása ezt természetesen adja.

### NOTE-1 — a BPM-csúszka minden drag-tickre ír a controllerbe

**Hol:** `practice_setup_screen.dart` — a korábbi `_BpmField` `onChangeEnd`-en
commitolt (`_bpmDraft` helyi vázlattal), az új `SsValueSlider` viszont
`onChanged: controller.setTempoBpm`, és az `SsValueSlider` nem kínál
`onChangeEnd`-et (`ss_value_slider.dart:38`).

Nem blokkol: a widget-oldali vázlatállapot **megszüntetése** a §5.1 irányába
mutat (kevesebb, nem több igazságforrás), és a setup képernyőn nem fut DSP,
tehát a §5.6 sem sérül. Megjegyzésként rögzítve, mert a Notifier-írás
gyakorisága drag közben nőtt.

## 4. Acceptance criteria — tételes ellenőrzés

| # | Állapot | Bizonyíték / megjegyzés |
|---|---|---|
| A1 | ✅ | `setup_validation_test.dart` — `group('A1 — reproducible from configuration')`, a gate [3] lépésében zöld |
| A2 | ✅ | `session_transitions_test.dart` A2 — egy Pause-koppintás → pontosan 1 `PausePractice`; gate [4] zöld |
| A3 | ✅ | `result_navigation_test.dart` mindhárom küszöb-cellája; a termékkód-oldali őr VALÓDI: `practice_effect_listener.dart:153` `_navigated` egyszer-ható kapu (`:172-174`), és az „above threshold" cella két FÜGGETLEN `NavigateToResult` effektet hajt rá |
| A4 | ✅ | `pause_recovery_test.dart`; a §10.2 valódi-sértés próbáját a handoff tényleges kimenettel dokumentálja (a mutáció PIROSRA váltotta, majd bájt-azonosan visszaállt) |
| A5 | ✅ | `practiceSessionConfirmExit` szövege következmény-központú, nem „Igen/Nem"; `barrierDismissible: false`. **DE** lásd MAJOR-1: a védett kijárat mellett van egy őrizetlen |
| A6 | ⚠ **MAJOR-1 + MAJOR-2** | a két tengely tényleg KÜLÖN renderel (mérve), és a hangolás-sor tényleg nem hazudik „in tune"-t — a hordozó belépő viszont őrizetlen kijárat (MAJOR-1) és 32 dp-s cél (MAJOR-2) |
| A7 | ✅ | `setup_validation_test.dart` — `group('A7 — invalid configuration never reaches the sink')` |
| A8 | ✅ | `session_transitions_test.dart` A8 — portrait és landscape túlcsordulás nélkül |
| A9 | ✅ | `test/ui/goldens/e13_r21_screens_golden_test.dart` 6 esete + 6 commitolt PNG; a felvétel az ADR 0426 szerint **x86-on** (`tools/golden-x86.sh record`), a `check` zöld — a §0.0/R5 revízió maradéktalanul követve |

## 5. A §0.0/B pre-flight revíziók ellenőrzése

| Revízió | Állapot |
|---|---|
| **R5** (golden x86-on) | ✅ követve — `record` + `check` az x86 konténerben, `--update-goldens` nem futott |
| **R6** (A6 két tengelyre szűkítve, nincs tuner-import) | ✅ a tengelyek külön; nincs `features/tuner/` import (az `architecture_dependency_test` zöld); a hangolás-sor „not measured" — **de** a belépő elhelyezése MAJOR-1/MINOR-1 |
| **R7** (helyben migrálás) | ✅ új `*_screen.dart` nem keletkezett; `ui_inventory_test.dart` `hasLength(84)` érintetlen és zöld; az S11 pin-tesztek ([8]/[9]/[10]) mind zöldek |
| **R8** (nincs `.acquire(` a practice fában) | ✅ ellenőrizve: a diff nem hoz `.acquire(`/`stop()` hívást; a Pause-overlay `onResume`-ja ugyanazt a `ResumePractice` parancsot küldi, amit a transport |

## 6. Architektúra és termékhatárok

- **Design-system határ:** a két új/módosított képernyő a
  `lib/core/design_system/public.dart` barrelen keresztül importál (nem
  `foundations/**` közvetlenül) — az E13-R16/F8 hibaosztály nem ismétlődik;
  `architecture_dependency_test` zöld.
- **Cross-feature:** nincs `features/tuner/` import; a navigáció az
  `AppRoutes.practiceTuner` konstanssal megy, a `route_literal_guard_test`
  zöld.
- **Domain-tisztaság:** `domain_purity_test` zöld; a readiness-sor bemenetei
  presentation-szintű primitívek (`bool`), nem domain reason-kódok.
- **Erőforrás:** a `lib/features/practice/` fában továbbra sincs `.acquire(`;
  a Pause parancsot küld, nem lease-t kezel (ADR 0276 §Döntés 1).

## 7. Mit kell tenni a merge előtt

1. **MAJOR-1** zárása: a Tuner-belépő ne legyen őrizetlen kijárat egy aktív
   sessionből; az A6 cella a megerősítést (vagy a nem-destruktív utat)
   bizonyítsa, ne a közvetlen navigációt.
2. **MAJOR-2** zárása: ≥ 48 dp érintési cél, **és** hozzá tartozó őr-cella,
   ami a renderelt méretet méri.
3. **MINOR-1** zárása (a MAJOR-1 javításával természetesen adódik).
4. A javítás után a §7 gate ÚJRA zöld, a golden-sáv `check` ÚJRA zöld (ha az
   elrendezés elmozdul, `record` x86-on), és exact-SHA CI az ÚJ HEAD-en.

Cella törlése, `skip`-je vagy állítás gyengítése továbbra is TILOS.

## 8. Javító kör után — a reviewer tölti ki

**Javító commit:** `6167d5be44e71f5117591ccb60b3fb7bbd995a59`
**Review-elt (friss) klón:** `/tmp/review-e13-r21b` @ `6167d5be`
**Dátum:** 2026-08-26

### 8.1 Gate-újrafuttatás a javított HEAD-en (izolált klón, saját kézzel)

`tools/round-gate.sh` a §7 szerinti 13 útvonallal:
**18/18 ZÖLD**, `GATE_EXIT=0` (format, analyze, 13 teszt, architecture,
secrets, l10n).

Scope-audit a teljes körre:

```
Legacy scope audit OK (24b95acf83e7..6167d5be44e7, 24 changed path(s),
  1 generated/ignored)
```

A `1 generated/ignored` a reviewer SAJÁT jelentése
(`docs/reviews/e13-r21-review.md`) — állandó, kód szintű mentesség
(`tools/ai_router/security.py::GENERATED_IGNORED_PREFIXES`), nem sértés.

### 8.2 Leletenkénti zárás — MÉRVE, nem olvasva

#### MAJOR-1 — ZÁRVA

A javítás **nem** a megerősítés hozzáadása, hanem a navigáció
nem-destruktívvá tétele: `context.go` → **`context.push`**
(`practice_session_screen.dart:244`), így a session képernyő a Tuner alatt
mountolva marad, és a session nem vész el. A reviewer mérése ugyanazon a
belépőn, `running` állapotban:

```
PROBE P1prime: onTuner=true sessionStillInStack=true commandsSent=()
               canPopBack=true
```

…és a `router.pop()` után a próba visszatalál az ÉLŐ sessionre
(`find.byType(PracticeSessionScreen)` → 1, a TUNER SENTINEL eltűnik).

Ez érdemben jobb megoldás, mint amit a jelentés javasolt: a felhasználó
elhangolás után **folytathatja** a gyakorlást ahelyett, hogy választania
kellene a hangolás és a session elvesztése között — és mivel semmi nem vész
el, megerősítés sem kell (ADR 0279 §1 a KÖVETKEZMÉNYRE köt, és itt nincs
következmény).

**Az őrcella is átírva** (`session_transitions_test.dart:225`): a cella most
azt bizonyítja, hogy a Tuner megnyílik ÉS a session képernyő
`skipOffstage: false` mellett is a fában marad ÉS `host.sent` üres — a `go`-ra
való visszaesés (ami a route-ot lecserélné) ezt pirosra váltaná. A korábbi,
bypasst pinnelő állítás megszűnt: **erősítés, nem gyengítés.**

#### MAJOR-2 — ZÁRVA

`practice_readiness_row.dart:139` — `minHeight: 32` → **`minHeight: 48`**.
A reviewer mérése:

```
PROBE P2prime: tuning entry rendered size = Size(277.5, 48.0)
```

**Az őrcella VALÓDI** — a reviewer valódi-sértés próbája: a 32 dp
visszaállítása után a kör saját új cellája
(`session_transitions_test.dart:257`, „the tuning entry meets the >= 48dp
touch-target contract (ADR 0280 §Döntés 5)") PIROSRA váltott:

```
Expected: a value greater than or equal to <48.0>
  Actual: <32.0>
00:01 +0 -1: … [E]
```

…majd a `git checkout --` visszaállítás után a fa tiszta
(`git diff --stat` üres) és a cella újra zöld. A cella a TÉNYLEGESEN
renderelt méretet méri (`tester.getSize`), nem a forrás konstansát — tehát
egy elrendezés-változás okozta zsugorodást is elfogna.

#### MINOR-1 — ZÁRVA

`practice_setup_screen.dart:195` — a readiness Tuner-belépő megjelent a
setup felületen is (`context.push(AppRoutes.practiceTuner)`), és van hozzá
cella: `practice_setup_screen_test.dart:487`
(`group('MINOR-1 — the readiness tuning entry is reachable from Setup')`),
ami a belépő jelenlétét ÉS a Tunerre navigálást is állítja. Az SDD UI-18 „A
tuning warningból közvetlen Tuner nyitható" elfogadási feltétele ezzel
teljesül.

#### NOTE-1 — tudatosan érintetlen

Az implementer a §10.6-ban indokolja; a jelentés nem blokkolt rá.

### 8.3 Golden-sáv a javítás után

Az elrendezés elmozdult (a setup képernyő új sort kapott, a session sor
magasabb lett), ezért a golden-készlet **x86-on** újra fel lett véve
(`tools/golden-x86.sh record`, ADR 0426) — a hat PNG-ből öt változott, egy
bájt-azonos maradt. A `check` a javító kör záró lépéseként zöld.

### 8.4 VÉGSŐ DÖNTÉS

**APPROVED** — 0 nyitott BLOCKER, 0 MAJOR, 0 MINOR. A NOTE-1 nem blokkol.

A merge feltétele változatlan: a **javított** HEAD-en (`6167d5be` vagy a záró
review-commit utáni SHA) az exact-SHA `full-gate.yml` ÉS `router-ci.yml`
egyaránt `success` (ADR 0086 §2) — a `ac33a8f5`-ös zöld futás erre NEM
mentesít.

