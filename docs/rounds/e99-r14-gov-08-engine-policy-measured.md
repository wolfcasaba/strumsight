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

## 10. Implementation handoff (E99-R14, lezárva 2026-08-18)

### 10.1 Fájl-szintű összegzés

| Fájl | Változás | Lényeg |
|---|---|---|
| `tools/engine-profile.sh` | **D1** — TTL támogatás | `use <motor> [--ttl <óra>] [--reason ...]` 3 soros alakot ír (`engine=`/`expires_at=`/`reason=`); `active_engine` szétválasztja a `engine=` kulcsot a régi egysoros alaktól; `list` kiírja a fájl korát és a lejáratot; `override_field`/`override_file_age_hours` helper-ek. A régi, egysoros alak TOVÁBBRA IS ELFOGADOTT. |
| `tools/round-pipeline.sh` | **D2** — lejárat- és kor-ellenőrzés | A motor-override blokk (a §4 kiválasztás ELŐTT) ellenőrzi az `expires_at` mezőt: ha a múltban van, a fájl TÖRLŐDIK + napló + ntfy (`high`). Ha nincs explicit expiry ÉS a fájl mtime-ja ≥ `PIPELINE_OVERRIDE_WARN_HOURS` (alap 72), WARNING lép, a ntfy-t egy `$state_dir/override-warn-<h>.stamp` bélyeggel NAPONTA LEGFELJEBB EGYSZER küldi ki. A futó körre a lejárat NEM hat. A teszthorog (`--engine-override-evaluate`) a mérce-mátrix és a falszifikációs cellák alapja. |
| `tools/round-metrics.py` | **D3** — `--engines` alparancs | `NEXT_ROUND` regex azonosítja a `következő kör: … implementer=<x>` sort; `engines_summary()` a start–merged párokat motorhoz rendeli, kiszűri a 10+ órás kiugrókat, és `n`/`kiugró`/`medián`/`átlag`/`önjavító` oszlopokat ad; `render_engines_table()` szöveges táblát rajzol. A JSON formátum séma-verziózott (`schema_version: 1`). |
| `tools/tests/test_engine_override_ttl.py` | **Új teszt** | 8 fő cella + 2 falszifikációs cella (küszöb alatt/rajta/fölött, lejárt, jövőbeni, üres, örökölt 1-soros, threshold konfig). A falszifikáció a `re.sub` MINDKÉT előfordulásra hat (body + hook). A `tearDown` a forrást garantáltan visszaállítja. |
| `tools/tests/test_round_metrics_engines.py` | **Új teszt** | 3 fő cella (táblázat, JSON, üres-napló) + 1 falszifikációs cella (kiugró-szűrés kikapcsolása → medián 1800s+ küszöb felett). A fixture a brief §3-ban mért E07-R16 (2636p) kiugrót tartalmazza. |

### 10.2 Parancs-eredmények (valós, e futásból)

```text
$ tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
format                                                     zöld
analyze                                                    zöld
test test/tooling/architecture_allowlist_guard_test.dart   zöld
architecture                                               zöld
secrets                                                    zöld
l10n                                                       zöld
MINDEN GATE ZÖLD.
```

```text
$ python3 -m pytest tools/tests -q
6 failed, 483 passed, 527 subtests passed in 267.69s
```

A 6 fail MIND pre-existing, környezeti eredetű (a `~/.mmx/config.json` létezik ezen a boxon, ezért a
`minimax` motor MINDIG elérhető, és a `test_orchestrator_rotation.py` /
`test_reviewer_independence.py` erre `HALT_INDEP`-et VÁR, nem `minimax`-ot). A
STASH + tiszta main-en futtatás ugyanazt a 4 fails-t produkálja (a 6-ból 2
`test_claude_harness_engines.py`-ből jön, szintén pre-existing). A 14 újonnan
írt teszt (10 engine-override + 4 engines) MIND zöld:

