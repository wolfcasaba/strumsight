# E15-R01 — független review (ADR 0055)

- **Reviewer:** Claude (Opus 5, orchestrátor-ülés) — read-only
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Ág:** `sonnet-impl/e15-r01-design-system-theme-adoption`
- **Reviewelt HEAD:** `901c9327`
- **Alap:** `7a46df1c` (pre-flight commit; a scope-audit bázisa)
- **Brief:** [`docs/rounds/e15-r01-design-system-theme-adoption.md`](../rounds/e15-r01-design-system-theme-adoption.md)
- **ADR:** [`0466`](../adr/0466-app-runtime-theme-is-the-design-system-theme.md)

## 1. A diff és a scope

```
docs/rounds/e15-r01-design-system-theme-adoption.md | 103 ++++++++
docs/ui/migration-status.md                        |  25 +-
lib/app/strumsight_app.dart                        |   8 +-
test/app/theme_adoption_test.dart                  | 195 +++++++++++++++
test/ui/goldens/e15_r01_theme_adoption_test.dart   | 266 +++++++++++++++++++++
5 files changed, 592 insertions(+), 5 deletions(-)
```

Mind az öt fájl a brief §4 engedélyezett listáján van; a gépi scope-audit két
futásban is `ok` (`scope_audit_base=7a46df1c…`, majd `5756204f…`). A tilos zóna
(`lib/features/**`, `lib/core/theme/**`, `test/ui/goldens/goldens/**`,
`docs/adr/**`, `tools/**`, `.github/**`) **érintetlen**. A
`lib/core/design_system/themes/ss_theme_extensions.dart` — a brief §0.0/R1 mért
előrejelzésének megfelelően — **nem változott**.

## 2. Amit a reviewer SAJÁT MAGA mért (izolált klón, read-only)

Klón: a `901c9327` friss másolata `/tmp`-ben, `prepare-flutter-generated.sh`
után. A próbák **eldobható** klónon futottak; a kör-ág változatlan.

### 2.1 Falszifikációs próba — A1 és A2

`lib/app/strumsight_app.dart` `theme:` ÉS `darkTheme:` visszaállítva
`AppTheme.light()`/`AppTheme.dark()`-ra, a tesztek érintetlenül:

```
Failing tests:
  test/app/theme_adoption_test.dart: A1: the running app theme carries all four design-system extensions, light and dark
  test/app/theme_adoption_test.dart: A2: a design-system component resolves tokens without a ThemeScope wrapper, under the app theme
```

Az A2 hibaüzenete a brief §0.0-ban megjósolt mechanizmust mutatja szó szerint:
`Null check operator used on a null value` — azaz a
`Theme.of(context).extension<SsColorScheme>()!` a `SsButton`-ban. **A cella
tehát valódi kapu, nem tautológia.**

### 2.2 Falszifikációs próba — A3

Ugyanabban a klónban a `BootstrapFailureApp` `theme:` sora is visszaállítva:

```
Failing tests:
  test/app/theme_adoption_test.dart: A3: the bootstrap-failure recovery screen also gets the design-system theme
```

### 2.3 Az implementer gate-jének VERIFIKÁLÁSA a nyers logból

A `/tmp/mm-e15-r01-resume.log`-ban a `tools/round-gate.sh` **előtérben**,
csővezeték nélkül futott (a `| tail -30` alakot a hook helyesen elutasította).
A záró futás gate-összegzése minden lépésre `zöld`:

```
format / analyze / test test/app/theme_adoption_test.dart /
test test/ui/goldens/e15_r01_theme_adoption_test.dart /
test test/accessibility/semantics_contract_test.dart /
test test/app/navigation/adaptive_scaffold_test.dart /
test test/core/design_system/foundations_test.dart /
test test/app/bootstrap_failure_app_test.dart / architecture … zöld
```

A valódi-sértés próba a logban is megvan: a `darkTheme:` visszaállítása után a
`[3] test test/app/theme_adoption_test.dart: PIROS (kilépési kód 1)`, majd
visszaállítás után újra zöld. **A §10 handoff állításai a nyers loggal
alátámasztottak** — nem bemondás.

### 2.4 A mátrix szerkezete

