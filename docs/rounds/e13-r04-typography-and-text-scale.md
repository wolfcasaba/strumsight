# E13-R04 — Tipográfia és text-scale resilience

- **Státusz:** IN PROGRESS (pre-flight folytatva: 2026-08-21, `main @ d5701b61`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 4
- **Kör-azonosító:** `E13-R04`
- **Branch:** `terra/e13-r04-typography-and-text-scale`
- **Előfeltétel:** `E13-R03` merge-elve (szemantikai színek)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0383` — a foglaló adta az E13-R04-nek.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd a Poppins és Montserrat
> **tényleges** asset-elérhetőségét (`pubspec.yaml` fonts szekció), mert a §5.1
> szerep-kiosztás erre épül. Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió — 2026-08-21

- A foglaló meglévő, atomi markere és a korábbi product pre-flight commitja
  az E13-R04-hez a `0383` számot rendeli; a kör döntéseit az
  [`ADR 0383`](../adr/0383-typography-and-text-scale-contract.md) rögzíti.
- A `pubspec.yaml:75-90` és a hat tényleges asset igazolja a Poppins
  400/500/600/700/800, valamint a Montserrat család elérhetőségét. A brief
  szerep-kiosztása emiatt változatlan.
- A tényleges theme-hívási lánc: `SsDarkTheme`/`SsLightTheme` először a
  `SsThemeExtensions.legacyThemeForBrightness` eredményét olvassa, majd a
  meglévő extensionöket megőrzi. A tipográfia a már engedélyezett
  `ss_theme_extensions.dart` fájlban mindhárom design-system témába beköthető.
- Nincs ma `ss_typography.dart`, chord-hero komponens vagy commitolt
  typography-teszt. A kör nem kezel állapotgépet vagy lifecycle-erőforrást,
  így a státusz-input és erőforrás-tulajdonlási mérés nem alkalmazandó.
- A kötelező, sorrendi **visszakeresett előzmény** vizsgálata megtörtént a szűkített
  `lessons,halts,adr`, majd `lessons,halts`, végül a teljes korpuszon. A
  közvetlen előzmény az [`ADR 0381`](../adr/0381-semantic-theme-and-accessibility-contract.md)
  theme-extension szerződése; a releváns falszifikációs precedensek
  [`lessons/L381`](../LESSONS.md) és [`lessons/L382`](../LESSONS.md). Az index
  egy committal elavult volt, ezért az újabb H3-heal tényét közvetlenül a
  verziózott [`lessons/L387`](../LESSONS.md) és a fenti §0.0.1 rögzíti.

> **Kockázat = high, indoklás:** a Stage Mode legfontosabb zenei jelének
> olvashatósága és a 200%-os accessibility text-scale termékhatár közvetlenül
> sérülhet clippinggel vagy ellipszissel. A magas kockázat accessibility és
> correctness eredetű, nem a router path-fragmentjeiből következik.

## 0.0.1 H3 scope-revízió — ADR 0112 önjavító kör, 2026-08-21

A megállt kör `54b32ed0` pre-flight commitja által lefoglalt ADR 0383 §D3
kötelezővé teszi, hogy az `SsTypography` a
`SsThemeExtensions.legacyThemeForBrightness` által visszaadott `ThemeData`
extensionjei közé kerüljön. A meglévő
`test/core/design_system/foundations_test.dart:41-50` ezzel szemben közvetlen
`equals(AppTheme.dark())` és `equals(AppTheme.light())` objektumegyenlőséget
vár. A helyes integráció ezért a teljes CI-ban ezt a már létező tesztet
szükségképpen pirosra vinné, miközben az eredeti brief nem engedte módosítani.

Ez B osztályú, tranzakciós brief-hiány, nem production- vagy gate-hiba. Az
allowlist és a célzott gate pontosan a
`test/core/design_system/foundations_test.dart` fájllal bővül. A product kör
ugyanabban a commitban köteles úgy frissíteni a kompatibilitási cellát, hogy a
legacy szín- és theme-forrásokra vonatkozó állítások megmaradjanak, miközben a
három design-system theme-ben ténylegesen ellenőrzi az `SsTypography`
extensiont. Más `test/core/design_system/**` út nem nyílik meg; a self-heal
production Dart-kódot nem visz előre.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_typography.dart",
  "lib/core/design_system/themes/ss_theme_extensions.dart",
  "lib/core/design_system/components/music/ss_chord_hero_text.dart",
  "lib/core/design_system/public.dart",
  "test/core/design_system/typography/ss_typography_test.dart",
  "test/core/design_system/typography/text_scale_overflow_test.dart",
  "test/core/design_system/foundations_test.dart",
  "docs/ui/typography.md",
  "docs/rounds/e13-r04-typography-and-text-scale.md",
]
gate_tests = [
  "test/core/design_system/typography/ss_typography_test.dart",
  "test/core/design_system/typography/text_scale_overflow_test.dart",
  "test/core/design_system/foundations_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Poppins/Montserrat alapú, **hozzáférhető** tipográfiai rendszer — clipping és
kézi `TextStyle`-duplikáció nélkül (SDD Ch13 Kör 4).

## 2. Jelenlegi állapot — mért tények

- Az R03 lezárta a szemantikai színeket; a tipográfia ugyanabba a
  `ThemeExtension`-rendszerbe illeszkedik.
- A Ch13 §9.4 megadja a teljes scale-t (`displayChord` 80/88 → adaptív max 128,
  `metricLarge` Montserrat 28/34 stb.) és a szabályokat: 200% text scale mellett
  **nincs clipping**, hosszú magyar szöveghez **≥30% tartalék**.

## 3. Scope

**Benne van:** a Ch13 scale implementációja · Poppins/Montserrat
szerep-kiosztás, `tabular figures` a metrikákhoz, ahol a font engedi · adaptív
`displayChord` méretező (viewport + text scale) · `maxLines`/overflow
irányelvek · **hosszú magyar** fixture-ök és 1.0 / 1.3 / 2.0 text-scale
tesztek · heading-hierarchia dokumentálása.

**NINCS benne (tilos):** geometria/felület (Kör 5) · motion (Kör 6) ·
`lib/features/**` · `lib/core/theme/**` · ad hoc `TextStyle` bevezetése ·
`docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_typography.dart` | **ÚJ** — a scale |
| `themes/ss_theme_extensions.dart` | a tipográfia bekötése |
| `components/music/ss_chord_hero_text.dart` | **ÚJ** — adaptív akkordnév |
| `public.dart` | az export bővítése |
| `test/…/typography/*_test.dart` (2) | a §6 cellái |
| `test/core/design_system/foundations_test.dart` | a legacy adapter és az új typography extension közös kompatibilitási cellája |
| `docs/ui/typography.md` | **ÚJ** — heading-hierarchia és használat |
| `docs/rounds/e13-r04-…md` | a §10 handoff |

**Tilos zóna:** `lib/core/theme/**` · `lib/features/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 Kötött szerep-kiosztás: Poppins tartalom, Montserrat mérőszám

A Ch13 §9.4 szerint. A metrikák (BPM, idő, százalék, timeline) Montserrat,
tabular figures-szel, hogy a számok ne ugráljanak frissítéskor.

### 5.2 200% text scale mellett NINCS clipping a kritikus komponensekben

Ez acceptance-cella (A1), nem törekvés. Fix magasságú sor a kritikus úton
tilos.

**NEM elfogadható gyengítés:** a szöveg méretének befagyasztása („úgyis
elfér"). Az a nagy betűméretet igénylő felhasználót zárja ki.

### 5.3 Az akkordnév ADAPTÍVAN skálázódik, nem ellipszálódik

Stage Mode-ban az akkordnév a legfontosabb információ. Hosszú név
(pl. `Cmaj7#11`) esetén **kisebb betű**, nem `…`.

**NEM elfogadható gyengítés:** `overflow: TextOverflow.ellipsis` az
akkordnéven. Az információt veszítene a legfontosabb elemen.

### 5.4 A mértékegység NEM válik le értelmetlenül

A `120 BPM` nem törhet úgy, hogy a `BPM` külön sorba kerül a szám elől.

### 5.5 Ad hoc `TextStyle` tilos

Minden szövegstílus a scale-ből jön. Az új komponensek nem definiálnak
sajátot.

### 5.6 A magyar szöveg 30% tartalékkal tesztelt

A Ch13 §9.4 mért szabálya: a magyar címek hosszabbak. A fixture-ök ezt
tükrözik.

### 5.7 Kötött integrációs szerződés

- Az `SsTypography` immutable `ThemeExtension`, a Chapter 13 §9.4 mind a
  tizenegy tokenjével.
- A design-system Dark Studio, Warm Light és High Contrast `ThemeData`
  eredményében a tipográfia ténylegesen lekérhető extensionként; puszta
  statikus style-katalógus nem elegendő.
- A metrika értékét és egységét a production API nem törő szóközzel kapcsolja
  össze; két, egymástól független `Text` widget nem elfogadható.
- A chord hero egyetlen teljes címkét renderel, a platform text scale-t
  megtartja, és csak helyhiánynál skáláz le. `ellipsis`, karakterlevágás vagy
  a text scale felülírása nem elfogadható.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | 200% text scale mellett nincs clipping a kritikus komponensekben | `text_scale_overflow_test.dart` |
| A2 | Az akkordnév skálázódik, NEM ellipszálódik | `ss_typography_test.dart` |
| A3 | A mértékegység nem válik le a számról | ugyanott |
| A4 | A metrika-stílus tabular figures-t kér, ahol elérhető | ugyanott |
| A5 | Hosszú magyar fixture 1.0 / 1.3 / 2.0 scale-en elfér | `text_scale_overflow_test.dart` |
| A6 | Nincs ad hoc `TextStyle` az új kódban | `grep` a diffben |
| A7 | A heading-hierarchia dokumentált és semantics-kompatibilis | `docs/ui/typography.md` |
| A8 | A legacy theme-források megmaradnak, és mindhárom design-system theme-ből lekérhető az `SsTypography` extension | `foundations_test.dart` + `ss_typography_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Fix magasságú sor a kritikus úton | **A1** |
| `ellipsis` az akkordnéven | **A2** |
| A szám és az egység külön `Text`-ben, tördelhetően | A3 |
| Proportional figures a metrikán | A4 |
| Csak angol fixture | A5 |
| Helyi `TextStyle(...)` a komponensben | A6 |

**A text scale három kötelező cellája** (a küszöb: a 2.0 skála):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 1.3 skála | minden elfér, nincs clipping |
| rajta (a küszöbön) | **2.0** skála | **elfér** — ez a kötelező felső határ |
| a küszöb fölött | 2.5 skála (platform-extrém) | **nem követelmény**, de nem omolhat össze |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** fagyaszd be az egyik
kritikus komponens magasságát → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/typography/ss_typography_test.dart test/core/design_system/typography/text_scale_overflow_test.dart test/core/design_system/foundations_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_typography.dart` — a Ch13 §9.4 scale-je.
2. A `ThemeExtension` bekötése.
3. A meglévő `foundations_test.dart` kompatibilitási cellájának tranzakciós
   frissítése: legacy forrásparitás + typography-extension regisztráció.
4. `ss_chord_hero_text.dart` — adaptív méretezés, ellipszis NÉLKÜL.
5. Hosszú magyar fixture-ök + a három text-scale cella.
6. `docs/ui/typography.md` — heading-hierarchia.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A fix magasság.** A layout stabilabbnak látszik tőle, és nagy
  betűméretnél kizárja a felhasználót (A1).
- **Az ellipszis az akkordnéven.** Kényelmes megoldás a túlcsordulásra, és
  pont a legfontosabb információt vágja le (A2).
- **Az angol-only fixture.** A magyar címek hosszabbak; a hiba csak
  lokalizált buildben látszik (A5).

## 10. Implementation handoff — az implementer tölti ki

### Implementáció

- `lib/core/design_system/foundations/ss_typography.dart`: az immutable,
  teljes Chapter 13 scale-t tartalmazó `ThemeExtension`, Poppins/Montserrat szerepekkel, tabular
  metric feature-rel, viewport-alapú chord design-size helperrel és nem törő
  metric label helperrel.
- `lib/core/design_system/themes/ss_theme_extensions.dart`: a legacy
  `AppTheme` adapter szín- és theme-forrásai változatlanok; a visszaadott
  `ThemeData` a meglévő extensionöket megőrizve kapja a közös typography
  extensiont. Dark Studio, Warm Light és High Contrast ezt az adaptert viszi
  tovább változatlan theme-builderrel.
- `lib/core/design_system/components/music/ss_chord_hero_text.dart`: egyetlen,
  teljes chord labelt renderel; platform text scale-t hagyja érvényesülni és
  csak a rendelkezésre álló szélességhez használ `BoxFit.scaleDown`-t. A
  külső `Semantics` kizárja a gyermek szemantikáját, így pontosan egy chord
  label marad a képernyőolvasónak.
- `lib/core/design_system/public.dart`: a typography és chord-hero public
  exportjai.
- `test/core/design_system/typography/*` és `foundations_test.dart`: token,
  font-feature, non-breaking metric label, theme-extension, 1.0/1.3/2.0/2.5
  Hungarian fixture és legacy-forrásparitás cellák.
- `docs/ui/typography.md`: token-hierarchia és heading-semantics használat.

### Futtatott bizonyíték

- RED: `flutter test test/core/design_system/typography/ss_typography_test.dart test/core/design_system/typography/text_scale_overflow_test.dart test/core/design_system/foundations_test.dart`
  az adapterbekötés előtt piros volt: mindhárom design-system theme-ből hiányzott
  az `SsTypography` extension.
- GREEN: `flutter test test/core/design_system/typography/ss_typography_test.dart test/core/design_system/typography/text_scale_overflow_test.dart test/core/design_system/foundations_test.dart`
  14 teszttel zöld volt az adapterbekötés után.
- Végső gate: `tools/round-gate.sh test/core/design_system/typography/ss_typography_test.dart test/core/design_system/typography/text_scale_overflow_test.dart test/core/design_system/foundations_test.dart`
  teljesen zöld volt a semantics javítás után: format 1768 fájl (0 változás),
  analyze 0 issue, typography 7/7, text-scale 5/5, foundations 3/3,
  architecture, secrets (3173 fájl / 0 lelet) és l10n (1532/1532) zöld.
- Valódi-sértés: az `SsChordHeroText` `FittedBox`-a köré ideiglenesen
  `SizedBox(height: 88)` került. A
  `flutter test test/core/design_system/typography/ss_typography_test.dart`
  célzott A1 cellája piros lett: `Expected: a value greater than <88.0>`,
  `Actual: <88.0>`. A fix magasságot azonnal eltávolítottuk.
- Review F1 RED: az exact semantics cella a javítás előtt piros volt:
  `Expected: 'Cmaj7#11'`, `Actual: 'Cmaj7#11\\nCmaj7#11'`.
- Review F1 GREEN: `flutter test
  test/core/design_system/typography/ss_typography_test.dart` a
  `excludeSemantics: true` javítás után 7 teszttel zöld.

## 11. Review — a Claude tölti ki
