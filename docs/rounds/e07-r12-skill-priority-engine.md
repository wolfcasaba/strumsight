# E07-R12 — SkillPriorityEngine és policy config

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ bb867ad4`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 12
- **Kör-azonosító:** `E07-R12`
- **Branch:** `<motor>/e07-r12-skill-priority-engine`
- **Előfeltétel:** `E07-R11` merge-elve (validátor + repair)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0264`](../adr/0264-explainable-priority-and-versioned-policy.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R06 tényleges
> `SkillEstimate` alakját — különösen az `unknown` állapot reprezentációját
> (ADR 0261 §2), mert a §5.2 erre épül. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/skill_priority.dart",
  "lib/features/practice_generator/domain/policy/priority_policy.dart",
  "lib/features/practice_generator/domain/service/priority_engine.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/priority/priority_engine_test.dart",
  "test/features/practice_generator/priority/priority_policy_test.dart",
  "docs/rounds/e07-r12-skill-priority-engine.md",
]
gate_tests = [
  "test/features/practice_generator/priority/priority_engine_test.dart",
  "test/features/practice_generator/priority/priority_policy_test.dart",
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

A célokból, evidence-ből és előfeltételekből **magyarázható** prioritási
sorrend (SDD Ch8 Kör 12).

## 2. Jelenlegi állapot — mért tények

- Az R06 `SkillEstimate`-je három megkülönböztethető állapotot ad: `unknown`,
  alacsony és magas bizonyosságú becslés (ADR 0261).
- Az R03 hard/soft korlátai (ADR 0258) a **szűrés** oldalán állnak, nem a
  rangsoroláson — a hard korlát sosem kerül költségfüggvénybe.
- A determinizmus kötelező (ADR 0255 §1), tehát a rendezés stabil kell legyen.

## 3. Scope

**Benne van:** normalizált prioritás-faktorok · előfeltétel-boost és
bizonytalanság-büntetés · lefedettségi adósság (coverage debt) · fáradás- és
újdonság-büntetés · **stabil holtverseny-feloldás** · **verziózott** policy
config · faktorokra bontható indoklás.

**NINCS benne (tilos):** jelölt-választás (Kör 13) · időfelosztás (Kör 14) ·
ütemezés (Kör 15) · a hard korlátok bevonása a pontszámba · Flutter,
`DateTime.now()`, `Random` · más `lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/skill_priority.dart` | **ÚJ** — prioritás + faktoronkénti indoklás |
| `domain/policy/priority_policy.dart` | **ÚJ** — verziózott súlyok |
| `domain/service/priority_engine.dart` | **ÚJ** — a rangsoroló |
| `public.dart` | a barrel bővítése |
| `test/…/priority/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r12-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0264)

### 5.1 Az indoklás FAKTORONKÉNT bontható, nem egy szám

Minden prioritás mellé jár a hozzájáruló faktorok listája, értékkel. Egyetlen
összesített pontszám nem magyarázható meg a felhasználónak (ADR 0255 célja).

**NEM elfogadható gyengítés:** utólag generált szöveges indoklás a pontszámból.
Az nem magyarázat, hanem racionalizálás.

### 5.2 Az `unknown` skill FELMÉRÉST kap, nem automatikus hiányt

Az ADR 0261 §2 folytatása: a nem mért készség nem „nagy hiány", hanem
**ismeretlen**. A prioritása felmérő jellegű gyakorlatot indokol, nem intenzív
drillt.

**NEM elfogadható gyengítés:** az `unknown` a legalacsonyabb becsléssel
egyenértékűként kezelve — az a legnagyobb prioritást adná neki.

### 5.3 Az elsődleges cél előnyt kap, de a BIZTONSÁG nem sérül

A `primary` cél emeli a kapcsolódó skillek prioritását — de a
kényelmetlenség/fájdalom jelzés (ADR 0260 §2) **felülírja**. A fókusz nem
nyomhatja el a biztonságot.

### 5.4 A holtverseny-feloldás STABIL és reprodukálható

Azonos pontszám esetén rögzített, determinisztikus kulcs dönt (nem
`hashCode`, nem beolvasási sorrend). Ugyanaz a bemenet ugyanazt a sorrendet
adja.

### 5.5 A policy VERZIÓZOTT, és a verzió a tervbe kerül

A súlyok verziószámmal rendelkeznek; a generált terv provenance-e rögzíti,
melyik verzióval készült. Enélkül egy súly-hangolás után nem lehet
megkülönböztetni a tanuló változását a policy változásától.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A prioritás faktoronként bontható, összegük a pontszám | `priority_engine_test.dart` |
| A2 | `unknown` skill felmérő prioritást kap, NEM maximálisat | ugyanott |
| A3 | Elsődleges cél emel, de a discomfort felülírja | ugyanott |
| A4 | Az előfeltétel-boost a függő skillt előre hozza | ugyanott |
| A5 | Magas bizonytalanság büntetést kap | ugyanott |
| A6 | A lefedettségi adósság idővel nő | ugyanott |
| A7 | Holtverseny → stabil, reprodukálható sorrend | `priority_policy_test.dart` |
| A8 | A policy verziója a kimenetben szerepel | ugyanott |
| A9 | Hard korlát NEM jelenik meg a pontszámban | `priority_engine_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egyetlen pontszám, utólagos szöveges indoklás | **A1** |
| `unknown` = legalacsonyabb becslés | **A2** |
| A primary cél a discomfortot is felülírja | **A3** |
| `hashCode`-alapú tie-break | A7 |
| A policy verzió nincs a kimenetben | A8 |
| A hard korlát nagy negatív súlyként a pontszámban | **A9** |

**A skill-állapot három kötelező cellája** (a határ: az `unknown`):

| Cella | Bemenet | Elvárt |
|---|---|---|
| ismert, erős | magas becslés, alacsony bizonytalanság | **alacsony** prioritás |
| a határon | `unknown` (nincs érvényes evidence) | **közepes, felmérő** prioritás — nem a legmagasabb |
| ismert, gyenge | alacsony becslés, alacsony bizonytalanság | **magas** prioritás |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld az `unknown`-t
`0.0` becslésként → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/priority/priority_engine_test.dart test/features/practice_generator/priority/priority_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `priority_policy.dart` — verziózott súlyok, normalizált faktorok.
2. `skill_priority.dart` — prioritás + faktoronkénti indoklás.
3. `priority_engine.dart` — a rangsorolás, stabil tie-breakkel.
4. Tesztek a §6.1 három skill-állapot cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az `unknown` mint maximális hiány.** A legkényelmesebb numerikus kezelés,
  és a rendszer a soha nem mért készséget tolná a tanuló elé (A2).
- **Az egy szám.** Egyszerűbb rangsorolni, és a „miért ezt gyakoroljam?"
  kérdés megválaszolhatatlan lesz (A1).
- **A hard korlát a pontszámban.** Elegánsnak tűnik egységesíteni, és
  megsérthetővé teszi a sérthetetlent (A9, ADR 0258 §1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
