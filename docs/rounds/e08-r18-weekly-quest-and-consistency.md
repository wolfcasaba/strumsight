# E08-R18 — Heti küldetés és következetességi objective

- **Státusz:** READY (pre-flight revízió: 2026-08-21, kód olvasva: `main @ 3000e9fa`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 18
- **Kör-azonosító:** `E08-R18`
- **Branch:** `<motor>/e08-r18-weekly-quest-and-consistency`
- **Előfeltétel:** `E08-R17` merge-elve (napi küldetés-generátor)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0386` — a számot a
  `tools/round-slots.py reserve-adr --round E08-R18` foglalta; az ADR-t a Sol
  orchestrátor írta meg a pre-flightban, az implementer a `docs/adr/**`-t nem
  érinti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R17 determinisztikus mag-származtatását (a heti generátor ugyanazt a mintát követi) és az R11 heti következetesség-projekcióját. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

## 0.0 Pre-flight revízió — 2026-08-21

A friss `main @ 3000e9fa` mérése az előre megírt brief három driftjét oldotta
fel, scope-bővítés nélkül:

1. Az R17 shipping contractja valóban caller-fed, immutable snapshotot és a
   `generationEpochDay|profileSnapshotKey|catalogVersion` UTF-8/FNV-1a mintát
   használ (`daily_quest_generator.dart`; `ADR 0384`). A heti seed ugyanez a
   minta, de a hívó-adta `generationEpochDay` a hét stabil kezdőnapja.
2. Az R11 tényleges heti projectionje a
   `StreakService.weeklyConsistency(endingEpochDay, qualifiedDayHistory)`;
   külön, egyedi, inkluzív 7 napos értéket ad és sem repositoryt, sem napi
   streak-state-et nem olvas. A heti generátor ezt sem hívja meg: kész,
   hívó-adta progress-számokat kap.
3. A prózai küszöb-összefoglaló felcserélte az elfogadott/elutasított oldalt,
   miközben a táblázat helyes volt. A mért hármas
   `python3 -c 'm=5; print({"below": m-1, "at": m, "above": m+1})'` →
   `4/5/6`: 4 és 5 elfogadott, 6 visszavágandó 5-re.

A `WeeklyRecap`-integrációhoz application-rétegben előállított angol mondat
ütközne az `AGENTS.md` §7 lokalizációs határával, miközben ARB-fájl nincs az
allowlistben. A rollover ezért típusos, nyelvfüggetlen tényprojekció
(`status`, `targetUnits`, `completedUnits`); a későbbi UI-kör lokalizálja.

**Visszakeresett előzmény**, szűkített korpusszal előbb: `adr/0384` megerősítette a
caller-fed snapshotot és a stabil FNV seedet; `adr/0382` a weekly lifecycle
kapcsolatát; `lessons/L13` és `lessons/L241` a számolt határértékek
újramérését. A teljes korpusz közvetlenül az R17 production kódját és tesztjét
hozta első helyen. A keresések nem mutattak a jelen revízióval ellentétes
elfogadott döntést.

**Kockázat = high, indoklás:** a kör a már megszerzett heti progressz
monotonitását és a nem büntető célképzést rögzíti; egy hibás plan-edit vagy
missed-day ág visszamenőleg elvehetne felhasználói haladást. A magas kockázat
termék-contractból ered, nem security-pathból; ezért kötelező a független Sol
correctness- és security-review.

## 0.0.1 Review-revízió — objective-azonosság és availability-végpontok

A `6300f497` implementáció független próbatesztje kimérte, hogy a puszta
`previousCompletedUnits` nem hordozza, MELYIK questhez tartozik. Ha az
improvement candidate measurement-hiány miatt kiesett, a generator active-days
replacementet választott, és annak progresszére vitte át a korábbi `4` unitot
(`Expected: 0`, `Actual: 4`). Ez téves completion/reward alap lehet.

A korábbi progressz ezért stabil `previousQuestId`-hez kötött. Csak akkor
vehető be a `max(previous, observed)` projekcióba, ha az ID az aktuálisan
kiválasztott candidate ID-jával egyezik; eltérő replacement kizárólag a saját
friss `observedCompletedUnits` értékével indul. Pozitív previous progress ID
nélkül invalid input. Ugyanazon candidate ID mellett a csökkentett idő/nap
változatlanul megőrzi a progresszt — ez az A3 plan-edit cella.

A Chapter 9 kötelező 3-day és 7-day availability cellái az első körben nem az
active-days targetet mérték. Az A1 ezért a 4/5/6 küszöbhármas mellett explicit
`3 nap → target 3` és `7 nap → target 5` végpontot is mér; a snapshot
`availableDays` tartománya pontosan `0..7`, a `-1` és `8` konstrukciós hiba.

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

- Az R17 determinisztikus napi generátort adott; seed materialja pontosan
  `generationEpochDay|profileSnapshotKey|catalogVersion`, és 64 bites FNV-1a
  sorrendkulcsot képez.
- Az R11 külön heti következetesség-projekciót ad: a
  `weeklyConsistency()` az utolsó inkluzív hét egyedi qualified napjait
  számolja `0..7` közé, caller-fed historyból.
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

## 5. Kötött architekturális döntések (ADR 0386)

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

A heti zárás nyelvfüggetlen, típusos tényprojekciót ad (státusz, cél,
teljesített egységek), nem user-facing mondatot. A későbbi `WeeklyRecap` UI
ARB-ból lokalizál; ez a kör így sem sürgető, sem szégyenítő szöveget nem
éget application kódba.

### 5.5 Caller-fed heti snapshot és pontos skálázás (ADR 0386)

A generátor nem olvas órát, repositoryt vagy tervet. A snapshot hordozza a
heti schedule-t, a profilkulcsot, az elérhető napokat/perceket, a normál heti
perceket, a korábbi és frissen mért completed unitokat, a verziózott
candidate-listát és az improvement-mérés elérhetőségét.

Minden candidate stabil ID-t, a négytagú `WeeklyQuestObjectiveKind` egyikét,
típusos `QuestObjective` referenciát és pozitív `baseTargetUnits` értéket ad.
A cél egészértékű képlete:
`ceil(baseTargetUnits * availableMinutes / baselineWeeklyMinutes)`. Nulla
elérhető nap vagy perc esetén nincs kötelező heti quest. Az aktívnap-cél ezen
felül `min(scaledTarget, availableDays, 5)`; más kindnál legalább 1, ha van
elérhető idő. A mért félidős referencia:
`python3 -c 'import math; print(math.ceil(6*180/360))'` → `3`.

A progress azonos `previousQuestId` mellett
`max(previousCompletedUnits, observedCompletedUnits)`; tervedit, kihagyott nap
vagy kisebb új target nem vonhat le belőle. Más candidate ID-ra váltó
replacement nem örököl progresszt. A completion `progress >= target`
összehasonlítás, ezért az azonos questen korán teljesített cél kész marad
célcsökkentés után is.

### 5.6 Típusmátrix és measurement fail-closed

Az aktívnap candidate `MetricQuestObjective(eventCount)`, a plan-blokk
`PlanBlockQuestObjective`, a mód-diverzitás
`MetricQuestObjective(diversityXp)`, a javulás pedig
`MetricQuestObjective(improvementXp)`. Más párosítás konstrukciós hiba. Ha
nincs improvement measurement, improvement candidate nem választható; a
generator a többi alkalmas kindból determinisztikusan választ, és csak teljes
candidate-hiánynál ad üres eredményt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A generált heti objective SOHA nem követel 7 (vagy 6+) egymást követő kötelező napot; a 3- és 7-napos availability végpont is explicit | `weekly_quest_generator_test.dart` — 3/4/5/6/7 active-days mátrix + `availableDays` -1/8 rejection |
| A2 | Csökkentett heti idő esetén a cél arányosan kisebb | `weekly_quest_generator_test.dart` — skálázás-mátrix |
| A3 | Hét közbeni tervváltozás után ugyanazon quest ID már elért haladása VÁLTOZATLAN; más replacement ID nem örökli | `weekly_quest_generator_test.dart` — same-ID monotonic + cross-ID isolation cella |
| A4 | A cél magyarázható: a küldetés visszaadja a származtatás bemeneteit | `weekly_quest_generator_test.dart` |
| A5 | A generálás determinisztikus (hét + profil + katalógus-verzió) | `weekly_quest_generator_test.dart` |
| A6 | A négy objective-típus (aktív napok / terv-blokk / mód-diverzitás / javulás) mind támogatott | `weekly_quest_generator_test.dart` — típus-mátrix |
| A7 | A heti átvezető nyelvfüggetlen, típusos tényprojekció; application kódban nincs user-facing mondat | `weekly_quest_generator_test.dart` — exact rollover státusz/cél/progress + forrásőr |
| A8 | Kihagyott nap NEM jár semmilyen levonással | `weekly_quest_generator_test.dart` |
| A9 | Measurement hiányában improvement objective nem választható, de más alkalmas objective igen | `weekly_quest_generator_test.dart` — no-measurements cella |
| A10 | A kimeneti candidate/projection nézetek immutable-ek; a generátor clock/repository/network nélkül pure Dart | `weekly_quest_generator_test.dart` — mutation + source-owner cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A generátor 7/7 napos objective-et ad | **A1** |
| A haladás az új célhoz arányosítva újraszámolódik | **A3** |
| A cél fix, függetlenül az elérhető időtől | **A2** (a skálázás-mátrix) |
| A cél nem adja vissza a származtatás bemeneteit | **A4** |
| A seed `DateTime.now()`-ra, `hashCode`-ra vagy rendezetlen iterationre épül | **A5** pinned seed + 100 futás |
| Valamely kind rossz típusos `QuestObjective`-vel fogadható el | **A6** négy kind + invalid cross-wiring mátrix |
| Az application réteg kész angol rollover mondatot ad | **A7** exact típusprojekció + source-owner cella |
| A kihagyott nap levonást okoz | **A8** |
| A filtered improvement progressze átkerül az active-days replacementre | **A3/A8 cross-ID isolation** |
| Measurement nélkül improvement candidate marad eligible | **A9** |
| A caller listája vagy a generált projection módosítható | **A10** |

**A küszöb három kötelező cellája** (a kötelező aktív napok felső korlátja a heti objective-ben (`maxRequiredDays`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `4` nap | elfogadható objective, target `4` |
| **rajta** (a küszöbön) | `5` nap | **MÉG elfogadható**, target `5` — a korlát inkluzív |
| a küszöb **fölött** | `6` nap | input elfogadható, de a generált targetet **5-re kell visszavágni**; ezt az A1 cella méri |

A hármas tömören: **4 → 4**, **5 → 5**, **6 → 5**. A határ az elfogadott
oldalhoz tartozik; a fölötte lévő input nem hiba, hanem capped targetet ad.

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
2. Az immutable caller-fed snapshot/candidate/output contract és a négy
   objective-kind exact típusmátrixa.
3. A skálázás, az aktívnap-cap és a nulla availability üres ága.
4. A monotonic progress-projekció és completion.
5. A measurement fail-closed szűrés és determinisztikus választás.
6. A nyelvfüggetlen rollover tényprojekció.
7. A `public.dart` egyetlen export-sora; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A 7/7 objective.** A műfaj legkézenfekvőbb heti célja, és egyetlen kihagyott nap után a hét hátralévő része értelmetlenné válik (A1).
- **A haladás arányosítása.** Matematikailag „korrekt”, és visszamenőleg elveszi a valós teljesítményt (A3).
- **A fix cél.** Egyszerű, és utazó vagy leterhelt héten teljesíthetetlen — a büntető minta közvetett formája (A2).

## 10. Implementation handoff — az implementer tölti ki

### Módosított fájlok

- `lib/features/gamification/application/weekly_quest_generator.dart`: caller-fed,
  immutable heti snapshot/candidate contract; UTF-8/FNV-1a ordering; availability
  scaling; 5 napos active-days cap; monoton progress; measurement fail-closed
  szűrés; nyelvfüggetlen rollover facts.
- `lib/features/gamification/public.dart`: a heti generator public exportja.
- `test/features/gamification/application/weekly_quest_generator_test.dart`:
  A1–A10 coverage, beleértve a 4/5/6 cap-hármast, 6×180/360=3 skálázást,
  cross-wiringokat, pinned seedet, immutabilityt és a valódi-sértés őrt.

### Futtatott parancsok és eredmények

- `git status --short` → tiszta baseline.
- `dart format lib/features/gamification/application/weekly_quest_generator.dart lib/features/gamification/public.dart test/features/gamification/application/weekly_quest_generator_test.dart`
  → 3 fájl, 2 formázott változtatással; a későbbi gate-format 0 változást talált.
- `dart format lib/features/gamification/application/weekly_quest_generator.dart test/features/gamification/application/weekly_quest_generator_test.dart`
  → a teljes cross-wiring mátrix és unique-ID fail-closed ellenőrzése után 2
  fájl, 1 formázott változtatással; az utána futtatott gate-format ismét zöld.
- `node -e "…FNV-1a…"` → a `20686|profile_alpha|7|weekly_active` pinned key
  értéke `-1830493033626131184`.
- `tools/round-gate.sh test/features/gamification/application/weekly_quest_generator_test.dart`
  (restored implementation) → format zöld, analyze zöld, célzott teszt 11/11
  zöld, architecture zöld; a gate a secrets lépést is elindította.
- Valódi-sértés: az active-days cap ideiglenesen `7`, majd ugyanaz a
  `tools/round-gate.sh …` → A1 PIROS: a 6 napos bemenetnél `Expected: <5>`,
  `Actual: <6>`; a cap visszaállítva `5`-re.

### Eltérés és nem futtatott ellenőrzés

- Nincs scope-eltérés. CI-dispatch, PR és merge nem futott: ezek a Claude
  orchestrátor feladatai.

## 11. Review — a Claude tölti ki
