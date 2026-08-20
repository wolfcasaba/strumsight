# E14-R15 — Hard-negative taxonómia és false-visible-event metrika

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 6371aa3`)
- **Típus:** Chapter 14, Kör 15 — a „strum onset + direction recovery" blokk (SDD §8: R15–R24) nyitó köre
- **Kör-azonosító:** `E14-R15`
- **Branch:** `<motor>/e14-r15-hard-negative-corpus-and-false-visible-metric`
- **Előfeltétel:** `E14-R08` merge-elve (a harness, amibe a metrika kerül) és
  `E14-R07` (annotációs szerződés, amivel a negatív anyag címkézhető).
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0367` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az `ml/negatives.py`
> fejlécét — a hard-negative BÁNYÁSZAT (r174) MÁR LÉTEZIK, és a mért állítása
> (a heurisztikus onset-detektor ~minden hatodik onsetje hamis, és a
> direction-CRNN ezekre ugyanolyan magabiztos: medián raw 0,94 vs 0,97) a §2
> alapja. Ez a kör NEM írja újra, hanem taxonómiát és termék-oldali metrikát
> ad hozzá. Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "evaluation/recognition/negative_taxonomy.json",
  "evaluation/recognition/fixtures/negative_taxonomy_sample.json",
  "lib/features/live/domain/evaluation/false_visible_event_metric.dart",
  "lib/features/live/public.dart",
  "test/features/live/evaluation/false_visible_event_metric_test.dart",
  "docs/eval/recognition-hard-negatives.md",
  "docs/rounds/e14-r15-hard-negative-corpus-and-false-visible-metric.md",
]
gate_tests = [
  "test/features/live/evaluation/false_visible_event_metric_test.dart",
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

## 0.0 Kötött scope-szűkítés a SDD-hez képest (drift, KÖTELEZŐ így)

A SDD Kör 15 „legalább 60 perc negatív anyagot" is kér. **Hangfelvétel nem
kerül a repóba** (ADR 0249 óta álló határ), és a felvételt a `E14-R06`
consent-kapuja végzi — ezért ez a kör a **taxonómiát, a capture-listát, a
manifest-szerződést és a termék-oldali metrikát** adja; a tényleges 60 perc
külső, kézi munkafolyam, amit a `docs/eval/recognition-hard-negatives.md`
ír le és a manifest tart nyilván. A kör acceptance-e a repóban ellenőrizhető
részre vonatkozik.

## 1. Cél

Legyen **gépi fogalma** a terméknek arról, hogy mennyi hamis eseményt mutat a
felhasználónak: `false visible arrow / min` és `false visible chord / min`.
Emellé kerüljön egy legalább tíz kategóriás hard-negative taxonómia (beszéd,
taps, asztalkoppanás, pengető-kattintás, húrzaj, fret squeak, metronóm,
háttérzene, tévé, ventilátor, telefonmozgatás), amellyel a negatív anyag
címkézhető és a leakage kizárható.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **`ml/negatives.py` (r174):** a mért gyökérok — a confidence önmagában NEM
  szűri a zajt, mert a modell a hamis onsetre is magabiztos. Ezért kell külön
  no-strum osztály ÉS termék-oldali hamis-esemény metrika.
- **ADR 0249:** nyers audio nem kerül a repóba — a manifest igen.
- **E14-R10:** az abstention csökkenti a hamis nyilakat; ez a kör adja a
  mérőszámot, amivel ez bizonyítható.

## 2. Jelenlegi állapot — mért tények

- `ml/negatives.py` — a tanító oldal hard-negative bányászata LÉTEZIK; a
  fejléce rögzíti a ~1/6 hamis onset arányt és a 0,94/0,97 medián
  confidence-párt.
- A **termék** oldalán nincs olyan metrika, amely a felhasználónak MEGMUTATOTT
  hamis eseményeket számolná — csak modell-szintű pontosság van.
- `evaluation/recognition/` — az `E14-R02` hozza létre; a taxonómia ide kerül.

## 3. Scope

**Benne:** taxonómia (JSON + doksi), capture-lista, a manifest kategória-mezője,
`FalseVisibleEventMetric` (esemény/perc, kategória-bontással), fixture, doksi.

**Nincs benne:** hangfájl a repóban, modelltanítás, DSP-konstans, a
`ml/negatives.py` átírása, UI.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `evaluation/recognition/negative_taxonomy.json` | a tíz+ kategória gépi listája |
| `evaluation/recognition/fixtures/negative_taxonomy_sample.json` | CI-fixture |
| `lib/features/live/domain/evaluation/false_visible_event_metric.dart` | esemény/perc metrika |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/evaluation/false_visible_event_metric_test.dart` | metrika-mátrix |
| `docs/eval/recognition-hard-negatives.md` | taxonómia + capture-lista + külső workflow |
| `docs/rounds/e14-r15-hard-negative-corpus-and-false-visible-metric.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `ml/**`, `assets/**`,
`lib/features/live/engine/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0367)

### 5.1 A metrika a MEGMUTATOTT eseményt számolja

A `false visible event` az, amit a felhasználó ténylegesen látott (elfogadott,
nem `uncertain`, nem `rejected`). **NEM elfogadható**: a modell nyers
kimenetének számolása — épp az a különbség, amiért ez a metrika létezik.

### 5.2 Percre normalizált, nem eseményre

Az érték `esemény / perc`, mert a felhasználói bosszúság időarányos. Az
osztás nevezője a NEGATÍV anyag hossza, nem az összes anyagé.

### 5.3 Kategória kötelező

Minden negatív felvétel-szegmens pontosan egy taxonómia-kategóriát kap;
ismeretlen kategória **típusos hiba**, nem `other`-be söprés.

### 5.4 Nincs klip-leakage

Ugyanaz a forrásfelvétel nem szerepelhet train és eval oldalon; a manifest
`sourceId`-t hordoz, és a leakage-detektor (E14-R08) ezt is nézi.

### 5.5 Nyers audio nem kerül a repóba

A manifest hivatkozik, nem tartalmaz. **NEM elfogadható**: „csak egy rövid
minta a fixture-höz" — a fixture szintetikus vagy annotáció-only.

## 6. Acceptance criteria

1. A taxonómia legalább **10** kategóriát tartalmaz: a hármas cella a határra —
   a küszöb **alatt** (9 kategória) a validátor hibát ad, pontosan **rajta**
   (10) elfogadott (a határ inkluzív), a küszöb **fölött** (11) elfogadott.
2. Ismeretlen kategória a manifestben típusos hibát ad.
3. A metrika kézzel ellenőrzött értéket ad a fixture-ön: 3 megmutatott hamis
   nyíl 120 másodperc negatív anyagon → **1,5 esemény/perc**.
4. `uncertain`/`rejected` esemény NEM számít bele (ugyanaz a fixture, a három
   esemény egyike `uncertain` → **1,0 esemény/perc**).
5. A metrika kategória-bontást is ad, és a bontás összege egyezik a
   teljes értékkel.
6. Azonos `sourceId` két splitben → a leakage-ellenőrzés hibát jelez.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A nyers modell-kimenetet számolja | 4. pont |
| Eseményre normalizál, nem percre | 3. pont `1,5` cellája |
| Ismeretlen kategória → `other` | 2. pont |
| A kategória-bontás külön számol | 5. pont összeg-cellája |
| 9 kategóriás taxonómiát elfogad | 1. pont „pontosan rajta" cellája |
| A `sourceId` nem kerül a manifestbe | 6. pont |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/evaluation
```

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A §10-ben dokumentáld: az `uncertain` szűrés ideiglenes kikapcsolásával a
4. pont **PIROS**, visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Taxonómia JSON + validáció + fixture.
2. `FalseVisibleEventMetric` + mátrix-teszt.
3. Kategória-bontás és leakage-mező.
4. Doksi: capture-lista és a külső (repón kívüli) workflow.

## 9. Kockázatok

- **Hangfájl-szivárgás:** az 5.5 tiltja; a review a diffben grepeli a
  bináris kiterjesztéseket.
- **Duplikáció az `ml/negatives.py`-vel:** a kör termék-oldali metrikát ad,
  nem tanító-oldali bányászatot; az `ml/**` tilos zóna.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
