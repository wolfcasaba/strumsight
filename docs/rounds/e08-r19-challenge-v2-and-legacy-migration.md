# E08-R19 — Challenge V2 és a legacy napi kihívás migrációja

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 19
- **Kör-azonosító:** `E08-R19`
- **Branch:** `<motor>/e08-r19-challenge-v2-and-legacy-migration`
- **Előfeltétel:** `E08-R18` merge-elve (heti küldetés)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0387` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/streak/daily_challenge.dart` (63 sor) TÉNYLEGES determinisztikus generálását és a `test/features/streak/daily_challenge_test.dart`-ot — a legacy minta-generátort változatlanul be kell csomagolni. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight revízió — 2026-08-21

A friss `main @ 0fb00aaf` mérése két driftet oldott fel, scope-bővítés nélkül:

1. **ADR-szám.** A brief 2026-08-18-i előírása (`ADR 0314`) időközben elavult:
   `0314-gate-step-taxonomy.md` egy korábbi, független körben már lefoglalta
   ezt a számot. `tools/round-slots.py reserve-adr --round E08-R19` a
   TÉNYLEGES szabad számot adta: **`ADR 0387`**. A brief minden `ADR 0314`
   hivatkozása erre cserélve (fejléc, §3 tilos-zóna sor, §5 címsor); az ADR
   fájl `docs/adr/0387-challenge-v2-legacy-wrap-and-single-reward-instance.md`
   néven íródott meg, a §5 döntéseit formalizálva.
2. **A §6.1 küszöb-táblázat `epochDayOf`-hivatkozása pontatlan.** A
   `epochDayOf` NEM a `daily_challenge.dart`-ban él (az csak egy `int
   epochDay` bemenetet fogad a `DailyChallenge.forDay`-ben), hanem a
   `StreakLogic.epochDayOf` (`lib/features/streak/streak_logic.dart:18`) —
   helyi éjfél alapú képlet, amit minden ma élő hívó (streak/progress/learn
   képernyők) használ. A táblázat SORTARTALMA (a küszöb inkluzív oldala)
   helyes marad, csak a forrás-hivatkozás pontosított: a szolgáltatás a
   hívó-adta epoch-napot fogadja bemenetként (nem maga számol
   `DateTime.now()`-ból), byte-azonos a `StreakLogic.epochDayOf`
   szemantikájával — [[L362]] mérten figyelmeztet egy UTC-only képzés
   pozitív időzónás hamis küszöb-ágára, ezért a hívó felelőssége (ezen a
   körön kívül) a helyes `epochDayOf` meghívása, a szolgáltatás csak a kapott
   `int`-et használja. Részletek: ADR 0387 Kontextus 1. pont.

**Visszakeresett előzmény** (`node tools/knowledge-rag.mjs`, szűkített
korpusszal előbb): `lessons/L362` (helyi-midnight epoch-nap képzés —
közvetlenül a fenti 2. pontra), `lessons/L384` (ismétlődő katalóguselem
receiptje a példányt azonosítsa, ne csak a definíciót — az A3 idempotencia-
kulcs tervezésébe beépítve, ADR 0387 Döntés 2), `adr/0116` (legacy adapter
HÍVJA, nem reprodukálja a forrást — ugyanaz a minta, mint a jelen kör §5.1,
ADR 0387 Döntés 1). A teljes korpuszos kiegészítő kérdés nem mutatott a
fentiekkel ellentétes elfogadott döntést.

**Kockázat = high, indoklás (változatlan a brief eredeti besorolásától):** a
kör a jutalom-főkönyv idempotenciáját és a legacy pengetés-minta
bitre-azonosságát érinti — egy hibás adapter vagy dedup-kulcs vagy a
felhasználó megszokott napi mintáját törné el, vagy dupla jutalmat adna.

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
- `docs/adr/**` — az ADR 0387-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/quests/challenge_definition.dart` | **ÚJ** — a kihívás-típusok |
| `lib/features/gamification/application/daily_challenge_service.dart` | **ÚJ** — a napi kihívás szolgáltatás |
| `lib/features/gamification/data/migration/legacy_daily_challenge_adapter.dart` | **ÚJ** — a legacy generátor becsomagolása |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/daily_challenge_service_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/streak/**` (a legacy generátor ÉRINTETLEN)

## 5. Kötött architekturális döntések (ADR 0387)

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

### 10.1 Production surface

| Fájl | Változás | Indoklás |
|---|---|---|
| `lib/features/gamification/data/migration/legacy_daily_challenge_adapter.dart` | NEW | A legacy `DailyChallenge.forDay` hívása (ADR 0387 Decision 1). Import: `package:strumsight/features/streak/public.dart` (a `check_architecture.dart` szerinti cross-feature határ). |
| `lib/features/gamification/domain/quests/challenge_definition.dart` | NEW | `DailyChallengeType` enum (5 tag) + 5 zárt altípus + `==`/`hashCode` + `toJson`/`fromJson` round-trip. |
| `lib/features/gamification/application/daily_challenge_service.dart` | NEW | `DailyChallengeInstance` (katalógus-verzió PINNELVE), `LocalDailyChallengeCompletionStore` (`KeyValueStore` + `JsonDocumentStore`), `DailyChallengeService.getOrGenerateInstance` (pin), `complete` (`appendIfAbsent` a napi példány azonosítójával). |
| `lib/features/gamification/public.dart` | +3 export-sor | `daily_challenge_service.dart`, `legacy_daily_challenge_adapter.dart`, `challenge_definition.dart` re-export. |
| `test/features/gamification/application/daily_challenge_service_test.dart` | NEW | A §6 minden cellája + a §6.1 küszöb-hármas + az A1 valódi-sértés próba. |

