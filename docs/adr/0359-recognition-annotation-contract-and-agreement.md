# ADR 0359 — A felismerési annotáció szerződése: a nyers hang érintetlen, a provenance kötelező, az átfedés hiba, az egyetértés mért szám

- **Státusz:** Elfogadva
- **Kör:** `E14-R07` (Chapter 14 — Recognition Accuracy & Useful UI Recovery, Kör 7)
- **Dátum:** 2026-09-04
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:** [ADR 0249](0249-analysis-evaluation-dataset-governance.md)
  (a repó sémát és annotációt tart, nyers audiót soha; `EvaluationManifestParser`
  típusos hiba-mintája), [ADR 0354](0354-recognition-baseline-manifest-and-evidence-index.md)
  (determinisztikus, bájtazonos mérési artefaktum),
  [ADR 0358](0358-consented-on-device-lab-capture-package.md)
  (az eszközön keletkező mérőcsomag, amit ez a kör annotál),
  [ADR 0054](0054-versioned-user-content-documents.md)
  (verziózott dokumentum: ismeretlen séma-verzió nem néma default)

## Kontextus — a pre-flight MÉRT tényei (2026-09-04, `main @ 1feecc11`)

- **A minta létezik és mérhető:**
  `lib/features/audio_analysis/data/evaluation/evaluation_manifest_parser.dart`
  egy `ManifestParseErrorKind` enumot (`missingAnnotation`, `unknownField`,
  `invalidChronology`, `duplicateCaseId`, `invalidSchemaVersion`,
  `malformedValue`) és egy `ManifestParseException(kind, message, {path})`
  típust használ, szigorú ismeretlen-kulcs ellenőrzéssel (`_checkKeys`), a séma
  pedig `evaluation/analysis/manifest_schema.json` (draft-07, `additionalProperties:
  false`, `schemaVersion` `const`). Ez a kör UGYANEZT a hármast (séma + típusos
  parser + CI-fixture) építi a felismerési annotációra — nem talál ki újat.
- **`evaluation/recognition/` MÁR LÉTEZIK** (`README.md`, `baseline_manifest.json`,
  `baseline_manifest_schema.json` — `E14-R02`/ADR 0354). A brief §2 „az E14-R02
  hozza létre" megfogalmazása tehát már teljesült; a `fixtures/` alkönyvtár új.
- **`lib/features/live/domain/` és `lib/features/live/data/` nem létezik**
  (`ls` → „No such file or directory"); a `live` feature ma `engine`, `model`,
  `providers`, `screens`, `widgets` könyvtárakból áll. Ez a kör hozza létre a két
  újat, az `audio_analysis` mintájára.
- **Nincs S5-típusnév-ütközés:** `RecognitionAnnotation`, `AnnotationEvent`,
  `AnnotationProvenance`, `Provenance`, `AgreementReport` egyike sem létezik a
  `lib/` és `tool/` fában (`grep -rn "class …|enum …"` → nulla találat).
- **A `live` barrel nem generált, és nem is válik elavulttá:** a generált
  barrel-ellenőrzés (`tool/check_architecture.dart:798` →
  `barrel.featuresWithPublicFragments`) csak azokra a feature-ökre fut,
  amelyeknek van `lib/features/<f>/public/` fragment-könyvtára
  (`tool/gen_public_barrel.dart:37-45`). A `lib/features/live/public/` **nem
  létezik**, a `public.dart` kézzel írott — új `domain/`/`data/` fájl tehát nem
  teszi elavulttá, és a `public.dart` (tilos zóna) érintése nem előfeltétel.
- **Az architektúra-őr csak a `lib/`-et méri** (`tool/check_architecture.dart:136`),
  ezért a `tool/` CLI és a teszt közvetlenül importálhatja az új fájlokat —
  pontosan úgy, ahogy a `tool/audio_analysis_evaluate.dart` ma is közvetlen
  útvonalon importálja az `evaluation_manifest_parser.dart`-ot.
- **A fixture-nyilvántartás nem terjed ki erre a fájlra:**
  `tool/check_fixture_manifest.dart:10` szerint a nyilvántartott korpusz a
  `test/fixtures/` fa, a `test/fixtures/manifest.json` ellenében. Az
  `evaluation/recognition/fixtures/annotation_pair.json` NEM oda tartozik, tehát
  sem bejegyzést nem kap, sem hiányzó bejegyzésként nem bukik el.
- **Az egress-felderítés a `lib/`-et nézi** (`tool/check_data_inventory.dart:431`),
  és ez a kör nem visz hálózati mintát a `lib/`-be — `docs/privacy/data-inventory.yaml`
  bejegyzés (tilos zóna) nem válik szükségessé.
- **A `StrumDirection` kétszer szerepel a fán:** `lib/core/music/strum.dart:5`
  (`down`, `up`) és `lib/features/audio_analysis/domain/analysis_event.dart:55`
  (`down`, `up`, `unknown`). A `core`-beli használata legális (feature → core nem
  kereszt-feature import); az `audio_analysis`-beli közvetlen importja
  architektúra-sértés lenne (`tool/check_architecture.dart:774`: kereszt-feature
  import csak `public.dart` barrelt célozhat).

## Döntés

### D1 — A nyers hang érintetlen

Az annotációs parser, a modell és a CLI kizárólag annotációt olvas és riportot
ír. WAV-ot vagy bármely hangfájlt **nem nyit írásra**, nem normalizál, nem
konvertál. A „konzisztencia kedvéért normalizáljuk a felvételt" megoldás
elutasítva: a mérés alapja a rögzített valóság, nem a hozzáigazított.

### D2 — A `provenance` kötelező mező, és soha nem lép elő

Minden annotált esemény kötelező `provenance` mezőt visel, felvehető értékei
`auto | human | reviewed`. A hiányzó mező **típusos hiba** (nem `null`, nem
default). A parser az `auto` értéket sosem konvertálja `human`-ná vagy
`reviewed`-dá — az előléptetés emberi aktus, amit az annotáció FORRÁSA rögzít,
nem a beolvasás mellékhatása. Mért indok: automatikus címke önmagában nem ground
truth (ADR 0249), és a „nem validált állítás visszavonva" szabály (E14-R01
release guard) csak akkor kikényszeríthető, ha a származás a típusban van.

