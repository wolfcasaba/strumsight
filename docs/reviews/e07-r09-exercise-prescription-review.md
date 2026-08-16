# E07-R09 — Review

Brief: `docs/rounds/e07-r09-exercise-prescription.md`  
Diff: `75b0cb36...de0efd35`  
Reviewer: Codex / GPT-5.6 Terra · Dátum: 2026-08-16  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 3 · MINOR: 0 · NOTE: 1

Az izolált reviewer-gate és a scope-audit zöld, de három eldobható,
shipping-kontraktusra célzott próbateszt piros: a recipe candidate-tartományon
kívüli időt, eltérő serializált identity-t és törtszámú countot fogad el.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Bounded repetition | ✅ | 9/10/11 cellák zöldek; A1 mutation is piros volt. |
| A2 | Tempo csak supported candidate-nél | ✅ | Célzott teszt és reviewer gate. |
| A3 | Mérhető criteria | ✅ | Explicit, nem üres capability-set + unsupported elutasítás. |
| A4 | Fallback skill-kompatibilitás | ✅ | Halmazegyezés tesztelt. |
| A5 | Explicit criteria | ✅ | Hiányzó/üres capability-set elutasított. |
| A6 | Veszteségmentes JSON round-trip | ❌ | F2, F3. |
| A7 | Hard időkorlát | ❌ | F1: candidate duration-bound nélkül érvényes recipe készül. |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e07-r09-impl --brief
/tmp/review-e07-r09-impl/docs/rounds/e07-r09-exercise-prescription.md --base
75b0cb369daec0db4642eca3a1fa80518dc45477` → **OK**, 7 changed path, 0
generated/ignored.

## Megállapítások

### F1 — MAJOR — A recipe nem tartja be a candidate duration-boundját

- **Fájl:** `lib/features/practice_generator/domain/model/exercise_prescription.dart:~190-225`
- **Probléma:** A konstruktor csak a saját `hardElapsedLimit` mezőt ellenőrzi,
  az `activeDuration` nem kerül a primary candidate
  `supportedDurations.minimum..maximum` inkluzív tartományába.
- **Hatás:** Egy 10–20 perces candidate mellé 5 perces, érvényesnek látszó
  recept készülhet; sérül a Ch8 duration-bounds contract.
- **Bizonyíték:** A reviewer-probe 10–20 perces candidate és 5 perces
  `activeDuration` mellett `throwsArgumentError`-t várt; a kód recipe-t adott.
- **Kötelező javítás:** Candidate-bound validáció konstrukcióban és `fromJson`
  újravalidációban; minimum alatt / minimumon / maximumon / maximum fölött
  regressziós cellák.
- **Státusz:** OPEN

### F2 — MAJOR — A decoder csendben más candidate-re írja át a receptet

- **Fájl:** `lib/features/practice_generator/domain/model/exercise_prescription.dart:~286-365`
- **Probléma:** A JSON `exerciseId`, `source`, `skillTargets` mezői nem
  kerülnek összevetésre a supplied candidate-tel; `contentRevision` nem is
  persisted. A fallback JSON-t is csak típusként vizsgálja, majd a hívói
  candidate-listából épít új referenciát.
- **Hatás:** Sérült vagy eltérő recipe kontrollált hiba helyett némán a hívó
  candidate-jére változik; ez nem veszteségmentes A6, és elveszti az ADR 0262
  revisioned executable identity-jét.
- **Bizonyíték:** A reviewer `exerciseId=exercise.other`, `source=legacyLesson`,
  `skillTargets=[other.skill]` manipulációra `throwsArgumentError`-t várt; a
  decoder sikerrel a primary candidate adatait adta vissza.
- **Kötelező javítás:** Persistáld a teljes stabil candidate-identity-t,
  beleértve `contentRevision`-t; dekódoláskor minden primary- és fallback-
  referencia pontos egyezését követeld meg, eltérés/hiány esetén `ArgumentError`.
- **Státusz:** OPEN

### F3 — MAJOR — A fractional JSON-count csendes kerekítése megváltoztatja a receptet

- **Fájl:** `exercise_prescription.dart:~35-70, ~335-365`; `progression_rule.dart:~55-82`
- **Probléma:** A JSON számlálók `num.round()` után kerülnek a konstruktorokba.
  Így `loopCount: 1.9` némán `2` lesz (ugyanez a repetition és progression
  delta útjain).
- **Hatás:** Tárolt recipe jelentése kontrollált korrupcióhiba nélkül változik;
  sérül a count-kontraktus és A6.
- **Bizonyíték:** A reviewer `loopCount: 1.9` értékre `throwsArgumentError`-t
  várt; a decoder `loopCount == 2` recipe-t adott.
- **Kötelező javítás:** Count/delta/microsecond mező csak pontos egész
  JSON-szám lehet; nincs `.round()` fallback. Minden érintett decoder kapjon
  fractional-elutasítás tesztet.
- **Státusz:** OPEN

### N1 — NOTE — A wrapper gate-shape lelete script-olvasásból jött

Az implementer `gate_shape=VIOLATION` mezője a `cat tools/round-gate.sh | head
-40` script-olvasásra illeszkedő regex eredménye, nem a gate pipe-os futtatása.
A reviewer valódi gate-je pipe nélkül zöld. Javító körben ne használj a
`round-gate.sh` nevét tartalmazó csővezetéket.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzött eredmény |
|---|---|
| scope-audit | ✅ 7 engedélyezett változás |
| format | ✅ |
| analyze | ✅ |
| célzott tesztek | ✅ 24 + 16 |
| architecture | ✅ |
| secrets + l10n | ✅ |
| content probes | ❌ F1, F2, F3 |
| CI | még nem dispatch-elt — nyitott MAJOR miatt tiltott |

## Merge-döntés

Merge **tilos**, amíg F1–F3 nyitott. A javító kör ugyanazzal a `sonnet-impl`
motorral fusson; utána új izolált review, gate és CI szükséges.