A `lib/features/streak/**` NEM módosult — `git diff main..HEAD -- lib/features/streak/` üres. A §6 A2 cellát a gate `test test/features/streak` lépése zölddel zárta (20/20 átment).

### 10.2 Acceptance mapping (a §6 cellái ↔ a teszt, ami pirosra váltja)

| Cella | Teszt | Megjegyzés |
|---|---|---|
| A1 (bitre azonos, 30 nap) | `A1: the V2 service matches the legacy generator byte-for-byte` (60 napra) | A `legacyAdapter.forDay(day).pattern` megegyezik `DailyChallenge.forDay(day).pattern`-tel. |
| A1 (visszatérési érték) | `A1: the same epoch day produces the same legacy strum pattern` | Azonos nap → azonos minta. |
| A2 (streak zöld) | gate lépés `test test/features/streak` | 20/20 zöld. |
| A3 (idempotens jutalom) | `A3: the reward ledger sees exactly one entry per daily instance` | 3 hívás → 1 ledger bejegyzés. |
| A3 (újrajátszás szabad) | `A3: the completion timestamp updates on every replay but the receipt is stable` | `completedAt` frissül, `ledgerId` állandó. |
| A4 (app-újraindítás) | `A4: a completion survives an "app restart" via a fresh store instance` | Ugyanaz a `InMemoryKeyValueStore` → friss `LocalDailyChallengeCompletionStore` visszaolvassa a completion-t. |
| A4 (új nap) | `A4: a new day generates a new instance after restart` | Másik epochDay → másik példány. |
| A5 (pin) | `A5: a catalog upgrade after the day started does NOT swap today's challenge` | 5→6 catalogVersion → tárolt 5-ös pin marad. |
| A5 (új nap) | `A5: the next epoch day does pick up the new catalog version` | Másik nap → új catalogVersion. |
| A6 (elérhetőség-mátrix) | 4 teszt: chord populált / chord 1 → fallback / rhythm üres / minden ID a katalógusban | A `_MultiTypeCatalog.isAvailable` és a `_definitionFor` szűri. |
| A7 (minden típus elérhető) | `A7: every supported type is reachable when the catalog is fully populated` | 100 nap alatt mind az 5 típust lefedi. |
| A8 (streak érintetlen) | `A8: only the adapter imports the legacy generator; streak files are not touched` | Fájlrendszer-szintű walk + a `git diff main..HEAD -- lib/features/streak/` üres. |
| §6.1 alatt / rajta / fölött | 3 cella a "below/on/above threshold" group-ban | Ugyanaz a service három nézőpontból. |

A valódi-sértés próba (`A1 real-violation: a copied-and-diverged generator breaks the identity cell`): egy `_BadStrumPattern` konstans mintát ad és azt állítja, hogy a `bad.pattern == legacy.pattern` HAMIS. Ezzel bizonyítja, hogy bármilyen másolat-és-eltérés az A1 cellát PIROSRA váltja.

### 10.3 Gate artefact

```
tools/round-gate.sh test/features/gamification/application/daily_challenge_service_test.dart test/features/streak
```

Eredmény (csonkítatlan, előtérben futtatva):
- format: ZÖLD (1777 files, 0 changed)
- analyze: ZÖLD (No issues found)
- test daily_challenge_service_test: ZÖLD (18/18)
- test streak: ZÖLD (20/20)
- architecture: ZÖLD (12 allowlisted deviation, de az adapter→streak határ a public.dart felé már át van irányítva — a "cross-feature imports must target public.dart" szabály teljesül)
- secrets: ZÖLD
- l10n: ZÖLD

### 10.4 Architectural decision log (ehhez a körhöz)

1. A legacy adapter `package:strumsight/features/streak/public.dart`-ot importál, nem a belső `daily_challenge.dart`-ot (a `tool/check_architecture.dart` szabálya).
2. A `StrumPatternChallenge` a `challenge_definition.dart`-ban van (nem az adapterben), hogy a `DailyChallengeDefinition` sealed factory-ja egyszerre kezelje az öt altípust — az adapter csak hívja és visszaadja.
3. A `DailyChallengeInstance` azonosítója `daily-challenge:<type>:<catalogVersion>:<epochDay>` — a `catalogVersion` pin miatt a `sourceEventId` stabil marad a nap folyamán, így a jutalom `appendIfAbsent` mindig ugyanazt a kulcsot látja.
4. A `getOrGenerateInstance` első lépése: ha a tárolt példány `epochDay`-e megegyezik a hívóéval, **visszaadjuk** — a `catalogVersion` paraméter figyelmen kívül van hagyva (ADR 0387 Decision 3, pin).
5. A service a `RewardReason.questCompleted` kódot használja, mert az enum nem tartalmaz `dailyChallenge`-t; a koncepció a legközelebbi illeszkedés (a jutalom kvóta-kezelő rétege nem különbözteti).

## 11. Review — a Claude tölti ki
