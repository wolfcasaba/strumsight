# E08-R02 — Kanonikus tanulási esemény-szerződések

- **Státusz:** PRE-FLIGHT COMMITTED (2026-08-19, kód olvasva: `main @ 1a051d85`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 2
- **Kör-azonosító:** `E08-R02`
- **Branch:** `<motor>/e08-r02-canonical-activity-events`
- **Előfeltétel:** `E08-R01` merge-elve (baseline)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** ~~`ADR 0300`~~ → **`ADR 0329`** (§0.0.1 pre-flight
  korrekció — a `0300` már foglalt volt, más körnek). Az ADR-t a Claude írja
  meg a kör indítási pre-flightjában a §5 döntéseiből; az implementer a
  `docs/adr/`-t NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a `lib/features/gamification/` fa tényleg nem létezik, és olvasd újra a baseline `docs/baseline/epic-08-start.md` esemény-forrás listáját — az esemény-típusok halmaza abból származik. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/domain/activity/learning_activity_event.dart",
  "lib/features/gamification/domain/activity/activity_source.dart",
  "lib/features/gamification/domain/activity/evidence_trust.dart",
  "lib/features/gamification/domain/activity/reward_eligibility.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/domain/activity_event_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r02-canonical-activity-events.md",
]
gate_tests = [
  "test/features/gamification/domain/activity_event_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight — mért revízió (Claude, 2026-08-19, `main @ 1a051d85`)

**Visszakeresett előzmény (ADR 0312, brief-lint S8).**
`node tools/knowledge-rag.mjs --top 5 "canonical learning activity event
sealed hierarchy gamification schemaVersion eventId"` legjobb találata a
saját SDD-forrás (`docs/sdd/09-epic-08-gamification.md` §8.1) — a brief
domain-modellje ezzel egyezik. `--corpus lessons --top 5 "new
feature-agnostic domain event type immutable schema versioning stable id
architecture guard"` releváns találatai: **L107** (egy új feature
domain-purity-je NEM automatikus a `tool/check_architecture.dart`-ból — lásd
lent, §0.0.2), **L283** (a domain-purity guard a tiltott API-literal
dokumentációs előfordulását is hibának veszi — a doc-commentekben ne írd le
szó szerint a `Random(`/`DateTime.now(`/`package:flutter/` mintát), **L190**
(a `public.dart`-only szabály az import CÉLJÁT kényszeríti ki, nem a behúzott
szimbólumokat — irreleváns erre a körre, nincs cross-feature fogyasztó még)
és **L302** (egy PREPARED brief pre-flight-callója mérethet Core/domain
hiányra anélkül, hogy a valódi megoldás a meglévő mechanizmussal is elérhető
— pontosan ez történt itt, lásd §0.0.2).

### 0.0.1 KRITIKUS — az előre kiosztott `ADR 0300` már foglalt volt (javítva a fejlécben)

Mérve `tools/round-slots.py reserve-adr --round E08-R02` előtt:
`.pipeline/inflight/adr/0300` már létezett, tartalma `round=E07-R15`
(foglalva 2026-08-16), és a `docs/adr/` könyvtárban NINCS `0300-*.md` fájl —
azaz a számot egy korábbi kör foglalta, sosem fogyasztotta el, és a foglalás
attól még érvényes marad (`reserve_adr()` csak `max(used)+1`-et ad ki,
sosem old fel egy alacsonyabb, korábban foglalt számot — `tools/round-slots.py:201-229`).
A brief eredeti fejléce (2026-08-18-i írás) tehát egy már ütköző számot
állított be. **Revízió:** a valódi, most lefoglalt szám **`ADR 0329`** — a
fejléc és az 5. szakasz címe fent javítva, az ADR fájl
`docs/adr/0329-canonical-activity-event-contracts.md` néven ugyanebben a
pre-flight commitban készül.

### 0.0.2 Az A6 architektúra-őr NEM a `tool/check_architecture.dart` bővítésével épül — mért, precedens-alapú technika

A brief §8 7. lépése („Az architektúra-guard bejegyzése az új
feature-gyökérre") félreérthető: a domain-purity ág
(`sharedDomainMustRemainFrameworkIndependent`) a `tool/check_architecture.dart`
`_isSharedDomain()` függvényében **hardcode-olt** prefixlistán megy
(`lib/core/music/`, `lib/core/audio/codec/`,
`lib/features/practice/domain/` — `tool/check_architecture.dart:382-385`,
mérve), és `lib/features/gamification/domain/` NINCS ezen a listán. A
`tool/check_architecture.dart` fájl **nincs** ennek a körnek az
`allowed_paths` listáján, tehát a bővítése ebben a körben elérhetetlen cél
(ugyanaz a hibaosztály, mint a pre-flight §1 1. mérési szabálya —
„elérhetetlen cél-státusz", csak itt egy gate-ág, nem állapotgép-cellán).

**Mért, már bevált megoldás ugyanerre a helyzetre (E07-R02, ADR 0257 §6,
`test/core/architecture_dependency_test.dart:16-97`):** a
`practice_generator/domain` ugyanígy kimaradt a hardcode-olt listából, és a
kör NEM a checkert bővítette, hanem egy **önálló, a saját fájlhalmazát
közvetlenül beolvasó teszt-csoportot** adott
`architecture_dependency_test.dart`-hoz (ami VAN ennek a körnek is az
`allowed_paths`-án). A fájlban ehhez már létező, újrafelhasználható
segédfüggvények vannak (`_forbiddenDomainMarkerOffenders`,
`_withoutTrivia` — sorok 591–652): import-URI markerekre (`package:flutter/`,
`dart:ui`) sztringtartalommal együtt, hívás-markerekre (`DateTime.now(`,
`Random(`) sztringtartalom NÉLKÜL keresnek, kommentet mindkét esetben
kiszűrve (L283 pontosan ezt a false-positive osztályt fedi).

**Ajánlott (nem kényszerítő, de mért-alapú) markerkészlet ehhez a
körhöz** — közvetlenül a brief §5.2/§5.3/§9 szövegéből:

- import-URI markerek (string-tartalommal együtt vizsgálva):
  `package:flutter/`, `package:flutter_riverpod/`, `package:riverpod/`,
  `package:shared_preferences/`, `package:flutter_secure_storage/`,
  `package:sqflite/`, `dart:ui` — a §5.2 „Flutter, Riverpod, storage vagy UI
  import" tilalmának mérőszáma.
- hívás-markerek (string-tartalom nélkül vizsgálva): `Random(`,
  `DateTime.now(` — a §5.3 explicit szövege szerint („NEM elfogadható
  gyengítés: az eventId generálása a konstruktorban óra- **vagy**
  véletlen-forrásból").

Az A7 (`crossFeatureImportsMustUsePublicApi`) ezzel szemben **automatikus,
nem igényel új tesztkódot**: ez a szabály `_featureName()`/
`_isFeaturePublicBarrel()` alapján generikusan fut MINDEN `lib/features/*`
fára (`tool/check_architecture.dart:353-380`, mérve — nincs hardcode-olt
feature-lista, csak a hardcode-olt DOMAIN-purity ág ilyen). A meglévő első
teszt (`contains exactly the allowlisted dependency deviations`) ezt a
`lib/features/gamification/` fa létrejötte után önműködően lefedi, mert
`checkArchitecture()` a teljes `lib/`-et rekurzívan bejárja. Mivel ez a kör
nulla cross-feature importot vezet be (§3 „NINCS benne"), az
`architectureAllowlist`-hez sem kell új bejegyzés.

### 0.0.3 Kisebb korrekció — a §2 sorszáma elavult (nem blokkoló)

A §2 „mért tények" `test/core/architecture_dependency_test.dart` sorát
467 sorral írja le; mérve a fájl ma **652 sor**. A fájl mindkét változatban
az `allowed_paths` listán van, a szám nem gate-elő, csak dokumentációs
pontatlanság — nem igényel külön revíziós lépést, csak jelzés, a §1 mérési
szabály szerint.

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

Hozd létre a feature-agnosztikus, **immutable** és **verziózott** tanulási eseményeket:
ezek a gamifikáció EGYETLEN bemenetei. Minden későbbi kör (ledger, outbox, XP, quest)
ezekre épül, ezért a szerződés stabilitása itt dől el.

Ez a kör **nem integrál** feature-öket — csak a szerződést és a public exportot hozza.

## 2. Jelenlegi állapot — mért tények

- `lib/features/gamification/` **nem létezik** — ez a kör hozza létre az első fájljait.
- A gyakorlási eredmények ma feature-specifikus alakban élnek: `lib/features/progress/model/practice_entry.dart` (86 sor), `lib/features/learn/data/lesson_progress_repository.dart`, `lib/features/streak/model/streak_data.dart` (80 sor). **Nincs közös esemény-típus.**
- `test/core/architecture_dependency_test.dart` (467 sor) „allowlisted dependency deviations” alapon tiltja a cross-feature importot — az új feature-gyökeret ide kell felvenni.
- A projekt konvenciója: minden feature EGY `public.dart` barrelen át importálható (lásd `lib/features/*/public.dart`, 21 feature).

## 3. Scope

**Benne van:** a `LearningActivityEvent` sealed hierarchia stabil `eventId` / `occurredAt` / `epochDay`
mezőkkel · a Practice, Song, Analysis, Plan, Tutor és Vision esemény-altípusok ·
konstruktor-szintű validáció (negatív időtartam, tartományon kívüli pontszám, ismeretlen
schema-verzió) · JSON round-trip **explicit type discriminatorral** · `ActivitySource`,
`EvidenceTrust`, `RewardEligibility` enum-szerződések · `public.dart` barrel ·
architektúra-guard bejegyzés.

**NINCS benne (tilos):**

- **Bármely feature integrálása** (`lib/features/practice/**`, `learn/**`, `songs/**` …) — Kör 24–26.
- Ledger, outbox, XP-számítás, eligibility-**logika** — Kör 3–6. Itt csak a típusok vannak.
- Flutter-, Riverpod-, storage- vagy UI-típus importálása a domainbe (§5.2).
- A meglévő `practice_entry.dart` / `streak_data.dart` átírása vagy eltávolítása.
- `docs/adr/**` — az ADR 0329-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/domain/activity/learning_activity_event.dart` | **ÚJ** — a sealed esemény-hierarchia |
| `lib/features/gamification/domain/activity/activity_source.dart` | **ÚJ** — a forrás-feature azonosítója |
| `lib/features/gamification/domain/activity/evidence_trust.dart` | **ÚJ** — a bizonyíték megbízhatósági szintje |
| `lib/features/gamification/domain/activity/reward_eligibility.dart` | **ÚJ** — a jutalmazhatóság szerződése (típus, nem logika) |
| `lib/features/gamification/public.dart` | **ÚJ** — az EGYETLEN belépő a feature-höz |
| `test/features/gamification/domain/activity_event_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | az új feature-gyökér határa |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0329)

### 5.1 Az esemény IMMUTABLE és verziózott — a `schemaVersion` KÖTELEZŐ mező

Minden eseménynek van `schemaVersion` mezője, és ismeretlen verzió **hibát ad**,
nem csendes alapértelmezést. A ledger (Kör 3) az eseményekből származtat jutalmat; egy
némán újraértelmezett régi esemény ott visszamenőleg hamis egyenleget termelne.

**NEM elfogadható gyengítés:** a hiányzó `schemaVersion` „legyen 1” alapértelmezéssel.
Az alapértelmezés pont azt a különbséget tünteti el, amit a mező mérni hivatott.

### 5.2 A domain TISZTA Dart — nincs Flutter, Riverpod, storage vagy UI import

Az esemény-típusok tesztelhetősége és újrafelhasználhatósága ezen áll. Az
architektúra-guard ezt kikényszeríti (A6).

**NEM elfogadható gyengítés:** `package:flutter/foundation.dart` behúzása `@immutable`
vagy `debugPrint` kedvéért. Az immutabilitást `final` mezők és a `const` konstruktor adja.

### 5.3 Stabil `eventId` — a dedup ezen fog állni

Az `eventId` a forrás-feature által adott, **stabil** azonosító: ugyanaz a
gyakorlási eredmény újrafeldolgozva UGYANAZT az azonosítót adja. A Kör 3 idempotencia-indexe
és a Kör 4 outboxa erre épül — véletlenszerű (`Random`, `UUID v4` menet közben generált)
azonosító mellett a dupla jutalom technikailag nem blokkolható.

**NEM elfogadható gyengítés:** az `eventId` generálása a konstruktorban óra- vagy
véletlen-forrásból. Az azonosítót a hívó adja, és a konstruktor validálja, hogy nem üres.

### 5.4 Explicit type discriminator a JSON-ban

A round-trip a `type` mezőn keresztül megy, nem a mezők jelenlétéből következtetve.
A strukturális kitalálás az első olyan altípusnál elromlik, amelynek mezői részhalmazát
adják egy másiknak — és némán rossz típusú eseményt ad vissza.

### 5.5 EGY belépő: `public.dart`

A gamification feature kizárólag a `public.dart`-on át importálható; belső fájl
importja kívülről tilos. A guard ezt méri (A6). Ez a 21 meglévő feature konvenciója.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden esemény-altípus immutable (`final` mezők, `const` konstruktor) | `activity_event_test.dart` — a mezők nem írhatók |
| A2 | A `schemaVersion` KÖTELEZŐ; ismeretlen verzió **hibát dob**, nem alapértelmezést ad | `activity_event_test.dart` — mind a hat altípusra |
| A3 | Stabil `type` discriminator: a JSON round-trip mind a hat altípusra azonosságot ad | `activity_event_test.dart` — mátrix, altípusonként egy cella |
| A4 | A konstruktor elutasítja a negatív időtartamot és a tartományon kívüli pontszámot | `activity_event_test.dart` — `throwsArgumentError` |
| A5 | Üres vagy hiányzó `eventId` elutasítva | `activity_event_test.dart` — `throwsArgumentError` |
| A6 | A domain NEM importál Flutter/Riverpod/storage/UI típust, és nem importál más feature-t | `architecture_dependency_test.dart` |
| A7 | A feature EGYETLEN `public.dart`-ból importálható | `architecture_dependency_test.dart` |
| A8 | A hat esemény-altípus (Practice, Song, Analysis, Plan, Tutor, Vision) mind létezik | `activity_event_test.dart` — a discriminator-mátrix hat sora |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A hiányzó `schemaVersion` 1-re alapértelmezik | **A2** (az ismeretlen-verzió cella nem dob) |
| A JSON round-trip a mezők jelenlétéből következtet típusra | **A3** (a részhalmaz-mezőjű altípus rossz típust ad vissza) |
| Az `eventId` a konstruktorban `Random`-ból generálódik | **A5** (üres azonosítót nem utasít el) — és a Kör 3 dedupja megbukna |
| `package:flutter/foundation.dart` importálva `@immutable` miatt | **A6** |
| Belső fájl közvetlenül importálható a barrel megkerülésével | **A7** |
| A negatív időtartam elfogadva, mert „a hívó úgyis validál” | **A4** |

**A küszöb három kötelező cellája** (az időtartam-validáció határa: `Duration.zero`):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `Duration(milliseconds: -1)` — negatív időtartam | `ArgumentError` — **elutasítva** |
| **rajta** (a küszöbön) | `Duration.zero` — pontosan a határon | **ELFOGADVA**: a nulla hosszú esemény legitim (megszakított session); a jutalmazhatóságát a Kör 5 eligibility dönti el, NEM a konstruktor |
| a küszöb **fölött** | `Duration(seconds: 1)` — a határ fölött | **ELFOGADVA** |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ a **„rajta"** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a `schemaVersion` ismeretlen-verzió ellenőrzését (engedd alapértelmezni 1-re),
futtasd a gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza. A visszaállítás
utáni zöld futás kimenete a §10-be kerül.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/domain/activity_event_test.dart test/core/architecture_dependency_test.dart
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

1. `activity_source.dart` és `evidence_trust.dart` — a két enum-szerződés.
2. `reward_eligibility.dart` — a jutalmazhatóság TÍPUSA (a döntési logika a Kör 5).
3. `learning_activity_event.dart` — a sealed bázis (`eventId`, `occurredAt`, `epochDay`, `schemaVersion`) + hat altípus.
4. Konstruktor-validáció: üres `eventId`, negatív időtartam, tartományon kívüli pontszám.
5. JSON round-trip explicit `type` discriminatorral, mind a hat altípusra.
6. `public.dart` — az egyetlen belépő.
7. Az architektúra-guard bejegyzése az új feature-gyökérre — **lásd §0.0.2**:
   `tool/check_architecture.dart` NINCS `allowed_paths`-on, tehát a
   domain-purity ág a bevált E07-R02 mintát követve, egy önálló teszt-csoporttal
   épül `architecture_dependency_test.dart`-ban (nem a checker bővítésével);
   az A7 cross-feature szabály automatikus, ahhoz nem kell új tesztkód.
8. A valódi-sértés próba, §10-be dokumentálva.
9. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **Az `eventId` menet közbeni generálása.** Kényelmes, és három körrel később a dupla jutalom válik technikailag blokkolhatatlanná (A5). Ez a kör legfontosabb invariánsa.
- **A `flutter/foundation.dart` behúzása.** Egyetlen `@immutable` annotáció kedvéért, és ezzel a domain tesztelhetősége és újrafelhasználhatósága elvész (A6).
- **A schema-verzió „pragmatikus” alapértelmezése.** A régi eseményeket némán újraértelmezi, és a ledger egyenlege visszamenőleg hamis lesz (A2).
- **A hat altípus egyben.** Csábító előbb kettőt megcsinálni és a többit „később” — a `public.dart` barrel viszont a Kör 3-tól kezdve fix felület, és az utólagos bővítés minden fogyasztót érint.

## 10. Implementation handoff — az implementer tölti ki

### Módosított fájlok

- `lib/features/gamification/domain/activity/activity_source.dart` — a nyolc
  stabil, perzisztálható forráskód enum-szerződése.
- `lib/features/gamification/domain/activity/evidence_trust.dart` — az öt
  bizonyítékmegbízhatósági szint enum-szerződése.
- `lib/features/gamification/domain/activity/reward_eligibility.dart` —
  immutable, validált reward-eligibility adatkontraktus; policy-logika nélkül.
- `lib/features/gamification/domain/activity/learning_activity_event.dart` —
  a sealed alaptípus és a Practice/Song/Analysis/Plan/Tutor/Vision altípusok;
  hívó-adta `eventId`, schema- és értékhatár-validáció, explicit `type`-alapú
  JSON dekódolás.
- `lib/features/gamification/public.dart` — az új feature kizárólagos public
  belépője.
- `test/features/gamification/domain/activity_event_test.dart` — A2–A5/A8
  mátrix, explicit-discriminator regresszió, és az időtartam küszöb alatti /
  rajta lévő / fölötti cellái.
- `test/core/architecture_dependency_test.dart` — a gamification-domain
  framework-, storage-, óra- és véletlenforrás-mentességi őre.

### Ténylegesen futtatott ellenőrzések

- `flutter test test/features/gamification/domain/activity_event_test.dart`
  (RED, a production fájlok létrehozása előtt): a hiányzó
  `package:strumsight/features/gamification/public.dart` és a szerződés-típusok
  fordítási hibája, ahogy elvárt.
- `flutter test test/core/architecture_dependency_test.dart` (RED, a
  gamification domain létrehozása előtt): az E08-R02 csoport a hiányzó
  `lib/features/gamification/domain` könyvtárra bukott.
- `flutter test test/features/gamification/domain/activity_event_test.dart`
  (GREEN): 13/13 teszt zöld a minimális implementáció után, majd ismét zöld a
  refaktor után.
- `flutter test test/core/architecture_dependency_test.dart` (GREEN): 19/19
  teszt zöld az új domain-guarddal.
- **Valódi-sértés próba:** a `schemaVersion !=
  learningActivityEventSchemaVersion` elutasító ága ideiglenesen ki lett véve,
  majd futott a kötelező `tools/round-gate.sh
  test/features/gamification/domain/activity_event_test.dart
  test/core/architecture_dependency_test.dart`. A format és analyze zöld volt;
  a célteszt az A2 cellán piros lett (exit 1): `Expected: throws ArgumentError`
  helyett `PracticeActivityEvent` tért vissza a 2-es schema-verzióra. Az ág
  visszaállítva.
- Visszaállítás után a kötelező `tools/round-gate.sh
  test/features/gamification/domain/activity_event_test.dart
  test/core/architecture_dependency_test.dart` teljesen zöld: format (0
  változás), analyze (0 issue), activity esemény teszt 13/13, architecture
  teszt 19/19, és `Architecture dependencies OK (12 allowlisted deviations)`.

### Eltérések és nem futtatott ellenőrzések

- Nincs scope- vagy szerződéseltérés.
- Teljes Flutter-suite, property gate, release APK, CI-dispatch, PR és merge
  nem futott ebben a körben: ezek a brief és az `AGENTS.md` szerint a Claude
  orchesztrátor feladatai.

## 11. Review — a Claude tölti ki

**Correctness review:** [`docs/reviews/e08-r02-review.md`](../reviews/e08-r02-review.md)
— **APPROVED**, 0 BLOCKER/MAJOR/MINOR, 3 NOTE. A gate-et és mindkét
brief-kötelező valódi-sértés próbát (schemaVersion A2, architektúra-guard
A6) a reviewer saját kézzel, izolált `/tmp` klónban megismételte, nem az
implementer önjelentése alapján fogadta el.

**Security review** (risk=high, AGENTS.md §15.1):
[`docs/reviews/e08-r02-security.md`](../reviews/e08-r02-security.md) —
**APPROVED (PASS)**, 0 CRITICAL/BLOCKER/MAJOR, 1 MINOR, 4 NOTE. Az ELSŐ
futás egy elavult worktree-snapshoton téves BLOCKER-t jelentett (az
implementer commitja akkor még nem volt pusholva); a megismételt futás a
GitHub origin-ról frissen klónozva megerősítette a valós tartalmat és PASS
verdiktet adott. Az egyetlen MINOR (a gamification architektúra-guard
marker-listája nem fed hálózati/fájl-IO markert — `dart:io`/`dart:convert`/
`package:dio/`/`package:http/`) **ma nem aktív sértés** (a domain tiszta),
és a security reviewer explicit **nem blokkolja** vele ezt a merge-öt —
follow-up a Kör 3/4 előtt, `docs/LESSONS.md`-ben rögzítve.

**Zöld kapu:** `full-gate.yml` [32298644861](https://github.com/wolfcasaba/strumsight/actions/runs/32298644861)
success a `3b63029d` SHA-n (a két review-report commit előtti implementációs
állapot + a correctness review commitja). Router CI ugyanezen az ágon
(`95ddec13`-on, az utolsó `docs/rounds/**`-et érintő push-on) szintén
success; a review-report-commitok `docs/reviews/**`-et érintenek, ami nem
Router-CI trigger-útvonal — ez a §11 szerkesztés (ami `docs/rounds/**`-et
érint) friss Router CI futást vált ki a valódi végső SHA-n, merge előtt
ellenőrizve.
