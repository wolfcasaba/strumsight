# E14-R39 — Adaptív, akadálymentességi és kültéri audit (ADR 0547)

- **Kör:** E14-R39 · **Csomag:** PKG-C · **ADR:** 0547
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK → **lokális gate nem futtatható**;
  egyetlen cella sem futott le itt. A kontraszt-számok statikusan, a repó
  saját kipinnelt WCAG-transzformjával készültek.
- **Audit-dokumentum:** [`docs/accessibility/ch14-r39-audit.md`](../accessibility/ch14-r39-audit.md)

## 1. Cél

A Ch14 Kör 39 négy nevesített hézagának bezárása annyira, amennyire teszt
egyáltalán tudja, és a maradék **őszinte** kimondása felelőssel:

1. 360 px profil a méret-mátrixba;
2. szürkeárnyalat / színlátás cella;
3. reduced-motion állítás a szállított beat-pulzusra;
4. high-contrast / kültéri kontraszt cella a stage-képernyőkre.

## 2. Mért állapot (a kör előtt)

- A variant-mátrix legkisebb profilja **compact 412** (`e13_r36`,
  `e15_r13`) — 360 dp-ről nincs cella.
- Volt „nincs csak-színnel közölt állapot" cella, de nem volt olyan, ami
  MEGMÉRI, mely szemantikus színek esnek egybe hue nélkül.
- `SsBeatPulse` (design system) betartja a reduced motiont (ADR 0274). A
  **szállított** `BeatPulseDot`
  (`lib/features/metronome/beat_pulse_dot.dart:115`) feltétel nélkül
  skálázott; a Live hero per-beat `flutter_animate` skálája
  (`chord_timeline.dart:204`) szintén.
- `SsHighContrastTheme.data()` == `SsDarkTheme.build(highContrast: true)`.

## 3. Scope

**Benne:** a 360 px overflow-mátrix; a szürkeárnyalatos szétválás mérése és
a nem-színes csatorna bizonyítása; a `BeatPulseDot` reduced-motion ága
(PKG-C tulajdon) + cellái; a kontraszt-mérés és a High Contrast téma valódi
hatásának kimondása; az audit-dokumentum.

**Kívül:** golden PNG (ADR 0547 D1 — a 360 profil overflow-mátrix, nem
golden); `lib/core/theme/**` és `lib/core/design_system/**` paletta-javítás
(nem PKG-C tulajdon); `lib/features/live/widgets/chord_timeline.dart`
(PKG-F); a `known-exceptions.yaml` (ADR 0547 D5 — nincs új tűrés, tehát
nincs mit bejegyezni és nincs mit tükrözni az A6 őrben).

## 4. Érintett fájlok

**Új**

- `test/ui/e14_r39_narrow_viewport_matrix_test.dart`
- `test/accessibility/e14_r39_reduced_motion_test.dart`
- `test/accessibility/e14_r39_colour_vision_test.dart`
- `test/accessibility/e14_r39_outdoor_contrast_test.dart`
- `docs/accessibility/ch14-r39-audit.md`

**Módosított**

- `lib/features/metronome/beat_pulse_dot.dart` — reduced-motion ág
  (`SsMotionScope.reduceMotionOf`): nincs skála, de a szín lépked az
  ütemmel; az off-beat tónus tompított brand, nem `mutedColor`

**Változatlan (szándékosan):** `docs/accessibility/known-exceptions.yaml`,
`test/accessibility/release_flow_semantics_test.dart` (A6 mirror).

## 5. Döntések

Lásd [ADR 0547](../adr/0547-narrow-viewport-colour-vision-and-outdoor-contrast.md)
D1–D5.

## 6. Acceptance

