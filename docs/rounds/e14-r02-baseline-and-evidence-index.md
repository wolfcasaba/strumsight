# E14-R02 — Reprodukálható felismerési baseline és evidence index

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 7b5315b`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 2
- **Kör-azonosító:** `E14-R02`. Az `E14` a **FEJEZETET** jelöli, nem epicet.
- **Branch:** `<motor>/e14-r02-baseline-and-evidence-index`
- **Előfeltétel:** `E14-R01` merge-elve (release guard — `docs/eval/recognition-release-guard.md`)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0354` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `docs/eval/real-audio-dsp-baseline.md` TÉNYLEGES számait és a benne rögzített
> mérési parancsot (a GOV-06b javítás óta a BPM-állítás visszavont), valamint
> ellenőrizd, hogy az `ml/data/klangio` corpus a boxon elérhető-e. Eltérésnél
> §0.0 revízió a brief tetején.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "evaluation/recognition/README.md",
  "evaluation/recognition/baseline_manifest_schema.json",
  "evaluation/recognition/baseline_manifest.json",
  "tool/benchmarks/recognition_baseline_manifest.dart",
  "test/tooling/recognition_baseline_manifest_test.dart",
  "docs/eval/recognition-baseline-index.md",
  "docs/rounds/e14-r02-baseline-and-evidence-index.md",
]
gate_tests = [
  "test/tooling/recognition_baseline_manifest_test.dart",
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

## 1. Cél

A ma szétszórt felismerési mérések **egyetlen, géppel olvasható manifestbe és
egy ember-olvasható indexbe** kerüljenek, úgy, hogy ugyanaz a bemenet **bitre
azonos** reportot adjon, és **egyetlen szám se álljon forrás és parancs nélkül**
(SDD Ch14 Kör 2).

Ez a kör **nem mér újra és nem javít semmit** a felismerésen — a mérés
*rendszerezése* a tárgya. Új DSP/ML konstans, küszöbhangolás, modellcsere
TILOS (AGENTS.md §9).

### 1.1 Visszakeresett előzmény (ADR 0312)

- **ADR 0271 §2** („előbb a mérés, aztán a modellcsere"): a legacy DSP a
  baseline, új modell csak mért A/B + grouped evaluation után — ez a kör adja
  ehhez a hivatkozási alapot.
- **ADR 0249 / `evaluation/analysis/`** (analysis evaluation dataset
  governance): kész minta a séma + README + fixture hármasra; ez a kör ezt
  követi, nem újat talál ki.
- **ADR 0136** (deterministic offline retrieval): a determinisztikus manifest +
  hash-lezárás mintája már bevált a tutor tudásbázisnál.

## 2. Jelenlegi állapot — mért tények

- `docs/eval/real-audio-dsp-baseline.md` **létezik** (E99-R04, javítva E99-R05):
  82 valós telefonos felvétel, `const ClipAnalyzer()` → **7 892 / 11 767 =
  67,069%** akkord-pontosság; többségi (G-major) baseline 2 216 / 11 767 =
  18,832%; onset precision/recall/F1 három tűrésre (25/50/100 ms); moll
  események 185/222 = 83,333%.
- Ugyanez a fájl **visszavonja** a korábbi 45,067 BPM-állítást (a `.strums`
  események pengetések, nem ütem-annotációk), és helyette librosa-referenciás
  egyezést közöl (11/82 = 13,415% szigorú, 32/82 = 39,024% metrikai-szint
  toleráns).
- A mérés futtatható parancsa a report §-ában szerepel:
  `flutter test --dart-define=REAL_AUDIO_DSP_BASELINE_CORPUS=ml/data/klangio
  --dart-define=REAL_AUDIO_DSP_TEMPO_REFERENCE=/tmp/tempo_reference.json
  tool/benchmarks/real_audio_dsp_baseline.dart`, a referencia-parancs pedig
  `ml/chords/tempo_reference.py`. **A `dart run` alak NEM működik** (a valós
  `ClipAnalyzer` tranzitívan `dart:ui`-t importál) — ezt a report külön rögzíti.
- `evaluation/` ma két alkönyvtárat tart: `evaluation/tutor/` és
  `evaluation/analysis/`. Utóbbi **kész mintát ad** ehhez a körhöz:
  `evaluation/analysis/manifest_schema.json` (draft-07 JSON Schema,
  `schemaVersion` konstanssal, `additionalProperties: false`) +
  `evaluation/analysis/README.md` (ADR 0249). **Ezt a mintát kell követni, nem
  újat kitalálni.**
- `evaluation/recognition/` **nem létezik** — ezt a kör hozza létre.
- `docs/eval/recognition-release-guard.md` (E14-R01) rögzíti az aktivációs
  szerződést és a rollout-fegyelmet — az index ehhez linkel, nem másolja.
- A corpus (`ml/data/klangio`) **nyers audiót tartalmaz, és nincs a repóban** —
  a manifest ezért kizárólag hash-t és darabszámot rögzíthet.

## 3. Scope

**Benne:**

1. `evaluation/recognition/baseline_manifest_schema.json` — draft-07 séma az
   `evaluation/analysis/manifest_schema.json` mintájára (`schemaVersion`
   konstans, `additionalProperties: false`, tételes leírások).
2. `evaluation/recognition/baseline_manifest.json` — a MAI mérés adatai:
   corpus-hash + darabszám, modell-hash(ek), app commit, konfiguráció, a
   futtatott parancsok, és metrika-blokkok **szétválasztva**: `onset`,
   `direction`, `chord`, `noChord`, `latency`, `calibration`.
3. `tool/benchmarks/recognition_baseline_manifest.dart` — determinisztikus
   generátor/ellenőrző: a manifestet a sémához validálja és a `docs/eval/`
   index táblázatait belőle rendereli (`--check` módban csak ellenőriz).
4. `docs/eval/recognition-baseline-index.md` — az ember-olvasható index.
5. `test/tooling/recognition_baseline_manifest_test.dart` — a §6 acceptance
   futtatható mércéje.

**Nincs benne (TILOS):** új mérés futtatása modellcserével, bármely DSP/ML
konstans, küszöb vagy modell-bináris módosítása, a `lib/**` bármely fájlja, a
`docs/eval/real-audio-dsp-baseline.md` felülírása (az történeti tény — az index
HIVATKOZIK rá), `docs/adr/**`, `.github/workflows/**`, `tools/round-gate.sh`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `evaluation/recognition/README.md` | mi lakik itt, hogyan frissül (az `analysis/README.md` mintájára) |
| `evaluation/recognition/baseline_manifest_schema.json` | a manifest gépi szerződése |
| `evaluation/recognition/baseline_manifest.json` | a mai baseline adatai |
| `tool/benchmarks/recognition_baseline_manifest.dart` | determinisztikus generátor/ellenőrző |
| `test/tooling/recognition_baseline_manifest_test.dart` | a mérce |
| `docs/eval/recognition-baseline-index.md` | az ember-olvasható index |
| `docs/rounds/e14-r02-baseline-and-evidence-index.md` | §10 handoff kitöltése |

**Tilos zóna:** minden más — kiemelten `lib/**`, `ml/**`, `assets/**`,
`docs/adr/**`, `docs/eval/real-audio-dsp-baseline.md`, `.github/workflows/**`.

## 5. Kötött architekturális döntések (ADR 0354)

### 5.1 A manifest sosem tartalmaz nyers audiót

Csak `corpusId`, `corpusSha256` (a fájllista + fájlhash-ek determinisztikus
összegzése), `recordingCount`. Egyetlen bájt hangminta sem kerülhet a repóba.

### 5.2 Minden szám mellett ott a forrás ÉS a parancs

Metrika-mezőnként kötelező: `value`, `n` (hány elemen mérve), `sourceFile`,
`command`. **NEM elfogadható gyengítés:** egy közös „lásd a report parancsát"
lábjegyzet a metrikák helyett — a mező-szintű `command` kötelező, mert épp az
volt a mért baj, hogy a számokhoz nem tartozott visszakereshető futtatás.

### 5.3 A visszavont állítás VISSZAVONT marad, gépileg is

A BPM-blokk `retracted: true` + `retractedReason` mezőt kap, és az indexben
áthúzva/„VISSZAVONT" jelöléssel jelenik meg. **NEM elfogadható gyengítés:** a
visszavont szám csendes törlése — a tévedés nyoma bizonyíték, nem szemét.

### 5.4 Bitre azonos újrafuttatás

A generátor determinisztikus: kulcsok ábécésorrendben, listák explicit rendezési
kulccsal, lebegőpontos értékek fix formátummal (3 tizedes, `toStringAsFixed`),
időbélyeg CSAK a manifestből (a generátor **nem** hív `DateTime.now()`-ot).

### 5.5 A report nem állít többet, mint amit a corpus bizonyít

Ha egy metrikához `n == 0` vagy hiányzik a `sourceFile`, a generátor
**fail-closed** hibával áll meg — nem ír ki „n/a" sort a táblázatba.

## 6. Acceptance criteria

1. `baseline_manifest.json` validál a sémára, és tartalmazza mind a hat
   metrika-blokkot (`onset`, `direction`, `chord`, `noChord`, `latency`,
   `calibration`) — az üresen hagyott blokk explicit `status: "not-measured"`
   értékkel szerepel, indoklással.
2. A generátor kétszeri futtatása **bájtra azonos** `docs/eval/recognition-baseline-index.md`-t ad.
3. Minden számhoz tartozik `sourceFile` + `command`; hiányuk fail-closed hiba.
4. A BPM-blokk `retracted: true`, és az indexben is visszavontként jelenik meg.
5. Az index a `docs/eval/real-audio-dsp-baseline.md`-re és a
   `recognition-release-guard.md`-re **hivatkozik**, nem másolja a tartalmukat.
6. `n == 0` vagy hiányzó forrás esetén a `--check` nem nulla exit-kóddal áll meg.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A generátor `Map` bejárási sorrendben ír (nem rendez) | 2. pont: a két futás diffje nem üres |
| A generátor `DateTime.now()`-ot tesz a fejlécbe | 2. pont: a két futás diffje nem üres |
| A metrika-szintű `command` elhagyása közös lábjegyzet javára | 3. pont: a séma `required` mezője miatt a validálás piros |
| A visszavont BPM-sor törlése a manifestből | 4. pont: az index-renderelő nem talál `retracted` blokkot → hiányzik a „VISSZAVONT" sor |
| `n: 0` metrika kiírása „n/a"-ként | 6. pont: a `--check` 0-val tér vissza, holott nem nullának kell lennie |
| Float-értékek nyers `toString()`-gel | 2. pont: platformfüggő formázás → diff |

**Numerikus küszöb — `n` (mért elemszám), a határ INKLUZÍV a hibaoldalon:**

| Cella | `n` | Várt viselkedés |
|---|---|---|
| alatt | `n = 0` | `--check` **hibázik** (fail-closed) |
| pontosan rajta | `n = 1` | átmegy, de az index `n=1` jelöléssel közli (egyetlen elem nem bizonyíték) |
| fölött | `n = 82` | átmegy, normál sor |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling
```

A gate önmagában futtatja a `format` → `analyze` → célzott teszt →
`architecture` lépéseket külön processzként (AGENTS.md §12). **`&&` láncolás
tilos** (OOM, L09/L05). CI-dispatch, PR és merge Claude-oldal — a Codex ne
hívjon `gh`-t.

### 7.1 Falszifikációs cella

A determinizmus-acceptance-hez a §10-ben dokumentáld: a generátor rendezését
ideiglenesen kikapcsolva a teszt **PIROS** lesz (másold be a kimenetet), majd
visszaállítva **ZÖLD**.

## 8. Implementációs sorrend

1. Séma (`baseline_manifest_schema.json`) az `analysis` minta alapján.
2. Manifest feltöltése a `real-audio-dsp-baseline.md` MÉRT számaiból.
3. Generátor + `--check` mód.
4. Teszt (determinizmus, fail-closed cellák, séma-validálás).
5. Index renderelése, README.
6. `tools/round-gate.sh test/tooling`.

## 9. Kockázatok

- **A corpus a boxon hiányozhat** (`ml/data/klangio`): a kör NEM futtat új
  mérést, tehát ez nem blokkoló — a manifest a MÁR MEGMÉRT számokat rögzíti. Ha
  a hash-eléshez sem érhető el a corpus, a `corpusSha256` mező
  `"unavailable-at-authoring"` értéket kap, és ezt az index is kimondja.
- A séma túl szigorú `additionalProperties: false`-a a későbbi körök
  metrikáit kizárhatja — ezért minden metrika-blokk `extra` objektumot kap.
- Az index és a report közti duplikáció drift-forrás — ezért az index
  kizárólag hivatkozik.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
