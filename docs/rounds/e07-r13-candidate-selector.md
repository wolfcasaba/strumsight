# E07-R13 — CandidateSelector, hard filter és diversity

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ bb867ad4`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 13
- **Kör-azonosító:** `E07-R13`
- **Branch:** `<motor>/e07-r13-candidate-selector`
- **Előfeltétel:** `E07-R12` merge-elve (prioritás-motor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0258 (hard korlát),
  0262 (jelölt-igazság) és 0264 (magyarázhatóság) rögzíti.

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

Sem elsődlegesen, sem fallbackként. Az offline-elérhetőség az R08 metaadatából
jön (ADR 0262 §5), nem futásidejű próbálkozásból.

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
| A2 | `locked`/elérhetetlen tartalom nem választható, fallbackként sem | ugyanott |
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

## 11. Review — a Claude tölti ki