### D3 — Átfedés és érvénytelenség: hiba, nem néma javítás

Két, ugyanarra a sávra eső, időben átfedő esemény esetén a parser típusos hibát
dob, amely **mindkét ütköző esemény indexét** tartalmazza. Tilos a csendes
feloldás: nem vág, nem von össze, nem sorrendez át. Indok: a néma javítás
elrejtené az annotáció hibáját, és a downstream mérés egy soha ki nem mondott
feltevésre épülne.

### D4 — Az egyetértés mért szám, a tolerancia paraméter

A két annotátoros riport onset-toleranciával párosít, és **külön** adja az
irány- és az akkord-címke egyezését. A tolerancia hívói paraméter (alapértéke
dokumentált), nem beégetett konstans. A határ **inkluzív**: a toleranciával
pontosan egyenlő eltérés még párosít (`<=`), a fölötte lévő nem. Az
egyetértési hányados nevezője a **párosított** események száma, nem az összes
esemény — a két mennyiség különbözik, és a keverésük néma torzítás.

### D5 — Determinisztikus kimenet

Ugyanaz a bemenet bájtra ugyanazt a riportot adja: kanonikus kulcsrend,
rendezett listák, semmilyen `DateTime.now()`, véletlen vagy környezetfüggő érték
a riport belsejében. Ez teszi a riportot diffelhető, dokumentumba másolható
bizonyítékká (ADR 0354 mintája).

### D6 — Nincs kereszt-feature függés

A `live` annotációs kód nem importálja az `audio_analysis` evaluation kódját. A
MINTA másolható, a FÜGGÉS nem: a kereszt-feature import csak `public.dart`
barrelt célozhat (`tool/check_architecture.dart:774`), az új típusok pedig nem
kerülnek a `live` barreljébe (nem publikus szerződés, csak mérőeszköz).

### D7 — A grafikus annotátor nem ebben a körben van

A séma, a validator és az egyetértés-mérés CLI-ként épül meg. A waveform/
spectrogram szerkesztő (húzható onset, undo/redo) külön kör (`E14-R07b`) — mért
ok: a repónak nincs desktop/web futtatási célja, és a gate egy GUI-t nem tud
vezetni, tehát a jelen kör acceptance-e nem hivatkozhat rá.

## Következmények

- Az annotáció verziózott, validált és visszakövethető artefaktummá válik, amire
  a Chapter 14 további körei (grouped harness, baseline dashboard) mérésként
  építhetnek.
- Az `auto` provenance-ú címkékből épülő „ground truth" a típusban válik
  megkülönböztethetővé — a release guard így nem csak dokumentált szabály.
- A két annotátoros egyetértés a mérés MEGBÍZHATÓSÁGÁRÓL ad számot: alacsony
  egyetértés esetén nem a modellt, hanem az annotációt kell javítani.
- Ára: a grafikus szerkesztő hiánya miatt az annotáció írása egyelőre kézi
  JSON-szerkesztés + `validate` futtatás. Ezt a `E14-R07b` oldja fel.
