# E99-R14 (GOV-08) — Motorválasztás mérésre kötve: lejáró override és motor-statisztika

- **Státusz:** PREFLIGHT COMMITTED (2026-08-18, `main @ 604253eb`)
- **Típus:** **governance-kör** — a lánc SAJÁT infrastruktúrája, nem terméki viselkedés
- **Kör-azonosító:** `E99-R14` (az `E99` a governance-körök fenntartott pszeudo-epicje). Emberi neve **GOV-08**.
- **Előfeltétel:** nincs (a sorban korábbi E99-körök mind `done`)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§1** — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tools/engine-profile.sh",
  "tools/round-pipeline.sh",
  "tools/round-metrics.py",
  "tools/tests/test_engine_override_ttl.py",
  "tools/tests/test_round_metrics_engines.py",
  "docs/rounds/e99-r14-gov-08-engine-policy-measured.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> A `gate_tests` csak `test/` alatti Dart útvonalat fogad, a kör diffjében
> viszont **nulla Dart sor** van. A választott cella **fa-egészség őr**; a kör
> TÉNYLEGES mércéje a `python3 -m pytest tools/tests -q` és a Router CI
> (`.github/workflows/router-ci.yml`, `tools/**` útvonalra indul) — lásd §7.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** ha a munka listán kívüli
fájlt kívánna, a kimenet `stopped` + a brief revíziójának kérése — az
`allowed_paths` lista tágítása TILOS.

### §0.0 Pre-flight revízió — 2026-08-18

