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
