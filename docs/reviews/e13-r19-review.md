# E13-R19 — Kör-review (Tuner és Metronome UI migráció)

- **Reviewer:** Claude (orchestrátor-session, read-only review — ADR 0055)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, effort=high)
- **Kör-branch:** `sonnet-impl/e13-r19-tuner-and-metronome-ui`
- **Review-HEAD:** `ad3900fb56a421f5b8efc24731cd916237c057f1`
- **Brief:** `docs/rounds/e13-r19-tuner-and-metronome-ui.md`
- **Dátum:** 2026-08-25

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `head=ad3900fb`, `scope_audit=ok`
(27 változott útvonal), a munkafa a jelzés után **tiszta**
(`git status --short` üres). A brief §10 handoffja kitöltött, és minden
állítása mögött van a naplóban visszakereshető parancs.

**Egy jelzésmező-lelet, ami NEM a köré:** `gate_shape=VIOLATION`. A
`tools/mm-round.sh:381` predikátuma a naplóban a
`round-gate\.sh[^\n]*(\| *(tail|head)|&&)` mintát keresi. A stream-json napló
egy JSON-objektuma EGYETLEN sor, ezért a `[^\n]*` átível az egész prompton és
minden tool-hívás szövegén. A ténylegesen lefuttatott Bash-hívásokat
kigyűjtve (3 találat a `round-gate` mintára):

```
[1] cat tools/round-gate.sh | head -40      ← a script ELOLVASÁSA
[2] cat tools/round-gate.sh
[3] tools/round-gate.sh test/features/tuner/tuner_ui_mapping_test.dart …   ← csonkítatlan
```

A `VIOLATION`-t az [1] váltotta ki (a gate-script megtekintése), nem egy
csonkolt gate-futás. **Nem lelet a kör ellen**; a predikátum javítása
`tools/**` hatáskör, tehát GOV/önjavító kör dolga (lásd §6/NOTE-4).

## 2. Saját gate-újrafuttatás (izolált klón)

`/tmp/review-e13-r19`, `git fetch origin` + `reset --hard` a kör HEAD-jére,
majd `tools/prepare-flutter-generated.sh`, végül a brief §7 parancsa
csonkítatlanul. **Mind a 22 lépés ZÖLD** (`GATE_EXIT=0`):

```
format · analyze · 17 megadott teszt-útvonal külön-külön · architecture · secrets · l10n
```

> **Reviewer-oldali mérési hiba, rögzítve:** az ELSŐ futásom `analyze`-nál
> pirosat adott 4 `undefined_getter`-rel (`metronomeAdvancedSettings`,
> `metronomeTimeSignature`, `tunerHoldSteady`). Ok: a `prepare-flutter-generated.sh`-t
> a klón `9cc5fe6b`-es állapotán futtattam, és csak UTÁNA resetteltem a kör
> HEAD-jére — a gitignore-olt generált `app_localizations.dart` így elavult
> maradt. A commitolt ARB-források mindhárom kulcsot tartalmazzák
> (`base/app_{en,hu}.arb`, `features/tuner_{en,hu}.arb` + a regenerált
> aggregátum), és a helyes sorrenddel (reset → prepare) a lépés zöld. A
> kör ellen **nem lelet**; a helyes reviewer-sorrend: *előbb a HEAD, utána a
> generálás*.

## 3. Scope-audit

```
python3 tools/scope-audit.py --repo /tmp/review-e13-r19 \
  --brief docs/rounds/e13-r19-tuner-and-metronome-ui.md --base 9cc5fe6b…
→ Legacy scope audit OK (9cc5fe6bcea5..ad3900fb56a4, 27 changed path(s), 0 generated/ignored)
```

A §0.0/R5.3 **típus-helyben kötés** is betartva (a pre-flight szűkítése):

| Kötés | Mért eredmény |
|---|---|
| `git diff --name-only origin/main...HEAD -- test/app/ test/core/ test/ui/ui_inventory_test.dart test/features/today/` | **üres** |
| `find lib/features -name '*_screen.dart' \| wc -l` | **84** (változatlan) |
| `test/ui/ui_inventory_test.dart` (`hasLength(84)`) | zöld a saját gate-futásomon |
| `TunerScreen` / `MetronomeScreen` típusnév és útvonal | változatlan |

Meglévő teszt-cellák: **egy sem törölve, egy sem `skip`-elve** (mérve:
`metronome_screen_test` 3→4, `reference_tone_test` 4→5, a többi öt fájl
cellaszáma változatlan; `grep -rn "skip:"` a kör teszt-fáin: 0 találat).

