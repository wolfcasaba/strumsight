# E08-R26 — Analysis, Vision, Tutor és Practice Generator integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 26
- **Kör-azonosító:** `E08-R26`
- **Branch:** `<motor>/e08-r26-cross-feature-gamification-integration`
- **Előfeltétel:** `E08-R25` merge-elve (dal-integráció)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/analyze/`, `lib/features/vision/`, `lib/features/ai_tutor/` és `lib/features/practice_generator/` TÉNYLEGES public szerződését — a mappanevek eltérhetnek az SDD-ben szereplőktől (`tutor`, `practice_planner`); eltérésnél §0.0 revízió, NEM új mappa létrehozása. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/analyze/application/gamification_analysis_adapter.dart",
  "lib/features/vision/application/gamification_vision_adapter.dart",
  "lib/features/ai_tutor/application/gamification_tutor_adapter.dart",
  "lib/features/practice_generator/application/gamification_plan_adapter.dart",
  "test/features/gamification/integration/cross_feature_reward_flow_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r26-cross-feature-gamification-integration.md",
]
gate_tests = [
  "test/features/gamification/integration/cross_feature_reward_flow_test.dart",
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

Kösd be a maradék négy forrást **konzervatív bizalmi szabályokkal** — és zárd ki a
két legfontosabb visszaélési utat: a **beszélgetés-farmolást** és a terv-jutalom duplázását.

## 2. Jelenlegi állapot — mért tények

- A tényleges mappanevek: `lib/features/analyze/`, `lib/features/vision/`, `lib/features/ai_tutor/`, `lib/features/practice_generator/` (az SDD `tutor`/`practice_planner` néven hivatkozik rájuk — a MÉRT nevek az irányadók).
- Az R05 `EvidenceTrust` kapuja már megvan; ez a kör a forrásonkénti bizalmi szabályokat alkalmazza.
- Az `ADR 0289`: bizonytalan bizonyíték nem old fel elsajátítottságot.

## 3. Scope

**Benne van:** az Analysis esemény dedupolhatósága forrás-hash és elemző-verzió alapján · a Vision
esemény CSAK minőségi kapu után ad technikai haladást · a **beszélgetés önmagában NEM ad XP-t** ·
a terv-befejezés kizárólag befejezési bónusz · az adapterek CSAK public szerződést importálnak ·
hiányzó jövőbeli feature esetén funkció-kapcsolós tartalék.

**NINCS benne (tilos):**

- A négy feature bármely más fájljának módosítása.
- A gamification belső fájljainak importálása.
- Új AI-hívás vagy modell-használat.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/analyze/application/gamification_analysis_adapter.dart` | **ÚJ** — elemzés-adapter |
| `lib/features/vision/application/gamification_vision_adapter.dart` | **ÚJ** — vision-adapter |
| `lib/features/ai_tutor/application/gamification_tutor_adapter.dart` | **ÚJ** — tutor-adapter |
| `lib/features/practice_generator/application/gamification_plan_adapter.dart` | **ÚJ** — terv-adapter |
| `test/features/gamification/integration/cross_feature_reward_flow_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az adapter-határok guardja |

**Tilos zóna:** a négy feature MINDEN más fájlja · `lib/features/` többi feature-e · `lib/features/gamification/` belső fájljai · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések

### 5.1 A BESZÉLGETÉS ÖNMAGÁBAN NEM AD XP-T

A tutorral folytatott beszélgetés nem jutalmazható tevékenység. Jutalom csak az
abból **következő gyakorlásért** jár, amelyet a saját forrása jelent.

**NEM elfogadható gyengítés:** „kis XP az elköteleződésért”. Az chat-farmolást termel, és
az ADR 0289 szerint sem részvételt, sem tudást nem mér értelmesen.

### 5.2 A VISION CSAK MINŐSÉGI KAPU UTÁN ad technikai haladást

Alacsony megbízhatóságú kamerás eredmény nem járul hozzá technikai haladáshoz
(az R21 mastery-kapuja szerint), és nem old fel semmit. Az alap-XP az erőfeszítésért
továbbra is jár (R05).

### 5.3 A TERV-BEFEJEZÉS CSAK BÓNUSZ

A terv blokkjainak elvégzése már jutalmazódott a saját forrásán (gyakorlás, dal).
A terv befejezése ezért kizárólag **befejezési bónuszt** ad — nem összegzi újra a blokkokat.

**NEM elfogadható gyengítés:** a terv-befejezéskor a blokkok jutalmának ismételt kiadása.

### 5.4 AZ ELEMZÉS DEDUPOLHATÓ forrás-hash + elemző-verzió alapján

Ugyanannak a felvételnek az újraelemzése ugyanazzal az elemző-verzióval NEM ad
új jutalmat. Új elemző-verzió viszont legitim új eredmény.

### 5.5 FUNKCIÓ-KAPCSOLÓS TARTALÉK a hiányzó feature-ökre

Ha egy forrás-feature az adott buildben nem elérhető, az adapter **fordítási hiba
nélkül** kimarad (funkció-kapcsoló vagy feltételes regisztráció) — nem omlik össze és nem
generál hamis eseményt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Tutor-beszélgetés önmagában NULLA XP-t ad | `cross_feature_reward_flow_test.dart` — chat-farm cella |
| A2 | Alacsony megbízhatóságú Vision-eredmény nem ad technikai haladást, de az alap-XP megmarad | `cross_feature_reward_flow_test.dart` — bizalmi mátrix |
| A3 | A terv befejezése csak bónuszt ad; a blokkok jutalma nem ismétlődik | `cross_feature_reward_flow_test.dart` — duplázás-cella |
| A4 | Ugyanazon felvétel újraelemzése AZONOS elemző-verzióval nem ad új jutalmat | `cross_feature_reward_flow_test.dart` |
| A5 | ÚJ elemző-verzió új jutalmat ad | `cross_feature_reward_flow_test.dart` |
| A6 | Az adapterek CSAK public szerződést importálnak | `architecture_dependency_test.dart` |
| A7 | Hiányzó forrás-feature esetén a build és a folyamat ép marad (tartalék működik) | `cross_feature_reward_flow_test.dart` |
| A8 | Semmilyen új AI-hívás nem történik a jutalmazási úton | review + `cross_feature_reward_flow_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A beszélgetés „elköteleződési” XP-t kap | **A1** |
| Az alacsony megbízhatóságú Vision technikai haladást ad | **A2** |
| A terv-befejezés összegzi a blokkokat | **A3** |
| Az elemzés dedupja csak a felvétel-hash-en | **A5** (az új verzió sem ad jutalmat) |
| Az adapter belső gamification típust importál | **A6** |
| Hiányzó feature-nél fordítási hiba | **A7** |

