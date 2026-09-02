# E12-R28 — Beta stabilization és scope cut

- **Státusz:** IN PROGRESS (előre megírva 2026-08-27 `main @ 9ca4a0dc`-ra; pre-flight újramérve 2026-09-02, `main @ 4bdedfbc` — lásd **§0.0.B**)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 28
- **Kör-azonosító:** `E12-R28`
- **Branch:** `<motor>/e12-r28-beta-stabilization-and-scope-cut`
- **Előfeltétel:** `E12-R27` merge-elve ÉS a Closed Beta USER általi lefuttatása (a kör bemenete a béta tapasztalata)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** `ADR 0489` — [`docs/adr/0489-ga-scope-classification-and-contract-freeze.md`](../adr/0489-ga-scope-classification-and-contract-freeze.md), a pre-flightban MEGÍRVA (a brief eredeti `0464` értéke elavult — §0.0.B R1).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "beta stabilization scope cut contract freeze preview feature"` → **[ADR 0306](../adr/0306-plan-preview-presentation-activation-boundary.md)** (plan-preview aktiválási határ): a repóban MÁR van mintája annak, hogy egy preview-funkció a core útra nem hathat. A scope-cut ezt a mintát általánosítja.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Closed Beta MEGTÖRTÉNT-e és van-e a `docs/beta/`-ban lezárt triage-anyag. Ha nincs béta-adat, a kör NEM indítható (`blocked` jelzés) — a scope-cut mérési döntés, nem vélemény.
>
> **MEGMÉRVE 2026-09-02 (§0.0.B R2): a Closed Beta NEM indult el, terepi triage-anyag NINCS.** A kör mégis fut, de a béta-hiányt MÉRT tényként szállítja, és a besorolás a fán mérhető bizonyítékra épül (a §5.2 „mérési riport" ága). A kitalált béta-adatot az [ADR 0489 D3](../adr/0489-ga-scope-classification-and-contract-freeze.md) útvonal-feloldása GÉPILEG zárja ki. Az indoklás teljes egészében a §0.0.B R2-ben.

## 0.0 A kör bemenete emberi mérésből jön

A béta-tapasztalat (top issue-k, funnel, támogatási terhelés) a user és a triage-jegyzőkönyvek terméke. Az implementer feladata: ezt az ANYAGOT gépileg ellenőrizhető scope-döntéssé alakítani (GA / preview / disabled / postponed), a döntést flag-profilba fordítani, és a core contractokat lefagyasztani.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/release/beta-findings.md",
  "docs/release/ga-scope.md",
  "docs/release/contract-freeze.md",
  "tool/release/verify_ga_scope.py",
  "test/tooling/ga_scope_test.dart",
  "docs/rounds/e12-r28-beta-stabilization-and-scope-cut.md",
]
gate_tests = [
  "test/tooling/ga_scope_test.dart",
  "test/tooling/beta_profile_test.dart",
]
native_gate = false
```

## 0.0.B Pre-flight revíziók (Claude, 2026-09-02) — ütközésnél EZ a szöveg érvényes

A brief 2026-08-27-én készült, `main @ 9ca4a0dc` állapotra. A pre-flight a fán
ÚJRAMÉRT minden hivatkozott állítást (`main @ 4bdedfbc`). Hét revízió.

### R1 — Az ADR száma **0489**, nem 0464

A `tools/round-slots.py reserve-adr --round E12-R28` foglaló **0489**-et adott (a
lemezen a legmagasabb ADR ma `0488`). A brief §0.0/§3/§5 „ADR 0464" említései
tehát a **`docs/adr/0489-ga-scope-classification-and-contract-freeze.md`** fájlt
jelentik. A queue `adr` oszlopa (`0464`) az előre kiosztott, elavult érték —
ugyanez a mintázat mérve az előző körökben: `E12-R22` queue `0461` → tényleges
`0486`; `E12-R25` queue `0463` → tényleges `0488`. A foglaló a mérce
(pipeline-prompt §1.0.1), az `ls docs/adr | tail` tilos. **Az ADR-t az
orchesztrátor MÁR megírta — az implementer nem írja át, és `docs/adr/**`-hoz nem
nyúl.**

### R2 — Az előfeltétel MÉRTEN nem teljesül: a Closed Beta NEM indult el

A brief §0.0 pre-flight-doboza a béta-adat hiányára `blocked` jelzést írt elő. A
pre-flight MÉRTE az állapotot:

- `docs/beta/closed-beta-launch.md:3` → „**Status: NOT launched** — this document
  is a gate, not a launch announcement";
- ugyanennek a fájlnak a §5 „Human launch field" mezője kipipálatlan és
  kitöltetlen („intentionally left unticked by this round");
- a HANDOFF `E12-R27` bejegyzése kimondja: „**A béta NEM indult el.**"

Tehát a fán **nulla** terepi béta-mérés van, és lesz is, amíg egy ember le nem
futtatja a bétát — ez `E12-R27` szerint szándékosan **emberi kapu**.

**Döntés: a kör NEM áll meg, hanem a béta-hiányt MÉRT tényként szállítja.**
Indoklás — és ez a döntés hatóköre:

1. A brief SAJÁT §5.2-je a bizonyítékra **vagylagos**: „a béta-adat **vagy a
   mérési riport** hivatkozása kötelező". A fán mérhető bizonyíték (flag-katalógus,
   cohort-profil, blocker-lista, felismerési release-guard, e2e-cellák) a második
   ág, tehát a besorolás nem lesz vélemény.
2. Az acceptance-kritériumok (A1–A6) egyike sem hivatkozik béta-adatra — mind a
   fán mérhető anyagból teljesíthető.
3. **Precedens:** az `E12-R27` PONTOSAN ezt tette ugyanezzel az emberi kapuval —
   leszállította a konfigurációt és a monitoring-eljárást, az indítást pedig
   kimondottan ÜRESEN hagyta. A kör review-t kapott és merge-elődött.

**A veszély, amit a §0.0 doboz el akart kerülni — a kitalált béta-adat — ettől
NEM enyhül, hanem gépi őrt kap:** [ADR 0489 D3](../adr/0489-ga-scope-classification-and-contract-freeze.md)
szerint minden bizonyíték-hivatkozásnak a fán **feloldható útvonalra** kell
mutatnia. Nem létező béta-riportra hivatkozni így nem stílushiba, hanem nem-nulla
kilépés.

**STOP-protokoll (szigorítva):** ha egy capability GA/`preview` besorolása
KIZÁRÓLAG béta-adatból következne, a besorolása **`postponed`**, feloldó
feltételként a béta lefutásával — **nem** becslés, és **nem** `stopped` jelzés. A
`stopped` marad a scope-ütközés jelzése (§0).

### R3 — A `beta-findings.md` tartalma átdefiniálva

A fájl **nem** terepi top-issue/funnel összefoglaló (nincs mihez). Az
[ADR 0489 D8](../adr/0489-ga-scope-classification-and-contract-freeze.md) köti:
rögzíti a béta MÉRT állapotát (feloldható hivatkozással a
`docs/beta/closed-beta-launch.md`-ra), felsorolja, mely bizonyítékforrásokra épül
helyette a besorolás, és kimondja, melyik besorolás melyik béta-mérés hatására
kerül újramérésre. **Kitalált top-issue lista, funnel-szám vagy tesztelői létszám
TILOS** — a D3 útvonal-feloldása ezt gépileg is fogja.

### R4 — A capability-halmaz MÉRT és zárt: a cohort-profil 16 kulcsa

