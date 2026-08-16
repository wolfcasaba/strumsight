# E07-R16 — Progression és regression policy

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 5cdd7472`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 16
- **Kör-azonosító:** `E07-R16`
- **Branch:** `<motor>/e07-r16-progression-policy`
- **Előfeltétel:** `E07-R15` merge-elve (heti ütemező)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0265`](../adr/0265-bounded-evidence-based-difficulty-adaptation.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R06
> `SkillEstimate` bizonytalanság-mezőjét és az R05 discomfort-mezőjét — a
> §5.3/§5.4 ezekre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/adaptation_decision.dart",
  "lib/features/practice_generator/domain/policy/progression_policy.dart",
  "lib/features/practice_generator/domain/service/adaptation_decider.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/adaptation/adaptation_decider_test.dart",
  "test/features/practice_generator/adaptation/progression_policy_test.dart",
  "test/fixtures/practice_generator/adaptation/",
  "docs/rounds/e07-r16-progression-policy.md",
]
gate_tests = [
  "test/features/practice_generator/adaptation/adaptation_decider_test.dart",
  "test/features/practice_generator/adaptation/progression_policy_test.dart",
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

Bizonyítékalapú, **korlátos** nehézségváltoztatás (SDD Ch8 Kör 16).

## 2. Jelenlegi állapot — mért tények

- Az R06 becslése hordozza a **bizonytalanságot** (ADR 0261 §3).
- Az R05 evidence-e külön mezőben hordozza a **discomfortot** (ADR 0260 §2).
- Az R09 receptjei korlátosak; a tempó csak támogatott jelöltnél él.

## 3. Scope

**Benne van:** minimum evidence- és bizonyosság-feltétel az emeléshez ·
tempó/hurok/variáció/szigorúság progresszió · „túl nehéz" és ismételt
küzdelem miatti regresszió · **cooldown** két emelés között · biztonsági és
discomfort-blokk · védelem egyetlen rossz session ellen.

**NINCS benne (tilos):** ismétlés-politika (Kör 17) · orchestrator (Kör 18) ·
több lépcsős ugrás · Flutter, `DateTime.now()`, `Random` · más
`lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/adaptation_decision.dart` | **ÚJ** — döntés + evidence-hivatkozás |
| `domain/policy/progression_policy.dart` | **ÚJ** — centralizált korlátok |
| `domain/service/adaptation_decider.dart` | **ÚJ** — a döntéshozó |
| `public.dart` | a barrel bővítése |
| `test/…/adaptation/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r16-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0265)

### 5.1 A korlátok CENTRALIZÁLTAK

Minden határ (maximális lépés, tempó-clamp, cooldown, minimum evidence) egy
helyen, a policyban. Szétszórt konstansok esetén a rendszer viselkedése
kiszámíthatatlanná válik.

### 5.2 EGY lépésnél többet nem lép

Egyetlen adaptáció legfeljebb egy nehézségi fokot mozdít. Több lépcsős ugrás
tilos, akkor is, ha az evidence „nagyon jó".

**NEM elfogadható gyengítés:** „kiemelkedő teljesítménynél két lépés". Az
evidence-ünk zajos; a cap az ADR 0261 §1 folytatása.

### 5.3 Discomfort és biztonság BLOKKOLJA az emelést

Ha a tanuló kényelmetlenséget jelzett, nincs nehezítés — függetlenül a
teljesítménytől. Ez felülírja a cél-fókuszt is (ADR 0264 §3).

### 5.4 EGY rossz session nem okoz regressziót

Az egyszeri gyenge eredmény zaj. A regresszióhoz **ismételt** küzdelem kell —
kivéve a kifejezett „túl nehéz" felhasználói visszajelzést, ami **azonnal**
érvényesül (§5.5).

### 5.5 A „túl nehéz" felhasználói jelzés GYORSAN hat

A tanuló explicit visszajelzése nem várja meg az evidence-küszöböt. Ez a
biztonsági szelep: aki azt mondja, hogy nehéz, annak könnyítünk.

### 5.6 Minden döntés EVIDENCE-hivatkozást tartalmaz

Az `AdaptationDecision` megnevezi, mely evidence alapján döntött. Enélkül a
változás magyarázhatatlan (ADR 0255).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Egyetlen adaptáció max EGY fokot lép | `adaptation_decider_test.dart` |
| A2 | Egy rossz session NEM okoz regressziót | ugyanott |
| A3 | Ismételt küzdelem regressziót okoz | ugyanott |
| A4 | Discomfort blokkolja az emelést, teljesítménytől függetlenül | ugyanott |
| A5 | A „túl nehéz" jelzés azonnal hat | ugyanott |
| A6 | A cooldown alatt nincs újabb emelés | `progression_policy_test.dart` |
| A7 | A tempó a támogatott tartományba van clampelve | ugyanott |
| A8 | Minden döntés evidence-hivatkozást hordoz | `adaptation_decider_test.dart` |
| A9 | A korlátok egy helyen, a policyban vannak | review + diff |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Két lépés „kiemelkedő" eredménynél | **A1** |
| Egy gyenge session után azonnali visszalépés | **A2** |
| Discomfort mellett is emel | **A4** |
| A „túl nehéz" jelzés az evidence-küszöbre vár | **A5** |
| Cooldown nélküli ismételt emelés | A6 |
| Tempó clamp nélkül | A7 |
| Döntés evidence-hivatkozás nélkül | A8 |

**Az evidence-mennyiség három kötelező cellája** (a határ: a minimum evidence az emeléshez):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | a minimumnál eggyel kevesebb sikeres session | **nincs** emelés |
| rajta (a küszöbön) | pontosan a minimum, elegendő bizonyossággal | **emelés** (a küszöb inkluzív) |
| a küszöb fölött | jóval a minimum fölött | emelés, de **csak egy** fokkal |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** engedj két fok
ugrást kiemelkedő evidence-nél → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/adaptation/adaptation_decider_test.dart test/features/practice_generator/adaptation/progression_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `progression_policy.dart` — minden korlát egy helyen.
2. `adaptation_decision.dart` — döntés + evidence-hivatkozás.
3. `adaptation_decider.dart` — küszöbök, cooldown, blokkolók.
4. Tesztek a §6.1 három evidence-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A „gyors haladás" csábítása.** Két lépés jobban érződik, és a zajos
  evidence miatt könnyen a tanuló fölé viszi a nehézséget (A1).
- **Az egyszeri rossz nap.** Azonnali visszalépés frusztráló és pontatlan (A2).
- **A discomfort felülbírálása teljesítménnyel.** „Jól ment, emeljünk" —
  miközben fáj. Ez a legkárosabb hiba az egész epicben (A4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