- A körhöz kiosztott `0307` ADR nem írandó újra: a
  `docs/adr/0307-pipeline-throughput-program-v2.md` már a merge-elt
  `main @ 604253eb` része (`docs(pipeline): ADR 0307 …`, PR #308). A
  foglaló a már elfoglalt számra `0308`-at adott. A `docs/adr/**` tilos zóna
  változatlan; ez a kör kizárólag az ADR §1-ben leírt D1–D3 megvalósítása.
- A jelenlegi út ténylegesen `tools/engine-profile.sh:active_engine` →
  `tools/round-pipeline.sh` motor-override blokk (`engine-override` első sora)
  → a kiválasztott `engine`; jelenleg sem lejárat-, sem mtime-ellenőrzés nincs.
  Ez a D2 mérési alapja, nem a rétegrajz.
- A brief-lint `strict` jelentése: nincs lelet. A 72 órás küszöb három cellája
  a §4-ben marad kötelező, a falszifikációs cellákkal együtt.

## 1. Cél — mit mértünk

A `.pipeline/engine-override` fájl **2026-08-08-tól 2026-08-18-ig**, tíz napon
át `terra`-ra állt (egy 08-06-i kvótaválság ideiglenes kapcsolója), miközben az
M3-keret 2026-08-18-án 92% / heti 98% volt. Az override MINDEN kört felülírt,
tehát a sor `engine` oszlopa tíz napig nem érvényesült.

Mért ár (azonos epicen belül, E07, összemérhető körök): `terra` medián **63
perc**, `minimax` **49 perc**, `sonnet-impl` **41 perc** — vagyis a beragadt
kapcsoló körönként 15–20 percet vitt el, önjavítási arányban mérhető nyereség
nélkül (`terra` 7/27 vs `sonnet-impl` 6/19).

**A hiba nem a motorválasztás volt, hanem hogy semmi nem mérte az override
korát.** Ez a kör ezt a vakfoltot zárja be.

## 2. Jelenlegi állapot — mérve a kódban

- `tools/engine-profile.sh use <név>` egyetlen sort ír a
  `.pipeline/engine-override` fájlba; lejárat, időbélyeg és indoklás nincs.
- `tools/round-pipeline.sh` (a „Motor-override (ADR 0140)" blokk) beolvassa,
  validálja, és felülírja a sor `engine` oszlopát. A fájl KORÁT nem nézi.
- `tools/round-metrics.py` kör-időt és holtidőt számol, de **motoronkénti
  bontást nem ad** — a §1 táblázata kézi elemzésből készült.

## 3. Feladatok

### D1 — Lejáró override (`tools/engine-profile.sh`)

- `use <motor> [--ttl <óra>] [--reason "<szöveg>"]`: az override fájl mostantól
  háromsoros, gépileg elemezhető alak: `engine=<név>`, `expires_at=<epoch|->`,
  `reason=<szöveg|->`. **Visszafelé kompatibilis:** a régi, egysoros alak
  (csak motornév) továbbra is érvényes, lejárat nélküli override-ként.
- `list` a mai kimenet mellé kiírja az override korát és lejáratát.
- `clear` változatlan.

### D2 — A driver érvényesíti a lejáratot (`tools/round-pipeline.sh`)

- Kör-KIVÁLASZTÁSKOR (nem futó körre): ha `expires_at` a múltban van, a driver
  **törli** az override fájlt, naplózza (`MOTOR-OVERRIDE LEJÁRT: <motor> —
  a queue engine oszlopa lép vissza`) és `notify`-ol.
- Ha nincs `expires_at`, és az override fájl mtime-ja régebbi, mint
  `PIPELINE_OVERRIDE_WARN_HOURS` (alap **72**), a driver figyelmeztet minden
  firingen, és **naponta legfeljebb egyszer** küld ntfy-t (állapotbélyeg a
  `$state_dir`-ben). Az override ilyenkor ÉL — a figyelmeztetés nem dönt
  helyette, csak láthatóvá tesz.
- Futó körre a lejárat NEM hat (a kör a saját motorjával fejezi be).

### D3 — Motor-statisztika (`tools/round-metrics.py --engines`)

Új alparancs a meglévő napló-elemzés fölé, `--epic <kód>` szűréssel:

| oszlop | jelentés |
|---|---|
| `implementer` | a `következő kör: … implementer=<x>` sorból |
| `n` | mért, merge-elt körök száma |
| `medián` / `átlag` | kör-idő percben |
| `önjavító` | ahány körhöz `ÖNJAVÍTÓ KÖR indul` esemény tartozik |

A számítás **kizárólag** a `.pipeline/chain.log` eseményeiből dolgozik (nincs
hálózat, nincs `gh` hívás), így tesztelhető rögzített napló-fixtúrából.
A 10 óránál hosszabb kör-idő kiugró értékként kimarad (mérve: E07-R16 = 2636
perc, egy 42 órás halt-epizód, ami nem motor-tulajdonság).

## 4. Mérce-mátrix

`PIPELINE_OVERRIDE_WARN_HOURS = 72` küszöb hármas cellája (`test_engine_override_ttl.py`):

| eset | override kora | elvárt viselkedés |
|---|---|---|
| küszöb **alatt** | 71 óra | nincs figyelmeztetés, nincs ntfy, az override él |
| küszöb **rajta** | pontosan 72 óra | figyelmeztetés a naplóban, ntfy legfeljebb naponta egyszer, az override él |
| küszöb **fölött** | 73 óra + `expires_at` a múltban | az override fájl TÖRLŐDIK, a queue `engine` értéke lép életbe |

**Falszifikációs cella (kötelező):** a D2 lejárat-ellenőrzésének kiszedése
(a `expires_at` összehasonlítás törlése) → a `test_engine_override_ttl.py`
lejárati esete **PIROS** → visszaállítás után zöld. Ha a teszt a kiszedés után
is zöld, a teszt hibás, nem a kód.

Második falszifikáció: a `--engines` kimenetből a kiugró-szűrés kivétele →
a fixtúrás teszt (ami tartalmaz egy 2636 perces kört) **PIROS** lesz a mediánon.

## 5. Tilos zóna

`docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
`.pipeline/**`, minden Dart forrás. A `tools/round-pipeline.sh`-ban KIZÁRÓLAG a
motor-override blokk és a hozzá tartozó napló/ntfy hívás módosulhat — a
kör-kiválasztás, a slot-logika és a self-heal ág változatlan.

## 6. Definition of Done

1. D1–D3 kész, a régi egysoros override-fájl továbbra is elfogadott.
2. Új tesztek: `tools/tests/test_engine_override_ttl.py` (küszöb-hármas +
   visszafelé kompatibilitás), `tools/tests/test_round_metrics_engines.py`
   (fixtúrás napló → determinisztikus táblázat).
3. `python3 -m pytest tools/tests -q` zöld (a meglévő 467 teszt is).
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. A kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate a `format` → `analyze` → `test` → `architecture` → `secrets` → `l10n`
lépéseket külön processzként futtatja; a kimenete csonkítatlanul a kör
bizonyítéka. A teljes suite + property gate a CI-ban fut (ADR 0053).
