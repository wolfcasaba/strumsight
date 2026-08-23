# E13-R07 — Review (kör 1)

- **Kör:** `E13-R07` — Ikonográfia és gitárglyph készlet
- **PR:** [#429](https://github.com/wolfcasaba/strumsight/pull/429)
- **Reviewer:** Claude Opus 5 (orchestrátor, ADR 0055) — READ-ONLY
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Review-alap:** `73dad023` (pre-flight) → `36caaa17`
- **Verdikt:** **CHANGES REQUESTED** — 1 MAJOR, 2 MINOR, 1 NOTE

A review izolált klónban futott (`/tmp/e13r07-review`, a munkapéldányból
klónozva), eldobható valódi-sértés próbákkal. Production fájlt a review NEM
módosított; minden próba után `git checkout --` visszaállítás, a záró
`git status --porcelain` üres.

## Scope

`scope_audit=ok` (base `73dad023`, 8 fájl). Ellenőrizve:

| Ellenőrzés | Eredmény |
|---|---|
| `git diff --exit-code 73dad023..HEAD -- pubspec.yaml` | **üres** — A7 ✅ |
| `git diff --name-only 73dad023..HEAD -- assets/` | **0 fájl** ✅ |
| listán kívüli fájl | **nincs** ✅ |
| `docs/adr/**` az implementer diffjében | **nincs** ✅ |

## Falszifikációs próbák — mit vittem ténylegesen pirosra

Minden próba a `docs/rounds/e13-r07-…md` §6.1 mérce-mátrixának EGY sorát
reprodukálja. A cél nem a zöld megerősítése, hanem annak mérése, hogy a
cella tényleg falszifikál-e.

| # | Beinjektált hibás implementáció | Elvárt PIROS cella | MÉRT eredmény |
|---|---|---|---|
| P1 | `_paintCapo` saját, kézzel írt `strokeWidth = 7.5` | **A9** | ❌ **MIND ZÖLD** (`+11 All tests passed`) → **F1 MAJOR** |
| P2 | `resolveForStage` assert-only (nem clamp) | **A5** | ✅ 2 cella piros (predikátum + valódi widget-út) |
| P3 | az interaktív ág `Semantics(label:)`-je eltávolítva | **A2** | ✅ piros (`Found 0 widgets with a semantics label`) |
| P4 | `SsFallbackIcon() => const SizedBox.shrink()` | **A4** | ✅ piros (a nem nulla méret cellája) |
| P5 | `downstrum` → `Text('↓')` | **A1** | ✅ piros |

A P2 külön is értékes: a **D5** azt írta elő, hogy legalább egy cella a
VALÓDI widget-úton mérjen, mert a puszta predikátum-cella idealizált
bemenettel zöld maradhat (`LESSONS` L381). A próba megerősítette, hogy
mindkét szint fog.

## Leletek

### F1 — MAJOR: az A9 cella nem falszifikál — a kézzel írt per-glyph stroke átmegy

**Fájl:** `test/core/design_system/icons/ss_icons_test.dart:56-79`
(a mért ok: `lib/core/design_system/icons/ss_guitar_glyphs.dart:42-47`)

Az A9 cella ezt méri:

```dart
final painter = SsGuitarGlyphs.painterFor(name, color: ..., size: size);
expect(painter.strokeWidth, SsGuitarGlyphs.strokeWidthFor(size));
```

A `SsGuitarGlyphPainter` konstruktora **mindig** ugyanazt az egy kifejezést
futtatja (`strokeWidth = SsGuitarGlyphs.strokeWidthFor(size)`), a `name`-től
függetlenül. A tizennégy néven végigmenő ciklus tehát ugyanazt a
konstruktort méri tizennégyszer — **egyetlen glyph tényleges festéséről sem
mond semmit**. A `strokeWidth` mező megléte nem bizonyítja, hogy a
`_paint*` metódus fel is használja.

**Mért bizonyíték (P1).** A `_paintCapo` `_line` Paintjét kicseréltem egy
kézzel írt értékre:

```dart
canvas.drawRRect(
  RRect.fromRectAndRadius(bar, Radius.circular(s.width * 0.06)),
  Paint()..color = color..strokeWidth = 7.5..style = PaintingStyle.stroke,
);
```

Eredmény: `00:00 +11: All tests passed!` — a `ss_icons_test.dart` MINDEN
cellája zöld maradt, köztük az A9.

Ez pontosan a §6.1 mérce-mátrix sora:

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy glyph saját, kézzel írt `strokeWidth`-tel | **A9** |

…tehát a brief által NEVESÍTETT őr nem őriz. Ugyanez a hibaosztály, mint a
`docs/LESSONS.md` **L403**: a próba a szerkezetet (widget-típus / mező
megléte) mérte, nem a tényleges tartalmat.

Ráadásul a §10 handoff kimondottan azt állítja, hogy „**szerkezetileg
kizárt**, hogy egy glyph saját `strokeWidth`-et találjon ki" — a P1 ezt az
állítást megcáfolta. Bizonyítatlan doc-állítás marad a fán.

**Mit várok a javító körtől.** Olyan cellát, amely a glyph TÉNYLEGES festési
hívásait figyeli meg, nem a konstruktort. Járható út: egy rögzítő
`Canvas`-szal (`PictureRecorder`, vagy egy `Canvas`-t implementáló
teszt-dupla, amely a `drawLine`/`drawPath`/`drawRRect`/`drawArc`/`drawCircle`
hívások `Paint.strokeWidth` értékeit gyűjti) mind a 14 glyph-et lefestve
mérni, hogy **minden `PaintingStyle.stroke` festés vonalvastagsága a
megosztott arányból származik** (a `strokeWidth * k` alakú, szándékosan
vékonyabb másodlagos vonások — pl. a hammer-on/pull-off üreges hangjegyfeje,
`ss_guitar_glyphs.dart:179,205` — engedélyezettek, de a mérce mondja ki,
hogy az arányuk a megosztott `strokeWidth`-hez képest van meghatározva, nem
abszolút dp-ben). Az injektált `7.5`-nek pirosra kell váltania a cellát.

A §10 „szerkezetileg kizárt" mondatát a javító kör igazítsa ahhoz, amit a
cella ténylegesen bizonyít.

### F2 — MINOR: az A8 három téma-cellájából kettő azonos nevet kap

**Fájl:** `test/core/design_system/icons/ss_icons_test.dart:81-119`

A teszt neve a `theme.brightness`-ből épül, a `SsHighContrastTheme`
`brightness`-e viszont `dark` — ezért a futás így néz ki:

```
+5: … all fourteen glyphs render under Brightness.dark without throwing
+6: … all fourteen glyphs render under Brightness.light without throwing
+7: … all fourteen glyphs render under Brightness.dark without throwing
```

Mind a három téma TÉNYLEG lefut (három külön `ThemeData`), tehát az A8
tartalmilag teljesül — de a duplikált név mellett egy piros futásból nem
derül ki, melyik téma bukott, és egy jövőbeli olvasó könnyen véletlen
másolásnak nézi. Kérem beszédes, témánként egyedi nevet (pl. a
`dark` / `light` / `highContrast` címkét explicit párként adva).

### F3 — MINOR: az A8 nem méri, hogy a 14 glyph tényleg KÜLÖNBÖZŐ jelet fest

**Fájl:** `test/core/design_system/icons/ss_icons_test.dart:81-119`

A cella `findsNWidgets(14)` `CustomPaint`-et számol és
`takeException()`-t néz. Egy olyan implementáció, amely mind a tizennégy
névre ugyanazt a jelet festi, zöld maradna. A `paint` `switch`-e ma
kimerítő (hiányzó ág = fordítási hiba), tehát a kockázat kicsi — de az A8
állítása („a készlet mind a 14 glyph-et rendereli") ennél többet ígér.

Ha az F1 javítása a fent javasolt festés-rögzítő próbatestet hozza be,
ugyanaz az eszköz olcsón lezárja ezt is: elég megmérni, hogy a tizennégy
glyph rögzített rajz-hívás-sorozata **páronként különbözik**.

### F4 — NOTE: `resolveByName` lineáris enum-keresés minden buildben

**Fájl:** `lib/core/design_system/icons/ss_icons.dart:97-104`

A feloldás minden `SsIcon.build`-nál végigmegy a
`SsGuitarGlyphName.values`-on. Tizennégy elemnél ez nem mérhető, és az
ikonok nem forró útvonalon vannak — **nem javítandó ebben a körben**,
csak rögzítve arra az esetre, ha egy jövőbeli kör listákban tömegesen
használná az `SsIcon`-t.

## Amit a review ZÖLDNEK talált

- **A1** ✅ — festett strum, a P5 próba pirosra viszi a karakteres változatot.
- **A2** ✅ — a cella a SZTRINGET méri (`find.bySemanticsLabel` +
  `find.byTooltip`), nem a widget típusát (D6/L403 teljesítve); az üres
  string konstruktor-szinten `ArgumentError`, a hiányzó label fordítási hiba.
- **A3** ✅ — `find.bySemanticsLabel(RegExp('.+'))` → `findsNothing`, tehát a
  dekoratív ikon nem visz labelt a fába.
- **A4** ✅ — `isFallback` + nem nulla renderelt méret; a P4 próba pirosra
  viszi a `SizedBox.shrink()`-et.
- **A5** ✅ — a három küszöbcella ÉS a valódi widget-úti cella; a P2 próba
  mindkét szintet pirosra viszi. A `resolveForStage` clamp, nem puszta
  `assert` — release buildben is hat.
- **A6** ✅ — a felmérés a D7 parancsaival reprodukálva, fájlonkénti
  bontással; a mért érték (16 emoji / 5 fájl, 25 nyíl / 13 fájl) pontosan
  egyezik az orchestrátor `main @ 667792b6` alapvonalával, és a
  `lib/features/**` érintetlen maradt.
- **A7** ✅ — a `pubspec.yaml` és az `assets/` diffje üres (gépi tény).
- **ADR 0411 §4** ✅ — az ikon-réteg nem importál `AppLocalizations`-t; a
  label és a tooltip hívó-oldali.
- **L387** ✅ — az implementer a `public.dart` bővítése után a meglévő
  `component_catalog_test.dart`-ot is lefuttatta, zölden.

## Következő lépés

Egy javító kör ugyanazzal a motorral (`sonnet-impl`), az **F1** (MAJOR),
**F2** és **F3** (MINOR) leletekkel. Az **F4** NOTE, nem javítandó.

---

# Review (kör 2) — a javító kör után

- **Review-alap:** `1421d823` (review 1) → `8221e727`
- **Diff:** 2 fájl (`ss_icons_test.dart`, a brief §10) — **production kód NEM
  változott**. Gépi scope-audit:
  `Legacy scope audit OK (1421d823acc9..8221e727425f, 2 changed path(s), 0 generated/ignored)`.
- **Verdikt:** **APPROVED**

Az ellenőrzés friss izolált klónban futott (`/tmp/e13r07-review2`),
ugyanazokkal az eldobható próbákkal — a cél annak MÉRÉSE, hogy a javított
cellák tényleg falszifikálnak-e, nem a zöld megerősítése.

## F1 — MAJOR → **LEZÁRVA**

Az új A9 cella egy `_RecordingCanvas` teszt-duplát használ
(`test/core/design_system/icons/ss_icons_test.dart:12-53`), amely
`implements Canvas` és `noSuchMethod`-dal nyeli el a nem érdekes tagokat,
miközben rögzíti a `drawLine` / `drawPath` / `drawRRect` / `drawCircle` /
`drawArc` hívások `Paint` értékeit. A cella mind a 14 glyph-et lefesti
**három** szerződéses méreten (24 / 32 / 48 dp), és minden
`PaintingStyle.stroke` festésre megméri, hogy a
`strokeWidth / painter.strokeWidth` arány az engedélyezett halmazban
(`{1.0, 0.6}`) van-e. Emellett `isNotEmpty` cellával kizárja a semmit nem
festő painter-t is.

**Mért bizonyíték.** A review 1 PONTOSAN ugyanazt az injekcióját újra
lefuttattam a javított fán (`_paintCapo` → `strokeWidth = 7.5`):

```
00:00 +4 -1: guitar glyphs (A9) — every painted stroke derives from the shared ratio
             every recorded PaintingStyle.stroke draw call uses an allowed ratio
             of the shared stroke width [E]
00:00 +11 -1: Some tests failed.
```

Korábban ugyanez `+11: All tests passed!` volt. **A cella most falszifikál.**

A három méreten mérés lényegi: egy abszolút dp-érték legfeljebb EGY méreten
tudná véletlenül eltalálni valamelyik engedélyezett arányt, három méreten
nem. A `{1.0, 0.6}` halmaz a mai kód két valódi arányát rögzíti (a `0.6` a
hammer-on/pull-off szándékosan vékonyabb üreges hangjegyfeje,
`ss_guitar_glyphs.dart:179,205`) — a felvétele tehát a viselkedés
dokumentálása, nem a mérce lazítása: egy ÚJ arány felvétele szándékos,
látható teszt-módosítást kíván.

A §10 bizonyítatlan „szerkezetileg kizárt" mondata is javítva.

## F2 — MINOR → **LEZÁRVA**

Az A8 téma-cellái explicit címkéből kapják a nevüket
(`{'dark': …, 'light': …, 'highContrast': …}`), tehát a három futás neve
egyedi, és egy piros futásból kiderül, melyik téma bukott.

## F3 — MINOR → **LEZÁRVA**

Új cella: mind a 14 glyph rögzített rajz-hívás-sorozatát aláírássá fűzi, és
megköveteli, hogy a tizennégy aláírás **páronként különbözzön**.

**Mért bizonyíték.** A `fretboard` ágat ideiglenesen a `_paintCapo`-ra
irányítva:

```
00:00 +8 -1: guitar glyphs (A8) — … every glyph paints a draw-call sequence
             distinct from all others [E]
  two or more of the fourteen glyphs painted the exact same draw-call sequence
  — the gallery would render duplicate marks under different names
```

**A cella falszifikál.**

## F4 — NOTE

Változatlanul nyitva, szándékosan — nem ennek a körnek a dolga.

## Regressziós ellenőrzés

A javító kör a production kódhoz **nem nyúlt** (a diff két fájl: a teszt és a
brief §10), tehát a review 1-ben zöldnek talált A1–A7 cellák alapja
változatlan. A P2–P5 próbák eredménye ezért érvényben marad.

**Verdikt: APPROVED** — a merge a zöld kapu (exact-SHA `full-gate.yml` +
`router-ci.yml`) után mehet.
