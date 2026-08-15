# E07-R27 — Missed day, catch-up, pause és returning flow

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 0afb9994`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 27
- **Kör-azonosító:** `E07-R27`
- **Branch:** `<motor>/e07-r27-missed-day-and-pause`
- **Előfeltétel:** `E07-R26` merge-elve (eredmény-feldolgozás)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0269`](../adr/0269-non-punitive-missed-day-handling.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R15 pihenőnap-
> jelölését és az R22 „ma"-számítását (helyi dátum, injektált óra).
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/policy/missed_day_policy.dart",
  "lib/features/practice_generator/application/usecase/pause_practice_plan.dart",
  "lib/features/practice_generator/application/usecase/resume_practice_plan.dart",
  "lib/features/practice_generator/presentation/widgets/catch_up_sheet.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/continuity/missed_day_policy_test.dart",
  "test/features/practice_generator/continuity/pause_resume_test.dart",
  "docs/rounds/e07-r27-missed-day-and-pause.md",
]
gate_tests = [
  "test/features/practice_generator/continuity/missed_day_policy_test.dart",
  "test/features/practice_generator/continuity/pause_resume_test.dart",
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

**Nem büntető** tervfolytatás kihagyás, szünet és hosszabb visszatérés után
(SDD Ch8 Kör 27).

## 2. Jelenlegi állapot — mért tények

- Az R15 megkülönbözteti a **pihenőnapot** a kihagyott naptól.
- Az R22 „ma"-ja helyi dátumból, injektált órával számol (ADR 0258 §4).
- Az R14 napi kerete hard maximummal korlátos (ADR 0258 §3).

## 3. Scope

**Benne van:** kihagyott-nap politika opciói · a következő napi keret
**megduplázásának tilalma** · „csak az elsődleges" újraütemezés · szünet/
folytatás dátum-korrekcióval · hosszabb szünet után **készültségi**
terv-javaslat · időzóna-váltás kezelése.

**NINCS benne (tilos):** backlog képzése · a hard napi maximum túllépése ·
szégyenítő szövegezés · flag `true`-ra állítása · `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/policy/missed_day_policy.dart` | **ÚJ** |
| `application/usecase/pause_practice_plan.dart` | **ÚJ** |
| `application/usecase/resume_practice_plan.dart` | **ÚJ** |
| `presentation/widgets/catch_up_sheet.dart` | **ÚJ** |
| `lib/l10n/app_en.arb`, `app_hu.arb` | a szövegek |
| `public.dart` | a barrel bővítése |
| `test/…/continuity/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r27-…md` | a §10 handoff |

**Tilos zóna:** a generátor többi rétege · más `lib/features/**` ·
`lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**`.

## 5. Kötött architekturális döntések (ADR 0269)

### 5.1 A kihagyott nap NEM duplázza a következőt

A kimaradt gyakorlás nem tolódik át tételesen. A következő nap kerete
változatlan marad (ADR 0258 §3).

**NEM elfogadható gyengítés:** „csak ma egy kicsit több". Ez a
backlog-spirál kezdete: a lemaradás nő, a tanuló feladja.

### 5.2 A pihenőnap NEM mulasztás

Az R15 jelölése szerinti pihenőnap teljesített állapot.

### 5.3 Szünet alatt NEM keletkezik lemaradás

A szüneteltetett terv nem termel „kihagyott" napokat. A folytatás **új
revíziót** hoz létre, korrigált dátumokkal (ADR 0256).

### 5.4 Hosszabb szünet után KÉSZÜLTSÉGI javaslat, nem folytatás ott, ahol abbahagytuk

Több hét kihagyás után a rendszer nem a régi nehézséggel folytat, hanem
felmérő/ráhangoló tervet javasol — az `unknown` elvének (ADR 0261 §2)
időbeli megfelelője: a régi becslés elavult.

### 5.5 A szövegezés NEM szégyenítő

Se „elmulasztottad", se „lemaradtál" hangvétel. A copy tényszerű és
folytatásra hívó. Ez acceptance-cella, nem stílus-kérés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A kihagyott nap NEM növeli a következő napi keretet | `missed_day_policy_test.dart` |
| A2 | A pihenőnap nem számít mulasztásnak | ugyanott |
| A3 | Szünet alatt nem keletkezik lemaradás | `pause_resume_test.dart` |
| A4 | A folytatás ÚJ revíziót hoz létre, korrigált dátumokkal | ugyanott |
| A5 | Hosszabb szünet után készültségi javaslat jön | ugyanott |
| A6 | Az újraütemezés csak az elsődleges célt mozgatja | `missed_day_policy_test.dart` |
| A7 | Időzóna-váltás nem generál hamis mulasztást | ugyanott |
| A8 | A szövegek nem szégyenítők (ARB, hu + en) | l10n + review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kimaradt idő átvitele a következő napra | **A1** |
| A pihenőnap mulasztásként | **A2** |
| A szünet alatt gyűlő backlog | **A3** |
| A folytatás a régi revízióba ír | A4 |
| Hosszú szünet után a régi nehézséggel folytat | **A5** |
| Utazáskor hamis mulasztás | A7 |

**A kihagyás-hossz három kötelező cellája** (a küszöb: a „hosszabb szünet" határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | egy kihagyott nap | egyszerű újraütemezés, **nincs** keret-növelés |
| rajta (a küszöbön) | pontosan a határon lévő kihagyás | **készültségi javaslat** (a határ a óvatosabb oldalhoz tartozik) |
| a küszöb fölött | több hét kihagyás | készültségi javaslat, csökkentett nehézséggel |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vidd át a kimaradt
időt a következő napra → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/continuity/missed_day_policy_test.dart test/features/practice_generator/continuity/pause_resume_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `missed_day_policy.dart` — opciók, keret-védelem, elsődleges-mozgatás.
2. `pause_practice_plan.dart` / `resume_practice_plan.dart` — dátum-korrekció,
   új revízió.
3. `catch_up_sheet.dart` — nem szégyenítő copy, ARB-ből.
4. Tesztek a §6.1 három kihagyás-cellájával és időzóna-utazással.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A backlog-spirál.** „Csak ma egy kicsit több" — és két hét múlva a tanuló
  behozhatatlan lemaradást lát, majd feladja (A1). Ez a kör lényege.
- **A szégyenítő copy.** Apróságnak tűnik, és pont a visszatérést nehezíti (A8).
- **A régi nehézséggel folytatás.** Két hónap kihagyás után ugyanaz a tempó
  kudarcélményt ad (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
