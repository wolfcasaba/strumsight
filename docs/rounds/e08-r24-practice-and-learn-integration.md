# E08-R24 — Practice Engine és Learn integráció

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 24
- **Kör-azonosító:** `E08-R24`
- **Branch:** `<motor>/e08-r24-practice-and-learn-integration`
- **Előfeltétel:** `E08-R23` merge-elve (Gamification Hub)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0317` — STALE, lásd §0.0 (a foglaló a tényleges
  szabad számot, `ADR 0390`-et adta). Az ADR-t a Claude írja meg a kör
  indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
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

## 0.0 Pre-flight revízió (Claude, 2026-08-22)

**ADR-szám korrekció:** a brief `0317`-et nevezte meg előre kiosztott
ADR-számként (2026-08-18-i írás állapota), de `docs/adr/` mára `0389`-ig tart
— a `0317` egy korábbi, független kör alatt régen elkelt. A kötelező
`tools/round-slots.py reserve-adr --round E08-R24` futás **`0390`**-et adott
(mérve); a foglaló eredménye az irányadó. Az architekturális döntéseket
[`ADR 0390`](../adr/0390-practice-and-learn-gamification-adapter-boundary.md)
rögzíti a lenti öt pontban.

**Kockázat = high, indoklás (S7):** a `risk = "high"` a brief mérce-tartalma
miatt áll — ez az ELSŐ kör, ami a gamifikáció jutalom-láncát (jogosultság →
XP → főkönyv) éles felhasználói eredményforráshoz (gyakorlási session,
lecke-befejezés) köti; egy hibás jogosultsági besorolás vagy egy nem stabil
esemény-azonosító közvetlenül XP-duplázást vagy jogosulatlan jutalmat
okozna — NEM azért, mert az `allowed_paths` a router
`high_risk_path_fragments` listájából (auth, authorization, camera,
credential, crypto, encryption, migration, payment, privacy, secret, share,
upload, vision) bármelyiket tartalmazná — nem tartalmazza.

**Kód-mérés a §2 „Jelenlegi állapot" ellen (a mérési szabály, §1 pont 1–2):**

- `grep -n "class.*ActivityEvent extends" lib/features/gamification/domain/
  activity/learning_activity_event.dart` → hat konkrét típus
  (`PracticeActivityEvent`, `SongActivityEvent`, `AnalysisActivityEvent`,
  `PlanActivityEvent`, `TutorActivityEvent`, `VisionActivityEvent`) — **nincs
  külön "lecke" típus**. A megkülönböztetés az `ActivitySource` mezőn megy
  (`practice` / `learn`); mindkét adapter `PracticeActivityEvent`-et épít
  (ADR 0390 1. döntés).
- `grep -rln "features/streak\|features/progress" lib/features/{practice,learn}/`
  → a `practice` egyetlen találata
  (`data/adapters/daily_challenge_practice_adapter.dart`) egy
  `DailyChallenge`→`PracticeDefinition` konverzió, session-befejezéssel
  nincs kapcsolatban; a `learn`-ben az `application/` szinten (ami MA nem is
  létezik könyvtárként) nulla találat, a két UI-screen-találat
  (`lesson_list_screen.dart`, `learn_screen.dart`) megjelenítési olvasás,
  nem írás. A brief §2 „MA közvetlenül hívja" állítása tehát a UI-rétegre
  igaz, az application-rétegre NEM — ez a kör egy önálló, egyelőre be nem
  kötött adaptert épít (mint a R02 kanonikus esemény), a tényleges élő
  hívási pont bekötése (`practice_session_controller.dart`, a `learn`
  screenek) ennek a briefnek a tiltott zónájában van, tehát KÉSŐBBI kör
  dolga — a §3 „fokozatos adapter mögé vitele" ebben a körben az adapter
  MEGÉPÍTÉSÉT jelenti, nem a hívási pontok tényleges átkötését.
- `find lib/features/gamification -iname "*eligib*"` →
  `application/reward_eligibility_policy.dart` (`ActivityOutcome.completed/
  cancelled/failed`, ADR 0338) és
  `infrastructure/default_reward_eligibility_policy.dart` léteznek, a `A5`
  megszakítás/részleges-session mátrixa ezekre a MEGLÉVŐ kapukra épül, új
  gate nem kell (ADR 0390 3. döntés).
- `grep -n "RewardLedgerEntry(" lib/features/gamification/application/*.dart`
  → két, EGYMÁSTÓL FÜGGETLEN írási minta létezik: a
  `daily_challenge_service.dart` közvetlenül hívja
  `rewardLedger.appendIfAbsent()`-et (nincs R05/R06 kapu), az
  `ActivityEventIngestor.recordSavedActivity` pedig az outbox-mintát követi
  (ADR 0333). A brief §6 A1 explicit „esemény → outbox → jogosultság → XP →
  főkönyv" sorrendje a MÁSODIKAT jelöli ki — ADR 0390 2. döntés.
- `ls test/features/gamification/` → `integration/` alkönyvtár MA nem
  létezik, az implementer hozza létre a `practice_reward_flow_test.dart`-tal
  együtt (nincs meglévő fájl, amit felül kellene írni).

**Visszakeresett előzmény (ADR 0312, §4.9):**

- `adr/0329` (canonical-activity-event-contracts), `adr/0333`
  (activity-outbox-reliable-processing), `adr/0338`
  (reward-eligibility-policy-four-gates), `adr/0301`
  (reward-ledger-append-only-idempotency) — mind a négy MEGLÉVŐ szerződést
  ez a kör az adapterek mögött használja fel, egyik sem nyílik újra
  (szűkített `lessons,halts,adr` lekérdezés, `adr/0290` emb#1, `adr/0344`
  emb#2, `adr/0085` bm25#8 emb#7).
- `lessons/L286` — **közvetlenül releváns**: a „mérd meg a `public.dart`-ot"
  pre-flight utasítás a repository/provider réteget is jelenti, nem csak a
  value-típusokat — ez erősítette meg, hogy a fenti `grep`-eket a tényleges
  application-rétegig kell futtatni, nem elég a domain value-típusok
  meglétét nézni.
- `lessons/L190` — a `public.dart`-only szabály az import CÉLJÁT
  kényszeríti ki, nem a szimbólumokat; releváns figyelmeztetés az A4
  architektúra-guard bővítéséhez (ne engedjen „csak egy típusért" kivételt).
- Nincs releváns korábbi HALT vagy self-heal erre a mintára (a lekérdezés
  0 `halts`-találatot adott) — a legközelebbi analóg az `E08-R02` (R02
  ugyanígy önálló, be nem kötött adaptert épített, hívó nélkül landolt,
  nem HALT-olt).

Az `allowed_paths` és a `gate_tests` a fentiek fényében változatlan marad —
egyik mérés sem igényelt lista-bővítést.

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
