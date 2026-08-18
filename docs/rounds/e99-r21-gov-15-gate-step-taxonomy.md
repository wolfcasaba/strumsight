# E99-R21 (GOV-15) — Kapu-lépés taxonómia: eseménysor és flaky-levezetés

- **Státusz:** READY FOR IMPLEMENTATION (brief 2026-08-18, `main @ 784e90e6`)
- **Típus:** **governance-kör** — a lánc SAJÁT mérése
- **Kör-azonosító:** `E99-R21`. Emberi neve **GOV-15**.
- **Előfeltétel:** nincs
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0314`](../adr/0314-gate-step-taxonomy.md) — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tools/round-gate.sh",
  "tools/round-metrics.py",
  "tools/tests/test_gate_events.py",
  ".github/workflows/router-ci.yml",
  "docs/rounds/e99-r21-gov-15-gate-step-taxonomy.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a diff MAGÁHOZ A MÉRCÉHEZ nyúl
> (`tools/round-gate.sh`). Egy elrontott ág elnyelhetne egy piros lépést —
> ez a legsúlyosabb hibaosztályunk (ADR 0052). Ezért a rögzítés append-only,
> mellékhatás nélküli, és a §4 első falszifikációs cellája pontosan a kapu
> kilépési kódjának sértetlenségét méri.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 0.1 Visszakeresett előzmény (tudás-index, ADR 0312 §4.1)

`node tools/knowledge-rag.mjs --top 4 "flaky teszt zöld újrafuttatásra kapu lépés bukás"`:

- **`lessons/L142`** (E04-R24) — a HARD-seed randomizált property-gate mérve
  **boundary-flaky** lehet (17/20 a ≥18 elvárás ellen), a körtől FÜGGETLENÜL;
  a helyes válasz **újradispatch volt, nem halt**, és a diff-érintettséget
  mérni kellett. Vagyis a flaky-osztály nálunk nem elméleti, és a jó reakció
  már ismert — csak ma emberi ítélet, nem gépi levezetés.
- **`docs/development/07-testing.md` §Flaky test** — a meglévő házirend: „ne
  kapcsold ki; rögzíts seedet/logot". Ez a kör ezt a házirendet **méréssel**
  támasztja alá; nem módosítja.

Ellenpróba: kapu-lépésenkénti bukás-statisztikára **nincs releváns előzmény** a
korpuszban — ez ma vak folt.

## 1. Cél

A `round-metrics.py` mérve 31,3% holtidőt és 142 körből 31 önjavítást igénylőt
mutat, a halt-rekordok pedig halt-kód szinten vannak vezetve (H3: 136, H6: 129,
H8: 36, H2: 16). Nincs viszont gépi nyoma annak, hogy **melyik kapu-lépés**
bukott és mennyi ideig futott — így nem tudjuk, hova érdemes optimalizálni, és
nem tudjuk szétválasztani a valódi regressziót a zajtól.

## 2. Jelenlegi állapot — mérve a kódban

- `tools/round-gate.sh` a lépéseket KÜLÖN processzben futtatja (OOM-lecke, L05),
  és a csonkítatlan kimenet a bizonyíték — de a futás után gépi nyom nem marad.
- `.pipeline/halted-*.txt` mezői: `round=`, `halt=`, `summary=`, `detail=`,
  `session_log=`, `halted_at=`.
- `tools/round-metrics.py` a lánc-naplóból kör-időt, holtidőt, blokkolt és
  önjavító számot aggregál; kapu-lépés bontása nincs.

## 3. Feladatok

### D1 — Eseménysor a kapuból

A `tools/round-gate.sh` minden lépés után egy sort fűz a
`.pipeline/gate-events.tsv` fájlhoz (fejléc egyszer, ha a fájl nem létezik):

```
ts  round  step  test_path  exit_code  duration_s  head_sha  tree_dirty
```

- `round`: a `STRUMSIGHT_ROUND_ID` értéke, hiányában `-`.
- `step`: `format` | `analyze` | `test` | `architecture` | `secrets` | `l10n`
  (+ a backend-sáv lépései, ha futnak).
- `test_path`: `test` lépésnél a konkrét útvonal, egyébként `-`.
- `tree_dirty`: a munkafa piszkos-e (`git status --porcelain` üres-e), `0`/`1`.
- A rögzítés **mellékhatás nélküli**: hibája `|| true`, és a kapu kilépési
  kódját, kimenetét, lépés-sorrendjét NEM változtatja.

### D2 — `round-metrics.py --gates`

Új alparancs, ami a `.pipeline/gate-events.tsv`-ből aggregál:

- lépésenként: futások száma, bukások száma, medián időtartam;
- a **levezetett** flaky-párok listája: azonos (`round`, `step`, `test_path`)
  azonos `head_sha` + azonos `tree_dirty` mellett előbb nem-nulla, majd nulla
  `exit_code` — a kapu NEM ítél, csak tényt ír (ADR 0314 §2).
- Hiányzó vagy üres eseménysor → üres jelentés és `0` kilépési kód, nem hiba.

### D3 — CI-szűrő

`.github/workflows/router-ci.yml` `paths:` blokkja fedje le a
`tools/tests/test_gate_events.py` fájlt. A fedés **nő, sosem szűkül**
(mérve: PR #309 piros CI-kapuja).

## 4. Mérce-mátrix (`tools/tests/test_gate_events.py`)

Hermetikus futtatás: a kapu csonkolt, gyors változatával (injektált lépés-parancsok),
`PIPELINE_STATE_DIR` ideiglenes könyvtárra állítva — az élő `.pipeline/`-t nem érinti.

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| zöld futás | minden lépés 0 | minden lépéshez pontosan egy sor, `exit_code=0` |
| piros lépés | az `analyze` nem-nulla | a sor `exit_code` mezője a valódi kód, ÉS a kapu kilépési kódja változatlanul nem-nulla |
| rögzítés bukik | az eseménysor írása lehetetlen (írásvédett könyvtár) | a kapu kilépési kódja és kimenete VÁLTOZATLAN |
| több teszt-útvonal | két `test` lépés | két külön sor, külön `test_path` értékkel |
| flaky-pár | azonos `head_sha`+`tree_dirty`, előbb 1, majd 0 | `--gates` flaky-párként listázza |
| NEM flaky (fa változott) | az első futás után a `head_sha` más | `--gates` NEM listázza flaky-ként |
| üres eseménysor | a fájl hiányzik | `--gates` üres jelentés, kilépési kód 0 |

**Küszöb-hármas** — a flaky-levezetés a *változatlanság* feltételére épül;
a határ két oldala és maga a határ:

| cella | eset | elvárt |
|---|---|---|
| a határ **alatt** | 0 korábbi piros futás (első futás zöld) | nem flaky |
| a határon (**rajta**) | pontosan 1 korábbi piros, azonos fán | flaky-pár |
| a határ **fölött** | 2 korábbi piros, azonos fán, majd zöld | flaky, egy párként jelentve (nem kettőként) |

**Falszifikációs cellák (kötelezők):**

1. A D1 rögzítés `|| true` védelmének kiszedése → a „rögzítés bukik" cella
   **PIROS** (a kapu kilépési kódja megváltozik) → visszaállítás után zöld.
2. A D2 `head_sha`-egyezés feltételének kiszedése → a „NEM flaky (fa változott)"
   cella **PIROS** (hamis flaky-jelölés) → visszaállítás után zöld.

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nem karanténoz és nem szűr tesztet.** A flaky-nak levezetett teszt továbbra
  is pirosra viszi a kaput; ez a kör MÉR, nem dönt.
- **Nem gyengíti a mércét**: lépés-sorrend, külön processz, csonkítatlan
  kimenet, kilépési kódok változatlanok (ADR 0052, L05).
- Nem vezet be teszt-kiválasztást (test impact analysis).
- Nem nyúl a `tools/round-pipeline.sh`-hoz, a slot-tervezőhöz és a landolóhoz —
  így nem ütközik az E99-R14…R20 körökkel.
- Fájlok: `docs/adr/**`, `.ai/router.toml`, `docs/execution/**`, Dart források — tilos.

## 6. Definition of Done

1. D1–D3 kész; a kapu viselkedése minden zöld és piros ágon bitre azonos.
2. `tools/tests/test_gate_events.py` lefedi a §4 mind a hét celláját és a
   küszöb-hármast, hermetikus `PIPELINE_STATE_DIR`-rel.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).
