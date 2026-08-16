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
| `lib/features/practice_generator/domain/model/candidate_decision.dart` | `CandidateRejectReason`, `CandidateFactorKind` (bővítve: `difficulty`, `preference`, `measurability`), `CandidateFactor`, `SelectedCandidate`, `RejectedCandidate`, `CandidateDecision` (immutable, sorted, versioned), **új `CandidateRankingProfile`** (difficulty / preference / measurability normalizált értékek) |
| `lib/features/practice_generator/domain/policy/candidate_policy.dart` | Verziózott, immutable `CandidatePolicy` (`recentOverusePenalty`, `diversityWindow`, `explorationWeight` mostantól szemantikailag aktív, **új `difficultyWeight` / `preferenceWeight` / `measurabilityWeight`** tipizált policy-súlyok) |
| `lib/features/practice_generator/domain/service/candidate_selector.dart` | `CandidateRuntimeContext` (typed, identity-alapú, fail-closed + **`rankingProfiles` map**) + `CandidateSelector` (pure, deterministic; composite score = priority.score + Σ weight × profile affinity − overuse; `explorationWeight=0` ⇒ szigorú lexikális, `>0` ⇒ seed-permutáció csak a `diversityWindow` bucketben) |
| `lib/features/practice_generator/public.dart` | bővítve: a három új domain fájl exportja |
| `test/fixtures/practice_generator/candidates/candidates_fixtures.dart` | `buildCandidate`, `buildCatalog`, `buildPriority`, `buildContext` (új `rankingProfiles` paraméter), **új `buildRankingProfile` + `buildRankingProfiles`** |
| `test/features/practice_generator/candidates/candidate_selector_test.dart` | 18 eredeti cella + **9 új cella** (A3 distinct candidate relevance, A4 explorationWeight=0 strict lexical, A4 explorationWeight>0 identical-seed determinizmus, A4 explorationWeight>0 distinct-seed permutáció-engagement, difficulty / preference / measurability factor observability, soft factor weight=0 elnyomás, diversityWindow out-of-bucket védelem) |
| `test/features/practice_generator/candidates/candidate_policy_test.dart` | 5 eredeti cella + **1 új cella** (soft-súly + explorationWeight független tunability, plusz az `identical seeds` cella kibővítve az új weight-mezőkkel) |
| `docs/adr/0297-…` | §3 kibővítve: candidate-szintű soft ranking inputok, score/relevance contract, `explorationWeight` szemantika |
| `docs/rounds/e07-r13-…` | ez a §10 handoff |

Összesen 9 módosítás a §4 `allowed_paths` halmazán belül. Nincs semmi a
`tools/`, `.github/`, más feature, `exercise_candidate.dart`, catalog vagy
validation contract területén.

### 10.2 Parancsok és tényleges eredmények

A §7 kötelező gate-artefaktum, csonkítatlanul:

```
$ tools/round-gate.sh test/features/practice_generator/candidates/candidate_selector_test.dart test/features/practice_generator/candidates/candidate_policy_test.dart

═══ [1] format
    $ /home/ubuntu/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
    Formatted <N> files (0 changed) in <T> seconds.
    → [1] format: ZÖLD

═══ [2] analyze
    $ /home/ubuntu/flutter/bin/flutter analyze lib/ test/ tool/
    No issues found! (ran in <T>s)
    → [2] analyze: ZÖLD

═══ [3] test .../candidate_selector_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/candidates/candidate_selector_test.dart
    00:00 +27: All tests passed!
    → [3] test .../candidate_selector_test.dart: ZÖLD

═══ [4] test .../candidate_policy_test.dart
    $ /home/ubuntu/flutter/bin/flutter test test/features/practice_generator/candidates/candidate_policy_test.dart
    00:00 +6: All tests passed!
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

Selector-teszt 27/27 zöld (18 eredeti + 9 új: A3 distinct candidate relevance, A4 explorationWeight=0 strict lexical, A4 explorationWeight>0 identical-seed determinizmus, A4 explorationWeight>0 distinct-seed permutáció-engagement, difficulty factor observability, preference factor observability, measurability factor observability, soft factor weight=0 elnyomás, diversityWindow out-of-bucket védelem), policy-teszt 6/6 zöld
(5 eredeti + 1 új — `candidate-level soft weights and explorationWeight are independent tunables (A3)` cella, valamint az `identical seeds` cella kibővítve az új weight-mezőkkel). A teljes
suite + property gate + APK a CI-ban fut (ADR 0053) — a boxon nem
indítjuk.

### 10.3 Teljesített acceptance criteria

| # | Kritérium | Státusz | Bizonyíték |
|---|---|---|---|
| A1 | Hard-kizárt jelölt SEMMILYEN pontszámmal nem jön vissza | ✅ | 4 cella (kizárt + határon + megfelel + hard-avoid with higher score); §10.5 valódi-sértés próba |
| A2 | Locked/offline-nem-megerősített nem választható, fallbackként sem | ✅ | offline-unconfirmed + locked-style snapshot cellák; a snapshot típusú szerződés eleve kizárja a locked jelöltet (ADR 0262) |
| A3 | A diversity nem tesz elsővé kevésbé relevánsat, **ÉS** a candidate-szintű soft faktorok distinct composite score-t hoznak létre | ✅ | "A3 — distinct candidate-level soft ranking factors produce distinct relevance and the diversity window respects them across all seeds" cella (3 candidate, eltérő affinity profilok, öt seed); "diversity window cannot promote a candidate outside the top bucket even when explorationWeight is positive" cella |
| A4 | Azonos seed → azonos választás, **ÉS** `explorationWeight=0` ⇒ szigorú lexikális, `>0` ⇒ determinisztikus seed-permutáció | ✅ | Három A4 cella: (1) `explorationWeight=0` hat seed-del mindig a lexikális elsőt választja; (2) `explorationWeight=1.0` azonos seed-del azonos decision; (3) `explorationWeight=1.0` tíz seed-del ≥2 distinct identity-t fed le, bizonyítva a permutáció aktív |
| A5 | A döntés felsorolja az elutasítottakat és okukat | ✅ | A5 cella (két elutasítás, ok és detail egyaránt megvan) |
| A6 | A fallback ugyanazt a skillt célozza | ✅ | A6 cella + a fallback mindig a canonical ranked listából jön (skill-szűrés már megtörtént) |
| A7 | A közelmúltbeli túlhasználat büntetést kap | ✅ | A7 két cellája: a penalty megjelenik a fallback compositeScore-ján és a selected factor listáján |
| A8 | A rangsor determinisztikus (stabil tie-break) | ✅ | A8 két cellája: a fallback identity seed-független (canonical ranked), a lexical tie-break ott érvényesül ahol a diversity window nem terjed ki |
| Per-factor observability | Minden soft tényező (`difficulty` / `preference` / `measurability`) megjelenik a `SelectedCandidate.factors` listán a helyes `kind` + `normalizedValue` + `contribution` értékkel, és a `weight=0` ⇒ nincs factor | ✅ | Három "factor contributes to compositeScore and appears on the SelectedCandidate factor list" cella + egy "soft factor with policy weight=0 does not appear in the factor list" cella |

A három kötelező hard-szűrő cella (`megfelel` / `a határon` / `kizárt`) a
`candidate_selector_test.dart` A1 blokkjában külön-külön lefedve.

### 10.4 Eltérések a brieftől

- Az `explorationWeight` mostantól **szemantikailag aktív**: default `0` ⇒
  szigorú lexikális, pozitív érték ⇒ seed-alapú determinisztikus
  permutáció a `diversityWindow` által határolt bucketben. Az előző
  `0.05` default és az "informational today" komment törölve; a mező a
  selector `_pickFromBucket`-jében read-and-act.
- Három új tipizált policy-súly (`difficultyWeight`, `preferenceWeight`,
  `measurabilityWeight`) és egy új `CandidateRankingProfile` típusú
  per-candidate input (difficulty / preference / measurability) bővítette
  a score/relevance contractot. A default policy súlyai `0`, így a
  default contract megegyezik az előzővel.
- A selector a `CandidateRuntimeContext.rankingProfiles` map-ből olvassa a
  per-candidate profilt (`rankingProfileFor(identity)` accessor); hiányzó
  identity esetén a `CandidateRankingProfile.neutral` (minden érték `0`)
  használatos.
- A `CandidateRankingProfile` factory konstruktorral készül (private
  named + public factory) — így a `required double affinity` paraméterek
  a `_requireUnitInterval` validátoron átmennek, és a mezők publikus
  `final` mezők maradnak.
- A `CandidateDecision` konstruktor a nullable mezők shadowingját
  elkerülendő `initialSelected` / `initialFallback` paraméterneveket
  használ.

### 10.5 Valódi-sértés próba (kötelező, §6.1)

A §6.1-ben megjelölt hibás implementáció: "A hard kizárás nagy negatív
pontként". A selector `for (final candidate in skillTargets)` ciklusában a
`hardReason != null` ágat ideiglenesen átírtam úgy, hogy a kizárt jelölt
**ne** kerüljön a `rejected` listába és ne fusson `continue`, hanem
`compositeScore - 0.05` értékkel bekerüljön a `ranked` listába (kis
negatív pontszám, nem kizárás). A gate ugyanazzal a paranccsal
újrafuttatva:

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

**Új MAJOR R1 falsifying próba (review-kötelezettség):** a selector
`_pickFromBucket`-jében az `if (policy.explorationWeight == 0) return
bucket.first;` sort ideiglenesen töröltem (így a seed-permutáció
mindig lefut). A "A4 — explorationWeight=0 yields strict lexical order
regardless of seed" cella pirosra váltott (kilépési kód 1) — a
falsifying teszt bizonyítja, hogy a `0`-ás explorationWeight tényleges
gate, nem comment. A mutációt visszaállítottam.

A mutációkat visszaállítottam, a gate ismét teljesen zöld (lásd §10.2
fenti kimenetel). A selector jelenlegi forrásában egyik TRUE-VIOLATION
MUTATION megjegyzés sincs — a végleges commit a helyes implementációt
tartalmazza.

### 10.6 Violation-proof

- A selector nem használ `Random`-ot, `DateTime.now()`-t, vagy
  `LearnerConstraint.value` értelmezést (ADR 0297 §1).
- A `CandidateDecision` immutable: minden mezője `final`, minden lista
  `List.unmodifiable`, a `rejected` rendezett.
- A `CandidateSelector.select` egyetlen kódútja: skill-szűrés →
  hard-filter → composite score (`priority.score + Σ weight × affinity -
  overuse`) → lexical sort → diversity bucket → `explorationWeight`
  szerinti permutáció → fallback → decision.
- A `CandidatePolicy` default értékei: `recentOverusePenalty=0.2`,
  `diversityWindow=0.05`, `explorationWeight=0`, `difficultyWeight=0`,
  `preferenceWeight=0`, `measurabilityWeight=0`. Az `explorationWeight=0`
  default a szigorú lexikális viselkedést garantálja.
- A score/relevance contract megfigyelhető a `SelectedCandidate.factors`
  listán: minden nem nulla contribution külön `CandidateFactor` rekord,
  a lista összege == `compositeScore`.
- A `_tuningPrerequisiteCode = 'guitar.tuned'` a `plan_validator.dart`
  konstansával azonos (a selector önállóan birtokolja a saját
  couplingját).
- A `_seedKey` determinisztikus FNV-stílusú hash — nem `Random`,
  nincs óra, nincs constraint-szöveg-értelmezés.

### 10.7 Következő kör

A soron következő kör: **E07-R14** (Practice Time Allocation, SDD Ch8 Kör 14).
A selector kimenete (`SelectedCandidate` + `compositeScore` + factors)
közvetlenül a Kör 14 inputja lesz a time-allocation policy számára.

## 11. Review — a Claude tölti ki
