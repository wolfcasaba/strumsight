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

## 0.0 Pre-flight revízió (Claude, 2026-09-04, `main @ d26f1958`)

A brief 2026-08-20-án készült (`main @ 7b5315b`). A mai mérés hét ponton
pontosít; mindegyik a KÖR SAJÁT, még nem merge-elt artefaktumát érinti
(ADR 0087 §2), tehát az orchestrátor hatásköre. A `brief-lint` egyetlen
`strict` leletét (S12) az **R1** zárja.

### R1 — S12: a §7 gate-parancs nem tükrözte a `gate_tests` listát

**Mérve:** `gate_tests = ["test/tooling/recognition_baseline_manifest_test.dart"]`,
a §7 viszont `tools/round-gate.sh test/tooling`-ot írt. A könyvtár-alak
technikailag lefedi a fájlt, de a lint jogos: a kör olyan mércét ígért, amit a
PARANCSSOR nem nevesít, és a `test/tooling/` teljes futtatása (49 fájl) ezen a
boxon fölösleges. **Javítva:** a §7 parancs mostantól szó szerint a `gate_tests`
egyetlen elemét futtatja.

### R2 — az ADR-szám 0354 marad (a foglaló 0504-et adott)

**Mérve:** `tools/round-slots.py reserve-adr --round E14-R02` → **`0504`**, mert
az algoritmus `max(használt) + 1`-et ad (a legmagasabb lemezen lévő ADR a
`0503`). A queue-sor és a pipeline-prompt viszont **`0354`**-et osztott ki. A
`0354` **szabad**: nincs `docs/adr/0354*.md` a fán, és `git log --all --
'docs/adr/0354*'` üres. A `.pipeline/inflight/adr/0354` marker **elavult**: a
`round=E08-R13` sort hordozza, az E08-R13 viszont ténylegesen a
[`0374`](../adr/0374-achievement-domain-and-catalog-contract.md)-et szállította
(a queue-ban nála `0310` áll — a marker sem a queue-val, sem a fával nem egyezik).
**Döntés:** a kör a queue-konzisztens **`0354`**-et használja (az E14-R03..R19
sorok `0355`..`0371`-et foglalnak, tehát a sáv számozása így marad zárt); a
mellékesen lefoglalt `0504` marker visszavonva. Ütközés kizárt: a foglaló soha
nem oszt ki `0503` alatti számot.

### R3 — nincs JSON-Schema könyvtár; a validálás KÉZZEL írt (BLOKKOLÓ lett volna)

**Mérve:** a `pubspec.yaml` nem deklarál `json_schema` (vagy bármely séma-)
függőséget, és a `pubspec.yaml` a kör **tilos zónájában** van. A meglévő minta
sem használ ilyet: az `evaluation/analysis/manifest_schema.json` szerződését az
`evaluation_manifest_parser.dart` **kézzel** kényszeríti ki (`required`,
`additionalProperties`, `const`), a `tool/check_fixture_manifest.dart` pedig
ugyanígy tiszta Dart. **Előírás:** a `--check` a sémafájlt BEOLVASSA és a
`type` / `required` / `additionalProperties: false` / `const` /
`enum` szabályokat maga érvényesíti. Séma-könyvtár felvétele `pubspec`-módosítást
igényelne → **`stopped` jelzés, nem lista-tágítás.**

### R4 — a `sourceFile`/`command` és a `not-measured` blokk NEM mondhat ellent

**Mért ellentmondás a briefben:** §5.2 minden metrika-mezőre kötelezővé teszi a
`value` + `n` + `sourceFile` + `command` négyest, a §6 AC1 viszont üres blokkra
`status: "not-measured"`-t ír elő — a kettő együtt kielégíthetetlen. **Feloldás
(kötelező alak):** minden metrika-blokk `status` mezőt kap, és a séma
`oneOf`-fal két alakot enged:

- `status: "measured"` → kötelező a `metrics` objektum, és **minden** metrikára
  a `value` + `n` + `sourceFile` + `command` négyes;
- `status: "not-measured"` → kötelező a `notMeasuredReason` (nem üres sztring),
  és **tilos** a `metrics` kulcs.

