# E99-R01 (GOV-05a) — kör-review

- **Dátum:** 2026-08-09
- **Reviewer:** Claude (Opus 5), orchesztrátor — READ-ONLY review
- **Implementer:** Codex (Terra, `gpt-5.6-terra`) — 1 implementációs forduló
  + 1 javító forduló (`stopped` feloldása)
- **Branch:** `codex/e99-r01-gov-05a-practice-and-song-trainer-shipping-rollout`
- **Diff:** `bb8b91c4...9b31544b` — 9 fájl, +499 / −60
- **Verdikt:** ✅ **APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR (a brief hibája,
  nem a kódé, utólag mérve zöld), 3 NOTE

## 1. Scope-audit

A diff **pontosan** a kilenc engedélyezett útvonalat érinti (nyolc az eredeti
listából + a `continue_card_test.dart`, amit a §0.0 R1 revízió nyitott meg).
Nulla listán kívüli fájl, nulla új fájl.

```
docs/manual-testing/practice-engine-device-matrix.md            |  41 +++--
docs/rounds/e99-r01-gov-05a-...-shipping-rollout.md             | 194 +++++++-
lib/app/config/feature_flags.dart                               |  16 +-
lib/features/learn/screens/lesson_list_screen.dart              |  55 ++++
lib/features/practice/presentation/practice_effect_listener.dart|   6 +-
test/app/feature_flags_test.dart                                |  43 +++
test/features/learn/continue_card_test.dart                     |  25 ++-
test/features/learn/lesson_list_screen_test.dart                | 155 +++++-
test/features/song_trainer/baseline/legacy_fixture_parity_test.dart | 24 ++-
```

**Kiemelendő pozitívum:** az implementer az első fordulóban `stopped`-dal
jelzett, amikor a flag-flip egy listán kívüli tesztet pirosra váltott — nem
tágította magától a listát, és nem lazította a mércét. Ez az OD-05 politika
pontos alkalmazása.

## 2. A reviewer SAJÁT mérései (izolált `/tmp/review-E99-R01` klón)

A klón a pushed branchről készült, `flutter pub get` +
`prepare-flutter-generated.sh` után.

### 2.1 Független gate-újrafuttatás

```
tools/round-gate.sh test/app test/features/learn test/features/song_trainer/baseline \
  test/features/auth test/features/settings test/features/vision/vision_offline_regression_test.dart
```

**Mind a 11 lépés ZÖLD** (exit 0): format, analyze, hat külön tesztútvonal,
architecture (12 allowlisted eltérés — **változatlan**, a kör nem adott hozzá),
secrets (2086 fájl, 0 lelet), l10n paritás (en → hu, 1019 üzenet).

### 2.2 Valódi-sértés próba 1 — a flag-határ mércéje

A factory `songTrainerV2Enabled: nonProd` sorát ideiglenesen `true`-ra írtam:

```
Failing tests:
  test/app/feature_flags_test.dart: Song Trainer V2 rollout boundary remains disabled in production
  test/features/song_trainer/baseline/legacy_fixture_parity_test.dart:
    E03-R01 rollout guard songTrainerV2Enabled remains off in production
      Expected: false
        Actual: <true>
      the production rollout boundary must remain closed
```

**Pontosan az a két cella lett piros, amit a brief §6.1 megjósolt** — az A1
production cellája és az átirányított A3 őr. A mérce mér. Visszaállítva.

### 2.3 Valódi-sértés próba 2 — a flagenkénti külön feltétel mércéje

A két külön `if`-et összevont `practiceEngineV2Enabled || songTrainerV2Enabled`
predikátumra cseréltem:

```
Failing tests:
  test/features/learn/lesson_list_screen_test.dart: V2 entries follow practice=false, songTrainer=true
  test/features/learn/lesson_list_screen_test.dart: V2 entries follow practice=true, songTrainer=false
```

**A két középső cella pirosodott, a két szélső zöld maradt** — pontosan a §6.1
sora szerint. Az összevont predikátum tehát nem tudna átcsúszni. Visszaállítva.

### 2.4 A gate-en KÍVÜLI érintett teszt (MINOR-1 mérése)

```
flutter test test/core/screen_size_guard_test.dart  →  +45: All tests passed!
```

Beleértve a landscape (915×412) és a kis kijelzős cellákat, azaz a két új
kártya nem okoz overflow-regressziót.

## 3. Acceptance-teljesülés

