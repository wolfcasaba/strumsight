# E12-R32 — Staged rollout 1–20 százalék

- **Státusz:** ACTIVE — pre-flight elvégezve 2026-09-02, **§0.0.1 brief-revízióval** (P1–P7; egy MÉRTEN hamis premissza javítva, a dokumentum-szerződés kimérve). Eredetileg előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 32
- **Kör-azonosító:** `E12-R32`
- **Branch:** `<motor>/e12-r32-staged-rollout-1-to-20-percent`
- **Előfeltétel:** `E12-R31` merge-elve (belső production cohort + rollout-csomag sablon)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör döntési eljárást és naplózó eszközt szállít.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "staged rollout percentage observation window decision packet"` → **[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** (a rollout-határ áthelyezése és a belépési pont mint a rollout része) — a repó MÉRT tapasztalata, hogy a rollout nem csak százalék, hanem BELÉPÉSI PONT kérdése is. A napló ezt is rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Kör 31 rollout-csomag sablonja és a Kör 19 dashboard-sémája MEGVAN, és hogy a Kör 5 kill switch dry-runja lefutott. Enélkül a lépcsőzés vak.

## 0.0 EMBERI KAPU

A rollout-százalék állítása **kizárólag user-művelet** (store/console hozzáférés). Az implementer terméke: a döntési napló SÉMÁJA és ellenőrzője, ami minden lépcsőhöz kötelezővé teszi a megfigyelési ablakot, a mért adatot és a döntést — és amely a hiányos csomagot elutasítja. A kör NEM állít rollout-százalékot.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/staged-rollout-log.md",
  "docs/release/rollout-decision.md",
  "tool/release/verify_rollout_decision.py",
  "test/tooling/rollout_decision_test.dart",
  "docs/rounds/e12-r32-staged-rollout-1-to-20-percent.md",
]
gate_tests = [
  "test/tooling/rollout_decision_test.dart",
  "test/tooling/freeze_policy_test.dart",
]
native_gate = false
```

## 0.0.1 Pre-flight brief-revízió (orchestrátor, Claude, 2026-09-02)

