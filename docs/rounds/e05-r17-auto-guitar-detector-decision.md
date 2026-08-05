# E05-R17 — Automatikus guitar/neck detector döntési kör

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 17; §31, §32
- **Branch:** `codex/e05-r17-auto-guitar-detector-decision`
- **Előfeltétel:** **E05-R11, E05-R16 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/adr/0169-vision-automatic-guitar-geometry-detection.md",
  "docs/baseline/epic-05-guitar-detector-evaluation.md",
  "docs/manual-testing/vision-device-matrix.md",
  "ml/vision/README.md",
  "ml/vision/dataset_manifest.md",
  "ml/vision/evaluate_geometry_baseline.py",
  "docs/rounds/e05-r17-auto-guitar-detector-decision.md",
]
gate_tests = [
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R11/R16 merge; olvasd újra az
> **ADR 0164**-et (manual calibration a production út) és `AGENTS.md` **§9**-et
> (training nem fut normál körben). **ADR 0169** előre kiosztva.
> PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR: **0169**.

## 1. Cél

**Go / no-go / experimental-only** döntés egy automatikus gitárnyak-detektorról
— reprodukálható kiértékelési harness és dataset-politika mellett, a **manual
fallback megtartásával**.

## 2. Jelenlegi állapot (mért, `5d082dc` + megelőző körök)

- Az R11 (manual kalibráció UI) és az R16 (tracking + loss) élesben adják a
  production geometria-utat — **a MVP nem függ detektortól** (ADR 0164).
- `ml/` létezik (audio-oldali kísérletek, `ml/README.md`, `make_manifest.py`),
  de **nincs `ml/vision/`**, és nincs vision dataset.
- **Ebben a környezetben nincs consentelt gitáros képanyag**, és a
  `AGENTS.md` §9 tiltja a training futtatását normál körben.

## 3. Scope

**Benne:** a dataset-kategóriák és a **consent-politika** írásos rögzítése; a
lehetséges detektor-kimenetek (bounding box / line / segmentation) összevetése;
egy **futtatható, de adat nélkül üresen záró** kiértékelő script váza (IoU,
anchor error, latency, failure rate metrikák implementálva, bemenet nélkül
`NO_DATA` státusszal kilépve); a manual kalibráció idő- és hibaköltségének
becslése a mérendő értékek megjelölésével; és az **ADR 0169**.

**Kívül — TILOS:** dataset gyűjtése vagy repóba töltése, training futtatása,
model-asset hozzáadása, bármely `lib/` vagy `test/` production fájl,
`assets/` módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `docs/adr/0169-*.md` | ÚJ | a döntés |
| `docs/baseline/epic-05-guitar-detector-evaluation.md` | ÚJ | összevetés + költségbecslés |
| `docs/manual-testing/vision-device-matrix.md` | meglévő | PENDING mérési sorok |
| `ml/vision/README.md` | ÚJ | a kísérleti út leírása |
| `ml/vision/dataset_manifest.md` | ÚJ | kategóriák + consent |
| `ml/vision/evaluate_geometry_baseline.py` | ÚJ | reprodukálható harness |
| `docs/rounds/e05-r17-*.md` | meglévő | §10 handoff |

**Tilos zóna:** `lib/`, `test/`, `assets/`, `pubspec.yaml`, minden képfájl.
Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Default döntés: `experimental-only`.** A production geometria a manual
   kalibráció marad (ADR 0164); egy detektor legfeljebb a
   `visionExperimentalFineFretEnabled`-hez hasonló, **külön flag mögött**
   létezhet, és **nem** válthatja ki a manual utat. **NEM elfogadható:**
   olyan ADR, amely a manual fallback megszüntetését engedi, vagy amely
   mérés nélkül minősít „production candidate"-nek.
2. **A go/no-go átfordításának feltétele számmal kötött:** a detektor akkor
   léphet experimental fölé, ha a kiértékelés (ugyanezzel a harness-szel,
   valós consentelt adaton) **anchor error** és **failure rate** tekintetében
   a manual kalibráció mért költségénél jobb — a küszöbszámok az ADR-ben állnak.
3. **Consent kötelező:** dataset csak explicit, dokumentált hozzájárulással
   gyűjthető, és a manifestnek forrást, jogalapot és felhasználási kört kell
   tartalmaznia. **NEM elfogadható:** webről gyűjtött, ismeretlen jogállású kép.
4. **A harness reprodukálható és adat nélkül is futtatható**: bemenet híján
   `NO_DATA` státusszal és nem nulla, de **definiált** kilépési kóddal áll meg,
   nem hamis eredménnyel.
5. **A hamis geometria kockázata dokumentált:** az ADR-nek le kell írnia, mi
   történik, ha a detektor magabiztosan téved (ez rosszabb, mint ha nincs).

## 6. Acceptance criteria

- [ ] Az ADR 0169 tartalmaz **döntést (experimental-only, hacsak a §5.2
      küszöbök nem teljesülnek), számszerű átfordítási küszöböket, elutasított
      alternatívákat és a hamis-geometria kockázat leírását**.
- [ ] A `dataset_manifest.md` minden kategóriához: forrás, jogalap, consent,
      számosság-cél, és a **tilos** források listája.
- [ ] Az `evaluate_geometry_baseline.py` **lefut** üres bemenettel, `NO_DATA`
      státuszt ír, és a metrikák (IoU, anchor error, latency, failure rate)
      unit-szinten ellenőrizhetők szintetikus bemeneten (a scripten belüli
      `--self-test` kapcsolóval).
- [ ] A baseline dokumentum tartalmazza a **manual kalibráció** idő- és
      hibaköltségének becslését, és megjelöli, melyik számot kell valós
      eszközön megmérni (PENDING a device-mátrixban).
- [ ] `git diff --stat` **nem** tartalmaz `lib/`, `test/`, `assets/`,
      `pubspec.yaml` fájlt és **egyetlen bináris fájlt sem**.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A `--self-test` futtatásának kimenetét
a §10 idézi.

## 8. Implementációs sorrend

1. Dataset-kategóriák + consent-politika.
2. Harness (metrikák + `--self-test` + `NO_DATA` út).
3. Összevetés + költségbecslés.
4. ADR 0169; gate.

## 9. Kockázatok

- **A kör „kutatássá" duzzad** és adatot próbál gyűjteni — a tilos zóna és a
  bináris-tiltás ezt zárja ki; adatigény esetén `stopped`.
- **Az ADR mérés nélkül minősít.** Ellenszer: a default `experimental-only`
  és a számszerű átfordítási küszöb.

**STOP:** dataset/model behúzása, training indítása vagy production kód
érintése helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r17-auto-guitar-detector-decision-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