| Pont | Verdikt | A reviewer bizonyítéka |
|---|---|---|
| A1 három környezet-cella | ✅ | három **külön** `test()`, nem ciklus; a production cellát a 2.2 próba pirosra váltotta |
| A2 default konstruktor | ✅ | a teszt szó szerint érintetlen a diffben |
| A3 őr átirányítva, nem törölve | ✅ | a `group('E03-R01 rollout guard')` megvan, production-`expect`-tel, `skip` nélkül; 2.2 próba pirosra váltotta |
| A4 kerítés a többi flagre | ✅ | `aiTutor*`, `migratedLearn`, `visionEnabled` mind a három környezetben `false` |
| A5 2×2 mátrix | ✅ | négy külön teszt, `find.byKey`; 2.3 próba a két középső cellát pirosra váltotta |
| A6 valódi navigáció | ✅ | valódi `GoRouter`, `router.state.uri.path` mindkét útvonalra külön |
| A7 production factory | ✅ | külön teszt a factory production-kimenetén, mindkét kulcs `findsNothing` |
| A8 nincs új ARB-kulcs | ✅ | a diff `lib/l10n/` alatt nulla fájlt érint; l10n-paritás zöld (1019 üzenet) |
| A9 avult állítások javítva | ✅ | a `practice_effect_listener.dart` doc-commentje és a device-mátrix figyelmeztetése is a mért valóságot írja |
| A10 gate zöld | ✅ | a reviewer saját, független futása (2.1), csővezeték nélkül |
| A11 `continue_card_test` kikötés | ✅ | a diff kizárólag importot + `_flags`/`_config` segédet + a `_pump` override-ot érint; a `findsNWidgets(2)` és a `reason:` szó szerint változatlan |

## 4. Leletek

### MINOR-1 — a brief `gate_tests` listája hiányos volt (orchesztrátor-hiba)

`test/core/screen_size_guard_test.dart` **pumpolja** a `LessonListScreen`-t, és
pontosan az a fajta teszt, amit egy lista tetejére kerülő UI-elem eltörhet
(overflow kis kijelzőn és landscape-ben). A brief `gate_tests` listájából
mégis kimaradt, mert a felmérést a `FeatureFlags.forEnvironment` hívóira
futtattam, nem a `LessonListScreen` pumpolóira — **két különböző sugár, és én
csak az egyiket mértem**.

Ez **nem az implementáció hibája**, és utólag mérve zöld (§2.4), tehát nem
blokkol. Tanulságként rögzítendő: ha egy kör egy *képernyőt* módosít, a
felmérés a képernyő **összes** teszt-pumpolójára is menjen, ne csak a
módosított *adatforrás* hívóira.

A hiány gyakorlati hatását a CI teljes suite-ja amúgy is lefedi — de a
brief-oldali mérce hiányossága akkor is valós, ha a védőháló megfogta volna.

### NOTE-1 — két dal-könyvtár egymás mellett

A Learn fülön most a legacy „Dalaim" ikon (`/songs`) és az új Song Trainer
kártya (`/song-trainer`) egyszerre él. Tudatosan vállalt (ADR 0197 Döntés 4,
OD-01), de a készülékes menet első visszajelzése valószínűleg ez lesz.
Follow-up: információs-architektúra kör.

### NOTE-2 — a belépési kártyáknak nincs explicit `Semantics` címkéjük

A `_V2EntryCard` `ListTile`-je a `title: Text(...)` révén felolvasható, tehát
funkcionálisan rendben van. A device-mátrix 2.8.4 TalkBack sora ezt úgyis
ellenőrizteti a userrel. Nem blokkoló; ha a menet gyenge felolvasást mutat,
egy explicit `Semantics` label a következő UI-kör olcsó javítása.

### NOTE-3 — a kártyák a `development` buildben is megjelennek

Szándékos (ADR 0197 Következmények): a `nonProd` a projekt bevett
rollout-alakja. Következmény, amit érdemes fejben tartani: minden fejlesztői
és CI dev-build mostantól mutatja a két belépési pontot.

## 5. Merge-döntés

Minden acceptance-pont teljesül, a scope sértetlen, a mérce két független
próbán bizonyítottan mér, a gate a reviewer saját izolált klónjában is zöld.
**A merge a zöld CI-kapu (Build APK + Router CI, exact SHA) mellett
engedélyezett.**

A készülékes bizonyíték (device-mátrix §2.2 és §2.9 PENDING sorai) **nem
merge-kapu** — az Epic 5 óta követett gyakorlat szerint azt a user tölti ki.
