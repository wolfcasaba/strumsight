# E08-R24 — Practice Engine és Learn integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 24
- **Kör-azonosító:** `E08-R24`
- **Branch:** `<motor>/e08-r24-practice-and-learn-integration`
- **Előfeltétel:** `E08-R23` merge-elve (Gamification Hub)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0317` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/practice/` session-eredmény és a `lib/features/learn/` lecke-eredmény TÉNYLEGES public szerződését, valamint a `lib/features/learn/data/lesson_progress_repository.dart`-ot — a csillagok a saját domainjükben maradnak. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice/application/gamification_practice_adapter.dart",
  "lib/features/learn/application/gamification_lesson_adapter.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/integration/practice_reward_flow_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r24-practice-and-learn-integration.md",
]
gate_tests = [
  "test/features/gamification/integration/practice_reward_flow_test.dart",
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

Kösd be a két legfontosabb eredmény-forrást a jutalmazási folyamatba — **dupla számolás
nélkül**, a lecke-csillagok érintetlenül hagyásával, és visszakapcsolható migrációs kapcsolóval.

## 2. Jelenlegi állapot — mért tények

- `lib/features/learn/` 24 fájl; a csillagok és a legjobb pontosság a `lesson_progress_repository.dart`-ban élnek — ez a kör NEM nyúl hozzájuk.
- A `lib/features/learn/` és `lib/features/practice/` MA közvetlenül hívja a streak/progress rendszert — ezt fokozatosan adapter mögé kell vinni.
- Az R04 outboxa a session mentése UTÁN vesz át eseményt.
- `test/features/learn/` MA zöld — elbukása `blocked`.

## 3. Scope

**Benne van:** stabil esemény a gyakorlási session és blokk befejezése után · a lecke legjobb
pontossága és csillagai a SAJÁT domainjükben maradnak · a lecke-befejezés esemény ne adjon
kétszer jutalmat útvonal-újranyitáskor · megszakított és részleges session kezelése · a legacy
közvetlen streak/gyakorlási-napló hívások fokozatos adapter mögé vitele · **kettős írás**
időszak migrációs kapcsolóval, dupla számolás nélkül.

**NINCS benne (tilos):**

- A `lib/features/learn/data/**` és a csillag-logika módosítása.
- A `lib/features/gamification/**` belső fájljainak módosítása — az adapterek a `public.dart`-on át dolgoznak.
- A `lib/features/streak/**` és `lib/features/progress/**` átírása.
- `docs/adr/**` — az ADR 0317-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/practice/application/gamification_practice_adapter.dart` | **ÚJ** — a gyakorlás adaptere |
| `lib/features/learn/application/gamification_lesson_adapter.dart` | **ÚJ** — a lecke adaptere |
| `lib/features/gamification/public.dart` | CSAK export-sor, ha új szerződés kell |
| `test/features/gamification/integration/practice_reward_flow_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az adapter-határ guardja |

**Tilos zóna:** `lib/features/practice/**` és `lib/features/learn/**` MINDEN más fájlja · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**` · `lib/features/gamification/` belső (nem `public.dart`) fájljai

## 5. Kötött architekturális döntések (ADR 0317)

### 5.1 AZ ADAPTER CSAK A PUBLIC SZERZŐDÉST importálja

A `practice` és `learn` feature soha nem importálja a gamification `data/` vagy
`domain/` belső fájljait — kizárólag a `public.dart`-ot. Az architektúra-guard ezt méri (A4).

**NEM elfogadható gyengítés:** „csak egy típusért” közvetlen import. Onnantól a
gamification belső átalakítása feature-öket tör el.

### 5.2 A LECKE-CSILLAGOK A SAJÁT DOMAINJÜKBEN MARADNAK

A gamifikáció **nem** veszi át a csillagokat és a legjobb pontosságot. Azok a
`learn` feature saját mérőszámai, és változatlanul működnek (A2).

### 5.3 AZ ÚTVONAL-ÚJRANYITÁS NEM AD ÚJ JUTALMAT

A lecke-befejezés eseményének azonosítója a session-ből származik, nem a képernyő
életciklusából. Az eredmény-képernyő újranyitása ezért nem termel új eseményt — és ha mégis,
az R03 dedupja fogja.

### 5.4 KETTŐS ÍRÁS: kapcsolóval, dupla számolás NÉLKÜL

Az átmeneti időszakban a legacy és az új rendszer is megkapja az eseményt, de a
JUTALOM csak egyszer keletkezik (a legacy oldal statisztikát ír, nem XP-t). A kapcsoló
**visszakapcsolható**: kikapcsolva a viselkedés a maival azonos.

**NEM elfogadható gyengítés:** kettős írás kapcsoló nélkül — visszaút nélkül nem
merge-elhető biztonságosan.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A gyakorlási session befejezése végigmegy a folyamaton: esemény → outbox → jogosultság → XP → főkönyv | `practice_reward_flow_test.dart` — end-to-end cella |
| A2 | A lecke csillagai és legjobb pontossága VÁLTOZATLAN | a `test/features/learn` suite a §7 gate-ben |
| A3 | Az eredmény-képernyő újranyitása NEM ad új jutalmat | `practice_reward_flow_test.dart` |
| A4 | A `practice` és `learn` NEM importál gamification belső fájlt (csak `public.dart`) | `architecture_dependency_test.dart` |
| A5 | Megszakított session nem ad jutalmat; részleges session az R05 szabálya szerint kap | `practice_reward_flow_test.dart` — session-mátrix |
| A6 | A migrációs kapcsoló KIKAPCSOLVA a mai viselkedést adja (nulla új mellékhatás) | `practice_reward_flow_test.dart` — kapcsoló-hármas |
| A7 | Kettős írás mellett a széria és az XP NEM duplázódik | `practice_reward_flow_test.dart` |
| A8 | A `test/features/learn` suite VÁLTOZATLANUL zöld | a §7 gate kimenete |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az adapter közvetlenül importálja a gamification `data/`-t | **A4** |
| A gamifikáció átveszi a csillag-számítást | **A2** |
| Az esemény azonosítója a képernyő életciklusából jön | **A3** |
| Kettős írás mellett a legacy oldal is XP-t ír | **A7** |
| A kapcsoló nem kapcsolható vissza | **A6** |
| A megszakított session jutalmat kap | **A5** |

**A küszöb három kötelező cellája** (a migrációs kapcsoló (`gamificationDualWriteEnabled`) három állása):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | **KIKAPCSOLVA** | a viselkedés BITRE a maival azonos: nincs új esemény, nincs új főkönyv-bejegyzés |
| **rajta** (a küszöbön) | **KETTŐS ÍRÁS** (átmeneti állás) | mindkét rendszer megkapja az eseményt, de a JUTALOM csak egyszer keletkezik |
| a küszöb **fölött** | **CSAK ÚJ RENDSZER** | a legacy hívás megszűnik; ez a Kör 30 végállapota, NEM ebben a körben aktiválandó |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** írass XP-t a legacy oldalon is kettős írás mellett, futtasd a gate-et → az **A7**
cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/integration/practice_reward_flow_test.dart test/core/architecture_dependency_test.dart test/features/learn
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

1. `gamification_practice_adapter.dart` — session/blokk befejezés → kanonikus esemény.
2. `gamification_lesson_adapter.dart` — lecke befejezés → esemény, a csillagok érintése NÉLKÜL.
3. Stabil esemény-azonosító a session-ből (nem a képernyő életciklusából).
4. Megszakított és részleges session kezelése.
5. A migrációs kapcsoló bevezetése, alapértéke KIKAPCSOLVA.
6. Az architektúra-guard bővítése az adapter-határra.
7. A valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint — a `learn` suite-tal EGYÜTT.

## 9. Kockázatok

- **A közvetlen import „egy típusért”.** A gamification későbbi átalakítása így feature-öket tör el (A4).
- **A képernyő-életciklusból származó azonosító.** Az eredmény-képernyő újranyitása jutalmat termelne (A3).
- **A kapcsoló nélküli kettős írás.** Visszaút nélkül a merge kockázata aránytalan (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
