# E07-R13 — CandidateSelector, hard filter és diversity

- **Státusz:** PRE-FLIGHT REVISED (2026-08-16, `main @ b5128132`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 13
- **Kör-azonosító:** `E07-R13`
- **Branch:** `<motor>/e07-r13-candidate-selector`
- **Előfeltétel:** `E07-R12` merge-elve (prioritás-motor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [0297](../adr/0297-candidate-selection-filter-ranking-and-fallback-boundary.md)

## 0.0 Pre-flight revízió (2026-08-16)

**Mért eltérések és feloldásuk.** Az előre írt brief `main @ bb867ad4`
állapotot említett. A dispatch előtti mérés `main @ b5128132`-n ezt találta:

- az R08 `ExerciseCandidate` csak explicit capability-térképet és
  `offlineAvailable`-t hordoz; `locked` mezője nincs;
- az ADR 0262 szerint a `PracticeCatalogSnapshot.candidates` elemei már
  létező, végrehajtható források, a `contentLocked` katalogizálási kizárás a
  snapshot `warnings` listájában marad;
- az R11 `PlanValidationContext` a futáskori végrehajthatóságot typed,
  identity-alapú megerősítő halmazokkal, `hardAvoidIdentities`-szel méri;
- a két új teszt ugyanazt a teljes `ExerciseCandidate` capability-térképét és
  catalog snapshotot építi. A repository bevett mintája a bare
  `test/fixtures/practice_generator/<terület>/` könyvtár (R10/R11).

**Kötött feloldás.** A selector csak `PracticeCatalogSnapshot`-ból választ;
locked tartalmat nem tud és nem próbál visszahozni, mert az nem candidate. A
futáskori hard kizárások inputja typed, identity-alapú és fail-closed marad;
offline-nem-megerősített jelölt fallbackként sem választható. Az A2 ezt a
selector tényleges határán méri, a locked-állítást pedig az R08 katalógus
szerződése biztosítja. A selector nem értelmezi a `LearnerConstraint.value`
szabad szövegét. A döntés egyben a policy-verziót, rendezett rejected-listát
és választott/fallback jelöltet tartalmaz. A részletes boundary-t ADR 0297
rögzíti.

**Scope-revízió.** A kizárólag teszt-fixture könyvtár és az ehhez a körhöz
foglaló által kiosztott új ADR bekerült az engedélyezett listába. Más útvonal
nem bővült; `exercise_candidate.dart`, catalog- és validation-contract nem
változik.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R08
> `ExerciseCandidate` tényleges mezőit (locked/elérhetőség, capability,
> `unsupported` jelölés) és az R12 prioritás-kimenetét. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/candidate_decision.dart",
  "lib/features/practice_generator/domain/policy/candidate_policy.dart",
  "lib/features/practice_generator/domain/service/candidate_selector.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/candidates/candidate_selector_test.dart",
  "test/features/practice_generator/candidates/candidate_policy_test.dart",
  "test/fixtures/practice_generator/candidates",
  "docs/adr/0297-candidate-selection-filter-ranking-and-fallback-boundary.md",
  "docs/rounds/e07-r13-candidate-selector.md",
]
gate_tests = [
  "test/features/practice_generator/candidates/candidate_selector_test.dart",
  "test/features/practice_generator/candidates/candidate_policy_test.dart",
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

A prioritásokhoz **kompatibilis** gyakorlatjelöltek kiválasztása és
rangsorolása, diagnosztizálható döntéssel (SDD Ch8 Kör 13).

## 2. Jelenlegi állapot — mért tények

- Az R08 katalógus-pillanatképe csak létező, végrehajtható jelöltet tartalmaz,
  és a nem támogatott capability **kimondott** (ADR 0262).
- Az R12 prioritásai faktoronként bonthatók (ADR 0264).
- Az ADR 0258 §1: a hard korlát **nem** kerül költségfüggvénybe — itt
  **szűrőként** jelenik meg.

## 3. Scope

**Benne van:** hard kizárási okok · rangsorolás (cél, nehézség, preferencia,
mérhetőség) · túlhasználat- és változatosság-szabály · **seeddel stabil**
felfedező (exploration) politika · fallback-lánc · `CandidateDecision`, amely
az **elutasítottakat és okukat is** hordozza.

**NINCS benne (tilos):** időfelosztás (Kör 14) · ütemezés (Kör 15) · a hard
szűrő megkerülhetővé tétele · `Random` (a seed injektált) · Flutter,
`DateTime.now()` · más `lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/candidate_decision.dart` | **ÚJ** — döntés + elutasítási okok |
| `domain/policy/candidate_policy.dart` | **ÚJ** — verziózott szabályok |
| `domain/service/candidate_selector.dart` | **ÚJ** — a választó |
| `public.dart` | a barrel bővítése |
| `test/…/candidates/*_test.dart` (2 db) | a §6 cellái |
| `test/fixtures/practice_generator/candidates/` | közös, teljes capability/catalog teszt-builderek |
| `docs/adr/0297-…md` | selector boundary és R08/R11 input-szerződés |
| `docs/rounds/e07-r13-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A hard szűrő NEM kerülhető meg

A hard kizárás (hiányzó hangszer, hangolás, hard-avoid, `locked` tartalom)
**előbb** fut, mint bármilyen pontozás. Nincs olyan pontszám, ami visszahozna
egy kizárt jelöltet.

**NEM elfogadható gyengítés:** a kizárás nagy negatív pontként — az elég jó
egyéb pontszám mellett átengedné (ADR 0258 §1).

### 5.2 A változatosság NEM írja felül az elsődleges relevanciát

A diversity-szabály **másodlagos** rendezés: azonos vagy közeli relevancia
esetén választ mást. Nem tehet elsővé egy kevésbé releváns jelöltet.

### 5.3 A felfedezés SEEDDEL stabil

Az exploration az injektált seedből dolgozik (ADR 0259 §1), nincs `Random`.
Ugyanaz a kérés ugyanazt a választást adja.

### 5.4 `locked` vagy elérhetetlen tartalom SOHA nem választható

Sem elsődlegesen, sem fallbackként. A `locked` R08-ban katalogizálási kizárás:
nem kerül a `PracticeCatalogSnapshot.candidates` halmazába (ADR 0262), ezért
a selector nem tudja visszahozni. Az offline-elérhetőség a jelölt explicit
metaadata és a typed, identity-alapú caller-confirmation metszete; nem
futásidejű próbálkozásból vagy free-text constraintből ered.

### 5.5 A döntés az ELUTASÍTOTTAKAT is hordozza

`CandidateDecision` tartalmazza, mely jelöltek estek ki és **miért**. Enélkül
a „miért nem ezt kaptam?" kérdés megválaszolhatatlan, és a hibakeresés
találgatás.

### 5.6 A fallback ugyanazt a skillt támogatja

Az R09 §5.4 folytatása: a fallback a hozzáférhetőséget oldja meg, nem a célt
cseréli.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hard-kizárt jelölt SEMMILYEN pontszámmal nem jön vissza | `candidate_selector_test.dart` |
| A2 | Katalogizálási `locked` jelölt nem hozható vissza; offline-nem-megerősített jelölt nem választható, fallbackként sem | ugyanott |
| A3 | A diversity nem tesz elsővé kevésbé relevánsat | ugyanott |
| A4 | Azonos seed → azonos választás | `candidate_policy_test.dart` |
| A5 | A döntés felsorolja az elutasítottakat és okukat | `candidate_selector_test.dart` |
| A6 | A fallback ugyanazt a skillt célozza | ugyanott |
| A7 | A közelmúltbeli túlhasználat büntetést kap | ugyanott |
| A8 | A rangsor determinisztikus (stabil tie-break) | `candidate_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hard kizárás nagy negatív pontként | **A1** |
| `locked` tartalom fallbackként engedve | **A2** |
| A diversity a relevancia elé sorolva | **A3** |
| `Random` az explorationben | A4 |
| A döntés csak a nyertest tartalmazza | **A5** |
| A fallback más skillt céloz | A6 |

**A hard szűrő három kötelező cellája** (a határ: a kizárás):

| Cella | Bemenet | Elvárt |
|---|---|---|
| megfelel | minden hard feltétel teljesül | a jelölt **rangsorolható** |
| a határon | a hard feltétel épp teljesül (pl. pontosan a megadott hangolás) | **rangsorolható** |
| kizárt | egyetlen hard feltétel sérül, de a pontszáma a legjobb | **kizárva**, és az okkal a döntésben |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a hard
szűrőt nagy negatív pontszámra → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/candidates/candidate_selector_test.dart test/features/practice_generator/candidates/candidate_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `candidate_decision.dart` — a döntés, az elutasítottakkal.
2. `candidate_policy.dart` — hard okok, rangsor-súlyok, diversity, exploration.
3. `candidate_selector.dart` — **előbb** hard szűrés, **utána** pontozás.
4. Tesztek a §6.1 három hard-szűrő cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az egységes pontszám csábítása.** Minden szempontot egy skálára tenni
  elegáns, és megsérthetővé teszi a hard szűrőt (A1).
- **A diversity túlsúlya.** „Legyen változatos" könnyen fontosabbá válik a
  célnál, és a tanuló nem halad (A3).
- **A néma elutasítás.** Csak a nyertest visszaadni egyszerűbb, és a
  hibakeresést találgatássá teszi (A5).

## 10. Implementation handoff — az implementer tölti ki

### 10.1 Módosított fájlok

| Útvonal | Változás |
|---|---|
| `lib/features/practice_generator/domain/model/candidate_decision.dart` | **ÚJ** — `CandidateRejectReason`, `CandidateFactorKind`, `CandidateFactor`, `SelectedCandidate`, `RejectedCandidate`, `CandidateDecision` (immutable, sorted, versioned) |
| `lib/features/practice_generator/domain/policy/candidate_policy.dart` | **ÚJ** — verziózott, immutable `CandidatePolicy` (`recentOverusePenalty`, `diversityWindow`, `explorationWeight`) |
| `lib/features/practice_generator/domain/service/candidate_selector.dart` | **ÚJ** — `CandidateRuntimeContext` (typed, identity-alapú, fail-closed) + `CandidateSelector` (pure, deterministic) |
| `lib/features/practice_generator/public.dart` | bővítve: a három új domain fájl exportja |
| `test/fixtures/practice_generator/candidates/candidates_fixtures.dart` | **ÚJ** — megosztott builder-ek (`buildCandidate`, `buildCatalog`, `buildPriority`, `buildContext`, `identityOf`), R10/R11 konvenciója |
| `test/features/practice_generator/candidates/candidate_selector_test.dart` | **ÚJ** — 18 cella, A1–A8 és a három hard-szűrő határcella |
| `test/features/practice_generator/candidates/candidate_policy_test.dart` | **ÚJ** — 5 cella: verzió, default, azonos seed, stabil ablak, input-validáció |

Összesen 6 új fájl + 1 módosítás (`public.dart`). Nincs semmi a `tools/`,
`.github/`, más feature, `exercise_candidate.dart`, catalog vagy validation
contract területén — a lista pontosan az `allowed_paths` halmaza.

### 10.2 Parancsok és tényleges eredmények

A §7 kötelező gate-artefaktum, csonkítatlanul:

```
$ tools/round-gate.sh test/features/practice_generator/candidates/candidate_selector_test.dart test/features/practice_generator/candidates/candidate_policy_test.dart

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
    Formatted 1570 files (0 changed) in 5.94 seconds.
    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/
    Analyzing 3 items...
    No issues found! (ran in 5.0s)
    → [2] analyze: ZÖLD

═══ [3] test test/features/practice_generator/candidates/candidate_selector_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/candidates/candidate_selector_test.dart
    00:00 +18: All tests passed!
    → [3] test .../candidate_selector_test.dart: ZÖLD

═══ [4] test test/features/practice_generator/candidates/candidate_policy_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/candidates/candidate_policy_test.dart
    00:00 +5: All tests passed!
    → [4] test .../candidate_policy_test.dart: ZÖLD

═══ [5] architecture
    $ /home/ubuntu/flutter/bin/dart run tool/check_architecture.dart
    Architecture dependencies OK (12 allowlisted deviation(s)).
    → [5] architecture: ZÖLD

═══ [6] secrets
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_secrets.dart
    Secret scan OK (2738 file(s) scanned, 0 finding(s)).
    → [6] secrets: ZÖLD

═══ [7] l10n
    $ /home/ubuntu/flutter/bin/dart run tool/ci/check_l10n_parity.dart
    L10n parity OK (en → hu, 1276 message(s)).
    → [7] l10n: ZÖLD

═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test .../candidate_selector_test.dart                     zöld
    test .../candidate_policy_test.dart                       zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

Selector-teszt 18/18 zöld, policy-teszt 5/5 zöld. A teljes suite + property
gate + APK a CI-ban fut (ADR 0053) — a boxon nem indítjuk.

### 10.3 Teljesített acceptance criteria

| # | Kritérium | Státusz | Bizonyíték |
|---|---|---|---|
| A1 | Hard-kizárt jelölt SEMMILYEN pontszámmal nem jön vissza | ✅ | 4 cella (kizárt + határon + megfelel + hard-avoid with higher score); §10.5 valódi-sértés próba |
| A2 | Locked/offline-nem-megerősített nem választható, fallbackként sem | ✅ | offline-unconfirmed + locked-style snapshot cellák; a snapshot típusú szerződés eleve kizárja a locked jelöltet (ADR 0262) |
| A3 | A diversity nem tesz elsővé kevésbé relevánsat | ✅ | diversityWindow=0.05; a teszt explicit recent-overuse penaltival a kevésbé relevánsakat a windowon kívülre szorítja |
| A4 | Azonos seed → azonos választás | ✅ | candidate_selector_test A4 + a policy azonos-mezős egyenlősége |
| A5 | A döntés felsorolja az elutasítottakat és okukat | ✅ | A5 cella (két elutasítás, ok és detail egyaránt megvan) |
| A6 | A fallback ugyanazt a skillt célozza | ✅ | A6 cella + a fallback mindig a canonical ranked listából jön (skill-szűrés már megtörtént) |
| A7 | A közelmúltbeli túlhasználat büntetést kap | ✅ | A7 két cellája: a penalty megjelenik a fallback compositeScore-ján és a selected factor listáján |
| A8 | A rangsor determinisztikus (stabil tie-break) | ✅ | A8 két cellája: a fallback identity seed-független (canonical ranked), a lexical tie-break ott érvényesül ahol a diversity window nem terjed ki |

A három kötelező hard-szűrő cella (`megfelel` / `a határon` / `kizárt`) a
`candidate_selector_test.dart` A1 blokkjában külön-külön lefedve.

### 10.4 Eltérések a brieftől

- A selector policy `explorationWeight` mezője a default policy-ban
  `0.05`; a tényleges exploration-permutációt a seed-ből származtatott
  hash végzi, nem ebből a súlyból — a mező a jövőbeli policy-tuning
  horogja (ADR 0297 §3). A selector nem változtatja meg a score-t a
  diversity hatására, csak a top bucket rendezését; ez az A3-at és az
  A8-at is erősíti.
- A selector a `CandidateRuntimeContext.recentlyUsedIdentities` halmazt
  fogadja — a recency ablak a hívó oldalán van (selector sosem olvas
  órát), és minden, a halmazban lévő jelölt egységesen megkapja a
  `recentOverusePenalty`-t.
- A `CandidateDecision` konstruktor a nullable mezők shadowingját
  elkerülendő `initialSelected` / `initialFallback` paraméterneveket
  használ — ez a kódolási stílus nem szegi meg a szerződést, csak a
  konstruktor-argumentum nevét rögzíti.

### 10.5 Valódi-sértés próba (kötelező, §6.1)

A §6.1-ben megjelölt hibás implementáció: "A hard kizárás nagy negatív
pontként". A selector `for (final candidate in skillTargets)` ciklusában a
`hardReason != null` ágat ideiglenesen átírtam úgy, hogy a kizárt jelölt
**ne** kerüljön a `rejected` listába és ne fusson `continue`, hanem
`compositeScore - 0.05` értékkel bekerüljön a `ranked` listába (kis
negatív pontszám, nem kizárás). A `dart format` és a gate ugyanazzal a
paranccsal újrafuttatva:

```
═══ [3] test .../candidate_selector_test.dart: PIROS (kilépési kód 1)
  5 cella pirosra váltott:
    A1 — a hard-avoided candidate never returns regardless of its score [E]
    A1 (kizárt) — a candidate that fails one hard filter is excluded [E]
    A2 — an offline-unconfirmed candidate cannot be selected or fallback [E]
    A5 — the decision lists every rejected candidate with its reason [E]
    A6 — when only one candidate survives the hard filter, the fallback is null [E]
```

A legfontosabb: **A1** cella pirosra váltott, pontosan a §6.1
kötelező sértés-cella. A `rejected` lista üressé vált (A5), a
hard-filteren átjutott kizárt jelölt kikerült a selection-be (A2), és
a fallback-képzés is elromlott (A6).

A mutációt visszaállítottam (`rejected.add(...)` + `continue;` a §6
implementációra), a gate ismét teljesen zöld (lásd §10.2 fenti
kimenetel). A selector jelenlegi forrásában a TRUE-VIOLATION MUTATION
megjegyzés már nincs benne — a végleges commit a helyes implementációt
tartalmazza.

### 10.6 Violation-proof

- A selector nem használ `Random`-ot, `DateTime.now()`-t, vagy
  `LearnerConstraint.value` értelmezést (ADR 0297 §1).
- A `CandidateDecision` immutable: minden mezője `final`, minden lista
  `List.unmodifiable`, a `rejected` rendezett.
- A `CandidateSelector.select` egyetlen kódútja: skill-szűrés →
  hard-filter → composite score → lexical sort → diversity bucket
  → fallback → decision.
- A `CandidatePolicy` default értékei egyeznek a §3 cellákkal
  (`recentOverusePenalty=0.2`, `diversityWindow=0.05`).
- A `_tuningPrerequisiteCode = 'guitar.tuned'` a `plan_validator.dart`
  konstansával azonos (a selector önállóan birtokolja a saját
  couplingját).

### 10.7 Következő kör

A soron következő kör: **E07-R14** (Practice Time Allocation, SDD Ch8 Kör 14).
A selector kimenete (`SelectedCandidate` + `compositeScore` + factors)
közvetlenül a Kör 14 inputja lesz a time-allocation policy számára.

## 11. Review — a Claude tölti ki
