# E07-R17 — Spaced repetition és maintenance queue

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 5cdd7472`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 17
- **Kör-azonosító:** `E07-R17`
- **Branch:** `<motor>/e07-r17-spaced-repetition`
- **Előfeltétel:** `E07-R16` merge-elve (progresszió)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a határokat az ADR 0255 (determinizmus),
  0258 §4 (helyi dátum) és 0261 (`unknown`) rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03 helyi-dátum
> modelljét (a due date erre épül) és az R08 katalógus-revízióit (a törölt
> tartalom felismeréséhez). Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/practice_generator/domain/model/review_item.dart",
  "lib/features/practice_generator/domain/policy/spaced_repetition_policy.dart",
  "lib/features/practice_generator/domain/service/review_queue.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/review/review_queue_test.dart",
  "test/features/practice_generator/review/spaced_repetition_policy_test.dart",
  "test/fixtures/practice_generator/review/",
  "docs/rounds/e07-r17-spaced-repetition.md",
]
gate_tests = [
  "test/features/practice_generator/review/review_queue_test.dart",
  "test/features/practice_generator/review/spaced_repetition_policy_test.dart",
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

A korábban megtanult skill- és tartalomelemek időzített, **korlátozott**
fenntartása (SDD Ch8 Kör 17).

## 2. Jelenlegi állapot — mért tények

- Az R03 helyi-dátum modellje (ADR 0258 §4) — a due date ehhez igazodik.
- Az R08 katalógus-revíziója alapján felismerhető a **törölt** tartalom.
- Az R15 ütemezője **korlátos arányban** enged ismétlést a napba.

## 3. Scope

**Benne van:** `ReviewItem` életciklus · **egyszerű, magyarázható** intervallum-
politika · sikeres / részleges / sikertelen / **bizonytalan** kimenet kezelése ·
napi review-budget · akkord-, minta-, lecke- és dalszakasz-hivatkozás ·
azonos cél deduplikálása.

**NINCS benne (tilos):** orchestrator (Kör 18) · repository (Kör 19) · a napi
budget túllépése · Flutter, `DateTime.now()`, `Random` · más
`lib/features/**`, `docs/adr/**`, `tools/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/review_item.dart` | **ÚJ** — elem + életciklus |
| `domain/policy/spaced_repetition_policy.dart` | **ÚJ** — intervallumok |
| `domain/service/review_queue.dart` | **ÚJ** — a sor, budgettel |
| `public.dart` | a barrel bővítése |
| `test/…/review/*_test.dart` (2 db) | a §6 cellái |
| `docs/rounds/e07-r17-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A sor NEM töltheti ki a napot

A napi review-budget felső korlát, és az R15 arány-korlátjával együtt hat.
A fenntartás nem szoríthatja ki a fejlődést.

**NEM elfogadható gyengítés:** „ma sok az esedékes, kivételesen több fér be".

### 5.2 A BIZONYTALAN mérés NEM büntet

Ha a mérés bizonytalan (alacsony confidence, hiányos adat), az **nem**
sikertelen ismétlés: az intervallum nem rövidül. Az `unknown` nem gyengeség
(ADR 0261 §2) — itt sem.

**NEM elfogadható gyengítés:** a bizonytalant sikertelenként kezelni „biztos,
ami biztos" alapon. Az a tanulót fölöslegesen visszaforgatná.

### 5.3 A due date DETERMINISZTIKUS és helyi dátum

Ugyanaz a történet ugyanazt az esedékességet adja; a dátum helyi naptári nap
(ADR 0258 §4), nem UTC-pillanat.

### 5.4 Az intervallum-politika EGYSZERŰ és MAGYARÁZHATÓ

Kevés, kimondott lépcső — nem hangolt, átláthatatlan képlet. A felhasználónak
megmondható, mikor és miért jön vissza egy elem (ADR 0255).

### 5.5 A törölt tartalom HELYETTESÍTÉST igényel

Ha a hivatkozott tartalom eltűnt a katalógusból, a review-elem nem tűnik el
csendben és nem is dob hibát: **helyettesítést kér**, jelzéssel.

### 5.6 Az azonos cél DEDUPLIKÁLT

Ugyanaz a review-cél egyszer szerepel a sorban, akkor is, ha több úton került
be.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A napi budget nem léphető túl | `review_queue_test.dart` |
| A2 | Bizonytalan kimenet NEM rövidíti az intervallumot | `spaced_repetition_policy_test.dart` |
| A3 | Sikeres → hosszabb, sikertelen → rövidebb intervallum | ugyanott |
| A4 | Részleges kimenet külön kezelt (nem sikeres, nem sikertelen) | ugyanott |
| A5 | A due date determinisztikus, helyi dátum | ugyanott |
| A6 | Törölt tartalom → helyettesítési kérés, nem csendes eltűnés | `review_queue_test.dart` |
| A7 | Azonos cél egyszer szerepel | ugyanott |
| A8 | Az időzóna-váltás nem tolja el az esedékességet | `spaced_repetition_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| „Kivételesen több fér be" | **A1** |
| A bizonytalan sikertelenként kezelve | **A2** |
| A részleges sikeresként könyvelve | A4 |
| `DateTime` alapú due date | A5/A8 |
| A törölt tartalom csendben eltűnik | **A6** |
| A dedup hiánya | A7 |

**A review-kimenet három kötelező cellája** (a határ: a bizonytalanság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| biztos siker | magas confidence, teljesítve | intervallum **nő** |
| a határon | **bizonytalan** mérés | intervallum **változatlan** — nem büntet |
| biztos kudarc | magas confidence, nem teljesítve | intervallum **csökken** |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kezeld a bizonytalan
kimenetet sikertelenként → az **A2** cellának PIROSNAK kell lennie → állítsd
vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/review/review_queue_test.dart test/features/practice_generator/review/spaced_repetition_policy_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `review_item.dart` — életciklus, tartalom-hivatkozás.
2. `spaced_repetition_policy.dart` — kevés, kimondott lépcső.
3. `review_queue.dart` — budget, dedup, helyettesítés.
4. Tesztek a §6.1 három kimenet-cellájával.
5. A valódi-sértés próba, §10-be dokumentálva.
6. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A bizonytalan mint kudarc.** „Biztos, ami biztos" — és a tanulót
  fölöslegesen visszaforgatja már tudott anyagra (A2).
- **A budget felpuhulása.** Egy „kivételes" nap után a fenntartás kiszorítja a
  fejlődést (A1).
- **A bonyolult képlet.** Jobb számokat ad papíron, és megmagyarázhatatlan
  lesz a felhasználónak (§5.4).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
