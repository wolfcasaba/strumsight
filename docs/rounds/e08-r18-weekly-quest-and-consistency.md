# E08-R18 — Heti küldetés és következetességi objective

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 18
- **Kör-azonosító:** `E08-R18`
- **Branch:** `<motor>/e08-r18-weekly-quest-and-consistency`
- **Előfeltétel:** `E08-R17` merge-elve (napi küldetés-generátor)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R17 determinisztikus mag-származtatását (a heti generátor ugyanazt a mintát követi) és az R11 heti következetesség-projekcióját. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/weekly_quest_generator.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/weekly_quest_generator_test.dart",
  "docs/rounds/e08-r18-weekly-quest-and-consistency.md",
]
gate_tests = [
  "test/features/gamification/application/weekly_quest_generator_test.dart",
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

Reális heti célok, amelyek **nem követelnek napi tökéletességet**: a cél a heti
elérhető idővel skálázódik, és a hét közbeni tervváltozás nem csökkenti a már elért haladást.

## 2. Jelenlegi állapot — mért tények

- Az R17 determinisztikus napi generátort adott; ez a kör ugyanazt a mag-mintát heti szinten alkalmazza.
- Az R11 külön heti következetesség-projekciót ad (hány minősített nap volt).
- `weekly_quest_generator.dart` **nem létezik**.
- Az `ADR 0290` §1: nincs büntető nyelv, a kihagyott nap normális.

## 3. Scope

**Benne van:** a heti terv és elérhetőség felhasználása · aktív napok, terv-blokk, mód-diverzitás és
javulás objective-ek · **tilos** hét egymást követő napot kötelezővé tenni · a cél skálázása
csökkentett heti időnél · a már elért haladás nem csökken tervváltozáskor · semleges heti
átvezető (rollover) összefoglaló.

**NINCS benne (tilos):**

- Napi küldetés (Kör 17), challenge (Kör 19), felület (Kör 20).
- A `WeeklyRecap` felület módosítása — ez a kör csak ELŐKÉSZÍTI az integrációt.
- A terv írása.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/weekly_quest_generator.dart` | **ÚJ** — a heti generátor |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/weekly_quest_generator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/practice_generator/**` · `lib/features/share/**`

## 5. Kötött architekturális döntések

### 5.1 NINCS hét egymást követő nap mint kötelező objective

A heti cél soha nem követel hibátlan sorozatot. A „7/7 nap” objective egyetlen
kihagyott nap után teljesíthetetlenné válik, és a hét hátralévő részét értelmetlenné teszi —
ez pontosan az a büntető minta, amit az ADR 0290 §1 tilt.

**NEM elfogadható gyengítés:** „7 nap, de van egy szabadnap” — a felső korlát akkor is 6
kötelező nap, és ezt acceptance-cella méri (A1).

### 5.2 A HALADÁS SOHA NEM CSÖKKEN tervváltozáskor

Ha a hét közben a terv változik (kevesebb idő, más napok), a már teljesített
haladás megmarad. A cél csökkenhet, a haladás nem.

**NEM elfogadható gyengítés:** a haladás újraszámítása az új célhoz arányosítva. A
felhasználó valós teljesítményét vonná el visszamenőleg.

### 5.3 A CÉL SKÁLÁZÓDIK a rendelkezésre álló idővel

Utazás vagy csökkentett heti idő esetén a cél arányosan kisebb — és a
skálázás **magyarázható**: a küldetés meg tudja mondani, milyen bemenetből jött a cél.

### 5.4 A hét vége SEMLEGES: átvezető összefoglaló, nem ítélet

A heti zárás tényközlő összefoglalót ad (mi teljesült, mi nem), sürgetés és
szégyenítés nélkül, és előkészíti a `WeeklyRecap` integrációt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A generált heti objective SOHA nem követel 7 (vagy 6+) egymást követő kötelező napot | `weekly_quest_generator_test.dart` — felső korlát cella |
| A2 | Csökkentett heti idő esetén a cél arányosan kisebb | `weekly_quest_generator_test.dart` — skálázás-mátrix |
| A3 | Hét közbeni tervváltozás után a már elért haladás VÁLTOZATLAN | `weekly_quest_generator_test.dart` — regresszió-cella |
| A4 | A cél magyarázható: a küldetés visszaadja a származtatás bemeneteit | `weekly_quest_generator_test.dart` |
| A5 | A generálás determinisztikus (hét + profil + katalógus-verzió) | `weekly_quest_generator_test.dart` |
| A6 | A négy objective-típus (aktív napok / terv-blokk / mód-diverzitás / javulás) mind támogatott | `weekly_quest_generator_test.dart` — típus-mátrix |
| A7 | A heti átvezető összefoglaló semleges nyelvű (tiltott-szó lista) | `weekly_quest_generator_test.dart` |
| A8 | Kihagyott nap NEM jár semmilyen levonással | `weekly_quest_generator_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A generátor 7/7 napos objective-et ad | **A1** |
| A haladás az új célhoz arányosítva újraszámolódik | **A3** |
| A cél fix, függetlenül az elérhető időtől | **A2** (a skálázás-mátrix) |
| A cél nem adja vissza a származtatás bemeneteit | **A4** |
| Az összefoglaló sürgetést használ | **A7** |
| A kihagyott nap levonást okoz | **A8** |

**A küszöb három kötelező cellája** (a kötelező aktív napok felső korlátja a heti objective-ben (`maxRequiredDays`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `maxRequiredDays - 1` nap | elfogadható objective |
| **rajta** (a küszöbön) | pontosan `maxRequiredDays` (a specifikáció szerint legfeljebb 5 a 7-ből) | **MÉG elfogadható** — a korlát az ELFOGADOTT oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `maxRequiredDays + 1` nap | **TILOS** — a generátornak vissza kell vágnia; ezt az A1 cella méri |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a generátort úgy, hogy 7 aktív napot követeljen, futtasd a gate-et → az
**A1** felső korlát cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/weekly_quest_generator_test.dart
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

1. A heti mag származtatása az R17 mintájára (hét + profil + katalógus-verzió).
2. A négy objective-típus generálása.
3. A felső korlát érvényesítése az aktív napokra.
4. A cél skálázása az elérhető heti idővel, magyarázható bemenetekkel.
5. A haladás megőrzése tervváltozáskor.
6. Semleges heti átvezető összefoglaló.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A 7/7 objective.** A műfaj legkézenfekvőbb heti célja, és egyetlen kihagyott nap után a hét hátralévő része értelmetlenné válik (A1).
- **A haladás arányosítása.** Matematikailag „korrekt”, és visszamenőleg elveszi a valós teljesítményt (A3).
- **A fix cél.** Egyszerű, és utazó vagy leterhelt héten teljesíthetetlen — a büntető minta közvetett formája (A2).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