`test/ui/goldens/e15_r01_theme_adoption_test.dart`: 6 képernyő × 2 fényerő ×
2 locale × 2 szövegskála = **24** `testWidgets` cella, fix `Size(412, 915)`
viewporton. **Nincs** `skip`, **nincs** tolerancia, **nincs** kizárási lista —
a §5.5 / ADR 0466 D7 betartva. Minden cella két állítást tesz
(`otherErrors` üres, `overflowPx` null) `FlutterError.onError`-on át, nem a
renderelt kimenet szöveg-heurisztikáján.

## 3. Leletek

### MINOR-1 — nem létező ADR-döntésre hivatkozás (`D8`)

Két helyen `ADR 0466 D1–D4, **D8**` szerepel, az ADR viszont **D1–D7**-et
tartalmaz; `D8` nincs.

- `test/app/theme_adoption_test.dart:2`
- `docs/ui/migration-status.md:6`

Egy olvasó a nem létező döntést fogja keresni. Javítás: `D1–D4` (a hibaágra
külön a `D1`), a `D8` törlendő.

### MINOR-2 — a §10 handoff cellaszáma ellentmond a briefnek és a kódnak

`docs/rounds/e15-r01-design-system-theme-adoption.md:263`: „a mátrix mind a
**48** kombinációja (6 képernyő × 2 fényerő × 2 locale × 2 szövegskála)". A
szorzat **24**, a fájl 24 `testWidgets` cellát generál, és a brief §3/§6 is
24-et ír elő. Számtani elírás egy MÉRÉST állító mondatban.

### NOTE-1 — az A6 cella nem falszifikálható a saját kritériumára

Az A6 kritérium: „hány képernyő old fel tokent az app témájából". A cella
ténylegesen a `Directory('lib/features')` `*_screen.dart` fájljait számolja
(`== 96`). **Mérve (2.1):** a téma-bekötés VISSZAÁLLÍTÁSA után az A6 cella
**zöld maradt**. A cella tehát a dokumentum-szám konzisztenciáját pinneli, nem
a token-feloldást — az utóbbit az A1 és az A2 méri, és azok valódi kapuk. A
brief §6.1 mátrixa sem rendel hibás implementációt az A6-hoz, tehát ez nem
szerződésszegés, csak a cella erejének pontos rögzítése.

### NOTE-2 — a mátrix a téma-osztályt hívja, nem az app témáját olvassa

A `_pumpCell` `SsLightTheme.data()` / `SsDarkTheme.data()`-t épít, nem a
`StrumSightApp` által ténylegesen átadott `ThemeData`-t. Elfogadható: az A1
és az A8 pontosan azt pinneli, hogy az app ezt a két témát adja át, tehát a
lánc zárt. Ha egy későbbi kör a `MaterialApp` témáját máshonnan veszi, ez a
mátrix némán a régit mérné — az A1 viszont akkor pirosra vált.

### Nincs BLOCKER és nincs MAJOR.

## 4. Az acceptance-kritériumok teljesülése

| # | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | gate zöld; a reviewer 2.1 próbája pirosra vitte a helytelen implementáción |
| A2 | ✅ | gate zöld; 2.1 — `Null check operator used on a null value` |
| A3 | ✅ | gate zöld; 2.2 próba |
| A4 | ✅ | 24 cella, kizárás/`skip`/tolerancia nélkül (2.4); gate zöld |
| A5 | ✅ | `semantics_contract_test`, `adaptive_scaffold_test`, `foundations_test`, `bootstrap_failure_app_test` mind zöld a gate-ben |
| A6 | ⚠️ | a dokumentum frissült és a szám (96) egyezik; a cella ereje: NOTE-1 |
| A7 | ✅ | gate zöld (a legacy `colorScheme`/`textTheme`/`scaffoldBackgroundColor` egyenlőség) |
| A8 | ✅ | gate zöld; a barrel-import `show SsDarkTheme, SsLightTheme` alakban |

## 5. Verdikt

**CHANGES REQUESTED** — kizárólag a két MINOR miatt (nem létező `D8`
hivatkozás, `48` helyett `24`). Mindkettő a kör SAJÁT, még nem merge-elt
artefaktumában van, mindkettő szövegjavítás az engedélyezett fájlokon belül.

A javító kör után a review frissül, és a teljes CI-kapu (Full Gate + Router CI)
az ÚJ head SHA-n futtatandó újra (exact-SHA, ADR 0086 §2).

## 6. Frissítés a javító kör után

*(a javító kör után tölti ki a reviewer)*