Az A1 („minden capability") csak akkor mérhető, ha a halmaz meg van nevezve. Mérve
(`python3 -c "import yaml; …"` a `docs/beta/cohort-profiles.yaml`-on): mindkét
cohort **16** flag-kulcsot rendel hozzá, ugyanazt a 16-ot, és mind a 16 benne van
a MÉRT 40-es `lib/core/feature_flags/feature_flag_registry.dart` katalógusban.
[ADR 0489 D1](../adr/0489-ga-scope-classification-and-contract-freeze.md): a
besorolás alanyainak halmaza **ez a 16 kulcs**, pontosan egy besorolással,
hallgatólagos default NÉLKÜL. A besorolási készlet zárt:
`ga` | `preview` | `disabled` | `postponed` (D2).

### R5 — Az A5 bemenete MÉRVE: van nyitott P0

`docs/release/blockers.md` a mérés pillanatában: `R-SIGN-01` **P0** nyitva
(owner-kör `E12-R07`, `pending`), mellette öt **P1** (`R-VER-01`, `R-PRIV-01`,
`R-SEC-01`, `R-STAGE-01`, `R-STORE-01`). Tehát a `ga-scope.md`-nek
[D7](../adr/0489-ga-scope-classification-and-contract-freeze.md) szerint
**kimondottan NEM-KÉSZ** állapotot kell hordoznia a fejlécében — ez a dokumentum
helyes állapota, nem hiányossága. Egy „GA-kész" fejléc a mai fán az A5 celláját
PIROSRA váltja.

### R6 — Az A3 gépi mérése: a core út lépései a scope-dokumentumban vannak nevesítve

A `verify_ga_scope.py` Dart e2e-tesztet nem futtat. Az A3
([D5](../adr/0489-ga-scope-classification-and-contract-freeze.md)) ezért
dokumentum-szintű: a `ga-scope.md` nevesíti a core út lépéseit, minden lépéshez a
D3 szerint feloldható bizonyítékkal — az `E12-R11` (`done`, ADR 0452) e2e-cellái,
MÉRVE: `test/e2e/first_practice_offline_test.dart`,
`test/e2e/returning_user_restart_test.dart`,
`test/e2e/upgrade_migration_test.dart`, `test/e2e/resource_coexistence_test.dart`
— és megjelöli, mely capabilityre támaszkodik a lépés. Minden core-úthoz
szükségesnek jelölt capability besorolása **`ga`** kell legyen; bármi más
nem-nulla kilépés.

### R7 — Parszer-fegyelem és külső függőség

[ADR 0489 D9](../adr/0489-ga-scope-classification-and-contract-freeze.md): a
`ga-scope.md`/`contract-freeze.md` táblázatait **fail-closed** parszer olvassa
(nem illeszkedő sor → hiba a sor számával, néma átugrás TILOS — L566); a
cohort-profil **PyYAML**-lel olvasandó (precedens: a testvér
`tool/release/verify_beta_profile.py` ugyanezt a fájlt így olvassa; a fán mérve
`PyYAML 6.0.1`). Az eszköz stdlib + `yaml`, más külső csomag nincs; a gate-teszt
egyetlen külső binárisa a `python3` (ADR 0488 D6 / ADR 0447 D5). Minden cella a
saját javítása ELŐTTI eszközzel PIROS (L563).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** `stopped` jelzés **scope-ütközésre** (a §4 listáján kívüli fájl kellene). — ⚠ **A §0.0.B R2 felülírja e szakasz korábbi szövegét:** a béta-adat hiánya MÉRT tény, nem `stopped`-ok; az ilyen capability besorolása `postponed`, a béta lefutásával mint feloldó feltétellel. A besorolás továbbra sem lehet becslés — ezt az [ADR 0489 D3](../adr/0489-ga-scope-classification-and-contract-freeze.md) útvonal-feloldása kényszeríti ki.

## 1. Cél

A GA-scope legyen kisebb, de stabil: minden capability mért indoklással kap GA / preview / disabled / postponed besorolást, a core contractok pedig lefagynak.

## 2. Jelenlegi állapot — mért tények

- `docs/release/`: a korábbi körök után `program-baseline.md`, `blockers.md`, `environment-matrix.md`, `kill-switches.md`, `supply-chain.md`, `ai-quality-gates.md`, `rc-checklist.md`, `client-migration.md`; `ga-scope.md` **nincs**.
- A flag-katalógus (Kör 5) és a cohort-profil (Kör 27) MEGVAN — a scope-döntés ezekre képződik le.
- Az Epic 10 (Offline AI) sáv `hold`-on áll → a helyi AI besorolása alapból `postponed`, hacsak a béta-adat mást nem indokol.
- A Chapter 14 (felismerés-helyreállítás) sáv `prepared` — a felismerési pontosság GA-kritériumát a `docs/eval/recognition-release-guard.md` hordozza.

## 3. Scope

**Benne van:** `docs/release/beta-findings.md` (a triage-anyagból származtatott top-issue és funnel összefoglaló, MINDEN állításhoz forrás) · `docs/release/ga-scope.md` (capabilityenként: besorolás + indoklás + a bizonyíték hivatkozása) · `docs/release/contract-freeze.md` (mely publikus contractok fagynak be, és mi a változtatás feltétele) · `tool/release/verify_ga_scope.py` (a besorolás ↔ flag-profil konzisztencia; preview capability nem lehet a core flow kötelező eleme) · `test/tooling/ga_scope_test.dart`.

**NINCS benne (tilos):**

- Kód-változtatás bármely feature-ben (a scope-cut ITT dokumentum + profil).
- Új flag bevezetése.
- A `docs/eval/recognition-release-guard.md` küszöbeinek átírása.
- `docs/adr/**` — az ADR 0489-et a Claude MÁR megírta (§0.0.B R1).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/release/beta-findings.md` | ÚJ — a béta mért tapasztalata |
| `docs/release/ga-scope.md` | ÚJ — a besorolás |
| `docs/release/contract-freeze.md` | ÚJ — a befagyasztott contractok |
| `tool/release/verify_ga_scope.py` | ÚJ — konzisztencia-ellenőrző |
| `test/tooling/ga_scope_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `.github/**` · `docs/eval/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0489)

### 5.1 A preview capability NEM lehet a core flow kötelező eleme

A core tanulási út preview-funkció nélkül is végigjárható (ADR 0306 mintája). **NEM elfogadható gyengítés:** „preview, de a Today-képernyő nélküle üres" — az funkcionálisan GA.

### 5.2 A besorolás MÉRT indoklást hordoz

**NEM elfogadható gyengítés:** „stabilnak tűnik" — a béta-adat vagy a mérési riport hivatkozása kötelező.

### 5.3 A contract freeze feloldása nevesített feltételhez kötött

**NEM elfogadható gyengítés:** „szükség esetén módosítható" megfogalmazás.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden capability pontosan egy besorolást kap, mért indoklással | `ga_scope_test.dart` |
| A2 | A besorolás és a cohort-flag-profil konzisztens (disabled ⇒ a profilban is `false`) | `ga_scope_test.dart` |
| A3 | Preview capability nélkül a core flow végigjárható | `ga_scope_test.dart` + a Kör 11 e2e cellái |
| A4 | Minden befagyasztott contracthoz tartozik feloldási feltétel | `ga_scope_test.dart` |
| A5 | Nyitott P0/P1 blocker mellett a GA-scope explicit „nem kész" jelzést kap | `ga_scope_test.dart` a `blockers.md` olvasásával |
| A6 | A Kör 27 `beta_profile_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy capability besorolás nélkül marad, vagy kettőt kap | A1 |
| `disabled` besorolás mellett a flag a profilban `true` | A2 |
| A core flow egy preview capabilityre támaszkodik | A3 |
| A contract freeze feloldási feltétel nélkül íródik | A4 |
| Nyitott P0 mellett a scope „GA-kész" jelzést kap | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd az egyik `disabled` capability flagjét a cohort-profilban `true`-ra, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/ga_scope_test.dart test/tooling/beta_profile_test.dart
```

A konzisztencia-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_ga_scope.py --scope docs/release/ga-scope.md --profile docs/beta/cohort-profiles.yaml
```

## 8. Implementációs sorrend

1. `docs/release/beta-findings.md` a triage-anyagból.
2. `docs/release/ga-scope.md` — besorolás + indoklás.
3. `tool/release/verify_ga_scope.py`.
4. `test/tooling/ga_scope_test.dart`.
5. `docs/release/contract-freeze.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Vélemény-alapú scope.** Béta-adat nélkül a besorolás becslés (`blocked` eset).
- **Rejtett GA.** Egy preview-nek nevezett, de a core flow-hoz szükséges capability (A3).
- **Örök freeze-kivétel.** Feltétel nélküli feloldhatóság a freeze-t értelmetlenné teszi (A4).

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-09-02.

### Mit szállít ez a kör

- [`docs/release/beta-findings.md`](../release/beta-findings.md) — a Closed
  Beta MÉRT NOT-launched állapota (D8), a helyette használt bizonyítékforrások
  listája, és melyik besorolás melyik jövőbeli béta-mérésre vár.
- [`docs/release/ga-scope.md`](../release/ga-scope.md) — a
  `docs/beta/cohort-profiles.yaml` 16 flag-kulcsának PONTOSAN egy besorolása
  mindegyikhez (`ga`/`preview`/`disabled`/`postponed`), a core tanulási út
  4 lépése a rátámaszkodó capabilityvel (csak `practiceEngineV2Enabled`
  szükséges — a másik három e2e-cella capability-független, `none`), és egy
  explicit **NEM KÉSZ (NOT READY)** fejléc (a nyitott P0 `R-SIGN-01` + öt P1
  miatt, D7).
- [`docs/release/contract-freeze.md`](../release/contract-freeze.md) — 4
  befagyasztott contract, mindegyikhez nevesített, ellenőrizhető feloldó
  feltétellel (D6).
- [`tool/release/verify_ga_scope.py`](../../tool/release/verify_ga_scope.py)
  — fail-closed konzisztencia-ellenőrző (D1–D7), PyYAML a cohort-profilhoz
  (a testvér `verify_beta_profile.py` precedense szerint), stdlib+`yaml`
  egyéb függőség nélkül.
- [`test/tooling/ga_scope_test.dart`](../../test/tooling/ga_scope_test.dart)
  — A1 (D1, 3 mutáció-próba), A2 (D4, a §6.1 valódi-sértés próba +
  tool-független sanity), A3 (D5), A4 (D6, 2 mutáció-próba), A5 (D7, 2
  mutáció-próba), plusz két exit-2 használati-hiba cella.

### Besorolási döntések rövid indoklása (a teljes indoklás `ga-scope.md`-ban)

`practiceEngineV2Enabled` az EGYETLEN `ga` — ez gátolja a Practice Hub
route-ot (`lib/app/routing/app_router.dart:180-183`), amit az `E12-R11` core
e2e-cellája (`test/e2e/first_practice_offline_test.dart`) ténylegesen
meghajt. A `docs/testing/device-matrix.yaml` egy MÁSIK, durvább szemcséjű,
MÁR meglévő tengelye (`practice_engine: ga_scope: true`, `ai_tutor`/
`computer_vision: ga_scope: false`) megerősítő, nem döntő forrásként
kereszthivatkozva. A `postponed` sorok mindegyike vagy egy Epic completion
report nyitott release-blokkolójára (`epic-03`/`epic-06-completion-report.md`),
vagy a `blockers.md` nyitott P1-jeire (`R-PRIV-01`, `R-SEC-01`) hivatkozik —
egyik sem béta-adatra (D8).

### Valódi-sértés próba (§6.1, KÖTELEZŐ) — tényleges kimenet

Ideiglenesen (a commit ELŐTT visszaállítva): `docs/beta/cohort-profiles.yaml`
`internal` cohortjában `accountEnabled: false` → `accountEnabled: true`
(`accountEnabled` a `ga-scope.md`-ban `disabled`).

```
$ python3 tool/release/verify_ga_scope.py --scope docs/release/ga-scope.md --profile docs/beta/cohort-profiles.yaml
verify_ga_scope: 1 finding(s):
  - ga-scope.md:45: capability 'accountEnabled' is classified disabled but cohort 'internal' sets it to true (D4)
exit=1
```

**A2 PIROSRA váltott, ahogy a §6.1 mátrix előírja.** A Dart gate-en
(`flutter test test/tooling/ga_scope_test.dart`) ugyanezen a mutált fán 4
sanity-cella bukott (a `_scope`/`_profile` alapértelmezéssel futó A1–A4
"exit 0 on the real tree" jellegű cellák) — ez a tool-független megerősítés.
A `docs/beta/cohort-profiles.yaml`-t ezután byte-pontosan visszaállítottam
(`git diff docs/beta/cohort-profiles.yaml` üres a commit előtt), a mutáció
NEM került commitba.

### `verify_ga_scope.py` közvetlen futtatása — a tiszta fán

```
$ python3 tool/release/verify_ga_scope.py --scope docs/release/ga-scope.md --profile docs/beta/cohort-profiles.yaml
verify_ga_scope: ok — 16 capability classification(s), 4 core-path step(s), 4 frozen contract(s), 6 open P0/P1 blocker(s)
```

### Gate

`tools/round-gate.sh test/tooling/ga_scope_test.dart test/tooling/beta_profile_test.dart`
— **MINDEN GATE ZÖLD** (format, analyze, mindkét test-fájl külön-külön,
architecture, secrets, l10n). A `beta_profile_test.dart` VÁLTOZATLAN és zöld
maradt (A6).

### Amit ez a kör NEM tett meg (szándékosan)

Nem indította el a Closed Bétát, nem gyártott terepi triage-adatot, nem
módosított `docs/adr/**`-t, nem nyúlt `lib/**`/`backend/**`/`.github/**`/
`docs/eval/**`-hoz, és a `docs/beta/cohort-profiles.yaml` egyetlen commitolt
sora sem változott (a valódi-sértés próba visszaállítva).

## 11. Review — a Claude tölti ki