| # | Kritérium | Státusz |
|---|---|---|
| B1 | 360×640 portré profil: Today hub, Tuner, Metronome, `en`+`hu` × textScale 1,0 / 1,3 / 2,0 — nincs overflow és nincs kivétel | **PINNED-BY-TEST** — `e14_r39_narrow_viewport_matrix_test.dart`, 30 cella |
| B2 | Az E14-R36 lánc új felületei is elférnek 360-on | **PINNED-BY-TEST** — a „chain on its recap" / „chain hand-off visible" cellák |
| B3 | A túlcsordulás-detektor valóban lát túlcsordulást | **PINNED-BY-TEST** — „the detector itself" hamisítási próba |
| B4 | Szürkeárnyalat: MÉRVE, mely szemantikus színek esnek egybe | **PINNED-BY-TEST** — `e14_r39_colour_vision_test.dart`, „no pair of confidence tokens reaches even the 3:1 non-text floor" + „the worst pair is a total collapse" (dark high↔medium = 1,01:1) |
| B5 | A szétválás-metrika hamisítható | **PINNED-BY-TEST** — fekete/fehér = 21:1, önmaga = 1:1 |
| B6 | Az egybeeső színek állapotát nem-színes csatorna hordozza (egyedi ikon, egyedi címke, `textPrimary` festés) | **PINNED-BY-TEST** — 3 cella |
| B7 | A hangoló in-tune / out-of-tune állapota teljes hue-vesztés alatt is elkülönül | **PINNED-BY-TEST** — „the tuner keeps its state under total hue loss" |
| B8 | A szállított metronóm-pulzus reduced motion alatt nem skáláz, de a szín lépked | **PINNED-BY-TEST (javítva ebben a körben)** — `e14_r39_reduced_motion_test.dart` |
| B9 | Ugyanez CSAK a platform-kapcsolóból is érvényesül | **PINNED-BY-TEST** |
| B10 | Full motion alatt a pont tényleg skáláz (hamisítás) | **PINNED-BY-TEST** |
| B11 | A dark (szállított) téma minden szöveg- és státusz-tokenje ≥ 4,5:1 | **PINNED-BY-TEST** — `e14_r39_outdoor_contrast_test.dart` |
| B12 | A light (kültéri) téma mért bukásai kipinnelve: `brand` 2,40, `info` 1,93 (a 3:1 padló alatt), `success` 3,84 és `danger` 3,27 (a 4,5 alatt) | **PINNED-BY-TEST** — 3 cella |
| B13 | A High Contrast téma valódi hatása kimondva: csak keret + fókuszgyűrű + dekoratív effektek, dark-only | **PINNED-BY-TEST** |
| B14 | A stage-képernyők renderelődnek High Contrast témán | **PINNED-BY-TEST** — Today hub + Tuner cella |
| B15 | A Live hero per-beat pulzusa és a feedback-animáció reduced motion alatt visszafogott | **NOT-DONE (PKG-F tulajdon)** — javasolt patch §10.1; a cella, ami MA igaz (az információ nem vész el, a fa lenyugszik), rögzítve van |
| B16 | 360 px profil a nem-PKG-C képernyőkre | **NOT-DONE (csomag-tulajdon)** |
| B17 | A light-téma paletta-hibák javítása | **NOT-DONE (`lib/core/theme/**`, nem PKG-C)** — a mérés viszont megvan, tehát a következő paletta-kör bemenete |
| B18 | Valódi kinti fény, 1–2 m, ≥3 telefon olvashatósági checklist | **NEEDS-MEASUREMENT (EMBER)** — E14-R40 field study, PKG-D |
| B19 | A cellák ténylegesen zöldek | **NEEDS-MEASUREMENT** — nincs Dart SDK; a mérce a CI |

## 7. Verifikáció

Lokálisan **nem futtatható**. Megírt cellák:

- `test/ui/e14_r39_narrow_viewport_matrix_test.dart` — 2 csoport, 31 cella
- `test/accessibility/e14_r39_reduced_motion_test.dart` — 2 csoport, 5 cella
- `test/accessibility/e14_r39_colour_vision_test.dart` — 3 csoport, 6 cella
- `test/accessibility/e14_r39_outdoor_contrast_test.dart` — 4 csoport, 8 cella

Sikeres verifikációt **tilos állítani**.

## 8. Kockázatok

- **B1 pirosra válthat.** A 360 px cellák soha nem futottak. Az elrendezéseket
  statikusan átnéztük (a Today body `ListView`, a metrika-sor `Expanded`; a
  stage-képernyők középső sávja görgethető, a hangoló chipjei
  `FittedBox(scaleDown)`, a metronóm tempó-sora fix 276 dp < 328 dp), de ez
  nem futtatás. **Ha egy cella pirosra vált, az VALÓDI lelet**: a helyes
  reakció a `lib/**` javítása (a Today/Tuner/Metronome PKG-C tulajdon), nem
  a cella gyengítése.
