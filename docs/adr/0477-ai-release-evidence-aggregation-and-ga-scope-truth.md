# ADR 0477 — AI-release bizonyíték-összesítés: egyetlen GA-scope igazság, örökölt küszöb, fail-closed hiány

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R16` (Chapter 12, Kör 16)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0474`](0474-benchmark-record-and-performance-budget-comparison.md)
  (benchmark-rekord + kétfokozatú, irány-tudatos regresszió-összevetés — ennek a
  küszöb-logikáját ez a kör NEM másolja, hanem IMPORTÁLJA),
  [`0473`](0473-release-fixture-corpus-manifest.md) (fail-closed manifest-minta,
  „ismeretlen ≠ zöld"),
  [`0177`](0177-ai-tutor-safety-injection-usage-evaluation-gate.md) (a Tutor
  evaluation MÁR merge-gate — ez a kör nem cseréli le, csak beolvassa),
  [`0271`](0271-recognition-recovery-program.md) (a felismerési aktivációs
  szerződés — a `docs/eval/recognition-release-guard.md` forrása),
  [`0447`](0447-release-manifest-provenance-and-sbom.md) (determinisztikus,
  gép-független release-manifest)

## Kontextus — a pre-flight MÉRT tényei (2026-08-29, `main @ e2a813e7`)

A kör előre megírt briefje (2026-08-27) négy állítást hordozott, amelyeket a
pre-flight megmért. Kettő igaznak bizonyult, kettő NEM:

1. **Igaz:** `tool/release/build_ai_report.py`, `tool/release/ai_report_schema.json`
   és `docs/release/ai-quality-gates.md` **nem létezik**; a `tool/release/` fa ma
   `generate_sbom.py`, `verify_artifacts.py`, `verify_signing_policy.py`.
2. **Igaz:** `docs/eval/` **két** riportot tartalmaz
   (`real-audio-dsp-baseline.md` 37 274 bájt, `recognition-release-guard.md`
   3 716 bájt), és a `.github/workflows/tutor-eval.yml` (41 sor) + `dsp-probe.yml`
   (48 sor) külön futnak, közös kimenet nélkül.
3. **HAMIS a brief §1 implikációja, hogy a tutor-bizonyíték GA-kritikus.**
   A GA-scope MA géppel olvasható, és a `docs/testing/device-matrix.yaml`
   `capabilities:` blokkja hordozza (E12-R13, PR #503): 14 capability, ebből
   **11 `ga_scope: true`** (`onboarding`, `live_and_tuner`, `practice_engine`,
   `song_trainer_local`, `audio_analysis_core`, `progress_goals_streak`,
   `storage_migration`, `offline_operation`, `localization_en_hu`,
   `accessibility_minimum`, `session_lifecycle_stability`) és **3
   `ga_scope: false`** (`computer_vision`, `offline_ai`, `ai_tutor`). A tutor
   tehát MA nem GA-scope — a riportban `not_in_scope`, nem blokkoló bemenet.
4. **HAMIS a brief 0456-os ADR-száma.** A `tools/round-slots.py reserve-adr`
   foglaló (ADR 0139-ütközés óta a kötelező út) `0477`-et adta; a `0456` sem a
   lemezen, sem foglalva nincs, tehát a briefben álló szám elavult batch-érték.

Egy ötödik, a briefben nem szereplő mérés dönti el a séma alakját:
`assets/ml/model_manifest.json` **kétféle** modell-azonosítót hordoz — a
`models[]` elemeket `filename` azonosítja és `training_run.identifier`
verziózza (`git:<40 hex>`), a `vision_models[]` elemeket `model_id` azonosítja
és egy `version` mező (`"1.0.0"`) verziózza. Egyetlen „modell-verzió" mező
feltételezése ezért mérés nélküli találgatás lett volna.

## Döntés

### D1 — A GA-scope EGYETLEN igazsága a device-mátrix, nem egy új lista

Az összesítő a `ga_scope` értéket kizárólag a `docs/testing/device-matrix.yaml`
`capabilities[].ga_scope` mezőjéből olvassa. A `docs/release/ai-quality-gates.md`
**bizonyíték-mátrix**: capability → milyen AI-bizonyíték kell hozzá; a GA-scope
kérdésre nem válaszol.

**NEM elfogadható gyengítés:** a GA-scope capability-lista újbóli felsorolása
(akár a Python forrásában, akár a Markdown mátrixban). Két lista garantáltan
szétcsúszik — pontosan az a hibaosztály, amit az ADR 0474 D6 a küszöbre már
kizárt. Ha egy `ai-quality-gates.md` sor olyan capability-t nevez meg, ami a
device-mátrixban nem szerepel, az nem-nulla kilépés, nem néma átugrás.

### D2 — A hiányzó KRITIKUS bizonyíték BLOKKOL, az ismeretlen sosem zöld

Ha egy `ga_scope: true` capabilityhez a bizonyíték-mátrix bizonyítékot ír elő,
és az a bizonyíték hiányzik, hibás formátumú vagy nem olvasható, az összesítő
nem-nulla kóddal lép ki, és a capability a kimenetben `missing` státusszal
látszik.

**NEM elfogadható gyengítés:** „nincs adat, tehát nincs regresszió" — ez az
ADR 0474 D5 és az ADR 0473 fail-closed mintájának közvetlen megsértése.

### D3 — A nem-GA-scope capability hiánya NEM blokkol, de LÁTSZIK

A `ga_scope: false` capability (ma: `computer_vision`, `offline_ai`, `ai_tutor`)
hiányzó bizonyítéka a kimenetben `not_in_scope` státusszal jelenik meg, és nem
befolyásolja a kilépési kódot.

**NEM elfogadható gyengítés:** minden capability kötelezővé tétele — az a
release-t a `hold`-on álló Epic 10 (Offline AI) sávtól tenné függővé. A
fordított gyengítés is tilos: a `not_in_scope` státusz nem hagyható ki a
kimenetből, mert akkor a hiány nem megkülönböztethető a nemlététől.

### D4 — A regresszió-küszöb IMPORTÁLT, nem újradefiniált

Az összesítő a `tool/compare_benchmarks.py` `classify`, `WARN_THRESHOLD` és
`FAIL_THRESHOLD` neveit importálja. Az 5,0% figyelmeztetés / 10,0% hiba
kétfokozatú, mindkét határon INKLUZÍV küszöb (ADR 0474 D6) és az irány-tudatos
(`lowerIsBetter` / `higherIsBetter`) osztályozás (ADR 0474 D7) az ott mért
egyetlen forrásból jön.

**NEM elfogadható gyengítés:** numerikus küszöb-literál vagy saját `classify`
az összesítőben, illetve CLI-kapcsolóból vett küszöb. Ezt gépi cella méri: az
összesítő forrása nem tartalmazhat küszöb-literált.

### D5 — Minden állítás modell- ÉS build-verzióhoz és korpuszhoz kötött

A riport minden metrikája kötelezően hordoz `corpusId`, `buildSha`, `modelId`
és `modelVersion` mezőt. A `modelId` vagy a `model_manifest.json`
`models[].filename` értéke (ekkor a `modelVersion` a
`training_run.identifier`), vagy a `vision_models[].model_id` értéke (ekkor a
`modelVersion` a `version`), vagy a bizonyíték-mátrix által kifejezetten
`none`-ként deklarált, modell nélküli (tisztán DSP) bizonyíték esetén a `none`
literál. Bármely más kombináció, illetve a manifesttől eltérő `modelVersion`,
nem-nulla kilépés.

**NEM elfogadható gyengítés:** verzió nélküli metrika átvétele egy korábbi
riportból („úgyis ugyanaz a modell"), vagy a `none` használata olyan sorra,
amit a mátrix modellhez kötött.

### D6 — A `--profile` provenancia, nem kapcsoló

A `--profile` értékkészlete zárt: `development`, `lab`, `production` (mérve:
`docs/release/environment-matrix.md:14`, `lib/app/config/app_environment.dart`).
Az érték a kimenetbe kerül, hogy egy riport ne legyen némán újrahasznosítható
másik csatornára, de **egyetlen ellenőrzést sem lazít és nem szigorít**.
Ismeretlen érték hiba (kilépés 2), nem alapértelmezés.

**NEM elfogadható gyengítés:** profil-függő kapu („development-ben elég a
figyelmeztetés"). Az ADR 0474 D6 indoklása szó szerint áll: a hívó által
befolyásolható szigorúság a „lazább CI-ban" gyengítés.

### D7 — Ez a kör NEM ír CI-workflow-t és nem ír át meglévő kaput

Az `ai-release-gate.yml` bevezetése külön kör; a `tutor-eval.yml`, a
`dsp-probe.yml` és a Chapter 14 `recognition-release-guard.md` küszöbei
változatlanok. Az összesítő ezeket BEMENETNEK tekinti. Ha a beolvasott
bizonyíték és a Chapter 14 guard ellentmond, az a `stopped` jelzés esete, nem
egy második, versengő küszöb bevezetése.

## Következmények

- A `python3 tool/release/build_ai_report.py --profile development` a mai fán
  **nem-nulla** kóddal lép ki, mert a `ga_scope: true` `audio_analysis_core` és
  `live_and_tuner` capabilityhez ma nincs gépileg beolvasható AI-bizonyíték-
  dokumentum. Ez a kör HELYES kimenete: a release AI-bizonyítéka valóban nincs
  összegyűjtve, és ezt a D2 fail-closed ága mondja ki. **A pirosat kitalált
  riport-dokumentum commitolásával elfedni tilos** — a kör engedélyezett
  fájllistája sem `docs/eval/**`, sem `evaluation/**` írást nem tartalmaz.
- A teszt-fixture-ök `Directory.systemTemp`-be íródnak és `addTearDown`-nal
  bomlanak le (E12-R14 / `benchmark_budget_test.dart` minta), mert a kör nem
  commitolhat `test/fixtures/**`-ot.
- A `tool/compare_benchmarks.py` importja az egyetlen megengedett kereszt-modul
  függés; a `docs/testing/device-matrix.yaml` olvasása PyYAML-lel történik,
  ugyanazzal a kemény függés-döntéssel, amit a `tool/device_report.py` már hoz.
