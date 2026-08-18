# E08-R16 — Quest domain, objective és életciklus

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 16
- **Kör-azonosító:** `E08-R16`
- **Branch:** `<motor>/e08-r16-quest-domain-objective-and-lifecycle`
- **Előfeltétel:** `E08-R15` merge-elve (achievement felület)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0312` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R13 objective-típusait (a quest-objective ugyanazt a metrika-hivatkozási mintát követi) és a `lib/features/practice_generator/` terv-blokk szerződését — a quest arra hivatkozik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/quests/quest_definition.dart",
  "lib/features/gamification/domain/quests/quest_objective.dart",
  "lib/features/gamification/domain/quests/quest_progress.dart",
  "lib/features/gamification/domain/quests/quest_schedule.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/domain/quest_model_test.dart",
  "docs/rounds/e08-r16-quest-domain-objective-and-lifecycle.md",
]
gate_tests = [
  "test/features/gamification/domain/quest_model_test.dart",
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

Típusos, determinisztikus életciklus a napi és heti küldetéseknek — és a legfontosabb
invariáns: a **jutalom automatikusan jár**, nem beváltáshoz (claim) kötött.

## 2. Jelenlegi állapot — mért tények

- Az R13 típusos objective-mintát adott az achievementeknek; a quest ugyanezt a mintát követi, de saját életciklussal.
- `lib/features/gamification/domain/quests/` **nem létezik**.
- A `lib/features/practice_generator/` (Epic 7) terv-blokkjai adják a `planBlock` hivatkozást.
- Az `ADR 0290` §2: a beváltás idempotens, és a felület nem számol jutalmat.

## 3. Scope

**Benne van:** az `active` / `completed` / `expired` / `replaced` / `archived` állapotok · típusos
objective-hivatkozás (skill-címke, terv-blokk, mód, metrika) · a generálás napja, időzóna-eltolás,
katalógus-verzió és lejárat tárolása · a teljesítés és a jutalom KÜLÖN állapot, de a jutalom
**automatikus** · helyettesítés indok-kóddal · a lejárat NEM törli a gyakorlási eredményt.

**NINCS benne (tilos):**

- A generálás (Kör 17/18), a challenge (Kör 19), a felület (Kör 20).
- Beváltás-mechanika (claim) bevezetése — a §5.1 tiltja.
- `docs/adr/**` — az ADR 0312-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/quests/quest_definition.dart` | **ÚJ** — a küldetés definíciója |
| `lib/features/gamification/domain/quests/quest_objective.dart` | **ÚJ** — a típusos objective |
| `lib/features/gamification/domain/quests/quest_progress.dart` | **ÚJ** — a haladás és az állapot |
| `lib/features/gamification/domain/quests/quest_schedule.dart` | **ÚJ** — generálási nap, időzóna, lejárat |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/domain/quest_model_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0312)

### 5.1 A jutalom AUTOMATIKUS — nincs beváltás (claim)

A teljesített küldetés jutalma azonnal a főkönyvbe kerül. A felhasználónak
nem kell megnyitnia a képernyőt, nem kell gombot nyomnia, és a jutalom nem jár le.

**NEM elfogadható gyengítés:** „claim” gomb, akár csak animáció kedvéért. A beváltás-alapú
minta elveszi a jutalmat attól, aki nem nyitja meg a felületet — az ADR 0290 §2 tiltja.

### 5.2 A LEJÁRAT SEMLEGES — nem törli a gyakorlás eredményét

A lejárt küldetés `expired` állapotba kerül. A közben elvégzett gyakorlás
eredménye, XP-je és a főkönyv bejegyzései érintetlenek maradnak.

**NEM elfogadható gyengítés:** a részleges haladás nullázása lejáratkor. A felhasználó
gyakorolt; a küldetés adminisztratív kerete nem veheti el a teljesítményét.

### 5.3 Az állapotgép DETERMINISZTIKUS és zárt

Az öt állapot közötti átmenetek halmaza kimerítően definiált, és minden átmenet
indok-kóddal jár. Nem definiált átmenet **hibát ad**, nem hallgatólagos no-opot.

### 5.4 Az objective TÍPUSOS, nem szabad szöveg

A skill-címkére, terv-blokkra, módra és metrikára típusosan hivatkozik — mint az
R13-ban. Így a Kör 17 generátora és a Kör 20 felülete is ellenőrizhetően tud rá építeni.

### 5.5 Az ütemezés tárolja az IDŐZÓNA-ELTOLÁST

A generálás napja mellett az akkori időzóna-eltolás is tárolódik. Utazáskor
enélkül nem eldönthető, hogy egy küldetés még aktív-e, és a lejárat órákkal elcsúszna.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A teljesített küldetés jutalma beváltás NÉLKÜL a főkönyvbe kerül | `quest_model_test.dart` — automatikus jutalom cella |
| A2 | A felület megnyitása NEM feltétele a jutalomnak (a nyugta a képernyő érintése nélkül létrejön) | `quest_model_test.dart` |
| A3 | Lejáratkor a részleges haladás és a gyakorlási eredmény ÉRINTETLEN | `quest_model_test.dart` |
| A4 | Az öt állapot közötti definiált átmenetek működnek; nem definiált átmenet HIBÁT ad | `quest_model_test.dart` — átmenet-mátrix |
| A5 | Minden átmenet indok-kóddal jár (a helyettesítés is) | `quest_model_test.dart` |
| A6 | Az objective típusos; ismeretlen hivatkozás hibát ad | `quest_model_test.dart` |
| A7 | Az ütemezés tárolja a generálási napot, az időzóna-eltolást, a katalógus-verziót és a lejáratot | `quest_model_test.dart` — round-trip |
| A8 | A modell verziózott; ismeretlen `schemaVersion` hibát ad | `quest_model_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A jutalom claim-hez kötött | **A1** és **A2** |
| A lejárat nullázza a haladást | **A3** |
| Nem definiált átmenet némán no-op | **A4** |
| Az objective szabad szöveg | **A6** |
| Az időzóna-eltolás nem tárolódik | **A7** |
| Az átmenet néma `bool` | **A5** |

**A küszöb három kötelező cellája** (a lejárati időpont (`expiresAt`) — a küldetés aktivitásának határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `expiresAt - 1s` (a lejárat előtt) | a küldetés **aktív**, a teljesítés jutalmat ad |
| **rajta** (a küszöbön) | pontosan `expiresAt` | a küldetés **MÁR lejárt** — a lejárati időpont a LEJÁRT oldalhoz tartozik (exkluzív felső határ az aktivitásra) |
| a küszöb **fölött** | `expiresAt + 1s` | lejárt; a haladás és a gyakorlási eredmény érintetlen |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kösd a jutalmat beváltáshoz (a főkönyv-írás csak a `claim()` hívásban történjen),
futtasd a gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/domain/quest_model_test.dart
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

1. `quest_objective.dart` — a típusos objective-hivatkozások.
2. `quest_schedule.dart` — generálási nap, időzóna-eltolás, katalógus-verzió, lejárat.
3. `quest_definition.dart` — a definíció, verziózva.
4. `quest_progress.dart` — az öt állapot és a zárt átmenet-halmaz, indok-kódokkal.
5. Az automatikus jutalom útja (a főkönyvbe, beváltás nélkül).
6. A lejárat semlegességének biztosítása.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A claim-mechanika.** A műfaj alapértelmezett mintája, és elveszi a jutalmat attól, aki nem nyitja meg a felületet (A1).
- **A lejárati nullázás.** „Tiszta” adatkezelésnek tűnik, és a felhasználó valós gyakorlását veszi el (A3).
- **Az időzóna-eltolás elhagyása.** Itthon soha nem látszik; utazáskor órákkal elcsúsztatja a lejáratot (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
