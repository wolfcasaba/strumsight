# E08-R14 — Achievement kiértékelő és haladás-projekció

- **Státusz:** IN PROGRESS (pre-flight 2026-08-21, kód olvasva: `main @ cfe43920`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 14
- **Kör-azonosító:** `E08-R14`
- **Branch:** `terra/e08-r14-achievement-evaluator-and-projection`
- **Előfeltétel:** `E08-R13` merge-elve (achievement katalógus)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `ADR 0377`. Az előre írt `0311` elavult; a kötelező atomi foglaló
  (`tools/round-slots.py reserve-adr --round E08-R14`) 2026-08-21-én `0377`-et
  adott. Az ADR-t az orchestrátor írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R13 objective-típusait és az R03 főkönyv-felületét (a completion a főkönyvhöz kötődik) — ha az objective szignatúrája eltér, §0.0 revízió. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/application/achievement_evaluator.dart",
  "lib/features/gamification/application/achievement_index.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/application/achievement_evaluator_test.dart",
  "docs/rounds/e08-r14-achievement-evaluator-and-projection.md",
]
gate_tests = [
  "test/features/gamification/application/achievement_evaluator_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revízió — 2026-08-21

- A tényleges R13 contract öt objective-típust ad (`count`, `threshold`,
  `distinct`, `sequence`, `compound`) plusz explicit unknown sentinelt. Az
  R02 `LearningActivityEvent` hat zárt runtime típust, stabil `eventId`-t,
  `occurredAt`-ot, `duration`-t, `score`-t és `source`-ot hordoz, de XP-
  komponenseket nem. Az evaluator ezért egy immutable, caller-supplied
  evaluation-evidence contracttal egészíti ki a canonical eventet; a típust,
  időtartamot, score-t és source-t az eventből származtatja, az XP-metrikát
  csak explicit átadott, véges értékből olvassa. Hiányzó metrika nem válik
  némán nullává: az érintett objective fail-closed diagnosztikát ad.
- Az R03 főkönyv `appendIfAbsent` dedupja a `sourceEventId`-re atomikus; a
  tényleges hívási láncban ma a repository szerzi meg az írás sorosítását.
  Achievement receipt forrás-ID-ja ezért `achievement:<achievementId>`, a
  ledger ID-ja pedig `achievement:<achievementId>:<triggerEventId>`; a receipt
  `createdAt` értéke a kiváltó event `occurredAt` értéke.
- Az R06 nem tartalmaz achievement reward-összeg policyt; az R03/R06 zárt
  contractja viszont már tartalmazza az `achievementUnlocked` reason kódot.
  Új balance-szabály vagy jutalomtípus bevezetése tilos, ezért ez a kör
  nulla-XP audit receiptet ír (`baseXp=bonusXp=totalXp=0`, reason:
  `achievementUnlocked`). Pozitív achievement XP csak külön balance-körben,
  explicit policyvel vezethető be.
- A progress nem építhető újra **csak** a reward ledgerből: a ledger az
  unlock receiptet őrzi, nem minden count/distinct/threshold bemenetet. A4
  pontosítva: az evaluator a caller által átadott kanonikus event-historyból
  építi újra a progresszt, és a ledgerből köti vissza az egyszeri completiont.
- A backfill konfigurált alapablaka 30 nap, az anchor caller-supplied UTC
  időpont. A kötelező 29/30/31 napos cellák pontos bemeneteit a
  `python3 -c "from datetime import datetime,timezone,timedelta; ..."`
  számolta: `2026-07-23T12:00:00Z`, `2026-07-22T12:00:00Z`,
  `2026-07-21T12:00:00Z` a `2026-08-21T12:00:00Z` anchorhoz.
- Visszakeresett előzmények: `adr/0301` (repository-szintű atomikus ledger
  dedup), `adr/0350` (caller-supplied, stabil bounded backfill precedens),
  `adr/0374` (zárt objective-vokabulár), `lessons/L372` (stabil achievement
  identitás), valamint az E08-R07 halt-bejegyzés (zöld suite mögötti projekció-
  regressziókhoz kötelező reviewer-mutatás).

**Review utáni §0.0 pontosítás (997a52a0, 2026-08-21).** A független
correctness/security review két BLOCKER-t reprodukált: a trigger eventet is
tartalmazó `sourceEventId` két párhuzamos eventnél két külön dedup-kulcsot ad,
a prefix-alapú receipt lookup pedig idegen ledger sort is completionként
elfogad. Az atomi kulcs ezért pontosan `achievement:<achievementId>`; a
trigger event kizárólag a `ledgerId`-ban marad. A visszaolvasott receipt csak
exact source ID, exact ledger ID-prefix, nulla XP és `achievementUnlocked`
reason mellett hiteles; névtérütközés fail-closed diagnosztika. A history
stabil `eventId` szerint deduplikált, azonos ID-jú eltérő payload fail-closed,
és idő szerint determinisztikusan rendezett. A backfill a cutoffnál régebbi
**és az anchor utáni** eventet is kizárja. A caller-history hard capje 10 000
event (9 999 / 10 000 elfogadott, 10 001 elutasított). A progress
`catalogVersion` mezője a katalógus `contentVersion` értéke. Az index event
kind **és metric/dimension** kulcsot hordoz; puszta event-kind map nem elég.
**Kockázat = high, indoklás:** a kör perzisztált reward receiptet és
újraépíthető user-progressz szerződést köt össze; egy dedup-, timestamp-
vagy backfill-hiba dupla jutalmat vagy történeti progresszdriftet okozhat,
ezért correctness mellett külön security review is kötelező.

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

Kanonikus eseményekből **idempotensen** építs eredmény-haladást: egy achievement soha
nem oldódik fel kétszer, a haladás újraépíthető, és a kiértékelő nem pásztázza feleslegesen
a teljes katalógust.

## 2. Jelenlegi állapot — mért tények

- Az R13 szállította a típusos objective-eket és a katalógust; az R03 a főkönyvet, amelyhez a feloldás kötődik.
- `lib/features/gamification/application/achievement_*` **nem létezik**.
- Az R03 `append-if-absent` művelete a dedup technikai alapja — a feloldás EZEN keresztül idempotens.

## 3. Scope

**Benne van:** az achievementek indexelése esemény-típus és metrika szerint · egy esemény CSAK a
releváns objective-eket értékeli · count / distinct / threshold / compound haladás · a
feloldás **egyszeri** és a főkönyvhöz kötött · **korlátos** backfill később hozzáadott
achievementhez · ismeretlen objective **fail-closed**.

**NINCS benne (tilos):**

- A katalógus tartalmának módosítása (Kör 13) és a felület (Kör 15).
- Új jutalom-típus vagy pozitív achievement-XP balance bevezetése — a kör a
  meglévő R03 ledger schema és R06 `achievementUnlocked` reason kód alapján
  nulla-XP audit receiptet ír.
- `docs/adr/**` — az ADR 0377-et az orchestrátor írta a pre-flightban; az
  implementer az ADR-ket nem módosítja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/application/achievement_evaluator.dart` | **ÚJ** — a kiértékelő |
| `lib/features/gamification/application/achievement_index.dart` | **ÚJ** — az esemény→objective index |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/application/achievement_evaluator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0377)

### 5.1 A feloldás EGYSZERI, és a főkönyv dedupja garantálja

A feloldás audit receiptje az R03 főkönyvébe kerül `append-if-absent`
művelettel, ahol a forrás-azonosító pontosan
`achievement:<achievementId>`, a ledger ID pedig
`achievement:<achievementId>:<triggerEventId>`. Az R13 nem hordoz reward-
összeget, ezért a receipt ebben a körben nulla XP és az explicit
`achievementUnlocked` reason kódot hordoz. Az ismételt kiértékelés így
technikailag nem tud dupla receiptet vagy jutalmat adni.

**NEM elfogadható gyengítés:** memóriabeli „már feloldottam” halmaz a főkönyv helyett.
Az app újraindítása után elvész, és a következő esemény újra feloldana.
Prefix-egyezés vagy reason/XP ellenőrzés nélküli lookup szintén tilos; az
ütköző, nem hiteles receipt fail-closed diagnosztikát ad.

### 5.2 A feloldás időbélyege STABIL

Az újraépítés ugyanazt a feloldási időpontot adja, mint az eredeti kiértékelés:
az időbélyeg a KIVÁLTÓ ESEMÉNYBŐL származik, nem a feldolgozás órájából.

**NEM elfogadható gyengítés:** `DateTime.now()` a feloldáskor. Egy projekció-újraépítés
átírná a felhasználó eredmény-előzményét.

### 5.3 INDEXELT kiértékelés — nem teljes katalógus-pásztázás

Egy esemény csak azokat az objective-eket értékeli, amelyek az adott esemény-típusra
és metrikára regisztráltak. A teljes katalógus végigpásztázása minden eseménynél a
katalógus növekedésével négyzetesen romlik.

### 5.4 Ismeretlen objective FAIL-CLOSED

Ha a kiértékelő olyan objective-típussal találkozik, amit nem ismer (régebbi
build, újabb katalógus), **nem** old fel semmit és jelzi a hibát — soha nem old fel
„biztos, ami biztos” alapon.

### 5.5 A backfill KORLÁTOS

Egy később hozzáadott achievement visszamenőleges kiértékelése korlátozott
ablakban történik (a korlát a konfigurációban él). A teljes előzmény minden
alkalmazás-indításkori újrapásztázása használhatatlanná tenné az indulást.

### 5.6 Az újraépítés bemenete event-history + ledger receipt

A caller rendezett kanonikus event-historyt ad át; az evaluator ebből építi
újra a count/distinct/threshold/sequence/compound progresszt. A ledger az
egyszeri completion receiptjének és stabil timestampjének igazságforrása.
Sem teljes activity repository scan, sem storage-owner átvétel nem kerül az
evaluatorba.

Az evaluator stabil `eventId` szerint deduplikálja a replayt, az azonos ID-jú
eltérő payloadot elutasítja, és determinisztikus időrendre normalizál. Egy
snapshot legfeljebb 10 000 event; a backfill az anchor utáni eventeket sem
dolgozza fel.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanaz az event ID replayben nem növeli kétszer a count/sequence progresszt és nem old fel kétszer | `achievement_evaluator_test.dart` — idempotencia-cella |
| A2 | App-újraindítás és két párhuzamos, külön trigger event után is pontosan egy exact-source receipt létezik | `achievement_evaluator_test.dart` |
| A3 | A feloldás időbélyege a kiváltó eseményből jön, és újraépítéskor VÁLTOZATLAN | `achievement_evaluator_test.dart` — stabilitás-cella |
| A4 | A historyból rebuildelt progress `catalogVersion` mezője a catalog contentVersion; az unlock receipt a főkönyvből kötődik vissza | `achievement_evaluator_test.dart` |
| A5 | Egy esemény csak az event-kind + metric/dimension index szerinti objective-eket értékeli | `achievement_evaluator_test.dart` — index-cella |
| A6 | Ismeretlen objective esetén NINCS feloldás, és hiba keletkezik | `achievement_evaluator_test.dart` |
| A7 | Nulla-XP `achievementUnlocked` receipt jön létre exact achievement source ID-val és achievement+event ledger ID-val; idegen prefix receipt nem completion | `achievement_evaluator_test.dart` |
| A8 | A backfill időben és darabszámban korlátos: régi/future event kimarad; 10 001 event elutasított | `achievement_evaluator_test.dart` — korlát-mátrix |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Memóriabeli feloldás-halmaz a főkönyv helyett | **A2** (az újraindítás-cella újra felold) |
| `DateTime.now()` a feloldás időbélyegének | **A3** |
| Minden esemény végigpásztázza a katalógust | **A5** (az érintett objective-ek száma a teljes katalógus) |
| Ismeretlen objective figyelmen kívül hagyva | **A6** |
| A backfill korlátlan | **A8** |
| A feloldás nem ír nyugtát | **A7** |
| Azonos event ID kétszer növeli a countot/sequence-et | **A1** |
| Két párhuzamos trigger két source ID-t ír | **A2** |
| Prefix-egyező normál ledger sort unlocknak fogad | **A7** |
| Definition version kerül a progress catalogVersion mezőjébe | **A4** |
| Az index metric/dimension kulcs nélkül csak event kind szerint épül | **A5** |
| Anchor utáni event vagy 10 001 elem átjut | **A8** |

**A küszöb három kötelező cellája** (a backfill ablak korlátja (`backfillWindowDays`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `2026-07-23T12:00:00Z` (29 napos esemény, 30 napos ablak) | **feldolgozásra kerül** a backfillben |
| **rajta** (a küszöbön) | `2026-07-22T12:00:00Z` (pontosan 30 napos) | **MÉG feldolgozásra kerül** — inkluzív határ |
| a küszöb **fölött** | `2026-07-21T12:00:00Z` (31 napos) | **NEM kerül feldolgozásra**; ez a diagnosztikában látszik |

A hármas tömören: **alatt** → feldolgoz · **rajta** → feldolgoz · **fölött** → kihagy és diagnosztikát ad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld a főkönyv-alapú dedupot memóriabeli halmazra, futtasd a gate-et → az
**A2** (újraindítás) cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/application/achievement_evaluator_test.dart
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

1. `achievement_index.dart` — esemény-típus + metrika → objective index.
2. `achievement_evaluator.dart` — indexelt kiértékelés, objective-típusonként.
3. A feloldás főkönyvhöz kötése (`append-if-absent`, stabil forrás-azonosító).
4. Stabil feloldási időbélyeg a kiváltó eseményből.
5. Fail-closed ág ismeretlen objective-re.
6. Korlátos backfill, a kihagyás jelzésével.
7. A `public.dart` export-sorai; a valódi-sértés próba §10-be.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A memóriabeli dedup.** A fejlesztés közben tökéletesen működik, és az első app-újraindításnál duplikál (A2).
- **A `now()` időbélyeg.** Csak az első projekció-újraépítéskor derül ki, amikor a felhasználó eredmény-előzménye átíródik (A3).
- **A teljes pásztázás.** 25 achievementnél észrevehetetlen, 200-nál a gyakorlás végén akadás (A5).

## 10. Implementation handoff — az implementer tölti ki

- `lib/features/gamification/application/achievement_index.dart` — új,
  immutable event-kind → achievement index; a compound és sequence objektív
  összes érintett event-kindjét indexeli, az unknown objective-eket pedig
  diagnosztikai fail-closed ágon tartja.
- `lib/features/gamification/application/achievement_evaluator.dart` — új,
  caller-supplied immutable evidence/result/diagnostic contract, count,
  distinct, threshold, sequence és compound projekció; repository-szintű
  `appendIfAbsent` receipt-dedup, event-időbélyeges, nulla-XP
  `achievementUnlocked` receipt, history rebuild és inkluzív, caller-anchored
  30 napos backfill.
- `lib/features/gamification/public.dart` — az evaluator és index publikus
  exportjai.
- `test/features/gamification/application/achievement_evaluator_test.dart` —
  A1–A8, index-scan, unknown/missing-metric fail-closed, tier, sequence,
  compound, 29/30/31 napos backfill és immutable collection cellák.

**TDD-bizonyíték.** Az első
`flutter test test/features/gamification/application/achievement_evaluator_test.dart`
RED volt: `AchievementEvaluator`, `AchievementEvaluationEvidence` és a
diagnosztikai contract még nem létezett. Az implementáció után a célzott
teszt 9/9 zöld.

**Valódi-sértés próba.** A repository-dedupot ideiglenes process-local
completed-setre cseréltem, majd a kötelező gate-et futtattam. A célzott
tesztben az A2 restart cella piros lett: várt `empty`, tényleges
`[AchievementUnlock]`; a restore után a ledger `appendIfAbsent` ága van
visszaállítva. A szándékos mutáció további receipt-/timestamp-függő cellákat
is pirosra vitt, ezért nem maradhatott a fán.

**Futtatott végső gate.**
`tools/round-gate.sh test/features/gamification/application/achievement_evaluator_test.dart`
— exit 0; `format`, `analyze`, a 9 tesztes célzott test, `architecture`,
`secrets` (3111 fájl, 0 finding) és `l10n` (1503 üzenet) mind zöld.

**Eltérés / nem futtatott ellenőrzés.** Nincs scope-eltérés. A teljes Flutter
suite, randomizált property gate és APK a brief/AGENTS szerint CI-orchestrator
feladat; implementerként nem indítottam CI-t, PR-t vagy push-t.

## 11. Review — a Claude tölti ki
