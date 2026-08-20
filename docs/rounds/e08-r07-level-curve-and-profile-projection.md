# E08-R07 — Szintgörbe és profil-projekció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 7
- **Kör-azonosító:** `E08-R07`
- **Branch:** `<motor>/e08-r07-level-curve-and-profile-projection`
- **Előfeltétel:** `E08-R06` merge-elve (XP policy engine)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0305` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R03 lapozott olvasási felületét (`limit` + kurzor) — a teljes újraépítés erre hív; és az R06 `experience_points.dart` komponens-bontását. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/levels/level_definition.dart",
  "lib/features/gamification/domain/levels/level_curve.dart",
  "lib/features/gamification/domain/profile/gamification_profile.dart",
  "lib/features/gamification/application/profile_projector.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/domain/level_curve_test.dart",
  "docs/rounds/e08-r07-level-curve-and-profile-projection.md",
]
gate_tests = [
  "test/features/gamification/domain/level_curve_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió (2026-08-20, `main @ 634562d7`)

**ADR-szám korrekció: `0305` → `0342`.** A brief 2026-08-18-i megírásakor a
`0305` volt a következő szabad szám; azóta (E08-R01…R06 + több self-heal kör)
`0306`–`0341` mind foglalt lett. A `tools/round-slots.py reserve-adr --round
E08-R07` futtatása (ADR 0171 §4.1) a jelen pre-flightban `0342`-t adott —
**ez a kötelező szám**, nem a brief fejlécében álló `0305`. Az implementer a
`docs/adr/`-t egyébként sem érinti (tilos zóna) — az ADR-t a Claude írta meg
[`0342-monotonic-level-curve-and-rebuildable-profile-projection.md`](../adr/0342-monotonic-level-curve-and-rebuildable-profile-projection.md)
néven, a brief §5 döntéseiből.

**Mért, megerősített tények (§1 pre-flight-mérés):**

- `lib/features/gamification/domain/levels/` és `domain/profile/` **nem
  léteznek** — a brief §2 állítása pontos (`ls` a domain könyvtáron: csak
  `activity/`, `rewards/` van jelen).
- Az R03 ledger lapozott olvasási felülete megerősítve:
  `RewardLedgerRepository.readPage({required int limit, String? cursor})` →
  `RewardLedgerPage { entries, nextCursor }`
  (`lib/features/gamification/data/reward_ledger_repository.dart:16`). A
  teljes újraépítés ezt hívja lapozva, `nextCursor == null`-ig.
- Az R06 komponens-bontás (`ExperiencePoints`: `baseXp/durationXp/qualityXp/
  improvementXp/diversityXp` → `totalXp`) a policy receiptjében él
  (`domain/rewards/experience_points.dart`); maga a **ledger-bejegyzés**
  (`RewardLedgerEntry`) ezt már `baseXp`/`bonusXp`/`totalXp`-re tömöríti
  (`policyVersion`, `schemaVersion` mellett). A `profile_projector.dart`
  ehhez a **ledger-bejegyzés** `totalXp` mezőjéhez olvas — a projektornak
  NEM kell (és NEM is tudja) az öt-komponensű bontást visszafejteni.
- Lokalizációs kulcs konvenció: a kódbázisban élő minta a `String titleKey`
  mező (l. `lib/features/practice/data/builtin_practice_catalog.dart`,
  `lib/features/practice/data/adapters/practice_adapter_keys.dart`) — a
  `LevelDefinition` ezt a mintát kövesse (`titleKey`, nem beégetett szöveg,
  nem `AppLocalizations`-hívás a domain rétegben).

**Visszakeresés (ADR 0312/0331, §4.9, brief-lint S8):**

```
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "monoton szintgörbe level curve profil projekció rebuild"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "túlcsordulás védelem több szint egyszerre level up overflow monotonicity"
node tools/knowledge-rag.mjs --top 5 "level_curve.dart profile_projector.dart gamification_profile.dart monoton szint schemaVersion"
```

Legközelebbi releváns találat: **L26** — „«a profilból jön» ≠ a
profil-OBJEKTUM": egy SDD-szakasz stricter, KÜLÖN predikátumot rögzíthet,
mint amit egy naiv implementáció összemos. Áttételesen releváns itt: a
projektor NE tételezze fel, hogy egy szomszédos objektum (pl. az R06
`ExperiencePoints`) mezői közvetlenül leképezik a szükséges bemenetet —
minden mezőt a ténylegesen olvasott típuson (`RewardLedgerEntry.totalXp`)
mérj, ne a szomszédos policy-típuson. **Nincs közvetlenül a monoton
szintgörcs/túlcsordulás témára illő korábbi lecke vagy halt** — a keresés
lefutott, a hiány dokumentált (S8 teljesítve).

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

Stabil, **monoton** szintrendszer és a főkönyvből teljes egészében **újraépíthető**
profil. A szint soha nem csökkenhet, és a szint SOHA nem kapuz tartalmat
(ADR 0289: az XP a részvételt méri, nem a tudást).

## 2. Jelenlegi állapot — mért tények

- Az R03 főkönyve lapozottan olvasható; az R06 komponensenként bontott XP-t ad policy-verzióval.
- `lib/features/gamification/domain/levels/` és `domain/profile/` **nem létezik**.
- A meglévő `lib/features/learn/` tartalom-feloldása ma **nem** XP-alapú (`lesson_progress_repository.dart`) — ez a kör ezt nem változtatja meg, csak kimondja invariánsként.
- Az i18n konvenció: minden felhasználónak látszó szöveg ARB-n át megy (`lib/l10n/app_en.arb`, `app_hu.arb`) — a szintcímek is lokalizációs kulcsok.

## 3. Scope

**Benne van:** monoton szintgörbe túlcsordulás-védelemmel · összes XP → aktuális szint + a következő
szintig hátralévő haladás · verziózott profil-pillanatkép · **teljes** újraépítés a főkönyvből
ÉS inkrementális projekció · több szint egyszerre átlépésének kezelése · a szintcímek
lokalizációs kulcsként.

**NINCS benne (tilos):**

- A szint felhasználása tartalom-kapuzásra (§5.4) — abszolút tilos.
- Perzisztencia — a Kör 8 storage-rétege; itt a projekció memóriában dolgozik.
- Bármely UI (Kör 23).
- A `lib/l10n/*.arb` szerkesztése — a kulcsokat a felületi kör (Kör 23) veszi fel.
- `docs/adr/**` — az ADR 0305-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/levels/level_definition.dart` | **ÚJ** — egy szint definíciója (küszöb + lokalizációs kulcs) |
| `lib/features/gamification/domain/levels/level_curve.dart` | **ÚJ** — a monoton görbe, EGY forrásból |
| `lib/features/gamification/domain/profile/gamification_profile.dart` | **ÚJ** — a verziózott profil-pillanatkép |
| `lib/features/gamification/application/profile_projector.dart` | **ÚJ** — teljes és inkrementális projekció |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/domain/level_curve_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0305)

### 5.1 A szint SOHA nem csökken

A projekció monoton: több XP soha nem adhat alacsonyabb szintet, és egy
újraépítés soha nem viheti lejjebb a felhasználót. Ez akkor is igaz, ha egy későbbi
policy-verzió más súlyokkal számol.

**NEM elfogadható gyengítés:** a szint „újraszámítása lefelé” balance-váltás után.
A felhasználótól elvett szint a termék legláthatóbb bizalomvesztése.

### 5.2 A profil TELJESEN újraépíthető a főkönyvből

A profil **projekció**, nem független igazságforrás: a főkönyvből bármikor
determinisztikusan előállítható. Az inkrementális frissítés csak gyorsítás — az
eredményének azonosnak kell lennie a teljes újraépítéssel (ez acceptance-cella, A2).

**NEM elfogadható gyengítés:** a profil önálló írása a főkönyv megkerülésével. Onnantól
két igazságforrás van, és az első eltérés után nem eldönthető, melyik a helyes.

### 5.3 A görbe EGYETLEN forrásból származik

A szintküszöbök egyetlen `LevelCurve` definícióban élnek. A szórt küszöbök a
Kör 29 balance-szimulációját mérhetetlenné teszik.

### 5.4 Az XP-szint NEM kapuz tartalmat

Semmilyen lecke, dal, gyakorlat vagy funkció nem tehető elérhetővé vagy
elérhetetlenné a szint alapján. Az [`ADR 0289`](../adr/0289-mastery-is-evidence-not-xp.md)
kimondja: az XP a részvételt méri. A tartalom-feloldás mért teljesítményhez köthető
(Kör 21 mastery), az XP-hez SOHA.

### 5.5 Túlcsordulás-védelem és a több szint egyszerre

Nagyon nagy XP-értéknél a görbe nem csordulhat túl és nem adhat negatív szintet;
egyetlen esemény több szintet is átléphet, és ilyenkor MINDEN átlépett szint megjelenik a
projekció kimenetében (a Kör 22 celebrationje ezt fogja felhasználni).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A görbe monoton: nagyobb összes XP soha nem ad kisebb szintet | `level_curve_test.dart` — property-jellegű, növekvő XP-sorozaton |
| A2 | A teljes újraépítés és az inkrementális projekció AZONOS profilt ad | `level_curve_test.dart` — egyenértékűségi cella |
| A3 | Egyetlen esemény több szintet is átléphet, és MINDEN átlépett szint megjelenik | `level_curve_test.dart` |
| A4 | Nagyon nagy XP-nél nincs túlcsordulás és nincs negatív szint | `level_curve_test.dart` — `maxInt` közeli bemenet |
| A5 | A szintküszöbök EGYETLEN forrásból jönnek (a görbe módosítása átüt) | `level_curve_test.dart` |
| A6 | A szintcímek lokalizációs KULCSOK, nem beégetett szövegek | `level_curve_test.dart` + review |
| A7 | A profil verziózott (`schemaVersion`), és ismeretlen verzió hibát ad | `level_curve_test.dart` |
| A8 | A szint NEM használható tartalom-kapuként: a projekció nem ad `unlock`-jellegű kimenetet | review + `level_curve_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A projekció a balance-váltás után lefelé számol | **A1** (a monotonitás-cella) |
| Az inkrementális ág külön logikát használ | **A2** (az egyenértékűségi cella eltérést mutat) |
| Több szint átlépésekor csak a végállapot jelenik meg | **A3** |
| A küszöbök a projektorba égetve | **A5** |
| A szintcím beégetett angol szöveg | **A6** |
| A projekció `unlockedContent` mezőt ad | **A8** — az ADR 0289 megsértése |

**A küszöb három kötelező cellája** (a szintküszöb (`levelThreshold`) — a szintlépés határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `levelThreshold - 1` XP | **még az alacsonyabb szint**; a hátralévő haladás 1 XP |
| **rajta** (a küszöbön) | pontosan `levelThreshold` XP | **MÁR a magasabb szint** — a küszöb az ÚJ szinthez tartozik (inkluzív) |
| a küszöb **fölött** | `levelThreshold + 1` XP | a magasabb szint, 1 XP haladással a következő felé |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a projekciót úgy, hogy több szint átlépésekor csak a végállapotot adja vissza,
futtasd a gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/domain/level_curve_test.dart
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

1. `level_definition.dart` — küszöb + lokalizációs kulcs.
2. `level_curve.dart` — a monoton görbe, EGY forrásból, túlcsordulás-védelemmel.
3. `gamification_profile.dart` — verziózott pillanatkép.
4. `profile_projector.dart` — teljes újraépítés a főkönyvből (lapozva) + inkrementális ág.
5. A több szint egyszerre átlépésének kimenete (az átlépett szintek listája).
6. A `public.dart` export-sorai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A két igazságforrás.** A profil önálló írása gyorsabb, és az első eltérésnél eldönthetetlenné teszi, melyik a helyes (A2).
- **A kapuzás csábítása.** A szinthez kötött tartalom-feloldás a legkézenfekvőbb gamifikációs minta, és az ADR 0289 kifejezetten tiltja (A8).
- **A lefelé számolás.** Balance-váltáskor „korrektnek” tűnik újraszámolni; a felhasználótól elvett szint viszont visszafordíthatatlan bizalomvesztés (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
