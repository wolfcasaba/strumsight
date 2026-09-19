# E14-R37 — Live Stage V2: döntési állapotok, stage-mód, reduced motion (ADR 0550)

- **Kör:** E14-R37 · **Csomag:** PKG-F · **ADR:** 0550
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**;
  egyetlen teszt sem futott le itt. Mérce: `full-gate.yml` + `build-apk.yml`,
  és végső fokon a valós gitáros APK-teszt.

## 1. Cél

A terv §2/R37 nyitott elfogadási feltételei közül azok lezárása, amelyek
**kód-szinten** zárhatók: a hat ADR 0505-ös döntési állapot megkülönböztetett
megjelenítése, a szabad/vezetett mód látható elválasztása (a cél célként, sosem
detekcióként), a `signal*` reject alatti magabiztos állítás tilalmának
megtartása, reduced motion MINDEN animált elemen, és a keskeny/fekvő/nagy
textScale elrendezések.

## 2. Mért állapot (a kör előtt)

- `live_screen.dart` a `LiveFrame.chordDecision`-t **nem olvasta** (`grep`);
  csak a `chordRejectReason`-t, az `UncertaintyReasonBanner`-en át.
- A hero feltétele `frame.current != null` volt. A „csak megerősített akkord"
  ma a `LivePipeline` egybeesése (`showChord == chordLatched && hasMatch`,
  `live_pipeline.dart:469` és `:397`), nem a képernyő őre.
- `chord_timeline.dart`: négy `flutter_animate` lánc + két implicit tween,
  **egyik sem** kérdezte az `SsMotionScope`-ot (E14-R39 audit B15 lelet).
- „Mód" fogalom a képernyőn nem létezett; `RecognitionMode` a MOTOR rezsimje.
- `strumEngineProvider` a `mode`-ot implicit konstruktor-alapértékből kapta.
- `newLiveStageEnabled` zászlónak nincs fogyasztója (mért, `grep`).

## 3. Scope

**Benne:** `RecognitionStateChip` (6 állapot, kimerítő szótár, saját glyph);
`GuidedTargetCard`; `_StageModeChip`; `LiveStageMode` + `liveGuidedTargetProvider`
+ `liveStageModeProvider`; `liveRecognitionModeProvider` (deklarált, felülírható
`RecognitionMode.free`); a hero/narráció döntés-kapuja; reduced-motion ág a
`chord_timeline.dart` minden animált elemén; `StorageKeys.tenMinuteFlow`
(PKG-C P2 patch — csak a kulcs).

**Kívül:** a `newLiveStageEnabled` zászló bekötése (ADR 0550 „Nem vállalt");
a history bottom sheet (nincs termékdöntés); a guided MOTOR bekötése (ADR 0550
D4 — mikrofon-lízing kérdés + `test/support/**` tulajdon kell hozzá);
`live_lab_panel.dart` (PKG-E); `live_pipeline.dart` / `public.dart` (PKG-A).

## 4. Fájlok

**lib (új):** `features/live/widgets/recognition_state_chip.dart`,
`features/live/widgets/guided_target_card.dart`,
`features/live/providers/live_stage_mode.dart`
**lib (módosított):** `features/live/screens/live_screen.dart`,
`features/live/widgets/chord_timeline.dart`,
`features/live/providers/live_providers.dart`,
`core/storage/storage_keys.dart` (egyetlen új kulcs)
**test (új):** `features/live/screens/live_stage_mode_test.dart`,
`features/live/screens/live_decision_state_truthfulness_test.dart`
**test (módosított):** `accessibility/e14_r39_reduced_motion_test.dart`
(a B15 lelet cellája megerősítve: hamisító pár + a szuppresszió állítása)

## 6. Elfogadás

| # | Feltétel | Állapot |
|---|---|---|
| A1 | mind a hat döntési állapot megjelenik és **megkülönböztetve** | **PINNED-BY-TEST** (`all six decision states are distinct` — mondat- és glyph-halmaz kardinalitás + képernyőcella államonként) |
| A2 | uncertain sosem renderelődik akkordként/nyílként | **PINNED-BY-TEST** (`only a confirmed decision may present a chord`, 5 negatív cella + 1 pozitív + 1 legacy) |
| A3 | free vs guided láthatóan elkülönül; guided = cél célként | **PINNED-BY-TEST** (`live_stage_mode_test.dart`, mód-chip + `GuidedTargetCard` + „nincs hero, mégis van cél" cella) |
| A4 | Live sosem ad hint-CÍMKÉT; a gyakorlás mindig ad | **PINNED-BY-TEST** (Live fele: `live_stage_mode_test.dart`; guided fele: `live_practice_observation_gateway_test.dart` új csoport) |
| A5 | `signal*` reject alatt nincs magabiztos állítás | **PINNED-BY-TEST** (megtartva + új cella: nincs BPM, nincs hero, a chip „nincs olvasat") |
| A6 | reduced motion minden animált elemen | **PINNED-BY-TEST** (`e14_r39_reduced_motion_test.dart` hamisító pár: teli mozgás ≥3 `Animate`, csökkentett < teli és ≥1) |
| A7 | landscape + 360 px + textScale 2.0 overflow nélkül | **PINNED-BY-TEST** (3 viewport × 2 textScale mátrix, `FlutterError` elkapással) |
| A8 | a mód minden exportban rögzül | **NEM ÉRINTI** ezt a kört (ADR 0544 PARTIAL, PKG-E/PKG-B patch) |
| A9 | a `candidate`/`provisional`/`expired` állapot valóban előfordul-e élesben | **NEEDS-MEASUREMENT** — ma a `LivePipeline` bizonyíthatóan nem állítja elő őket; a chip a SZERZŐDÉST szolgálja ki |
| A10 | 10 perces valós eszközös session (overflow/jank/mic-leak) | **NEEDS-MEASUREMENT** — ember + telefon |

## 10. Handoff

1. **Golden-újragenerálás KELL** (különben piros a CI): a stage kapott egy
   mód-chipet, ezért két PNG eltér:
   `test/ui/goldens/goldens/e13_r18_live_stage_compact.png` és
   `…_compact_scale2.png` →
   `flutter test --update-goldens test/ui/goldens/e13_r18_screens_golden_test.dart`.
   Más Live-golden nincs (`e15_r01_theme_adoption_test.dart` nem
   golden-összehasonlító, az `e13_r36`/`e15_r13` mátrixok overflow-mátrixok).
2. **l10n beolvasztás:** `<scratch>/l10n/PKG-F.json`, `base` szegmens,
   11 R37-kulcs + 4 R38-kulcs, en+hu+`@`-metaadattal.
3. **Nyitva marad:** a guided MOTOR bekötése (ADR 0550 D4) — a patch a
   PKG-F riport §5-ben.
