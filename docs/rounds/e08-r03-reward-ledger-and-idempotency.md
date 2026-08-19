# E08-R03 — Reward ledger és idempotencia-index

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 3
- **Kör-azonosító:** `E08-R03`
- **Branch:** `<motor>/e08-r03-reward-ledger-and-idempotency`
- **Előfeltétel:** `E08-R02` merge-elve (kanonikus esemény-szerződések)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0301` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/features/gamification/domain/activity/` R02-ben létrejött típusait (különösen az `eventId` szerződését) és a `lib/core/storage/json_document_store.dart` tényleges felületét — a ledger tárolása erre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/rewards/reward_ledger_entry.dart",
  "lib/features/gamification/domain/rewards/reward_reason.dart",
  "lib/features/gamification/data/reward_ledger_repository.dart",
  "lib/features/gamification/data/local_reward_ledger_repository.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/data/reward_ledger_repository_test.dart",
  "docs/rounds/e08-r03-reward-ledger-and-idempotency.md",
]
gate_tests = [
  "test/features/gamification/data/reward_ledger_repository_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight — mért revízió (Claude, 2026-08-19, `main @ fc1ff764`)

Az `ADR 0301` [megírva](../adr/0301-reward-ledger-append-only-idempotency.md)
a §5 döntéseiből. Öt mérés indokolja ezt a revíziót — egyik sem H-halt-ok,
mind a pre-flight normál teendője (AGENTS.md §1, S8).

### 0.0.1 Visszakeresés (ADR 0312 / brief-lint S8)

`node tools/knowledge-rag.mjs --top 5 "reward ledger idempotency
append-if-absent race dedup"` — a találatok túlnyomó része maga ez a brief
(elvárt, PREPARED dokumentum). `node tools/knowledge-rag.mjs --corpus
lessons --top 6 "JsonDocumentStore JsonCollectionStore capRecords maxItems
silent data loss storage"` **egy közvetlenül releváns találatot** adott:
**[[L28]]** — a `JsonDocumentStore.write()` egy `StorageException`-t
logol-és-normálisan-visszatér, nem dob; egy „auditálható igazságforrásnak"
hirdetett rétegnél ez pontosan a CLAUDE.md „Cloud writes swallowed by
try/catch → silent no-op" hibaosztálya, ha a repository felülete TÖBBET
ígér, mint amit ténylegesen teljesít. Lásd 0.0.4.

### 0.0.2 A§6.1/A2 hivatkozott „mintája" pontatlan — mindkét idézett fájlt elolvastam

A §6.1 tábla és a §9 „Kockázatok" is a `test/features/progress/
practice_log_race_test.dart`-ot nevezi meg úgy, mint ami „pontosan ezt [a
`Future.wait` konkurens dupla-hozzáfűzést] őrzi". **Mérve: nem.** Elolvasva
mindkét jelölt fájlt (`practice_log_race_test.dart` ÉS a testvér-sweep
`test/core/store_race_sweep_test.dart`) — egyik sem `Future.wait`-alapú
konkurens írást tesztel. Mindkettő a „hideg indulás után az azonnali írás
nem törli a már tárolt előzményt" hibaosztályt őrzi regresszióként (E01-R07
óta szerkezetileg megszűnt hibaosztály — a szinkron `build()`-beli olvasás
miatt nincs „üres alapérték most, tárolt adat később" ablak). Ez **más**
hibaosztály, mint az A2 versenyhelyzet (két konkurens hívás azonos
`sourceEventId`-vel).

**Nem blokkoló, de a implementert téves keresésre küldte volna:** az A2
cellának NINCS meglévő mintafájlja ebben a projektben — ez az ELSŐ
`Future.wait`-alapú konkurens-írás próba. A helyes precedens a
**szerializálás mechanizmusára** (nem a teszt alakjára) `SongTransport.
_commandTail` (`lib/features/song_trainer/application/trainer/
song_transport.dart:52,68-70`) — lásd ADR 0301 2. pont. A §6.1 és §9
szövegét változatlanul hagyom (a hiba ártalmatlan félreirányítás, nem téves
acceptance-elvárás), ez a bekezdés a helyesbítés.

### 0.0.3 `JsonDocumentStore`, NEM `JsonCollectionStore` — kimondva, mert az utóbbi a megszokottabb minta

A §8.4 „a `JsonDocumentStore` mintájára" már a helyes réteget nevezi meg, de
nem mondja ki, MIÉRT nem a `JsonCollectionStore<T>` — a projekt ma MINDEN
más kollekciója (streak, songs, setlists, favourites, library — mérve:
`test/core/store_race_sweep_test.dart`) ez utóbbin megy, tehát ez a
„megszokott" választás egy implementer számára. Mérve
(`lib/core/storage/json_document_store.dart`): a `JsonCollectionStore.
write()` minden híváskor `capRecords`-ot hív, ami `maxItems` fölött **eldobja
a legrégebbi bejegyzéseket** — ez egy audit-ledgernél a §5.1 append-only
invariáns csendes megsértése volna. Lásd ADR 0301 4. pont — ez a döntés oka,
nem új elvárás.

### 0.0.4 Írás-hiba jelzése — review-time ellenőrzés, NEM új acceptance-cella

**[[L28]]** (E02-R18) pontosan ugyanezen a `JsonDocumentStore.write()`
swallow-szemantikán bukott két BLOCKERT: egy „valódi implementációnak"
hirdetett recorder `Success`-t adott, miközben a lemezre semmi nem íródott.
A brief §8.3 nem ír elő explicit hiba-jelzési szerződést az
`appendIfAbsent`-re, és az A1–A8 egyike sem teszteli írás-hiba
propagálását — **új, teszttel alá nem támasztott mandátumot ezért NEM
adok** (az S2 falszifikációs-cella elvvel ütközne). Amit a §0.0 helyett a
review fog kézzel ellenőrizni: az `appendIfAbsent` doc-commentje/felülete
NE ígérjen erősebb tartósságot, mint amit ténylegesen teljesít (pl. ha a
metódus neve vagy dokumentációja garantált perzisztenciát sugall, miközben a
mögötte álló `JsonDocumentStore.write()` egy `StorageException`-t csak logol
— az L28 pontos alakja, review-BLOCKER). Az „in-memory igaz a
session-höz, a lemez best-effort" szerződés önmagában elfogadható —
UGYANEZ a szerződés minden más kollekcióra is érvényes ma —, amíg a
felület ezt nem tagadja.

### 0.0.5 Megerősített, nem változtatott tények

- `LearningActivityEvent.eventId` (`lib/features/gamification/domain/
  activity/learning_activity_event.dart:12`) `String`, kötelező,
  hívó-adta — a brief pre-flight calloutja pontos, nincs teendő.
- `lib/features/gamification/domain/rewards/` és `data/` valóban nem
  léteznek (mérve újra ezen a pre-flighton).
- `test/core/architecture_dependency_test.dart` „gamification domain stays
  framework-free" csoportja `lib/features/gamification/domain`-t
  REKURZÍVAN listázza — egy új `rewards/` alkönyvtár automatikusan a
  scope része, a teszt (ami NINCS az engedélyezett listán) módosítása
  nélkül. Lásd ADR 0301 7. pont.
- `ADR 0301` a `.pipeline/inflight/adr/0301` foglalás szerint még
  fogyasztatlan volt ezen a pre-flighton — most írva, nincs ütközés.

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

Hozd létre a jutalmak EGYETLEN auditálható igazságforrását: egy **append-only**
főkönyvet, amelyben a `sourceEventId` egyedi, és a hozzáfűzés **atomikus**
append-if-absent művelet.

Ez a kör a dupla jutalom technikai blokkja. Az ADR 0290 §2 („a beváltás idempotens,
és a felület nem számít jutalmat”) itt válik kikényszerítetté.

## 2. Jelenlegi állapot — mért tények

- Az R02 létrehozta a `lib/features/gamification/domain/activity/` szerződéseket stabil `eventId`-vel.
- `lib/features/gamification/domain/rewards/` és `data/` **nem létezik** — ez a kör hozza létre.
- A projekt tárolási mintája: `lib/core/storage/json_document_store.dart` + `JsonObjectStore` (lásd `lib/features/streak/data/streak_repository.dart`, 47 sor) — verziózott dokumentum, `legacyKey` támogatással.
- A mai `streak_repository.dart` a sérült tárolt bájtokat **nem írja felül némán**: dekódolási hibánál `null`-t ad, és a hívó friss állapotra esik vissza. Ez a minta kötelező itt is.
- Az [`ADR 0290`](../adr/0290-compassionate-streaks-and-idempotent-claims.md) már kimondta: a beváltás idempotens, a felület nem számol jutalmat.

## 3. Scope

**Benne van:** immutable `RewardLedgerEntry` (`sourceEventId` **unique** invariánssal, policy-verzióval,
XP-komponensekkel és `RewardReason` kódokkal) · `RewardReason` szerződés · a repository
interfész + lokális implementáció **atomikus append-if-absent** művelettel · feldolgozott
esemény-azonosítók indexe a gyors dedupra · részleges írás / app-crash utáni helyreállítás ·
lapozott olvasás a projekció újraépítéséhez.

**NINCS benne (tilos):**

- **XP-számítás** — a ledger tárolja, amit kap; a policy-motor a Kör 6.
- Eligibility-döntés (Kör 5), outbox (Kör 4), profil-projekció (Kör 7).
- Bármely UI vagy provider — ebben a körben nincs `presentation/`.
- A ledger bejegyzések **módosítása vagy törlése**: a főkönyv append-only (§5.1).
- `docs/adr/**` — az ADR 0301-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/rewards/reward_ledger_entry.dart` | **ÚJ** — az immutable főkönyv-bejegyzés |
| `lib/features/gamification/domain/rewards/reward_reason.dart` | **ÚJ** — stabil, lokalizálható indok-kódok |
| `lib/features/gamification/data/reward_ledger_repository.dart` | **ÚJ** — az interfész |
| `lib/features/gamification/data/local_reward_ledger_repository.dart` | **ÚJ** — a lokális implementáció |
| `lib/features/gamification/public.dart` | az R02-ben létrejött barrel bővítése — CSAK export-sor |
| `test/features/gamification/data/reward_ledger_repository_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0301)

### 5.1 A főkönyv APPEND-ONLY — nincs update, nincs delete

A `RewardLedgerEntry` immutable, és a repository felülete **nem tartalmaz**
`update` vagy `delete` műveletet. A javítás módja **kompenzáló bejegyzés**, nem
visszamenőleges átírás.

**NEM elfogadható gyengítés:** „belső használatra” `_update` metódus a hibás bejegyzések
javítására. Onnantól a főkönyv nem auditálható, és a Kör 28 szinkron-merge-e
összeegyeztethetetlen állapotokat kap.

### 5.2 Az `append-if-absent` ATOMIKUS — a dupla jutalom technikailag blokkolt

A hozzáfűzés egyetlen műveletben ellenőrzi a `sourceEventId` jelenlétét ÉS ír.
Az „előbb `contains`, aztán `append`” alak versenyhelyzetben duplikál — ez a projektben
MÉRT hibaosztály (`test/features/progress/practice_log_race_test.dart` pontosan ezt őrzi
a gyakorlási naplóra).

**NEM elfogadható gyengítés:** a `contains` + `append` szétválasztása azzal az indoklással,
hogy „a Dart egyszálú”. Az `await` minden pontján átadható a vezérlés; a race valós.

### 5.3 Ismeretlen schema-verziójú bejegyzés MEGMARAD, nem törlődik

Ha a tárolt főkönyv olyan bejegyzést tartalmaz, amelynek verzióját ez a build nem
ismeri, a bejegyzés **érintetlen marad** és izolálódik — nem törlődik, és nem íródik felül.
Ez a `streak_repository.dart` mai mintája.

**NEM elfogadható gyengítés:** a nem dekódolható bejegyzés kihagyása az újraíráskor.
Az a felhasználó jutalmának néma elvesztése egy régebbi buildre visszalépéskor.

### 5.4 A UI nem írhat a főkönyvbe

A repository írási felülete az application-rétegnek szól. A `presentation/`
rétegből származó írás az ADR 0290 §2 megsértése lenne — minden képernyő-újranyitás
újabb jutalmat adna. Az architektúra-guard ezt méri.

### 5.5 Lapozott olvasás — a projekció újraépíthető

A Kör 7 profil-projekciója a teljes főkönyvből számol. Egy több ezer bejegyzéses
főkönyv egyben-olvasása memória-csúcsot ad, ezért a felület lapozott (`limit` + kurzor).
A lapozás **stabil rendezésű**: azonos bemenetre azonos sorrend.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Ugyanazzal a `sourceEventId`-vel kétszer hozzáfűzve a főkönyv **egy** bejegyzést tartalmaz | `reward_ledger_repository_test.dart` — dedup cella |
| A2 | A párhuzamos (`Future.wait`) kettős hozzáfűzés is EGY bejegyzést ad | `reward_ledger_repository_test.dart` — race cella, a `practice_log_race_test.dart` mintájára |
| A3 | A repository felületén **nincs** `update` és `delete` művelet | `reward_ledger_repository_test.dart` + review |
| A4 | Ismeretlen schema-verziójú bejegyzés az újraírás után is jelen van | `reward_ledger_repository_test.dart` — megőrzés-cella |
| A5 | A bejegyzés tárolja a policy-verziót, az XP-komponenseket és a `RewardReason` kódot | `reward_ledger_repository_test.dart` — round-trip |
| A6 | Részleges írás / crash után a főkönyv konzisztens (nincs félig írt bejegyzés) | `reward_ledger_repository_test.dart` — helyreállítás-cella |
| A7 | A lapozott olvasás stabil sorrendű és teljes (a lapok uniója = a főkönyv) | `reward_ledger_repository_test.dart` — lapozás-mátrix |
| A8 | A `RewardReason` kódok stabilak és lokalizálhatók (nem szabad szöveg) | `reward_ledger_repository_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `contains` + `append` két külön műveletben | **A2** (a párhuzamos cella két bejegyzést lát) |
| A repository kap egy `_update` metódust a javításokhoz | **A3** |
| Az újraírás kihagyja a nem dekódolható bejegyzést | **A4** (a megőrzés-cella nem találja) |
| A `RewardReason` szabad szöveg | **A8** (nem lokalizálható kód) |
| A lapozás rendezése a `Map` bejárási sorrendjéből jön | **A7** (a lapok uniója hiányos vagy duplikál) |
| A bejegyzés nem tárolja a policy-verziót | **A5** — és a Kör 6 policy-váltása visszamenőleg értelmezhetetlenné tenné a főkönyvet |

**A küszöb három kötelező cellája** (a lapozás `limit` paramétere):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `limit = 0` | `ArgumentError` — a nulla méretű lap végtelen ciklust adna |
| **rajta** (a küszöbön) | `limit = 1` — a legkisebb értelmes lap | **ELFOGADVA**: a lapozás egyesével is teljes és stabil sorrendű |
| a küszöb **fölött** | `limit` > a főkönyv mérete | **ELFOGADVA**: egyetlen lap, a teljes főkönyvvel, kurzor nélkül |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az atomikus `append-if-absent`-et `contains` + `append` párra, futtasd a gate-et →
az **A2** (párhuzamos) cellának PIROSNAK kell lennie → állítsd vissza. A visszaállítás utáni
zöld futás kimenete a §10-be kerül.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/data/reward_ledger_repository_test.dart
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

1. `reward_reason.dart` — a stabil indok-kódok.
2. `reward_ledger_entry.dart` — immutable bejegyzés, `sourceEventId`, policy-verzió, XP-komponensek.
3. `reward_ledger_repository.dart` — az interfész: append-if-absent, lapozott olvasás, index-lekérdezés. **Nincs** update/delete.
4. `local_reward_ledger_repository.dart` — a lokális implementáció a `JsonDocumentStore` mintájára.
5. Feldolgozott-azonosító index a gyors deduphoz.
6. Részleges írás / crash helyreállítás (journal vagy tranzakciós írás).
7. A `public.dart` export-sorai.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `contains` + `append` szétválasztása.** A leggyakoribb és leglátványosabb hiba: egyszálúsággal indokolható, a race mégis valós (A2). A projekt már megmérte a gyakorlási naplón.
- **A „takarítsuk ki a sérült bejegyzéseket” reflex.** Egy régebbi buildre visszalépés után a felhasználó jutalma némán elvész (A4).
- **A policy-verzió elhagyása.** Nem itt fáj, hanem a Kör 6 első policy-váltásánál, amikor a régi bejegyzések értelmezhetetlenné válnak (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
