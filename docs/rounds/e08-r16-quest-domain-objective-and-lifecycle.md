# E08-R16 — Quest domain, objective és életciklus

- **Státusz:** READY (pre-flight revízió 2026-08-21, mérve: `main @ 5967831a`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 16
- **Kör-azonosító:** `E08-R16`
- **Branch:** `<motor>/e08-r16-quest-domain-objective-and-lifecycle`
- **Előfeltétel:** `E08-R15` merge-elve (achievement felület)
- **Brief szerzője:** Claude (Opus 5)
- **Pre-flight ADR:** `ADR 0382` — az atomi foglaló adta. Az ADR-t az orchestrátor írja meg a
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

## 0.0 Pre-flight revíziók — 2026-08-21

### 0.0.1 Aktuális kódmérés és végrehajtható típusszerződés

A dispatch előtti mérés az aktuális `main @ 5967831a` állapoton a következőt
találta:

- `lib/features/gamification/domain/quests/` és quest-státuszt előállító
  reducer ma nincs; ezért nincs elérhetetlen, örökölt cél-státusz vagy
  erőforrás-acquire lánc, amelyhez a körnek igazodnia kellene;
- az R13 objektív-metika pontos típusa az `AchievementMetric`, stabil kódjai:
  `eventCount`, `durationSeconds`, `score`, `baseXp`, `durationXp`,
  `qualityXp`, `improvementXp`, `diversityXp`, `totalXp`;
- a practice-generator publikus szerződése exportálja a stabil `BlockId`-t,
  a practice feature publikus szerződése pedig a `PracticeMode`-ot; a quest
  ezekre a két `public.dart` határon keresztül hivatkozik, belső feature-import
  nélkül;
- az R03 `RewardLedgerEntry` és `RewardReason.questCompleted` már létezik.
  A domain nem végez repository-I/O-t: a sikeres completion eredménye
  kötelezően és azonnal tartalmazza a determinisztikus ledger entry-t, így
  completion nem reprezentálható reward nélkül. A későbbi application-hívó
  ezt az R03 idempotens repositoryba írja; külön `claim()` állapot vagy API
  nincs.

A quest objective zárt sealed vokabulárja ezért négy konkrét hivatkozás:
validált stabil skill-tag, `BlockId`, `PracticeMode`, illetve
`AchievementMetric`; az explicit `UnknownQuestObjective` csak a fail-closed
decode/validáció mérésére létezik, érvényes definícióban nem fogadható el.

Az ütemezés `generationEpochDay` egész napazonosítót,
`timezoneOffsetMinutes` értéket, pozitív `catalogVersion`-t és UTC
`expiresAt` instantot tárol. Az aktivitási intervallum felső határa exkluzív:
`now < expiresAt` aktív, `now >= expiresAt` lejárt.

Az állapotgép definiált élei: `active → completed|expired|replaced`, továbbá
`completed|expired|replaced → archived`; az `archived` terminális. Minden
sikeres él stabil reason code-ot ad, minden más él típusos failure. A
`complete` parancs idempotens kivétel az élképzés alól: ismételve az eredeti
completion időt és ugyanazt a determinisztikus ledger ID-t adja vissza, új
jutalmat nem hoz létre.

### 0.0.2 ADR-szám, visszakeresett előzmény és brief-helyesbítések

Az előre írt `0312` nem foglalható ehhez a körhöz: a repositoryban már az
elfogadott `docs/adr/0312-knowledge-rag.md` viseli. A kötelező
`tools/round-slots.py reserve-adr --round E08-R16` futás `0382`-et adott;
ezért e kör saját döntési artefaktuma
`docs/adr/0382-quest-objective-and-lifecycle-contract.md`. A brief minden
korábbi `0312` kör-ADR hivatkozását ez a revízió írja felül; a merge-elt ADR
0312 változatlan marad.

A kötelező, szűkített RAG-keresések releváns előzményei: `adr/0073`
(determinista, tiszta state machine), `adr/0374` (zárt, típusos objective és
fail-closed unknown), valamint `lessons/L20` (egy átmenettábla önmagában nem
bizonyít elérhető inpututat). A teljes korpuszos keresés elsődlegesen ezt a
briefet és a mai public barrel-t hozta vissza. Az index friss, a mért HEAD-del
azonos (`5967831a`).

A korábbi rövid küszöbmondat felcserélte az acceptance irányát; ezt a §6.1
helyesbíti: lejárat előtt completion elfogadott, a határon és utána completion
elutasított, az expiry viszont elfogadott. A Chapter 9 kötelező
„completion idempotency” ellenőrzése külön A9 cellát kapott.

Az ADR 0290 nem tilt általánosan minden claim fogalmat: idempotens claimet és
UI-oldali jutalomszámítás-tilalmat mond ki. E kör szigorúbb, claim nélküli
quest-szerződésének normatív forrása a Chapter 9 Kör 16 és az ADR 0382.

**Kockázat = high, indoklás:** a completion egyszerre változtat tartós
quest-életciklust és állít elő jutalom-főkönyvi receiptet. Hibás
idempotenciával duplikált XP, hibás expiryvel elvesző reward vagy részleges
haladás keletkezhet; ezért a correctness review mellett a külön security
review is kötelező.

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
- Az `ADR 0290` §2: az esetleges beváltás idempotens, és a felület nem számol
  jutalmat; e kör Chapter 9 szerződése ennél szigorúbb, quest-claimet nem enged.

## 3. Scope

**Benne van:** az `active` / `completed` / `expired` / `replaced` / `archived` állapotok · típusos
objective-hivatkozás (skill-címke, terv-blokk, mód, metrika) · a generálás napja, időzóna-eltolás,
katalógus-verzió és lejárat tárolása · a teljesítés és a jutalom KÜLÖN állapot, de a jutalom
**automatikus** · helyettesítés indok-kóddal · a lejárat NEM törli a gyakorlási eredményt.

**NINCS benne (tilos):**

- A generálás (Kör 17/18), a challenge (Kör 19), a felület (Kör 20).
- Beváltás-mechanika (claim) bevezetése — a §5.1 tiltja.
- `docs/adr/**` — az ADR 0382-t az orchestrátor írja.

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

## 5. Kötött architekturális döntések (ADR 0382)

### 5.1 A jutalom AUTOMATIKUS — nincs beváltás (claim)

A teljesített küldetés domain-eredménye azonnal tartalmazza a determinisztikus,
R03-kompatibilis főkönyvi bejegyzést. A felhasználónak
nem kell megnyitnia a képernyőt, nem kell gombot nyomnia, és a jutalom nem jár le.

**NEM elfogadható gyengítés:** „claim” gomb, akár csak animáció kedvéért. A beváltás-alapú
minta elveszi a jutalmat attól, aki nem nyitja meg a felületet — a Chapter 9
Kör 16 és az ADR 0382 tiltja; az ADR 0290 ehhez az idempotens ledger- és
UI-oldali nem-számítási alapot adja.

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
| A9 | A completion ismétlése ugyanazt a completion-időt és ledger ID-t adja, új jutalmat nem hoz létre | `quest_model_test.dart` — idempotencia-cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A jutalom claim-hez kötött | **A1** és **A2** |
| A lejárat nullázza a haladást | **A3** |
| Nem definiált átmenet némán no-op | **A4** |
| Az objective szabad szöveg | **A6** |
| Az időzóna-eltolás nem tárolódik | **A7** |
| Az átmenet néma `bool` | **A5** |
| Az ismételt completion új receiptet vagy új időpontot hoz létre | **A9** |

**A küszöb három kötelező cellája** (a lejárati időpont (`expiresAt`) — a küldetés aktivitásának határa):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `expiresAt - 1s` (a lejárat előtt) | a küldetés **aktív**, a teljesítés jutalmat ad |
| **rajta** (a küszöbön) | pontosan `expiresAt` | a küldetés **MÁR lejárt** — a lejárati időpont a LEJÁRT oldalhoz tartozik (exkluzív felső határ az aktivitásra) |
| a küszöb **fölött** | `expiresAt + 1s` | lejárt; a haladás és a gyakorlási eredmény érintetlen |

A hármas tömören: **alatt** → completion elfogadott, expiry elutasított ·
**rajta** → completion elutasított, expiry elfogadott · **fölötte** →
completion elutasított, expiry elfogadott.

A lejárt oldal a határon **inkluzív** — a fenti táblázat „rajta” sora mondja
ki, melyik oldal nyer. A három kiszámolt UTC fixture:
`2026-08-21T23:59:59Z / 2026-08-22T00:00:00Z / 2026-08-22T00:00:01Z`.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a
completion eredményéből az automatikus ledger entry létrehozását (mintha csak
egy későbbi `claim()` adná),
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

### Megvalósítás

- `quest_objective.dart`: zárt, JSON-képes skill-tag / `BlockId` /
  `PracticeMode` / `AchievementMetric` objective-vokabulár; ismeretlen type
  explicit sentinel, amelyet a definition fail-closed elutasít.
- `quest_schedule.dart`: verziózott generálási nap, eredeti timezone-offset,
  pozitív katalógusverzió és UTC lejárati instant; az aktivitási felső határ
  exkluzív.
- `quest_definition.dart`: napi/heti, verziózott definition és runtime
  validált, pozitív automatikus reward-paraméterek.
- `quest_progress.dart`: immutable, ötállapotú transition-result modell;
  completionkor azonnali, determinisztikus `quest:<id>:completion` receipt;
  idempotens újra-completion; expiry a progress/evidence mezőket változatlanul
  őrzi.
- `public.dart`: a négy quest domain contract exportja.
- `quest_model_test.dart`: A1–A9 és a három expiry-határ tesztje.

### TDD- és ellenőrzési bizonyíték

- RED: `flutter test test/features/gamification/domain/quest_model_test.dart`
  a production contractok hiányában fordítási hibával állt meg
  (`QuestProgress`, `QuestDefinition`, `QuestObjective` és lifecycle típusok
  nem találhatók).
- GREEN: ugyanaz a célzott teszt a contractok elkészülte után `8` teszttel
  zölden futott.
- Formázás: `dart format` a négy új domain fájlon, a public barrelen és a
  célteszten — `Formatted 6 files (5 changed)`.
- Kötelező valódi-sértés próba: a completion-eredmény automatikus receiptjét
  ideiglenesen eltávolítva a teljes `tools/round-gate.sh
  test/features/gamification/domain/quest_model_test.dart` futásban format és
  analyze zöld volt, a célteszt A1/A2 és A9 cellája piros lett (2 failure:
  `Actual: <null>` receipt). A receiptet ezután visszaállítottam.
- Végső round-gate: `tools/round-gate.sh
  test/features/gamification/domain/quest_model_test.dart` — 6/6 zöld
  (format, analyze, célteszt, architecture, secrets, l10n).

### Eltérés és nem futtatott ellenőrzés

- Nincs scope-eltérés. Backend, CI, PR és merge nem futott: nem implementer
  feladat.

## 11. Review — a Claude tölti ki