**A küszöb három kötelező cellája** (a Vision megbízhatósági kapu (`minVisionConfidence`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `minVisionConfidence - 0.01` | **nincs** technikai haladás; alap-XP viszont **jár** (R05 §5.1) |
| **rajta** (a küszöbön) | pontosan `minVisionConfidence` | **VAN** technikai haladás — a küszöb az ELFOGADÓ oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `minVisionConfidence + 0.01` | van technikai haladás |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj kis XP-t a tutor-beszélgetésért, futtasd a gate-et → az **A1** chat-farm
cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/integration/cross_feature_reward_flow_test.dart test/core/architecture_dependency_test.dart
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

1. A négy feature TÉNYLEGES public szerződésének ellenőrzése (mappanevek!).
2. `gamification_analysis_adapter.dart` — forrás-hash + elemző-verzió dedup.
3. `gamification_vision_adapter.dart` — minőségi kapu utáni technikai haladás.
4. `gamification_tutor_adapter.dart` — beszélgetésre NULLA XP.
5. `gamification_plan_adapter.dart` — kizárólag befejezési bónusz.
6. Funkció-kapcsolós tartalék a hiányzó forrásokra.
7. Az architektúra-guard bővítése; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A chat-farmolás.** Az „elköteleződési” XP a legkézenfekvőbb ötlet, és mérhetetlen tevékenységet jutalmaz (A1).
- **A mappanév-eltérés.** Az SDD `tutor`/`practice_planner` néven hivatkozik; a MÉRT nevek `ai_tutor`/`practice_generator`. Új mappa létrehozása scope-sértés — a pre-flight ezt zárja.
- **A terv-jutalom duplázása.** A blokkok már fizettek; az újraösszegzés inflációt ad (A3).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
