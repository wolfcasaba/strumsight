# E07-R11 — PlanValidator és deterministic repair

- **Státusz:** IN PROGRESS (pre-flight felülmérve 2026-08-16, `main @ 74215044`)
- **Típus:** Epic 7 (AI Practice Generator), SDD Ch8 Kör 11
- **Kör-azonosító:** `E07-R11`
- **Branch:** `<motor>/e07-r11-plan-validator-and-repair`
- **Előfeltétel:** `E07-R10` merge-elve (terv-domain)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** [`0263`](../adr/0263-bounded-deterministic-plan-repair.md)
  — **MÁR MEGÍRVA, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R10 tényleges
> terv-modelljét és a `PlanChangeSet` alakját (a repair ebbe naplóz), valamint
> az R03 hard/soft korlát-modelljét. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/practice_generator/domain/model/plan_validation_issue.dart",
  "lib/features/practice_generator/domain/service/plan_validator.dart",
  "lib/features/practice_generator/domain/service/plan_repairer.dart",
  "lib/features/practice_generator/public.dart",
  "test/features/practice_generator/validation/plan_validator_test.dart",
  "test/features/practice_generator/validation/plan_repairer_test.dart",
  "test/property/planner_repair_property_test.dart",
  "test/fixtures/practice_generator/validation",
  "docs/rounds/e07-r11-plan-validator-and-repair.md",
]
gate_tests = [
  "test/features/practice_generator/validation/plan_validator_test.dart",
  "test/features/practice_generator/validation/plan_repairer_test.dart",
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

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**2026-08-16, H3 self-heal revízió (ADR 0112 önjavító kör, E07-R11, 1/3.
kísérlet).** Új ADR nincs — ez a revízió kizárólag `allowed_paths`-ot bővíti,
normatív döntést nem hoz.

**Mért gyökérok.** Az eredeti `allowed_paths` a két validáció-tesztfájlt
(`plan_validator_test.dart`, `plan_repairer_test.dart`) és a property-tesztet
egyenként, névre szólóan sorolta fel, de egyetlen megosztott fixture-helyet
sem — miközben a §6/§6.1 acceptance criteria mind a két tesztfájltól
**ugyanazt** a nem-triviális `AdaptivePracticePlan`/`PracticeDay`/
`PracticeBlock`/`WeeklyAvailability` felépítést várja el (9 kritérium +
a súlyosság három kötelező cellája). A sonnet-impl (engine=minimax-m3)
implementer emiatt a listán kívül hozta létre a
`test/fixtures/practice_generator/validation/validation_fixtures.dart`
fájlt (munkapéldány `/home/ubuntu/ss-sonnet-impl-e07-r11`, `head=a82bef17`,
7 piszkos fájl, egyik sem commitolva), amit a scope-audit helyesen
`stopped`-ra váltott (H3, `.pipeline/HALTED` halted_at=2026-08-16T06:06:06Z):

```
python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e07-r11 \
  --brief docs/rounds/e07-r11-plan-validator-and-repair.md \
  --base a82bef17a5b9cd6d8ac27f45c12c50e494511775
# exit 1 — "path outside allowed scope:
#   test/fixtures/practice_generator/validation/validation_fixtures.dart"
```

A self-heal a fenti parancsot a halt-olt munkapéldányon újra lefuttatta —
ugyanaz a verdikt.

**Miért pont ez a fájl, és miért ártalmatlan.** A self-heal elolvasta a fájl
teljes (225 soros) tartalmát: kizárólag a már engedélyezett
`package:strumsight/features/practice_generator/public.dart` publikus
típusaiból (`ExerciseCandidate`, `ExercisePrescription`, `PracticeBlock`,
`PracticeDay`, `WeeklyAvailability`, `AdaptivePracticePlan`, …) épít
paraméterezhető teszt-builder függvényeket — **nincs** benne domain-döntés,
`Random` vagy óra-olvasás (a `DateTime.utc(2026, 8, 16)` egy rögzített
fixture-literál, nem futásidejű hívás), és nem duplikál semmilyen production
logikát. 0 tartalmi/architekturális döntés változik ezzel a revízióval.

**Ez NEM új probléma-osztály.** Ugyanez a hiányzó-megosztott-fixture minta a
repóban már többször mérve volt: [[L242]] (E06-R20, PR #236,
`test/fixtures/analysis/insights`) és [[L246]] (E06-R23,
`labels_adapter.dart`) — mindkettő H3 self-heal, mindkettő azonos alakú
feloldással. A **közvetlen** precedens viszont az ELŐZŐ kör, ugyanebben a
feature-fában: `docs/rounds/e07-r10-adaptive-practice-plan-domain.md` §0.0.1
(2026-08-16, kör-közbeni kiegészítés, MERGE-ELVE `c2778bbc`/PR #283-ként) —
ott a Terra implementer SAJÁT `stopped` jelzése után az orchesztrátor
felvette `test/fixtures/practice_generator/plan/plan_fixtures.dart`-ot, és
explicit dokumentálta a repo-szintű `test/fixtures/<feature>/<terület>/
<név>_fixtures.dart` konvenciót — de az R11 brief **2026-08-15-én, R10 előtt**
lett előre megírva (`Státusz: PREPARED`), és R10 csak `05:50:55`-kor (ma
reggel) merge-elődött, közvetlenül R11 dispatchja (`05:51:04`) előtt — a két
esemény között nem futott friss pre-flight, ami az R10-frissen-mért
konvenciót R11-re is átvezette volna. Ez a NEGYEDIK mérés ugyanarra a
gyökérokra (hiányos `allowed_paths` egy több tesztfájl által megosztott,
nem-triviális builder-igényre) — a legfrissebb kettő (R10 §0.0.1 és ez a
self-heal) között alig öt óra telt el, ugyanabban a feature-ágban.

**Feloldás.** `allowed_paths` a `test/fixtures/practice_generator/validation`
könyvtárral bővült (bare directory, `*` nélkül — a `tools/ai_router/brief.py`
`SAFE_PATH` mintája globot nem enged; a `_matches()` prefix-szemantikája a
könyvtár ALATTI bármely fájlt automatikusan fedi, R10/E06-R20 mintáját
követve, nem az egyetlen jelenleg létező fájlnevet rögzítve). Regressziós
védelem: `tools/tests/test_e07_r11_validation_fixture_scope.py` — a valódi
mért halt-útvonalat futtatja `audit_legacy_scope()`-on a ténylegesen
committolt brief ellen, bizonyítva, hogy a mért útvonal az új listával belül
van, egy szomszédos, a `validation/` alkönyvtáron KÍVÜLI útvonal viszont
továbbra is kívül marad (a bővítés szűk, nem az egész `test/fixtures/
practice_generator/` fa).
### 0.0.1 Pre-flight revízió — a validáció bemenete explicit domain-context

**Mérés.** A `PracticeBlock` csak az `ExercisePrescription` snapshotját
tárolja (`exerciseId`, `source`, `contentRevision`, idő és success criteria);
nem tartalmaz aktuális catalog-assetet, eszközállapotot, hangolást vagy
load-profilt. Ezek a `ExerciseCandidate`/`PracticeCatalogSnapshot` oldalon
érhetők el, a `LearnerConstraint.code`/`value` pedig szándékosan általános
string, tehát a validátor nem következtethet belőle saját string-szabályt.
`PlanChangeReason.systemAdaptation` már létezik és a repair strukturált oka
lehet. Bizonyíték: `practice_block.dart`, `exercise_prescription.dart`,
`exercise_candidate.dart`, `practice_catalog_snapshot.dart`,
`learner_constraints.dart`, `plan_change_set.dart` a `main @ c573ed2f`-n.

**Feloldás.** A két új service saját, public domain contractja
`PlanValidationContext`: a hívó által adott, immutable catalog snapshot,
hard availability és comparison input. A context explicit, typed/identity
alapú állításokkal szolgáltatja az aktuális executabilityt (referenced
candidate + content revision, asset, device capability, offline, tuning és
hard-avoid); a validator ezekből **csak** determinisztikus leletet készít,
nem értelmezi a constraint szabad szövegét. A load-profile-t ugyanebből a
catalog snapshotból olvassa. A completed-history ellenőrzéshez a context az
előző teljes snapshotot is hordozza.

**Kötelező szűk szerződés.** Az identity `source.code:exerciseId`; a jelenlegi
catalogban hiányzó identity vagy eltérő content revision `error`. A context
nem megerősített asset/capability/offline/tuning/hard-avoid állapota szintén
`error` (nincs optimistic fallback). A hard maximum a `WeeklyAvailability`
hard maximuma, összehasonlítás mikrosecond pontosságú és inkluzív. A
terhelési sorrend egy day blokkjainak növekvő `order` sorrendje; három egymást
követő, `frettingHand == LoadLevel.high` blokk `warning` (a terv review-ra
szorul, de nem lesz automatikusan végrehajthatatlan). Az érték a service
injektálható policy-paramétere, alapértelmezése 2 megengedett egymás után.

**Repair-határ.** A repair kizárólag nem-completed blokkokat rövidíthet vagy
eltávolíthat; a contextből kapott új `RevisionId`-vel `PlanChangeSet`-et ad
vissza, minden változáshoz `PlanChangeReason.systemAdaptation`-nel. `fatal`,
completed-history sértés vagy a megadott iterációs korlát kimerülése sikertelen
eredmény, nem további próbálkozás. Ez a feloldás nem módosít lezárt ADR-t és
nem bővíti a fájllistát.

## 1. Cél

Minden generált és kézzel szerkesztett terv **teljes invariáns-ellenőrzése**,
és korlátos, determinisztikus javítás (SDD Ch8 Kör 11).

## 2. Jelenlegi állapot — mért tények

- Az R03 hard/soft korlát-modellje (ADR 0258): a hard **nem sérthető**.
- Az R10 terv-domainje: revíziók, `completed` múlt, `PlanChangeSet`.
- A projekt property-teszt konvenciója: `test/property/` a `PROPERTY_SEED`
  env-et olvassa (hiányában 42), a CI külön HARD lépést futtat véletlen
  seeddel. **Ez a kör property-tesztet ad** — a repair terminálását fuzz-zal
  kell bizonyítani.

## 3. Scope

**Benne van:** a teljes hard invariáns-lista · `info`/`warning`/`error`/`fatal`
súlyosság · **korlátos, determinisztikus** repair · a repair change setbe
naplózva, **okkal** · hiányzó asset, capability, hangolás és hard-avoid
kezelése · a befejezett múlt módosításának tiltása.

**NINCS benne (tilos):** tervező-algoritmus (Kör 12-től) · repository ·
UI · a hard korlát fellazítása · Flutter, `DateTime.now()`, `Random` (a
property-teszt seedje injektált) · más `lib/features/**`, `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `domain/model/plan_validation_issue.dart` | **ÚJ** — lelet + súlyosság |
| `domain/service/plan_validator.dart` | **ÚJ** — az invariánsok |
| `domain/service/plan_repairer.dart` | **ÚJ** — korlátos javítás |
| `public.dart` | a barrel bővítése |
| `test/…/validation/*_test.dart` (2 db) | a §6 cellái |
| `test/property/planner_repair_property_test.dart` | **ÚJ** — terminálás fuzz-zal |
| `test/fixtures/practice_generator/validation/**` | **ÚJ** — megosztott `AdaptivePracticePlan`/`PracticeDay`/`WeeklyAvailability` builder a validator+repairer teszthez (H3 self-heal, §0.0) |
| `docs/rounds/e07-r11-…md` | a §10 handoff |

**Tilos zóna:** más `lib/features/**` · `lib/app/**` · `docs/adr/**` ·
`docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések (ADR 0263)

### 5.1 `error`/`fatal` mellett a terv NEM aktiválható

A validáció eredménye kapu, nem tanács. Hibás terv nem kerülhet végrehajtásra.

### 5.2 A repair TERMINÁL — kimondott iterációs korláttal

A javítás lépésszáma felülről korlátos. Ha a korláton belül nem sikerül,
a repair **feladja** és a hibát jelenti — nem ciklizál.

**NEM elfogadható gyengítés:** „konvergálni fog" feltevés korlát nélkül. A
terminálást a property-teszt bizonyítja, nem az érvelés.

### 5.3 A repair SOHA nem növeli az időt a hard maximum fölé

Egy javítás nem oldhat meg problémát azzal, hogy több időt ír be, mint amit a
tanuló megadott (ADR 0258 §3).

### 5.4 Minden repair-lépés OKKAL naplózott

A `PlanChangeSet`-be strukturáltan bekerül, mit és **miért** változtatott.
Ok nélküli változtatás tilos — enélkül a terv magyarázhatatlanná válik
(ADR 0255 kimondott célja).

### 5.5 A repair DETERMINISZTIKUS

Ugyanaz a hibás terv ugyanazt a javított tervet adja. Nincs `Random`, nincs
óra-olvasás, és a lépések sorrendje rögzített.

### 5.6 A befejezett múltat a repair SEM módosíthatja

Az ADR 0256 §1 a repairre is érvényes: a javítás a jövőt rendezi át.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `error`/`fatal` lelet mellett a terv nem aktiválható | `plan_validator_test.dart` |
| A2 | A repair terminál minden bemenetre | `test/property/planner_repair_property_test.dart` |
| A3 | A repair nem lépi túl a hard időmaximumot | `plan_repairer_test.dart` |
| A4 | Minden repair-lépésnek van OKA a change setben | ugyanott |
| A5 | Ugyanaz a hibás terv → ugyanaz a javított terv | ugyanott |
| A6 | A repair nem módosítja a `completed` múltat | ugyanott |
| A7 | Hard-avoid sértés `error`, nem `warning` | `plan_validator_test.dart` |
| A8 | Hiányzó asset / capability / hangolás detektált | ugyanott |
| A9 | A terhelés-sorrend (load sequencing) invariáns ellenőrzött | ugyanott |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A repair korlát nélkül iterál | **A2** (a fuzz nem terminál) |
| A repair időt ad hozzá a hard max fölé | **A3** |
| Ok nélküli változtatás | A4 |
| `Random` a repairben | A5 |
| A repair a `completed` napot rendezi át | **A6** |
| Hard-avoid csak `warning` | A7 |
| `error` mellett is aktiválható terv | **A1** |

**A súlyosság három kötelező cellája** (a határ: az aktiválhatóság):

| Cella | Bemenet | Elvárt |
|---|---|---|
| alatta | csak `info`/`warning` lelet | a terv **aktiválható** |
| a határon | pontosan egy `error` | **nem aktiválható** |
| fölötte | `fatal` lelet | nem aktiválható, és a repair sem próbálkozik |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** vedd ki a repair
iterációs korlátját → az **A2** property-cellának PIROSNAK (vagy timeoutosnak)
kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/practice_generator/validation/plan_validator_test.dart test/features/practice_generator/validation/plan_repairer_test.dart test/property/planner_repair_property_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `plan_validation_issue.dart` — lelet + négy súlyossági szint.
2. `plan_validator.dart` — a teljes hard invariáns-lista.
3. `plan_repairer.dart` — korlátos, determinisztikus, okkal naplózó javítás.
4. A property-teszt a terminálásra (`PROPERTY_SEED` konvencióval).
5. Tesztek a §6.1 három súlyossági cellájával.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A nem termináló repair.** A „konvergálni fog" feltevés a legveszélyesebb:
  éles adaton fagyást okoz. Ezt csak fuzz bizonyítja (A2).
- **Az idő-hozzáadás mint javítás.** A legegyszerűbb megoldás sok problémára,
  és pont a tanuló megadott korlátját sérti (A3).
- **A repair mint csendes szerkesztő.** Ok nélkül változtatva a terv
  magyarázhatatlan lesz, és a felhasználó bizalma vész el (A4).
- **A `completed` átrendezése.** Egy „takarítás" a múltba nyúlna (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
