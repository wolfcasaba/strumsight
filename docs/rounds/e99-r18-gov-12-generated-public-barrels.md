# E99-R18 (GOV-12) — Generált `public.dart` barrelek: a második fizikai ütközés-felület feloldása

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 52324cb3`)
- **Típus:** **governance-kör**
- **Kör-azonosító:** `E99-R18`. Emberi neve **GOV-12**.
- **Előfeltétel:** `E99-R17` merge-elve (ugyanaz a `tools/round-slots.py` felület bővül)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§5**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/gen_public_barrel.dart",
  "tool/check_architecture.dart",
  "lib/features/practice_generator/public.dart",
  "lib/features/practice_generator/public/",
  "tools/round-slots.py",
  "tools/tests/test_round_slots_generated_barrels.py",
  "test/tooling/gen_public_barrel_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e99-r18-gov-12-generated-public-barrels.md",
]
gate_tests = [
  "test/tooling/gen_public_barrel_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a `public.dart` a feature-ek közötti
> KONTRAKTUS (SDD Ch8, ARCH-szabályok); egy elveszett export néma
> fordítási hibaként vagy — rosszabb — egy másik szimbólum árnyékolásaként
> jelentkezne. A mérce ezért az export-halmaz azonossága.

## 0.0 Pre-flight revízió (önjavítás, ADR 0112, 2026-08-19, `main @ 1a051d85`)

**Végrehajthatósági eredmény: a H3 halt oka NEM tartalmi hiányosság, hanem
igazoltan ártalmatlan implementer-debris — a feloldás REVERT, nem
`allowed_paths`-bővítés.**

### Mért tények

A MiniMax implementer (`/home/ubuntu/ss-minimax-e99-r18`, ág
`minimax/e99-r18-gov-12-generated-public-barrels`, HEAD `e9c4a26b`) a
fenti `allowed_paths`-on BELÜLI, öt commitban felépített D1/D2/D4 munkája
(a jelenlegi, commitolatlan diffben mérve hat fájl: a négy
`practice_generator/public/*.dart` fragmentum, `test/tooling/
gen_public_barrel_test.dart`, `tool/gen_public_barrel.dart`) MELLETT három
NYOMKÖVETETLEN (untracked) fájlt hagyott a munkapéldányban:

```
test_project/lib/features/demo/public.dart
test_project/lib/features/demo/public/application.dart
test_project/lib/features/demo/public/domain.dart
```

Ez a saját scope-audit-ja (`tools/scope-audit.py`, `.codex-round-status`)
szerint is sértés (`scope_audit=VIOLATION`,
`scope_audit_base=6a6344a07d2fcfcebeb4916e43179b110ea9b7d9`, a base-től az
öt commitot is számoló `scope_audit_changed=14`, ebből 3 a violation); az
implementer MAGA is `stopped`-ot jelzett (`implementer_status=stopped`) —
tehát a modell is észlelte, hogy valami kilóg. A Terra orchesztrátor-session
(`pipeline-E99-R18-fallback`) ezt követően `H3`-mal állt le,
`.pipeline/HALTED`-ben rögzítve: „A new brief-revision/human decision is
required before any continuation."

**A `test_project/` NEM legitim munka — ez mérve van, nem feltételezve:**

- `grep -rn "test_project" .` a teljes munkapéldányban (a stopped
  implementer worktree-jén) **nulla** találatot ad bármely tracked vagy
  untracked Dart/Python/shell forrásban — semmi nem hivatkozik rá, semmi nem
  generálja.
- A `test/tooling/gen_public_barrel_test.dart` SAJÁT, automatizált
  fixture-je már helyesen `Directory.systemTemp.createTempSync
  ('strumsight_public_barrel_')`-t használ (a fájl `setUp`/`tearDown`-ja) —
  a `test_project/` tehát funkcionálisan redundáns ezzel a fixture-rel.
- A `test_project/lib/features/demo/public.dart` +
  `public/{application,domain}.dart` tartalma **bájtra megegyezik** a fenti
  automatizált teszt `seedFreshBarrel()` segédfüggvénye által memóriában
  felépített fixture-tartalommal (`export '../application/port/a.dart';`
  stb.) — ez egy kézi, a repó fájlrendszerén kívülre nem szánt smoke-teszt
  lenyomata, nem egy elfelejtett deliverable.
- A brief D1–D4 feladatai és az 5. „Tilos zóna" (kizárólag a
  `practice_generator` barrel migrálható) egyike sem nevez meg semmilyen
  `demo`/`test_project` scaffoldot.

### Kötelező feloldás

`docs/execution/pipeline-orchestrator-prompt.md` VIOLATION-sorát idézve: „a
listán kívüli fájlokat **vissza kell állítani**, vagy H3 halt" — és ugyanott
a §2 „Önállóan dönthetsz és folytathatod a kört" felsorolása kifejezetten
tartalmazza „az engedélyezett-fájllista **szűkítését**" mint a kör saját
hatáskörét. A `test_project/` TÖRLÉSE (nem allow-listázása) éppen ez az
eset: a diffet az EREDETI `allowed_paths`-hoz igazítja, nem a tiltott zóna
feloldását kéri — tehát nem H3-t igénylő döntés, hanem a §2 alatt már
felhatalmazott revert. A fenti `ai-router` blokk **változatlan**: a
`test_project/`-hez (vagy bármely `demo`/scratch mintához) **nem** kerül
`allowed_paths`-bejegyzés.

A folytatás módja: a megállt implementer-worktree
(`/home/ubuntu/ss-minimax-e99-r18`) törölje a három fájlt, majd a hat,
ÉRDEMI, scope-on belüli fájl (D1/D2/D4 munka) a szokásos módon megy tovább
review/gate felé. Ezt a self-heal SZÁNDÉKOSAN nem hajtja végre saját kézzel
— a self-heal jogosultsága (ADR 0112 §2) a briefre és az
engedélyezett-fájllistára szól, nem a kör saját, még nem review-zott
implementer-ágára; a következő E99-R18 dispatch (friss
orchesztrátor-session) dolga eldönteni, hogy a meglévő worktree-t
újrahasznosítja-e (a törlés után) vagy frissen indul.

**Miért nem illik ide az E07-R29/H3 minta** (`tools/tests/
test_e07_r29_accessibility_privacy_scope.py`): ott a listán kívüli fájlok
IGAZOLTAN szükséges, meglévő storage-tulajdonosok voltak — a helyes
feloldás `allowed_paths`-bővítés volt. Itt a mérés az ELLENKEZŐJÉT mutatja
(nulla hivatkozás, redundáns az automatizált fixture-rel, kívül esik minden
D1–D4 cellán) — a helyes feloldás ezért a bővítés tükörképe: **revert, és
az allowlist érintetlenül hagyása**. A self-heal jelentése ezt a döntést a
regressziós teszttel (`tools/tests/test_e99_r18_scope_debris_revert.py`)
gépileg is rögzíti, mindkét irányban (a debris VIOLATION marad, amíg jelen
van; az allowlist nem bővül).

Lecke: `docs/LESSONS.md` [[L333]]. ADR: [`0112`](../adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-19).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió; az `allowed_paths` tágítása TILOS.

## 1. Cél — mit mértünk

A 75 nyitott briefből a `lib/features/gamification/public.dart` **25**-ben, a
`lib/core/design_system/public.dart` **18**-ban, a
`lib/features/practice_generator/public.dart` **8**-ban szerepel — kizárólag
azért, mert minden kör hozzáfűz egy `export` sort. Ez a második olyan
ütközés-felület (az ARB után), ami mechanikus, nem tartalmi.

A `practice_generator/public.dart` ma **67 sor**, tisztán export-lista → ez a
pilot. (A `gamification` és a `design_system` barrel még nem létezik a fán; a
mechanizmus az ő születésükkor már készen áll.)

## 2. Jelenlegi állapot — mérve

- `lib/features/practice_generator/public.dart`: `library;` + 60+ `export`
  sor, kézzel karbantartva.
- `tool/check_architecture.dart` gate-lépés őrzi a feature-határokat
  (cross-feature import csak `public.dart`-on át).
- `tools/round-slots.py`: az E99-R17-ben bevezetett `GENERATED_PATHS` halmaz
  már létezik (l10n-aggregátumokra).

## 3. Feladatok

### D1 — `tool/gen_public_barrel.dart`

- Bemenet: `lib/features/<feature>/public/*.dart` fragmentumok, mindegyik egy
  modul export-sorait tartalmazza (fájlonként egy témakör).
- Kimenet: `lib/features/<feature>/public.dart` — a fragmentumok
  **fájlnév szerint rendezett**, determinisztikus konkatenációja, változatlan
  fejléc-dokumentációval (`/// Public domain contract…` + `library;`).
- `--check` mód: a lemezen lévő barrel egyezik-e a generálttal (kilépési kód 1,
  ha nem).
- **Duplikált export** (ugyanaz az útvonal két fragmentumban) → hiba.

### D2 — A gate méri a frissességet (`tool/check_architecture.dart`)

A meglévő `architecture` gate-lépés kiegészül a `--check` hívással minden
generált barrelre. Új gate-LÉPÉS nem születik, tehát a `round-gate.sh` és a CI
composite lépéslistája változatlan (ADR 0171 paritás-őre sértetlen).

### D3 — Pilot: `practice_generator`

- A mai 60+ export témakörök szerinti fragmentumokra bomlik
  (`public/application.dart`, `public/data.dart`, `public/domain.dart`,
  `public/presentation.dart` — a MAI export-útvonalak könyvtár-előtagja szerint).
- **Acceptance:** a generált barrel **export-halmaza bitre azonos** a
  migráció előttivel (sorrend változhat, halmaz nem).

### D4 — `tools/round-slots.py`: a generált barrel nem ütközés

- A `GENERATED_PATHS` halmaz mintával bővül: `lib/features/*/public.dart`
  (glob, nem fix lista) — ezek újragenerálhatók, tehát nem ütközés.
- A fragmentumok (`lib/features/*/public/*.dart`) TELJES ÉRTÉKŰ ütközési
  felületek maradnak.

## 4. Mérce-mátrix

| eset | bemenet | elvárt |
|---|---|---|
| export-halmaz **azonos** | migráció előtti vs. generált barrel | ZÖLD |
| export **hiányzik** | fixtúra: egy fragmentum kimarad | `--check` **PIROS** |
| export **duplikált** | ugyanaz az útvonal két fragmentumban | a generátor hibával áll meg (kilépési kód ≠ 0) |
| barrel **elavult** | kézi szerkesztés a generált fájlban | `--check` **PIROS** |
| `round-slots.py` | két brief, mindkettő `lib/features/x/public.dart` | NINCS ütközés |
| `round-slots.py` | két brief, mindkettő `lib/features/x/public/domain.dart` | ÜTKÖZÉS |

**Falszifikációs cella (kötelező):** a D2 `--check` hívás kiszedése az
`architecture` lépésből → a „barrel elavult" eset **PIROS** helyett zöld lenne,
ezért a `test/tooling/gen_public_barrel_test.dart` erre írt esete **PIROS** →
visszaállítás után zöld. Második falszifikáció: a D4 glob leszűkítése egyetlen
feature-re → a `round-slots.py` „NINCS ütközés" esete másik feature-rel
**PIROS**.

## 5. Tilos zóna

- `docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
  `.pipeline/**`, `tools/round-pipeline.sh`.
- **Csak a `practice_generator` barrel migrálható** — más feature barreljéhez
  nyúlni tilos (a mechanizmus bizonyítása a cél).
- A feature-határ szabály (cross-feature import csak `public.dart`-on át)
  NEM lazul: a fragmentumok a feature-en BELÜL élnek, kívülről nem importálhatók.
  Ezt a `test/core/architecture_dependency_test.dart` méri.

## 6. Definition of Done

1. D1–D4 kész; a `practice_generator` barrel generált, export-halmaza változatlan.
2. A §4 mind a hat cellája tesztelt.
3. `tools/round-gate.sh test/tooling/gen_public_barrel_test.dart test/core/architecture_dependency_test.dart` zöld
   (az `architecture` lépés a frissességet is méri).
4. `python3 -m pytest tools/tests -q` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/gen_public_barrel_test.dart test/core/architecture_dependency_test.dart
python3 -m pytest tools/tests -q
```

A teljes suite (minden `public.dart`-fogyasztó teszttel) + property gate a
CI-ban fut (ADR 0053).