A `--check` mindkét ágat fail-closed méri; a „félig kitöltött" blokk (pl.
`status: "measured"` üres `metrics`-szel) hiba.

### R5 — mely blokk mérhető MA, és mely nem

**Mérve** (`docs/eval/real-audio-dsp-baseline.md` a MAI fán, és
`grep -rn "latency|direction|noChord" docs/eval/*.md` → **0 találat**):

| Blokk | Ma | Forrás |
|---|---|---|
| `chord` | **measured** | 7 892/11 767 = 67,069%; G-major többségi 2 216/11 767 = 18,832%; moll 185/222 = 83,333%; per-label precision/recall 12 címkére |
| `onset` | **measured** | 25/50/100 ms tűrés, precision/recall/F1 (38,532/42,517/40,427 · 64,233/70,876/67,391 · 81,208/89,607/85,201 %) |
| `direction` | **not-measured** | a korpusz `.strums` fájljai pengetés-események; a report nem közöl irány-pontosságot |
| `noChord` | **not-measured** | a korpusz 98%-ban dúr akkord-felvétel, N.C.-annotáció nincs benne |
| `latency` | **not-measured** | a baseline offline batch-mérés (`flutter test`), nem valós idejű futás |
| `calibration` | **not-measured** | nincs konfidencia-annotáció ehhez a korpuszhoz (vö. ADR 0249 §Döntés 4 küszöbei) |

A BPM külön, **`retracted`** blokk (§5.3) — nem a hat metrika-blokk egyike.

### R6 — a korpusz ELÉRHETŐ; a `unavailable-at-authoring` ág ma NEM alkalmazható

**Mérve:** `ml/data/klangio` létezik a boxon, **82** `*_phone.wav`, 167 fájl
összesen. A hash-t nem kell újraszámolni: a report §Reprodukálhatóság rögzíti —
`corpusSha256 = 4880faceab27217640701f1b93db477606d5fb3aa2c4434574040b6590315827`,
`recordingCount = 82`, `eventCount = 11767`, `skippedRecordings = 0`. A §9 első
kockázata tehát MA tárgytalan: a manifest ezeket a MÉRT értékeket veszi át, a
`"unavailable-at-authoring"` érték kiírása ebben a körben **hiba**.

### R7 — a mért konfiguráció NEM használt ML-modellt

**Mérve:** a baseline a változatlan `const ClipAnalyzer()`-t futtatta
(`lib/features/analyze/engine/clip_analyzer.dart:36` — `strumRefiner` alapértéke
`null`), tehát **egyetlen** `assets/ml/*.bin` súly sem vett részt a mérésben. A
`recognition-release-guard.md` „model SHA-256" elvárása a JELÖLTRE vonatkozik,
nem a legacy baseline-ra. **Előírás:** a manifest `models` mezője **üres
tömb**, és ilyenkor **kötelező** a nem üres `modelsRationale` (a `--check`
fail-closed méri). Kitalált vagy „a teljesség kedvéért" bemásolt
`chord_crnn.bin` hash a manifestben **hamis állítás** — a séma sem engedi
indoklás nélkül.

### R8 — a generátor TISZTA Dart, és a teszt könyvtárként importálja

**Mérve:** `test/tooling/benchmark_budget_test.dart:19` →
`import '../../tool/benchmarks/benchmark_record.dart';` — ez a bevett minta a
`tool/`-alatti tiszta Dart forrásra. A testvér `real_audio_dsp_baseline.dart`
tranzitívan `dart:ui`-t húz (a report külön rögzíti, hogy `dart run`-nal nem
indul) — az ÚJ generátor ezt **nem** importálhatja, semmit a `lib/**`-ból, és a
determinizmus-cellának in-process, két temp-könyvtárba írt futással kell
mérnie.

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
   értékkel szerepel, indoklással (`notMeasuredReason`), a §0.0/R4 két
   `oneOf`-alakja szerint, és a §0.0/R5 táblázatának megfelelő besorolásban
   (`chord` + `onset` = `measured`, a másik négy = `not-measured`).
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
| A `_validate` egy le nem fedett séma-kulcsot (pl. `maxLength`) némán átenged, nem `ManifestIssue`-t ad | A9 teszt-csoport: ismeretlen kulcs a sémán → `--check` nem nulla exit-kóddal áll meg, az üzenet megnevezi a kulcsot (ADR 0354 D8, review MAJOR-1) |