## 4. Acceptance criteria — tételesen, bizonyítékkal

| # | Verdikt | Bizonyíték (saját mérés) |
|---|---|---|
| A1 | **teljesül** | `tuner_ui_mapping_test.dart` — `tunerUiStateOf` mind a négy ága + a három kötelező ±5 cent cella (±3 / pontosan −5 / ±9). A kód `TunerReading.inTuneCents = 5`, `<=` → a határ inkluzív, a cella ezt méri. |
| A2 | **teljesül, egy méréssel kimutatott réssel** | `find.text('18 cents sharp')` / `'18 cents flat'` + irány-ikon a `outOfTune` ágon. **De:** az új `unstable` állapotban a látható iránymező eltűnik — lásd MINOR-1. |
| A3 | **teljesül** | `find.text('IN TUNE')` + `Icons.check_circle` együtt; a haptika a lock-eseményen (meglévő út). |
| A4 | **teljesül — SAJÁT valódi-sértés próbával igazolva** | lásd §5.1 |
| A5 | **teljesül — SAJÁT valódi-sértés próbával igazolva** | lásd §5.2 |
| A6 | **teljesül** | `TapTempo` érintetlen (`git diff` a `lib/features/metronome/tap_tempo.dart`-on üres); a meglévő tap-tempo cellák zöldek. |
| A7 | **teljesül** | 320×690 portré és 844×390 fekvő, `textScale 2.0`, `tester.takeException()` `null`. |
| A8 | **teljesül** | 4 golden PNG commitolva (`e13_r19_{tuner,metronome}_compact{,_scale2}.png`), a golden-teszt a saját gate-futásomon zöld. |

## 5. Valódi-sértés próbák (reviewer-oldali, eldobható, visszaállítva)

### 5.1 A4 — a fázis forrása

`lib/features/metronome/beat_pulse_dot.dart` `_onTick`-jében a
`widget.clock.position` helyett a saját `Ticker` `elapsed`-jéből számoltam a
fázist (ez a `Timer.periodic`-osztály lényege: a hangzó órától független
futás). Eredmény:

```
Failing tests:
  metronome_beat_sync_test.dart: within tolerance: 0ms lag is accepted
  metronome_beat_sync_test.dart: at the boundary: exactly 100ms lag is accepted (inclusive)
  metronome_beat_sync_test.dart: the rendered size exactly matches the phase formula
```

**A guard valódi** — az ADR 0274 tiltása gépileg védve van. Visszaállítva
(`git checkout --`, a `git diff` üres).

### 5.2 A5 — az erőforrás-elengedés

`referenceTonePlayerProvider`: `Provider.autoDispose` → `Provider`. Eredmény:

```
Failing tests:
  tuner_route_cleanup_test.dart: leaving Tuner disposes the reference-tone player even mid-tone (A5)
```

**A guard valódi.** Visszaállítva. (A teszt az `overrideWith((ref) { ref.onDispose(…); … })`
alakot használja, nem `overrideWithValue`-t — ez tudatos: az utóbbi
megkerülné a provider saját `create` törzsét, tehát sosem mérné a valódi
teardown-utat. Helyes döntés.)

### 5.3 A2 — a látható iránymező az ÚJ `unstable` állapotban

Eldobható próbateszt (`test/features/tuner/_review_probe_test.dart`, a review
után **törölve**): két azonos hangú leolvasás 30 centtel egymástól
(`TunerStability.jumpThreshold = 12` fölött), majd a fa lekérdezése:

```
PROBE hold-steady visible: 1
PROBE direction text visible: 0
```

Azaz stabil olvasásnál `„10 cents sharp"` látszik, az `unstable` ágra váltva
viszont **kizárólag** a `„Hold steady…"` — az irány látható szövege eltűnik.
(A `CentsGauge` szemantikai címkéje az irányt továbbra is FELOLVASSA, tehát ez
nem ADR 0280-sértés; a rés a *látható* csatornán van, amit a brief §5.1
kifejezetten a felolvasótól függetlenül is elvár.) → MINOR-1.

## 6. Leletek

