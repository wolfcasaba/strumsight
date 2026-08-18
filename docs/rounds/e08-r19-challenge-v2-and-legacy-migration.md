# E08-R19 — Challenge V2 és a legacy napi kihívás migrációja

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 19
- **Kör-azonosító:** `E08-R19`
- **Branch:** `<motor>/e08-r19-challenge-v2-and-legacy-migration`
- **Előfeltétel:** `E08-R18` merge-elve (heti küldetés)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0314` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/daily_challenge.dart` (63 sor) TÉNYLEGES determinisztikus generálását és a `test/features/streak/daily_challenge_test.dart`-ot — a legacy minta-generátort változatlanul be kell csomagolni. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/quests/challenge_definition.dart",
  "lib/features/gamification/application/daily_challenge_service.dart",
  "lib/features/gamification/data/migration/legacy_daily_challenge_adapter.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/daily_challenge_service_test.dart",
  "docs/rounds/e08-r19-challenge-v2-and-legacy-migration.md",
]
gate_tests = [
  "test/features/gamification/application/daily_challenge_service_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Bővítsd a determinisztikus napi kihívást több típussal — **a legacy pendítés-minta
bitre azonos megőrzésével**, offline működéssel és idempotens jutalommal.

## 2. Jelenlegi állapot — mért tények

- `lib/features/streak/daily_challenge.dart` (63 sor): a minta **determinisztikusan** az epoch-napból származik, szerver nélkül; `test/features/streak/daily_challenge_test.dart` MA zöld.
- Az R16 típusos küldetés-életciklust adott; az R03 főkönyve idempotens jutalmat.
- `challenge_definition.dart` **nem létezik**.

## 3. Scope

**Benne van:** a jelenlegi pendítés-minta generátor becsomagolása **legacy szolgáltatóként** ·
akkordváltás, ritmus, dal-szakasz és időzítés kihívás-definíciók · a generátor CSAK elérhető
tartalom-azonosítót használ · a napi példány azonosítójának és teljesítésének tárolása · a
kihívás újrajátszható, de a jutalom **egyszer** jár · katalógus-verzió váltásakor az AZNAPI
aktív kihívás nem cserélődik.

**NINCS benne (tilos):**

- A `lib/features/streak/daily_challenge.dart` MÓDOSÍTÁSA — becsomagoljuk, nem írjuk át.
- A `test/features/streak/daily_challenge_test.dart` átírása — elbukása `blocked`.
- Felület (Kör 20), hálózat.
- `docs/adr/**` — az ADR 0314-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/quests/challenge_definition.dart` | **ÚJ** — a kihívás-típusok |
| `lib/features/gamification/application/daily_challenge_service.dart` | **ÚJ** — a napi kihívás szolgáltatás |
| `lib/features/gamification/data/migration/legacy_daily_challenge_adapter.dart` | **ÚJ** — a legacy generátor becsomagolása |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/daily_challenge_service_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/streak/**` (a legacy generátor ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0314)

### 5.1 A legacy minta BITRE AZONOS marad

Az adapter a meglévő `DailyChallenge` generátort **hívja**, nem reprodukálja.
Ugyanaz az epoch-nap ugyanazt a mintát adja, mint ma — ezt acceptance-cella méri (A1).

**NEM elfogadható gyengítés:** a generálási logika átmásolása az új fájlba „hogy egy helyen
legyen”. A két másolat az első javításnál elcsúszik, és a felhasználó mintája megváltozik.

### 5.2 Az újrajátszás SZABAD, a jutalom EGYSZERES

A felhasználó annyiszor játssza újra a napi kihívást, ahányszor akarja. A jutalom
az R03 főkönyvének `append-if-absent` műveletén megy át, a napi példány azonosítójával —
így technikailag egyszeres.

**NEM elfogadható gyengítés:** az újrajátszás tiltása „hogy ne farmoljon”. A gyakorlás
korlátozása a termék magját bünteti a jutalomréteg kedvéért.

### 5.3 A katalógus-verzió váltása NEM cseréli az AZNAPI aktív kihívást

A napi példány a generáláskori katalógus-verziót tárolja. Egy app-frissítés a nap
közepén nem cserélheti ki a már megkezdett kihívást — az elveszett haladásnak látszana.

### 5.4 CSAK elérhető tartalom

A generátor nem választhat olyan dal- vagy gyakorlat-azonosítót, ami az eszközön
nincs meg. Offline is teljes értékű kihívást kell adnia.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz az epoch-nap UGYANAZT a pendítés-mintát adja, mint a legacy generátor | `daily_challenge_service_test.dart` — bitre azonosság, 30 napra |
| A2 | A `test/features/streak/daily_challenge_test.dart` VÁLTOZATLANUL zöld | a §7 gate kimenete |
| A3 | Az újrajátszás megengedett; a jutalom mégis EGYSZER kerül a főkönyvbe | `daily_challenge_service_test.dart` — idempotencia-cella |
| A4 | A teljesítés tartós (app-újraindítás után is megmarad) | `daily_challenge_service_test.dart` |
| A5 | Katalógus-verzió váltása után az AZNAPI aktív kihívás VÁLTOZATLAN | `daily_challenge_service_test.dart` |
| A6 | A generátor csak elérhető tartalom-azonosítót választ (offline is teljes) | `daily_challenge_service_test.dart` — elérhetőség-mátrix |
| A7 | Mind a négy új kihívás-típus támogatott | `daily_challenge_service_test.dart` — típus-mátrix |
| A8 | A `lib/features/streak/**` ÉRINTETLEN | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A generálási logika átmásolva az új fájlba | **A1** (az azonosság-cella az első eltérésnél) |
| Az újrajátszás tiltva | **A3** |
| A jutalom minden játszásnál jóváíródik | **A3** (az idempotencia-cella) |
| A katalógus-verzió váltása újragenerál | **A5** |
| Nem elérhető dal-azonosító választva | **A6** |
| A legacy fájl „rendbetéve” | **A8** |

**A küszöb három kötelező cellája** (a napi példány érvényességi ablaka (az epoch-nap határa)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | az előző epoch-nap utolsó másodperce | az **előző** napi kihívás aktív |
| **rajta** (a küszöbön) | pontosan a helyi éjfél (az új epoch-nap első pillanata) | **MÁR az új** napi kihívás aktív — a nap az ÚJ kihíváshoz tartozik (inkluzív), a `daily_challenge.dart` mai `epochDayOf` szemantikája szerint |
| a küszöb **fölött** | az új epoch-nap első másodperce | az új napi kihívás aktív; az előző teljesítése és jutalma megmarad |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** másold át a legacy generálási logikát az új szolgáltatásba, majd változtass meg egy
konstansot → az **A1** azonosság-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/daily_challenge_service_test.dart test/features/streak
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `legacy_daily_challenge_adapter.dart` — a meglévő generátor becsomagolása (hívás, nem másolás).
2. `challenge_definition.dart` — a négy új típus.
3. `daily_challenge_service.dart` — napi példány azonosító, teljesítés, elérhetőség-szűrés.
4. A jutalom bekötése a főkönyvbe (`append-if-absent`, napi példány azonosítóval).
5. A katalógus-verzió rögzítése a példányban.
6. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
7. `tools/round-gate.sh` a §7 szerint — a RÉGI streak-tesztekkel együtt.

## 9. Kockázatok

- **A logika átmásolása.** „Egy helyen legyen” — és a felhasználó megszokott mintája az első javításnál megváltozik (A1).
- **Az újrajátszás tiltása.** Farmolás-ellenesnek látszik, és a gyakorlást bünteti; a helyes védelem a főkönyv dedupja (A3).
- **A nap-határ UTC-ben.** Kényelmes, és a felhasználó estéjén cseréli a kihívást (a küszöb-hármas).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