**Numerikus küszöb — `n` (mért elemszám), a határ INKLUZÍV a hibaoldalon:**

| Cella | `n` | Várt viselkedés |
|---|---|---|
| alatt | `n = 0` | `--check` **hibázik** (fail-closed) |
| pontosan rajta | `n = 1` | átmegy, de az index `n=1` jelöléssel közli (egyetlen elem nem bizonyíték) |
| fölött | `n = 82` | átmegy, normál sor |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/recognition_baseline_manifest_test.dart
```

(§0.0/R1 — a parancs szó szerint a `gate_tests` listát tükrözi.)

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
6. `tools/round-gate.sh test/tooling/recognition_baseline_manifest_test.dart`.

## 9. Kockázatok

- ~~**A corpus a boxon hiányozhat** (`ml/data/klangio`) … `"unavailable-at-authoring"`~~
  — **TÁRGYTALAN a §0.0/R6 mérés szerint:** a corpus a boxon VAN (82 WAV), és a
  hash a reportból átvehető. Az `"unavailable-at-authoring"` érték kiírása ebben
  a körben hiba.
- A séma túl szigorú `additionalProperties: false`-a a későbbi körök
  metrikáit kizárhatja — ezért minden metrika-blokk `extra` objektumot kap.
- Az index és a report közti duplikáció drift-forrás — ezért az index
  kizárólag hivatkozik.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** `sonnet-impl` (Claude Sonnet 5). **Branch:**
`sonnet-impl/e14-r02-baseline-and-evidence-index`.

### 10.1 Mit szállít a kör

A brief `ai-router` §0.0/R8 engedélyezett-fájllistájának mind a hét sorát:

- `evaluation/recognition/baseline_manifest_schema.json` — draft-07 séma az
  `evaluation/analysis/manifest_schema.json` mintájára; hat metrika-blokk
  (`oneOf` `measured`/`not-measured` alakkal, §0.0/R4), `corpus`,
  `configuration`, `models`/`modelsRationale` (§0.0/R7), retracted `bpm`
  blokk (D4 `const true`).
- `evaluation/recognition/baseline_manifest.json` — a MÉRT számok
  (`docs/eval/real-audio-dsp-baseline.md`-ből, §3 szerint): `chord` és
  `onset` `measured` (27, ill. 9 metrika — a 12 per-label precision/recall is
  felvéve, opcionálisan, mert a report közli és minden számhoz van
  `sourceFile`+`command`), `direction`/`noChord`/`latency`/`calibration`
  `not-measured` a §0.0/R5 indoklásaival, `bpm` `retracted: true` a
  visszavont pengetés-sűrűség számmal ÉS a librosa-referenciás
  strict/tolerant egyezéssel.
- `tool/benchmarks/recognition_baseline_manifest.dart` — tiszta Dart
  (`dart:convert`+`dart:io` only), kézzel írt JSON-Schema-részhalmaz
  validátor (`type`/`required`/`additionalProperties`/`const`/`enum`/
  `oneOf`/`not`/`$ref`/`pattern`/`minimum`/`minLength`/`minItems`/
  `maxItems`/`minProperties`), determinisztikus Markdown-renderer
  (ábécésorrendbe rendezett kulcsok, `toStringAsFixed(3)`,
  `DateTime.now()` sehol), `--check` mód.
- `docs/eval/recognition-baseline-index.md` — a generátorral rendered
  (SOSEM kézzel írva), a `real-audio-dsp-baseline.md`-re és a
  `recognition-release-guard.md`-re hivatkozik, nem másolja a tartalmukat.
- `evaluation/recognition/README.md` — az `evaluation/analysis/README.md`
  mintájára.
- `test/tooling/recognition_baseline_manifest_test.dart` — 28 teszt, A1–A8
  csoport, a §6 mind a hat acceptance-pontjára és a §6.1 mérce-mátrix minden
  sorára (Map-bejárási sorrend, `DateTime.now()` önellenőrzés, hiányzó
  `command`/`sourceFile`, `n=0`/`n=1`/`n=82` numerikus küszöb-hármas,
  visszavont BPM-sor törlése, `models`/`modelsRationale` feltétel).

### 10.2 §7.1 Falszifikációs cella — MÉRT kimenet

A generátor mindkét `..sort()` hívását ideiglenesen eltávolítottam
(`tool/benchmarks/recognition_baseline_manifest.dart` — `blockKeys` és
`metricKeys` rendezése), majd lefuttattam a tesztet.

**PIROS** (`flutter test test/tooling/recognition_baseline_manifest_test.dart`,
sort() nélkül — tényleges terminálkimenet):

```
00:00 +12 -1: A4 — bitwise-identical re-runs: the renderer sorts, it does not
trust manifest authoring order (ADR 0354 D5, §6 AC2, §6.1 "Map traversal
order" / "raw toString()" matrix rows) two temp-directory runs fed the SAME
data with metric keys in DIFFERENT insertion order render byte-identical
index files — a generator that writes in Map traversal order instead of
sorting would fail this [E]
  ...
     Which: at location [1571] is <97> instead of <122>

00:00 +26 -2: A8 — the real, shipped manifest and the real, committed index
agree byte-for-byte right now (ties AC1/AC2/AC3 together on real data — a
"--check" run against the real repository files) rendering the real manifest
reproduces docs/eval/recognition-baseline-index.md exactly [E]
  ...
     Which: is different.
            Expected: ... s\n\n### calibration ...
              Actual: ... s\n\n### chord — mea ...
                                    ^
             Differ at offset 2066

00:00 +26 -2: Some tests failed.

Failing tests:
  test/tooling/recognition_baseline_manifest_test.dart: A4 — bitwise-identical
  re-runs: ... two temp-directory runs fed the SAME data with metric keys in
  DIFFERENT insertion order render byte-identical index files ...
  test/tooling/recognition_baseline_manifest_test.dart: A8 — the real,
  shipped manifest and the real, committed index agree byte-for-byte right
  now ... rendering the real manifest reproduces
  docs/eval/recognition-baseline-index.md exactly
```

Pontosan a két várt cella vált pirosra: az A4 (szándékosan eltérő
kulcs-beszúrási sorrendű, de tartalmilag azonos két fixture összevetése) és
az A8 (a valódi manifest renderelése már nem egyezik a lemezen lévő,
korábban ábécésorrendben generált indexszel — a `calibration` blokk most a
`chord` elé kerül, mert a `metricBlocks.keys` beszúrási sorrendje
`chord, onset, direction, noChord, latency, calibration`, rendezés nélkül).

Ezután mindkét `..sort()` hívást visszaállítottam.

**ZÖLD** (ugyanaz a parancs, visszaállítva):

```
00:00 +27: A8 — the real, shipped manifest and the real, committed index
agree byte-for-byte right now (ties AC1/AC2/AC3 together on real data — a
"--check" run against the real repository files) rendering the real manifest
reproduces docs/eval/recognition-baseline-index.md exactly
00:00 +28: All tests passed!
```

### 10.3 Záró mérce

```
tools/round-gate.sh test/tooling/recognition_baseline_manifest_test.dart
```

**Eredmény:** minden lépés ZÖLD — `format`, `analyze`, `test
test/tooling/recognition_baseline_manifest_test.dart` (28/28), `architecture`,
`secrets`, `l10n`. A `--result-json` nélküli futás konzolkimenete a fenti
lépéseket csonkítatlanul mutatta.

### 10.4 Scope-igazolás

`git status --porcelain` a kör végén pontosan az `ai-router` engedélyezett
hét fájlját mutatja (a `docs/rounds/e14-r02-*.md` ezt a §10-et kapja):
`evaluation/recognition/README.md`, `baseline_manifest.json`,
`baseline_manifest_schema.json`, `tool/benchmarks/recognition_baseline_manifest.dart`,
`test/tooling/recognition_baseline_manifest_test.dart`,
`docs/eval/recognition-baseline-index.md`. Tilos zónát (`lib/**`, `ml/**`,
`assets/**`, `docs/adr/**`, `docs/eval/real-audio-dsp-baseline.md`,
`.github/**`, `tools/**`, `pubspec.yaml`) nem érintettem.

## 11. Review — a Claude tölti ki