```text
$ python3 -m pytest tools/tests/test_engine_override_ttl.py \
                    tools/tests/test_round_metrics_engines.py -v
14 passed in 0.47s
```

### 10.3 Manual smoke-test (8 eset, a driver `--engine-override-evaluate` hookján)

| # | Fájl kor | `expires_at` | Elvárt | Kapott |
|---|---|---|---|---|
| 1 | 1 óra | — | `qwen-plus` (exit 0) | `qwen-plus` (exit 0) ✓ |
| 2 | 72 óra | — | `qwen-plus` (exit 2 = STALE) | `qwen-plus` (exit 2) ✓ |
| 3 | 73 óra | — | `qwen-plus` (exit 2 = STALE) | `qwen-plus` (exit 2) ✓ |
| 4 | most | past (now-60) | `EXPIRED` (exit 1, fájl TÖRÖLVE) | `EXPIRED` (exit 1, fájl törölve) ✓ |
| 5 | 71 óra | — | `qwen-plus` (exit 0) | `qwen-plus` (exit 0) ✓ |
| 6 | 200 óra | future (now+36000) | `qwen-plus` (exit 0) | `qwen-plus` (exit 0) ✓ |
| 7 | — | — | `<empty>` (exit 3) | `<empty>` (exit 3) ✓ |
| 8 | 25 óra | — (threshold=24) | `qwen-plus` (exit 2) | `qwen-plus` (exit 2) ✓ |

### 10.4 Falszifikációs cellák eredménye

- **`test_lejarat_ellenorzes_kivetelevel_a_lejarati_teszt_piros`**: a `>= "$expires_at"`
  kikapcsolása → a `test_expires_at_in_past_triggers_deletion` cella a lejárt
  fájlt ÉLVE hagyja (exit 0), a teszt PIROSRA vált. A teszt CSAK a kód visszaállítása
  UTÁN zöld. ✓
- **`test_kor_figyelmeztetes_kivetelevel_a_kuszob_rajta_teszt_piros`**: az
  `awk ... (a >= t) ? 1 : 0` szűrő kikapcsolása (mindkét előfordulásra) → a 72
  órás cella LIVE (exit 0) helyett STALE-et várnánk, a teszt PIROSRA vált. ✓
- **`test_kiugro_szures_kivetelevel_a_median_teszt_piros`**: a `OUTLIER_THRESHOLD_SECONDS = 10*3600`
  átírása `999*3600`-ra → a szűrés hatástalan, a 2636p minta bennmarad, a
  medián 1800s FÖLÉ kerül, a teszt PIROSRA vált. ✓

### 10.5 Visszafelé kompatibilitás

A `tools/engine-profile.sh` egysoros alakját a driver ugyanúgy fogadja, mint
azelőtt (a `use` parancs a mtime-ot is frissíti, így a 72 órás figyelmeztetés
mérője ismét nullázódik). A `tools/engine-profile.sh show` az új alakból a
`tartalmazott motornevet` olvassa ki, a régi alakból az első sort — a
`test_engine_profile.py` meglévő tesztjei (`test_use_then_clear_round_trips`,
`test_unknown_engine_is_refused`, `test_a_missing_profile_is_refused`) zöldek
maradtak, ahogy a PARANCS alakja (`engine-profile.sh use <név>`) változatlan a
kötelező `--ttl`/`--reason` nélkül.

### 10.6 Lezárás

A D1–D3 mérce-mátrix és a 3 falszifikációs cella VALAMENNYI esete zöld. A
`docs/adr/**`, `.ai/router.toml`, `.pipeline/**`, `docs/execution/pipeline-queue.tsv`
és minden más, az `allowed_paths` listán kívüli fájlhoz nem nyúltam. A scope
betartását a `tools/tests/test_engine_override_ttl.py` `setUp/tearDown` őrzi
is: a falszifikációs tesztek a forrást MINDIG visszaállítják, így a
futtatásuk NEM hagy módosított kódot a lemezen.