- **Formázás.** `dart format` nem futott.
- **`tool/ui_contrast_check.dart` API.** Csak a `relativeLuminance`-t
  használjuk (a `themes/contrast_test.dart` által bizonyítottan létező
  felület); az arányt helyben számoljuk, hogy ne feltételezzünk nem látott
  metódust.

## 9. Nem-célok

Nem hangol DSP-küszöböt. Nem ír golden PNG-t. Nem javít paletta-tokent
(nem PKG-C tulajdon, és mérés nélküli hangolás tilos — itt a mérés MEGVAN,
a javítás a következő tulajdonos köre). Nem bővíti a
`known-exceptions.yaml`-t.

## 10. Handoff

### 10.1 Javasolt patch PKG-F-nek — Live hero reduced motion (B15)

`lib/features/live/widgets/chord_timeline.dart`, a `_heroCard` INNERMOST
beat-pulzusa (jelenleg 204–210. sor). A `ChordTimeline` `StatelessWidget`, a
`BuildContext` a `_heroCard`-ban rendelkezésre áll:

```dart
    // INNERMOST: a single, whisper-subtle beat-pulse per engine beat.
    // (…meglévő komment változatlanul…)
    // E14-R39: reduced motion alatt a pulzus NEM tűnik el — csak a mozgás
    // extentje nullázódik, ahogy az `SsBeatPulse` (ADR 0274 §5.1) teszi:
    // az akkord maga a visszajelzés, a skála csak a hangsúly.
    if (!SsMotionScope.reduceMotionOf(context)) {
      card = card
          .animate(key: ValueKey('beat-$beat'))
          .scaleXY(
            begin: 1.022,
            end: 1.0,
            duration: 180.ms,
            curve: Curves.easeOutCubic,
          );
    }
```

`import '../../../core/design_system/public.dart';` szükséges (a fájl ma nem
importálja). Ugyanez a minta a belépő flash/shimmer gesztusra: a
`SsMotionScope.durationOf(context, base)` a meglévő időtartamokra
alkalmazva `Duration.zero`-t ad reduced motion alatt, tehát a mozgás
eltűnik, a végállapot marad.

**A hozzá tartozó cella**, amit a patch-csel EGYÜTT lehet a
`test/accessibility/e14_r39_reduced_motion_test.dart`-ba tenni (előtte
szándékosan piros lenne, ezért nem szállítjuk most):

```dart
    testWidgets('the Live hero does not scale-pulse under reduced motion', (
      tester,
    ) async {
      Future<Size> heroSize({required bool reduceMotion}) async {
        await _pumpLive(
          tester,
          SsMotionScope(
            appOverride: reduceMotion,
            child: ChordTimeline(events: [_event('G', 1)], capo: 0, beat: 7),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(ChordTimelineCard).first);
      }

      final reduced = await heroSize(reduceMotion: true);
      final full = await heroSize(reduceMotion: false);
      expect(reduced, isNot(full));
    });
```

(A `beat: 7` a pulzus első képkockáján méri a nagyítást; a cella pontos
alakja a patch szerzőjén múlik — a lényeg, hogy a MOZGÁST mérje, ne a
jelenlétet.)

### 10.2 Javasolt bemenet a következő paletta-körnek (B17)

`lib/core/theme/app_colors.dart` / `app_palette.dart`: a light témán a
`primary` (#D98A46) 2,40:1, a `secondary` (#E0A44A) 1,93:1 a `bg`
(#F3F0E9) ellenében. Mindkettő a 3:1 nem-szöveg padló ALATT van, és a
hangoló a `primary`-vel festi az irány-kijelzést. A javítás iránya egy
light-módra sötétített akcens (a repóban erre már van precedens: a
`_confidenceHighInk` / `_confidenceMidInk` / `_confidenceLowInk` trió). A
konkrét értéket **mérni kell**, nem szemre választani.

### 10.3 Sor a pipeline-queue-hoz (az orchestrátor írja)

```
E14-R39	PKG-C	adaptive/a11y/outdoor audit	docs/accessibility/ch14-r39-audit.md	ADR 0547	PARTIAL (B15/B16/B17 más tulajdonos, B18 ember)
```
