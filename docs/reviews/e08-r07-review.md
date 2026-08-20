# E08-R07 — Review

Brief: `docs/rounds/e08-r07-level-curve-and-profile-projection.md`
Diff: `git diff be86e77e..e3a0eba0` (pre-flight base → implementer HEAD)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-20
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 2 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Görbe monoton: nagyobb XP soha nem ad kisebb szintet | ⚠️ Részleges | `level_curve_test.dart` "a greater total XP never maps to a lower level" zöld, DE csak azonos görbén, növekvő XP-n — ez a tulajdonság bármely helyes `progressForTotalXp`-re triviálisan igaz, a guard nélkül is. Lásd **F2**. |
| A2 | Teljes újraépítés = inkrementális projekció | ✅ | `level_curve_test.dart:36` "paged rebuild equals incremental projection" — 3 bejegyzés, `pageSize: 1` (3 lapon át), `expect(rebuilt.profile, incrementalProfile)` zöld. Független gate-futtatással megerősítve. |
| A3 | Egyetlen esemény több szintet is átléphet, mind megjelenik | ✅ | `level_curve_test.dart:59` — 650 XP egy eseményben → `crossedLevels` = `[2,3,4]`. Az implementer saját valódi-sértés próbája (§10) is dokumentálva: csak-végállapot verzió PIROSRA fogta. |
| A4 | Nagyon nagy XP-nél nincs túlcsordulás, nincs negatív szint | ✅ | `level_curve_test.dart:80` — `maximumSupportedTotalXp - 1` + 10 XP → szaturál `maximumSupportedTotalXp`-n, `_saturatingAdd` felül-túlcsordulás nélkül (kód olvasva: `remaining` előbb, `additional >= remaining` védi az összeadást). |
| A5 | Küszöbök egyetlen forrásból (`LevelCurve`) | ✅ | `LevelCurve` konstruktor kikényszeríti: level 1 = 0 XP-nél kezdődik, szigorúan növekvő küszöbök, konszekutív sorszámok. |
| A6 | Szintcímek lokalizációs kulcsok, nem beégetett szöveg | ✅ | `titleKey: String` mező, a kódbázis meglévő konvenciója (`practice/data/builtin_practice_catalog.dart`) szerint; teszt ellenőrzi `contains('.')`. |
| A7 | Profil verziózott, ismeretlen verzió hibát ad | ✅ | `gamificationProfileSchemaVersion`, konstruktor `ArgumentError` ismeretlen verzióra; teszt zöld. |
| A8 | Szint nem kapuz tartalmat, nincs `unlock`-kimenet | ❌ | A §6.1 által előírt gépi mérce (a forráskód regex-szkennelése) **hibás regex miatt soha nem talál semmit** — lásd **F1**. A tényleges forráskód ma valóban nem ad unlock-mezőt (kézi olvasással megerősítve), de ez bizonyítatlan marad. |

## Scope-audit