| # | Osztály | Lelet |
|---|---|---|
| MINOR-1 | MINOR | Az A2 látható irány-szövege eltűnik az új `unstable` állapotban |
| MINOR-2 | MINOR | `ReferenceTonePlayer.stop()` halott felület — nincs production hívója, és a `dispose()` sem hívja |
| NOTE-1 | NOTE | `_TunerFeedback` `TunerUiState.idle` ága elérhetetlen |
| NOTE-2 | NOTE | `CentsGauge` konstans `hasSignal: true`-t ad tovább |
| NOTE-3 | NOTE | `BeatPulseDot` nem nullázza a `_phase`-t megálláskor |
| NOTE-4 | NOTE | `gate_shape=VIOLATION` téves pozitív a burkoló predikátumában (nem a kör hibája) |

### MINOR-1 — az A2 látható iránya az `unstable` ágon

`lib/features/tuner/screens/tuner_screen.dart:~320` (`_TunerFeedback.build`,
a `TunerUiState.unstable` ág). Mérve az §5.3 próbával: az irány látható
szövege 1 → 0 widgetre vált, amint a `TunerStability` instabilnak jelöli a
leolvasást. Ez pontosan az a felhasználói pillanat (a kulcs tekerése), amikor
a hangoló-irány a legfontosabb, és a `jumpThreshold = 12` cent két EGYMÁST
KÖVETŐ leolvasás között gyors tekerésnél reálisan átléphető.

**Javasolt irány (nem kész patch):** az `unstable` ág is mutassa az irányt
(pl. a `Hold steady…` a másodlagos, halványabb sor, az irány marad az elsődleges),
VAGY — ha a szándék tudatosan a „ne reagálj a tranziensre" — a kör kösse ki
ezt egy cellával, ami a szándékolt viselkedést pinneli. A mai állapot se
egyiket, se másikat nem rögzíti: az `unstable` ág vizuális szerződése
teszteletlen.

### MINOR-2 — halott `stop()` a referenciahang-felületen

`lib/features/tuner/providers/reference_tone_provider.dart:14,40-45`. Az
absztrakt `ReferenceTonePlayer.stop()`-nak nincs production hívója
(`grep` a `lib/features/tuner/` fán: a két `.stop()` találat az `AudioPlayer`
SAJÁT metódusa a `play()`-en belül és a `stop()` törzsében), és a `dispose()`
sem hívja meg — közvetlenül `_player?.dispose()`-ra megy.