A brief 2026-08-27-én készült `main @ 9ca4a0dc`-re. A kötelező pre-flight
(prompt §1: „a táblát mértem, nem a tényleges utat") **egy állítást MÉRTEN
megcáfolt** (P1), a többi pontban a séma tényleges adatforrásait és a
dokumentum-szerződést mérte ki, hogy az implementernek ne kelljen alakot
kitalálnia. A revízió a mércét NEM lazítja (P7 egy ÚJ cellát tesz hozzá) és
az engedélyezett-fájllistát NEM tágítja.

**Visszakeresés (ADR 0312, szűkítve → teljes):** `lessons,halts,adr` ágon
**[ADR 0197](../adr/0197-song-trainer-shipping-rollout-boundary.md)** (a
rollout a belépési pont kérdése is), `lessons/L527` (az ÖNVÉDŐ cella volt a
vakon zöld — a guard a saját hibaosztályát engedte át), `lessons/L110`
(külső binárisra shellelő teszt a boxon zöld, a CI-n piros),
`lessons/L206` (a `paths:`-szűrős workflow-k kézi dispatchje),
`lessons/L102` (az implementer saját teszt-futtatása NEM a `round-gate.sh`).
Teljes korpuszon a testvér-kör `docs/rounds/e12-r33-staged-rollout-50-to-100-and-ga.md`
(a §7 gate-je ÚJRA futtatja a `rollout_decision_test.dart`-ot → az itt
szállított szerződés a következő körben is köt).

### P1 — a Kör 5 kill switch dry-run NEM futott le *(a §13 pre-flight-jegyzet állítása HAMIS)*

**Mérés:** `grep -rn -i "dry.run" docs/release docs/operations docs/adr/0446*.md`
→ **nulla találat**; a `docs/release/kill-switches.md` §3 kimondja, hogy
„valódi hálózati remote-flag csatorna vagy aláírás-ellenőrzés" nincs a fán, a
40 flag többségének kill-switch útja **build-idejű `dart-define` vagy
forráskód-módosítás**.

**Következmény (a kör NEM oldja meg, csak őszintén jelöli):** a napló váza a
kill-switch utat lépcsőnkénti **`[EMBERI]` előfeltétel-sorként** hordozza a
MÉRT mechanizmussal (dart-define / forrás-módosítás), nem „lefutott
dry-runra" hivatkozik. Kitalált automatizmus TILOS (§0 STOP-protokoll).

### P2 — a Kör 19 terméke MÉRVE: `release-dashboard.md` + `slo.yaml`, és a küszöb NEM ismételhető

**Mérés:** `docs/operations/slo.yaml` (5 SLO, mind `required: true`,
`verdict_values: [success, degraded, breach, unknown]`,
`blocking_verdicts: [degraded, breach, unknown]`, `on_missing: unknown`,
soronként `source:` mező), `docs/operations/release-dashboard.md` („Threshold
source of truth: `docs/operations/slo.yaml`. This document does **not**
repeat any objective/threshold").

**Következmény:** az ellenőrző a **kötelező mutató-halmazt és a blokkoló
verdikteket a `slo.yaml`-ből OLVASSA**, nem másolja a saját forrásába vagy a
sémadokumentumba. A `crash_free_sessions` és a `tutor_turn_success_rate`
`source:` mezője maga mondja ki, hogy telemetria-gyűjtés nincs (`rollout
round 31-33 … not yet wired`) — ez a §5.3 forrás-jelölés MÉRT alapja.

### P3 — a Kör 31 sablonja megvan; a séma hivatkozza, nem másolja

**Mérés:** `docs/release/rollout-packet-template.md` létezik, 9 `## `-szintű
szakasszal; a sorrendjét a `test/tooling/production_readiness_test.dart` A6
cellája már méri. **Következmény:** a `rollout-decision.md` a csomag-sablonra
HIVATKOZIK (a lépcsőnként kitöltendő csomag), és nem duplikálja a kilenc
szakaszt — két divergens sablon rosszabb, mint egy.

### P4 — a `blockers.md`-ben nincs státusz-oszlop: minden felsorolt sor NYITOTT

**Mérés:** `docs/release/blockers.md` fejléce `| ID | Severity | Cím | Owner
(kör) | Chapter | Bizonyíték | Zárási feltétel |` — nincs `status` oszlop, és
a „Miért pont ezek" szakasz szerint minden sor valódi, nyitott hiányt jelöl.
Ma **R-SIGN-01 (P0)** és öt P1 sor van nyitva.

**Következmény (két, egymást erősítő előírás):**

1. az `open P0/P1` fogalma gépileg = *„a `blockers.md` táblájában szerepel egy
   `P0` vagy `P1` súlyosságú sor"* — nem kell (és nem is szabad) státusz-mezőt
   kitalálni hozzá;
2. **a szállított `staged-rollout-log.md` váz MINDEN lépcsője `pending`
   döntésű** — egyetlen `approved` sor sem szerepelhet benne, különben a §7
   gate a saját fáján PIROS. A valós fán mért `exit 0` maga is
   acceptance-cella (A8).

### P5 — a kilépőkód-szerződés fagyott: 0 / 1 / 2, nincs negyedik kód

**Mérés:** `docs/release/contract-freeze.md` 4. sora a
`verify_ga_scope.py`/`verify_beta_profile.py` `0 = ok, 1 = validációs
találat, 2 = használati/formátumhiba` szemantikáját fagyasztja; a
`verify_freeze.py` (Kör 30) ugyanezt a hármat használja.

**Következmény:** a `verify_rollout_decision.py` UGYANEZT a három kódot
használja. Továbbá — a Kör 30 MAJOR-1 tanulsága —: **a csupasz hívás
(`python3 tool/release/verify_rollout_decision.py`, kapcsolók nélkül) TELJES
ellenőrzést futtat**, nem hagy ki csendben egyetlen szabályt sem; minden
útvonal-kapcsolónak van a valós fára mutató alapértelmezése.

### P6 — a teszt `python3`-ra shellel: önellenőrző cella KÖTELEZŐ

**Mérés:** `test/tooling/freeze_policy_test.dart:46-51` első csoportja egy
`python3 --version` cellát futtat, hogy egy hiányzó interpreter PIROS legyen,
ne néma átugrás (L110, L527). **Következmény:** a
`rollout_decision_test.dart` ELSŐ csoportja ugyanez a cella. Külső bináris
(`rg`, `jq`, …) hívása a tesztben és az ellenőrzőben TILOS — csak `python3`,
a Python standard library, és `git` NEM kell.

### P7 — ÚJ acceptance-cella (A7): cohort-dimenzió, metszet nélkül

**Mérés:** az SDD Ch12 Kör 32 „Kötelező tesztek" szakasza kimondottan kéri a
**dashboard cohort filtering** ellenőrzését, a `release-dashboard.md`
„Cohort filter" szakasza pedig kimondja: „the dashboard does not silently
intersect dimensions". Ez ma gépileg SEHOL nincs mérve.

**Következmény:** a megfigyelési sorok `cohort` oszlopa pontosan EGY
dimenziót hordoz (`all`, vagy `platform:<érték>` / `app_version:<érték>` /
`build_mode:<érték>`); két dimenzió egy cellában (metszet) → nem-nulla
kilépés. Ez a **§6 A7** cellája.

### P8 — a kör diffje a feature-freeze osztályokba esik (nincs teendő, csak igazolás)

A `docs/**`, `tool/release/**` és `test/tooling/**` mind lefedett osztály a
`docs/release/feature-freeze.md` zárt hármasában, ezért a Kör 30
`freeze_policy_test.dart`-ja (A6) ettől a körtől nem válik pirossá.

### 0.0.2 Dokumentum-szerződés (NORMATÍV — az implementer ezt valósítja meg)

A parsereket a `tool/release/verify_freeze.py` mintájára írd: **marker-blokk
+ tábla, fail-closed** — hiányzó/üres blokk és alakra nem illő sor
`exit 2`-t ad, a sor SOSEM esik ki csendben (L566/L571/L573/L575).

**`docs/release/rollout-decision.md`** — a séma. Kötelező blokkjai:

```text
<!-- human-gate:begin -->    … <!-- human-gate:end -->
<!-- rollout-steps:begin --> … <!-- rollout-steps:end -->
```

- a `human-gate` blokk nem lehet üres, és tartalmazza szó szerint a
  `A rollout-százalék állítása EMBERI művelet.` mondatot (A5 gépi horgonya);
- a `rollout-steps` tábla sorai: `| step | rollout_percent | min_observation_hours |`
  — `step` ∈ `` `stage-1` ``/`` `stage-5` ``/`` `stage-20` ``, a százalékok
  `1`/`5`/`20`, a minimális megfigyelési ablak **`24` / `48` / `72` óra**;
- a kötelező mutató-halmazt és a blokkoló verdikteket a séma **nem** sorolja
  fel — azok a `docs/operations/slo.yaml`-ből jönnek (P2).

**`docs/release/staged-rollout-log.md`** — a napló. Két blokkja:

```text
<!-- rollout-decisions:begin -->     … <!-- rollout-decisions:end -->
<!-- rollout-observations:begin -->  … <!-- rollout-observations:end -->
```

- döntés-sor: `| step | window_start | window_end | observed_hours | decision | decision_maker | rollback_target |`
  — `decision` ∈ `pending` / `approved` / `held` / `rolled_back`;
- megfigyelés-sor: `| step | metric | cohort | source | verdict | measured_value |`
  — `metric` egy `slo.yaml`-beli `id`, `source` ∈ `machine` / `manual`,
  `verdict` a `slo.yaml` `verdict_values` egyike, `measured_value` értéke
  `n/a` KIZÁRÓLAG `unknown` verdikt mellett (üres cella SOSEM elfogadható);
- a váz a három lépcső × öt `slo.yaml`-mutató = **15 megfigyelés-sort** és
  **3 döntés-sort** tartalmazza, minden döntés `pending`, minden verdikt
  `unknown`, `measured_value` `n/a`, a kitöltendő szöveges cellák értéke a
  `TBD` literál (P4).

**Az ellenőrző szabályai** (`tool/release/verify_rollout_decision.py`,
`--log` / `--decision` / `--blockers` / `--slo` kapcsolókkal, mind a valós
fára mutató alapértelmezéssel):

| # | Szabály | Kód |
|---|---|---|
| R1 | hiányzó/üres marker-blokk, alakra nem illő sor, hiányzó fájl | `2` |
| R2 | üres cella bármely sorban; ismeretlen `decision`; ismeretlen `step`; egy deklarált lépcsőhöz nem pontosan egy döntés-sor; ismétlődő `(step, metric, cohort)` | `1` |
| R3 | `source` ∉ {`machine`, `manual`} (A3) | `1` |
| R4 | a `cohort` cella nem pontosan egy ismert dimenzió (A7) | `1` |
| R5 | `approved` döntés, miközben a `blockers.md`-ben van nyitott P0/P1 sor (A2) | `1` |
| R6 | `approved` döntés `observed_hours < min_observation_hours` mellett (INKLUZÍV határ) | `1` |
| R7 | `approved` lépcső, amelynek van `blocking_verdicts`-beli verdiktű megfigyelés-sora, VAGY hiányzik egy `slo.yaml`-beli kötelező mutató sora | `1` |
| R8 | `approved` döntés üres vagy `TBD`/`<…>` alakú `decision_maker` vagy `rollback_target` cellával | `1` |

Az `approved`-hoz kötött szabályok (R5–R8) szándékosan NEM futnak a `pending`
sorokra: a napló váza így marad zöld anélkül, hogy a mérce lazulna — egy
kitöltött, valódi `approved` sor MINDEN szabályt kiállni köteles.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a döntési séma egy kötelező mezőjéhez a fán nincs adatforrás (pl. nincs telemetria), a kimenet a `stopped` jelzés vagy a mező EXPLICIT „manuális megfigyelés" jelölése — kitalált automatizmus TILOS.

## 1. Cél

Az első publikus lépcsők (1% → 5% → 20%) legyenek dokumentált, mért döntések: minden lépés előtt megfigyelési ablak, mért adat és explicit jóváhagyás — vak, automatikus rollout nélkül.

## 2. Jelenlegi állapot — mért tények

- `docs/release/rollout-packet-template.md` a Kör 31 terméke; `staged-rollout-log.md` **nincs**.
- Telemetria-GYŰJTÉS nincs (a Kör 19 szerződést adott) — a megfigyelés forrása a store-konzol, a visszajelzés és a diagnosztikai bundle. A séma ezt EXPLICIT jelöléssel kezeli.
- A kill switch (Kör 5) és a rollback (Kör 26) MÉRT úton elérhető — a döntési csomag ezekre hivatkozik.
- A `docs/release/blockers.md` a P0/P1 forrás.

## 3. Scope

**Benne van:** `docs/release/rollout-decision.md` (a döntési séma: lépcső, megfigyelési ablak hossza, mért mutatók, forrásuk — GÉPI vagy MANUÁLIS —, döntés, döntéshozó, rollback-cél) · `tool/release/verify_rollout_decision.py` (hiányzó mező, hiányzó megfigyelési ablak, nyitott P0/P1 melletti előrelépés → nem-nulla kilépés) · `test/tooling/rollout_decision_test.dart` · `docs/release/staged-rollout-log.md` (a napló váza az 1/5/20%-os lépcsőkkel, kitöltésre készen).

**NINCS benne (tilos):**

- Tényleges rollout-százalék állítása vagy store-művelet.
- Automatikus (emberi jóváhagyás nélküli) lépcsőzés bármilyen formában.
- `lib/**`, `.github/**` módosítás.
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/rollout-decision.md` | ÚJ — a döntési séma |
| `tool/release/verify_rollout_decision.py` | ÚJ — az ellenőrző |
| `test/tooling/rollout_decision_test.dart` | a §6 cellái |
| `docs/release/staged-rollout-log.md` | ÚJ — a napló váza |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/release/blockers.md` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 Nincs automatikus lépcsőzés

Minden lépcső explicit emberi jóváhagyás. **NEM elfogadható gyengítés:** „ha 24 órán át nincs hiba, automatikusan lépjünk" szabály.

### 5.2 Nyitott P0/P1 mellett NINCS előrelépés

**NEM elfogadható gyengítés:** „ismert, de nem kritikus" átsorolás mérési indoklás nélkül.

### 5.3 A mutató FORRÁSA jelölt: gépi vagy manuális

**NEM elfogadható gyengítés:** olyan mutató, amiről a séma azt sugallja, hogy automatikusan gyűlik, holott nincs gyűjtés.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hiányzó kötelező mező (ablak, mutató, döntéshozó) → nem-nulla kilépés | `rollout_decision_test.dart` |
| A2 | Nyitott P0/P1 melletti előrelépés → nem-nulla kilépés | `rollout_decision_test.dart` (a `blockers.md` olvasásával) |
| A3 | Minden mutató forrás-jelölést hordoz (`machine` / `manual`) | `rollout_decision_test.dart` |
| A4 | A napló váza mind a három lépcsőt (1%, 5%, 20%) tartalmazza, rollback-céllal | a dokumentum |
| A5 | A séma kimondja: a százalék állítása EMBERI művelet | a dokumentum |
| A6 | A Kör 30 `freeze_policy_test.dart` VÁLTOZATLANUL zöld | a §7 gate |
| A7 | A `cohort` cella pontosan egy dimenziót hordoz; két dimenzió (metszet) → nem-nulla kilépés (§0.0.1 P7) | `rollout_decision_test.dart` |
| A8 | A SZÁLLÍTOTT fán a csupasz `python3 tool/release/verify_rollout_decision.py` **exit 0** (a váz `pending`-only, §0.0.1 P4), és a csupasz hívás minden szabályt futtat (Kör 30 MAJOR-1) | `rollout_decision_test.dart` |
| A9 | Marker-blokk fail-closed: hiányzó blokk, üres blokk, alakra nem illő sor → **exit 2** mindkét dokumentumra (L566/L571/L573/L575) | `rollout_decision_test.dart` |

**Küszöb-cellahármas a megfigyelési ablakra** — a `stage-1` lépcső mért
küszöbe `W = 24` óra (§0.0.1 0.0.2 szerződés), a határ **INKLUZÍV**. A három
cella (a szomszédok `python3 -c 'W=24; print(W-1, W, W+1)'` → `23 24 25`)
egy TEMP fixture-naplón, `approved` döntéssel, tiszta (P2-only) fixture
`blockers.md`-vel és csupa `success` verdikttel fut:

| Cella | `observed_hours` | Elvárt kilépőkód |
|---|---|---|
| küszöb alatt | `23` | `1` (a stderr nevezze meg a lépcsőt és a `24`-et) |
| pontosan rajta | `24` | `0` |
| küszöb fölött | `25` | `0` |

A „pontosan rajta" cella az egyetlen, ami a szigorú `>` implementációt
pirosra váltja — enélkül a hármas vak.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az ellenőrző nem olvassa a `blockers.md`-t | A2 |
| A mutatók forrás-jelölés nélkül kerülnek a sémába | A3 |
| Az ablak-ellenőrzés szigorú `>`-t használ | a küszöb-cellahármas „pontosan rajta" cellája |
| A séma automatikus előrelépést enged | A5 |
| A `cohort` cella két dimenziót is elfogad (csendes metszet) | A7 |
| A csupasz hívás (kapcsolók nélkül) csendben kihagy egy szabályt | A8 |
| Egy alakra nem illő sor csendben kiesik a táblából (fail-OPEN parser) | A9 |
| Az ellenőrző nem olvassa az `slo.yaml`-t, hanem a saját forrásába másolja a mutató-listát vagy a blokkoló verdikteket | R7 cellája (hiányzó kötelező mutató-sor → nem-nulla) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a `blockers.md`-olvasást az ellenőrzőből, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart
```

Az ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_rollout_decision.py --log docs/release/staged-rollout-log.md
```

## 8. Implementációs sorrend

1. `docs/release/rollout-decision.md` — a séma a §0.0.2 marker-blokkjaival, forrás-jelöléssel.
2. `docs/release/staged-rollout-log.md` váz (3 döntés-sor `pending`, 15 megfigyelés-sor `unknown`/`n/a`, + a kill-switch `[EMBERI]` előfeltétel-sorok, §0.0.1 P1).
3. `tool/release/verify_rollout_decision.py` — az R1–R8 szabályok, `slo.yaml`-ből olvasott mutató-halmazzal és blokkoló verdiktekkel.
4. `test/tooling/rollout_decision_test.dart` — `python3` önellenőrző cella, az A1–A9 cellák és a küszöb-cellahármas (`23`/`24`/`25`), TEMP fixture-ökön; a szállított dokumentumokat egyetlen cella sem módosítja.
5. A valódi-sértés próba a §10-be (a `blockers.md`-olvasás kivétele → az A2 cella PIROS → visszaállítás).

## 9. Kockázatok

- **Vak rollout.** Telemetria hiányában a „mért adat" könnyen üres marad — ezért kötelező a forrás-jelölés (A3).
- **Automatizmus-csábítás.** Az automatikus lépcsőzés kényelmes és pontosan az, amit a SDD tilt (A5).
- **Blocker-átsorolás.** A P1 „nem kritikus"-sá minősítése a legolcsóbb módja a kapu megkerülésének (§5.2).

## 10. Implementation handoff — az implementer tölti ki

**Motor:** Claude Sonnet 5 (`sonnet-impl`). **Ág:** `sonnet-impl/e12-r32-staged-rollout-1-to-20-percent`.
**Jelzés:** `blocked` — a §7 gate NEM zöld, egy MÉRT, ezen a körön KÍVÜLI, a
tilos zónába eső oksági lánccal (részletek alább). A kör saját négy
terméke (`rollout-decision.md`, `staged-rollout-log.md`,
`verify_rollout_decision.py`, `rollout_decision_test.dart`) elkészült,
commitolva van, és **önmagában, elszigetelten futtatva teljesen zöld**
(28/28 cella, ld. lent) — a blokkoló ok egy MÁSIK, a szállított
`test/tooling/freeze_policy_test.dart`-ban mért, ezen kör engedélyezett
fájllistáján kívül eső, előre létező regresszió.

### 10.1 A négy szállított termék

| Fájl | Tartalom |
|---|---|
| `docs/release/rollout-decision.md` | séma: `human-gate` + `rollout-steps` marker-blokk (stage-1/5/20 → 1/5/20% → 24/48/72 óra), R1–R8 szabálytábla dokumentálva |
| `docs/release/staged-rollout-log.md` | váz: 3 döntés-sor (`pending`, `TBD` cellák), 15 megfigyelés-sor (3 lépcső × 5 `slo.yaml`-mutató, `unknown`/`n/a`, `source: manual`), kill-switch `[EMBERI]` előfeltétel-tábla |
| `tool/release/verify_rollout_decision.py` | R1–R8 ellenőrző; `slo.yaml`-t és `blockers.md`-t frissen olvassa minden futáskor (nem másolja a saját forrásába) |
| `test/tooling/rollout_decision_test.dart` | `python3` önellenőrző cella + A1/A2/A3/A4/A5/A7/A8/A9 csoportok + a `23`/`24`/`25` küszöb-hármas — 28 teszt, mind zöld |

### 10.2 Az ellenőrző közvetlen futtatása (§7)

```text
$ python3 tool/release/verify_rollout_decision.py
verify_rollout_decision: ok — 3 decision row(s), 15 observation row(s)
(exit 0)

$ python3 tool/release/verify_rollout_decision.py --log docs/release/staged-rollout-log.md
verify_rollout_decision: ok — 3 decision row(s), 15 observation row(s)
(exit 0)
```

### 10.3 Küszöb-cellahármas (24 órás, INKLUZÍV határ) — MÉRT

TEMP fixture-ön, `approved` `stage-1` döntéssel, tiszta (P2-only) fixture
`blockers.md`-vel, csupa `success` verdikttel (a `test/tooling/rollout_decision_test.dart`
„threshold triple" csoportja):

| `observed_hours` | Kilépőkód | Megjegyzés |
|---|---|---|
| `23` | `1` | stderr: „step 'stage-1' approved with observed_hours '23' < min_observation_hours 24 (R6)" — nevesíti a lépcsőt és a `24`-et |
| `24` | `0` | pontosan a határon — a INKLUZÍV határ bizonyítéka |
| `25` | `0` | a határ fölött |

A hármas bizonyítja: az ablak-ellenőrzés NEM szigorú `>`-t használ (§6.1
mérce-mátrix).

### 10.4 Valódi-sértés próba (KÖTELEZŐ, §6.1) — A2 / R5

1. `tool/release/verify_rollout_decision.py`-ban a `validate_decisions()`
   `open_blockers` számítását ideiglenesen `{}`-re cseréltem (a
   `blockers.md`-olvasás hatását kiiktatva, a fájlt magát is beolvasva
   hagyva — csak a talált súlyosságokat dobtam el).
2. `flutter test test/tooling/rollout_decision_test.dart` → **A2 csoport
   első cellája PIROS** (`Expected: <1> Actual: <0>`), pontosan az a cella,
   ami a REAL `blockers.md`-t olvassa nyitott P0/P1 mellett `approved`
   döntésre.
3. A módosítást visszaállítottam (`git diff --stat` üres a visszaállítás
   után).
4. `flutter test test/tooling/rollout_decision_test.dart` → **28/28 zöld**
   újra.

Ezzel bizonyítva: az A2 cella TÉNYLEG a `blockers.md`-olvasást méri, nem egy
önvédő (vakon zöld) cella (L527).

### 10.5 §7 gate — MÉRT, és MIÉRT nem zöld

```text
$ tools/round-gate.sh test/tooling/rollout_decision_test.dart test/tooling/freeze_policy_test.dart
[1] format:  ZÖLD
[2] analyze: ZÖLD
[3] test test/tooling/rollout_decision_test.dart: ZÖLD (28/28)
[3] test test/tooling/freeze_policy_test.dart:    PIROS — exit 10
```

A piros cella: `sanity — … exit 0 classifying the real freeze-era diff since
freeze_base_sha … (§7 — this round's own diff is documentation +
release-tooling only)`. A `verify_freeze.py --since 4ac78365` (a
`docs/release/feature-freeze.md` frozen `freeze_base_sha`-ja) egy
osztályozatlan útvonalat talál:

```text
verify_freeze: 1 finding(s):
  - backend/tests/test_production_smoke_contract.py: not classified under
    any freeze change class (no documentation/release-tooling path prefix
    matched, and the commit names no P0/P1/P2 blockers.md id) — commit
    message: '[E12-R31] Production deployment és internal production
    cohort (ADR nincs) (#527)…'
```

**Mérve — EZ NEM az én diffem hatása.** `git worktree add --detach
/tmp/freeze-check 852633f3` (a jelen kör ELSŐ, pre-flight commitja, a saját
munkám ELŐTT) + `python3 tool/release/verify_freeze.py --since 4ac78365`
ugyanazt az 1 findinget adja, ugyanazzal az exit 1-gyel. A gyökér ok: az
`E12-R31` squash-merge commitja (`accd30c2` / PR #527) egy `backend/**`
útvonalat (`backend/tests/test_production_smoke_contract.py`) módosított,
és a commit-üzenet nem nevez meg P0/P1/P2 `blockers.md`-azonosítót — ezért
a `verify_freeze.py` `blocker-fix` osztálya nem fogadja el. Az `E12-R31`
kör saját `§7` gate-parancsa (`docs/rounds/e12-r31-…md:277`) **nem
tartalmazta** a `test/tooling/freeze_policy_test.dart`-ot — ez a Kör 30
gate-je azóta nem futott újra, és a regresszió észrevétlen maradt egészen
addig, amíg a jelen kör brief-je elő nem írta az együtt-futtatást.

**Miért nem javítható ez a kör hatáskörében:** a javítás vagy (a) a
`docs/release/feature-freeze.md` `freeze_base_sha`-jának előreléptetése az
`E12-R31` merge-e utánra, vagy (b) egy retroaktív blocker-azonosító idézése
— egyik sem lehetséges a már mergelt git-történet módosítása nélkül, és
mindkét fájl (`feature-freeze.md`, `test/tooling/freeze_policy_test.dart`)
a jelen kör tilos zónájában van (§4 — nincs a `4` engedélyezett fájl
között). A STOP-protokoll (§0, közös preambulum §4) szerint ehhez a
fájlhoz nem nyúlok.

### 10.6 Ajánlás a láncnak

Egy külön, `docs/release/feature-freeze.md`-t érintő kör (vagy egy
Kör 30/31 utólagos javító köre) léptesse előre a `freeze_base_sha`-t egy,
az `E12-R31` merge UTÁNI SHA-ra (pl. a jelen ág szülője, `852633f3`, vagy
`origin/main` aktuális feje), miután megerősítette, hogy az azóta eltelt
összes commit a három zárt osztály valamelyikébe esik. Eddig a pontig a
`test/tooling/freeze_policy_test.dart` a `--since 4ac78365` sanity cellán
PIROS marad minden jövőbeli körben is, függetlenül azok saját diffjétől.

## 11. Review — a Claude tölti ki