```
tools/scope-audit.py --repo <izolált klón> --brief docs/rounds/e08-r07-level-curve-and-profile-projection.md --base be86e77e
→ Legacy scope audit OK (be86e77e..e3a0eba0, 7 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A 7 megváltozott fájl pontosan
a brief §4 listája + a brief maga (§10 handoff-kitöltés).

## Megállapítások

### F1 — BLOCKER — `ProfileProjector.rebuild()` kivételt dob egy vadonatúj (üres) főkönyvön

- **Fájl:** `lib/features/gamification/application/profile_projector.dart:39-52` (a `do`/`while` lapozó ciklus, konkrétan a 49. sor `throw StateError`-ja)
- **Probléma:** a ciklus `do { … } while (cursor != null)` alakú, tehát a törzs
  MINDIG lefut legalább egyszer. Az első hívásnál `cursor == null`. Egy üres
  (vadonatúj felhasználó) főkönyvnél a `readPage(limit: …, cursor: null)`
  természetesen `nextCursor: null`-lal tér vissza — nincs mit lapozni. A ciklus
  ezt összekeveri a „a lapozás nem haladt" hibaeset jelével
  (`page.nextCursor == cursor`, itt `null == null` → igaz), és
  `StateError('ledger page cursor did not advance')`-ot dob, ahelyett hogy a
  kezdő (nulla XP-s) profilt adná vissza.
- **Hatás:** minden vadonatúj StrumSight-felhasználó — a brief §1 saját fő
  use case-e („a főkönyvből teljes egészében újraépíthető profil") — kivétellel
  állna meg, amint a profilját először építik újra a (még üres) főkönyvből.
  Ez nem szélsőséges eset, hanem a NULLADIK állapot minden telepítésnél.
- **Ellenőrzés (megerősítve, eldobható próbateszt, visszaállítva):** izolált
  klónban egy `_EmptyLedger implements RewardLedgerRepository` (mindig
  `RewardLedgerPage(entries: [], nextCursor: null)` ad) + `await
  projector.rebuild()` hívás → ténylegesen elszáll:
  ```
  Bad state: ledger page cursor did not advance
  package:strumsight/features/gamification/application/profile_projector.dart 49:9  ProfileProjector.rebuild
  ```
  A PRODUKCIÓS `LocalRewardLedgerRepository.readPage` forráskódját is
  ellenőriztem (`lib/features/gamification/data/local_reward_ledger_repository.dart`):
  üres `_entries`-nél ugyanígy `nextCursor: null`-t ad `cursor: null` bemenetre
  — a hiba a valódi implementáció ellen is reprodukálódik, nem csak a
  tesztdublőr ellen.
- **Kötelező javítás:** a stall-guard csak akkor jelezzen hibát, ha a lapon
  VOLT bejegyzés, de a cursor mégsem haladt (pl. `if (page.entries.isNotEmpty
  && page.nextCursor == cursor)`), vagy külön ágban kezelje az „első hívás,
  nulla bejegyzés" esetet a hurok elé/köré szervezve (pl. `while` a `do-while`
  helyett, vagy explicit `if (page.entries.isEmpty && cursor == null) return
  <initial projection>;`).
- **Ellenőrzés a javításhoz:** egy MEGTARTOTT (nem eldobott) teszt a
  `level_curve_test.dart`-ban: `rebuild()` egy ÜRES ledgeren → nem dob, és a
  visszaadott profil `totalXp == 0`, `currentLevel.number == 1`.
- **Státusz:** OPEN

### F2 — MAJOR — A1 (a kör központi invariánsa) nincs valódi teszttel védve: a lefelé-korrekció elleni guard törölhető anélkül, hogy bármelyik teszt pirosra váltana

- **Fájl:** `lib/features/gamification/application/profile_projector.dart:67-70`
- **Probléma:** a brief §5.1 és az ADR 0342 §2 kifejezetten, „NEM elfogadható
  gyengítés" jelöléssel emeli ki: a szint egy ÚJRASZÁMÍTÁS (pl. görbe-/policy-
  verzióváltás) után SEM csökkenhet egy már elért profilnál. Ezt a kódban a
  `curveProgress.currentLevel.number < profile.currentLevel.number ?
  profile.progress : curveProgress` ág valósítja meg — de ez az ág egyetlen
  meglévő teszt által sincs kikényszerítve. Az A1 teszt
  (`level_curve_test.dart:8`) rögzített görbén, monoton növekvő XP-n fut — ez a
  guard NÉLKÜL is triviálisan igaz, mert `curve.progressForTotalXp` önmagában
  monoton egy FIX görbén. Az „a changed curve changes projection…" teszt
  (`level_curve_test.dart:106`) a `projector.initialProfile`-ból indul,
  vagyis a profilt is az ÚJ görbével számolja — így a guard branch-ét (`<`)
  sosem éri el.
- **Hatás:** egy jövőbeli kör (pl. Kör 29 balance-szimuláció után egy
  policy-/görbe-verzió-váltás) szó szerint törölheti ezt a guard-ágat, és a
  teljes `level_curve_test.dart` suite zöld maradna — miközben pontosan az
  történne, amit az ADR 0342 „a termék legláthatóbb bizalomvesztéseként" ír le.
- **Ellenőrzés (megerősítve, eldobható próbateszt, visszaállítva):** izolált
  klónban a guard-sort ideiglenesen `final progress = curveProgress;`-re
  cseréltem (a guard-ág teljes törlése). `flutter test
  test/features/gamification/domain/level_curve_test.dart` → **mind a 10 teszt
  zöld maradt**. Visszaállítva (`git checkout --`).
- **Kötelező javítás:** egy MEGTARTOTT teszt, ami egy MEGLÉVŐ, magasabb szintű
  profilt egy MÁSIK (alacsonyabb küszöbű vagy máshogy súlyozott) görbével
  vetít tovább, és megköveteli, hogy a szint NE csökkenjen (pl.: profil A
  görbén szint 3-nál áll; ugyanazt a `totalXp`-t egy B görbével — ahol B
  szerint ez csak szint 2 lenne — `projectIncrementally`-vel továbbvetítve a
  szint marad 3, nem esik vissza 2-re).
- **Státusz:** OPEN

### F3 — MAJOR — A8 gépi mércéje (unlock-tiltás) hibás regex miatt soha nem talál semmit

- **Fájl:** `test/features/gamification/domain/level_curve_test.dart:178-191` (a `RegExp(r'\\bunlock\\w*\\b', caseSensitive: false)` sor)
- **Probléma:** a minta egy Dart RAW string (`r'…'`) BELSEJÉBEN dupla
  backslash-sel írja a `\b`/`\w` regex-metaszekvenciákat (`\\b`, `\\w`).
  Raw stringben a backslash NEM escape-elődik, tehát a ténylegesen átadott
  minta szó szerint két backslash karaktert tartalmaz `b`/`w` előtt — a
  compilelt regex ezért egy szó szerinti `\` karaktert keres a mintában, amit
  a forráskód soha nem tartalmaz. A teszt emiatt garantáltan zöld, függetlenül
  attól, mi áll a vizsgált fájlokban.
- **Ellenőrzés (megerősítve, eldobható próbaszkript):**
  ```dart
  final pattern = RegExp(r'\\bunlock\\w*\\b', caseSensitive: false);
  pattern.hasMatch('unlockedContent');                 // false
  pattern.hasMatch('this level does not unlock anything'); // false
  print(pattern.pattern); // \\bunlock\\w*\\b — a literális két-backslash minta
  ```
  Mindkét, egyértelműen tiltott mintát tartalmazó minta-szöveg `false`-t adott.
- **Hatás:** az A8 — az egyetlen ADR-abszolút tiltás (ADR 0289: az XP soha nem
  kapuz tartalmat) ezen a rétegen — gépi védelem NÉLKÜL marad. Élesben ma
  nincs sértés (kézi olvasással megerősítve: egyik új fájl sem tartalmaz
  `unlock`-mezőt), de egy jövőbeli regresszió észrevétlen maradna.
  Analóg korábbi lelet: `docs/LESSONS.md` L180 (egy fail-closed guard, ami a
  DEKLARÁLT alakot nézi a tényleges tartalom helyett, gyengébb védelmet ad,
  mint a neve sugallja).
- **Kötelező javítás:** `r'\bunlock\w*\b'` (egyszeres backslash a raw
  stringben) — vagy ugyanez explicit `RegExp('\\\\bunlock...')` nem-raw
  stringgel, de az egyszeres-backslash raw forma a konzisztens ezzel a
  kódbázissal.
- **Ellenőrzés a javításhoz:** a javított regex mellé egy MEGTARTOTT
  valódi-sértés próba: egy ideiglenesen bevezetett `unlockedContent`-jellegű
  mező a vizsgált fájlok egyikében pirosra kell váltsa a tesztet, majd
  visszaállítva zöld.
- **Státusz:** OPEN

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld (implementer log) | ✅ — saját futtatás izolált klónban: zöld (1702 fájl, 0 módosítás) |
| analyze | zöld (implementer log) | ✅ — saját futtatás: 0 issue |
| célzott teszt (`level_curve_test.dart`) | 10/10 zöld (implementer log) | ✅ — saját futtatás: 10/10 zöld (a mögöttes hiányosságok a fenti F1–F3 leletek, nem gate-piros) |
| architecture | zöld (implementer log) | ✅ — saját futtatás: OK, 12 allowlistelt eltérés (pre-existing, a scope-audit szerint ez a kör egyetlen fájlt sem ad az allowlisthez) |
| secrets | zöld (implementer log) | ✅ — saját futtatás: OK, 3016 fájl, 0 lelet |
| l10n | (nem jelentve az implementer log-ban) | ✅ — saját futtatás: OK (en/hu parity, 1405 üzenet) |
| CI (teljes suite + property + APK) | — | ⏳ még nem dispatch-elve — a merge előtti kötelező lépés, F1–F3 javítása UTÁN |

## Merge-döntés

Az ADR 0052 szerint minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR szükséges
a merge-hez. **F1 (BLOCKER) és F2/F3 (MAJOR) nyitva — merge TILOS.** Javító
kört indítok ugyanazzal a motorral (`codex`), a fenti három lelettel a
promptban, majd a javítás után újrafuttatom a teljes gate-mátrixot és
frissítem ezt a jelentést.