**Javasolt irány:** vagy a `dispose()` hívja előbb a `stop()`-ot (ezzel a
„mid-tone leállás" állítás szó szerint igazzá válik, és a felület élővé), vagy
a `stop()` kerüljön ki a felületről. A jelenlegi alak egy nem hívott,
teszttel nem fedett publikus metódus.

### NOTE-1…NOTE-3

- **NOTE-1:** `_TunerFeedback` `idle` ága sosem renderel (a `feedback` slot
  `idle`-re `SizedBox.shrink()`) — védekező, de holt ág.
- **NOTE-2:** `CentsGauge` mindig `hasSignal: true`-t ad az `SsTunerGauge`-nak;
  ma helyes (csak jel mellett mountolódik), de a paraméter az egyetlen
  hívási helyen konstans.
- **NOTE-3:** `BeatPulseDot._onTick` nem állítja vissza a `_phase`-t
  megálláskor, így egy újraindítás első frame-je elvileg egy elavult fázist
  rajzolhat (≤1 frame, a `playing: false` ág amúgy is a nyugalmi pontot
  rajzolja). Nem viselkedési hiba, csak higiénia.

### NOTE-4 — a `gate_shape` predikátum (infrastruktúra)

Lásd §1. A javítás `tools/mm-round.sh` + `tools/codex-round.sh` (a predikátum
a tényleges tool-hívásokat nézze, ne a nyers naplósort) — a kör hatáskörén
KÍVÜL, GOV/önjavító kör dolga.

## 7. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `SsTunerGauge` (design system) **tisztán prezentációs**: minden színt és a
  `semanticLabel`-t a hívó adja, l10n a feature-rétegben marad — nincs
  core→feature függés. A `test/core/architecture_dependency_test.dart` és a
  `tool/check_architecture.dart` is zöld a saját futásomon.
- A DSP-t (`lib/features/tuner/engine/**`) a kör **nem érintette**
  (`git diff` üres azon a fán) — az „instabil" állapot tisztán UI-rétegbeli
  származtatás (`TunerStability`), ahogy a §0.0/R5.1 előírta.
- A metronóm **időzítése** változatlan: a `beat_clock.dart` és a
  `tap_tempo.dart` diffje üres, a kattintás-ütemezés a régi `_onTick` ág.
  Az `SsBeatClock` adapter ugyanazt az elapsed-értéket olvassa, amit a
  klikk-ütemező — a vizuális pulzus szerkezetileg nem tud elcsúszni tőle.
- **Erőforrás-életciklus:** a mikrofon a meglévő `StreamProvider.autoDispose`
  úton szabadul (mérve: `engine.stopCalls == 1` route-elhagyás után), a
  referenciahang az új `Provider.autoDispose`-on (mérve az §5.2 próbával).
- **Golden-hordozhatóság (L486):** `grep -rn "colorScheme"` a kör teljes
  érintett fáján (`lib/features/tuner/`, `lib/features/metronome/`,
  `ss_tuner_gauge.dart`) → **0 találat**; a színek `AppColors` /
  `context.palette` konstans forrásból jönnek. A mért box↔CI
  raszterizációs csapda ezzel szerkezetileg elkerülve.

## 8. Verdikt

**CHANGES REQUESTED** — nincs BLOCKER és nincs MAJOR; a kör tartalmilag kész,
a két architekturális szerződés (ADR 0274 audio óra, A5 erőforrás-elengedés)
független próbával igazoltan gépileg védett. A két MINOR a kör SAJÁT fáján,
kis diffel javítható, ezért javító körben zárandó (a MINOR-1 a kör saját A2
kritériumának teszteletlen rését érinti).

A javító kör után a review frissül, és a merge-kapu változatlan: exact-SHA
Full Gate + Router CI zölden a merge SHA-n.

## 9. Javító kör — a leletek zárása

**Javító kör:** `2c3df0ee` (MINOR-1), `e7d143eb` (MINOR-2), `b353a47c` (§10.7
handoff). Motor: ugyanaz (`sonnet-impl`). Scope-audit a javító körre:
`scope_audit=ok`, 5 változott útvonal.

### MINOR-1 — ZÁRVA

`lib/features/tuner/screens/tuner_screen.dart` `_TunerFeedback`: az
`unstable` ág mostantól **ugyanazt az irány-ikont és irány-szöveget** kapja,
mint az `outOfTune` (`TunerUiState.unstable || TunerUiState.outOfTune` közös
ág), és a `Hold steady…` egy hozzáadott, halványabb MÁSODIK sor — nem
helyettesíti az irányt. Az implementer az 1. feloldást választotta, a
review-ban felkínált kettő közül.

**Őrcella:** `tuner_ui_mapping_test.dart` új cellája („unstable: the direction
stays visible as primary text…") két azonos hangú leolvasást ad 30 centtel
egymástól, majd EGYSZERRE állítja a `'40 cents sharp'` szöveget, az
`Icons.arrow_upward` ikont ÉS a `'Hold steady…'` másodlagos sort. A javítás
ELŐTTI kódon ez a cella piros lenne (a §5.3 próbám pontosan azt mérte, hogy
az irány-szöveg 1 → 0 widgetre vált) — tehát a lelet gépi őrt kapott, nem csak
javítást.

### MINOR-2 — ZÁRVA

`reference_tone_provider.dart`: a `dispose()` első lépése immár `await stop()`,
és csak utána jön a player teardown — ezzel a felület élővé vált, és a
„mid-tone leállás" állítás szó szerint igaz.

**Őrcella:** `tuner_route_cleanup_test.dart` A5-cellája új állítást kapott
(`tone.stopCalls == 1`), a fake `dispose()`-a pedig a valódi sorrendet
tükrözi. A javítás előtti kódon `stopCalls == 0` lett volna → piros.

### Saját újramérés a javító kör után

Friss izolált klón (`/tmp/review2-e13-r19`, `git fetch` → `reset --hard`
b353a47c → `prepare-flutter-generated.sh` → gate): **mind a 22 lépés ZÖLD**
(`GATE_EXIT=0`).

A NOTE-1…NOTE-3 szándékosan nyitva marad (nem blokkol, és a javításuk
fölöslegesen hizlalná a diffet); a NOTE-4 `tools/` hatáskör, GOV/önjavító kör
dolga.

## 10. VÉGSŐ DÖNTÉS: APPROVED

Nincs nyitott BLOCKER, MAJOR vagy MINOR. A merge feltétele változatlanul az
exact-SHA zöld kapu: `full-gate.yml` + `router-ci.yml` `success` a merge
SHA-ján (ADR 0052/0086).
