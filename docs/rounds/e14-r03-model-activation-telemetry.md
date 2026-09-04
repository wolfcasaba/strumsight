# E14-R03 — Model activation telemetry és fail-visible működés

- **Státusz:** READY (pre-flight elvégezve 2026-09-04, kód ÚJRAMÉRVE: `main @ 4f293403`;
  előre megírva 2026-08-20, akkori olvasat: `main @ 7b5315b`)
- **Típus:** Chapter 14 (Recognition Accuracy & Useful UI Recovery), Kör 3
- **Kör-azonosító:** `E14-R03`
- **Branch:** `<motor>/e14-r03-model-activation-telemetry`
- **Előfeltétel:** `E14-R01` merge-elve (release guard). Az `E14-R02`-től
  FÜGGETLEN — a két kör fájlhalmaza diszjunkt, párhuzamosítható.
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `0355` — **a Claude írja meg, a `docs/adr/` a TILOS zónában van.**

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a
> `lib/features/live/engine/dsp/live_pipeline.dart` `_tryLiveCrnn` függvényét és
> a `lib/features/live/engine/ml/strum_crnn.dart` `tryLoad`-ját — a §2 sorszámai
> ezekre mutatnak. Ellenőrizd a `docs/eval/recognition-release-guard.md`
> „Activation contract" szakaszát is: az ott rögzített mezőnevek KÖTELEZŐEK.
> Eltérésnél §0.0 revízió.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/live/model/recognition_runtime_info.dart",
  "lib/features/live/engine/ml/model_activation.dart",
  "lib/features/live/engine/ml/strum_crnn.dart",
  "lib/features/live/engine/dsp/live_pipeline.dart",
  "lib/features/live/providers/live_lab_provider.dart",
  "lib/features/live/public.dart",
  "test/features/live/model_activation_test.dart",
  "test/features/live/recognition_runtime_info_test.dart",
  "docs/rounds/e14-r03-model-activation-telemetry.md",
]
gate_tests = [
  "test/features/live/model_activation_test.dart",
  "test/features/live/recognition_runtime_info_test.dart",
]
native_gate = false
```

## 0.0 Pre-flight revíziók (Claude, orchestrátor — 2026-09-04, `main @ 4f293403`)

Minden alábbi pont **mérve** van a fenti fán. A revíziók **szűkítenek** vagy
pontosítanak; az engedélyezett-fájllista NEM bővült.

### R1 — `StrumCrnn.tryLoad` szignatúrája NEM változhat (H3-elkerülés) — SZŰKÍTÉS

A §3.2 eredeti előírása („a `tryLoad`/`_tryLiveCrnn` ezt adja vissza `null`
helyett") a mai fán a **tilos zónába** kényszerítene. Mérve — hat, a listán
KÍVÜL élő teszt pinneli a mai `StrumCrnn?` visszatérést:

| Fájl:sor | Mit pinnel |
|---|---|
| `test/property/crnn_ab_property_test.dart:38` | `final crnn = StrumCrnn.tryLoad('assets/ml/strum_crnn.bin');` |
| `test/property/crnn_ab_property_test.dart:115-116` | `expect(StrumCrnn.tryLoad('assets/ml/nope.bin'), isNull);` |
| `test/tools/crnn_detected_time_probe_test.dart:20` | `StrumCrnn.tryLoad(…)!` |
| `test/tools/klangio_real_ab_test.dart:82` | `StrumCrnn.tryLoad(…)!` |
| `test/tools/crnn_cost_and_batch_calibration_test.dart:92` | `StrumCrnn.tryLoad(…)!` |
| `test/tools/crnn_shift_sweep_test.dart:20` | `StrumCrnn.tryLoad(…)!` |

**Kötelező alak (ADDITÍV):**

```dart
static ModelActivation activate(String path) { … }        // ÚJ, típusos belépő
static StrumCrnn? tryLoad(String path) => activate(path).model;  // MEGMARAD
```

A `tryLoad` viselkedése bitre változatlan (hiány/sérülés → `null`), tehát a hat
fenti teszt-fájl **érintetlen** marad. A `tryLoad` átírása, törlése vagy
szignatúra-változtatása ebben a körben **`stopped`-ot érő scope-sértés**.

### R2 — `_tryLiveCrnn` szabadon átköthető

Mérve (`grep -rn "_tryLiveCrnn" lib/ test/ tool/`): kizárólag
`live_pipeline.dart:21` (definíció) és `:60` (egyetlen hívó, ugyanabban a
fájlban). Privát, fájlon kívülről nem pinnelt → typed eredményre cserélhető.

### R3 — A Lab NEM érheti el a pipeline runtime-infóját ebben a körben — SZŰKÍTÉS

Mérve: a `LivePipeline` a **DSP-izolátumban** jön létre
(`lib/features/live/engine/real_strum_engine.dart:167` `_DspInit`, `:220`
`_dspEntry` → `LivePipeline(...)`), a `LiveLabController` viszont a
`strumEngineProvider`-t olvassa, és a `StrumEngine` seam
(`lib/features/live/engine/strum_engine.dart`) **nem hordoz** runtime-információt
(mérve: a 6 tagja `frames`, `start`, `stop`, `setExpectedChord`,
`setDiagnosticsCapture`, `recentPcm`, `dispose`). Az izolátum → UI átvitel a
`real_strum_engine.dart` **és** a `strum_engine.dart` módosítását kívánná — mindkettő
a **tilos zónában** van (§4) → H3.

**Ezért a kör hatóköre:**

1. a `LivePipeline` **közzéteszi** a runtime infót egy szinkron getterrel
   (`RecognitionRuntimeInfo get runtimeInfo`), a konstruktorban EGYSZER
   kiszámolva — a per-frame útvonalra nem kerül semmi (§9);
2. a `LiveLabState` **additív** `RecognitionRuntimeInfo? runtimeInfo` mezőt kap,
   a `LiveLabController` pedig egy `reportRuntimeInfo(RecognitionRuntimeInfo?)`
   belépőt, amely csak az állapotot frissíti;
3. a **tényleges izolátum → Lab bekötés KIMONDOTTAN elhalasztva** az
   `E14-R04`-re (az a kör szabja át a `LiveFrame` szerződését — ez a §3 „Nincs
   benne" sora), és a `live_lab_panel.dart` megjelenítése szintén nem ezé a köré
   (a fájl nincs az engedélyezett listán).

A 6/5. acceptance-pont mércéje ennek megfelelően **a Lab-állapot megkülönböztető
képessége**: az `activated` és a `fallback` infót hordozó `LiveLabState` mérhetően
különbözik, és az alapállapot `runtimeInfo` mezője `null`.

### R4 — A redakciós cella KANÁRI-próba, nem kulcsnév-lista (L260)

`docs/LESSONS.md` L260 (E06-R26): egy fix kulcskészletű DTO ellen a
`forbiddenKeys.any((k) => json.contains('"$k"'))` alakú teszt **konstrukció
szerint mindig zöld** — a tényleges szivárgás az ÉRTÉK-oldalon van.

**Kötelező cella a 4. acceptance-ponthoz:** olyan úton kell fallbacket
provokálni, amelynek van egy egyedi, felismerhető útszegmense (pl.
`Directory.systemTemp` alatt létrehozott `strumsight_canary_<n>` könyvtár), és
a cellának azt kell mérnie, hogy sem a `toString()`, sem a `toJson()`
**értékei** nem tartalmazzák ezt a szegmenst (és a temp-gyökér nevét sem).
Kulcsnév-tiltólistás állítás önmagában NEM elégíti ki a 4. pontot.

### R5 — A `public.dart` NEM generált ehhez a feature-höz

A §9 „a `public.dart` barrel generált lehet" kockázata **mérve tárgytalan**:
`lib/features/live/public/` **nem létezik**, és a `tool/gen_public_barrel.dart`
kizárólag a `lib/features/<feature>/public/*.dart` fragmentekből dolgozik (a
fában egyedül a `practice_generator` használja). A `lib/features/live/public.dart`
tehát **kézzel írt** barrel: additív `export` sort kézzel adj hozzá, generátort
NE futtass.

### R6 — A release-guard „Activation contract" nem ír elő mezőnevet ehhez a modellhez

A brief fejlécének „az ott rögzített mezőnevek KÖTELEZŐEK" mondata mérve
szűkebb, mint ahogy hangzik. `docs/eval/recognition-release-guard.md:21-38`
artefaktumokat sorol (evaluation report, baseline manifest, candidate model
manifest, corpus identity, rollback recipe); a nevesített mezők
(`corpus SHA-256`, `model SHA-256`, app commit, konfiguráció, mérési parancs) a
**baseline manifestre** vonatkoznak, amit az `E14-R02` definiál. Egyetlen kötés
öröklődik ide: a modell azonosságát **SHA-256** hordozza → `strumModelSha256`,
a ténylegesen betöltött bájtokból számolva (§5.5). Más mezőnév innen nem
kötelező.

### R7 — A `strumModelId` / `strumModelVersion` mért forrása

- `assets/ml/model_manifest.json` (`schema_version: 1`) minden modellhez
  `filename`, `path`, `sha256`, `format`, `format_version`, `input_shape`,
  `output_classes` mezőt hord.
- A **live** út a 3 osztályos assetet preferálja
  (`real_strum_engine.dart:187-196`): `assets/ml/strum_crnn_live_3c.bin`
  (`output_classes: [down, up, no-strum]`), fallbackje a 2 osztályos
  `strum_crnn_live.bin`. A **batch/Analyze** út assete `assets/ml/strum_crnn.bin`
  (`[down, up]`).
- A bináris fejléc-szerződése (`crnn_strum_net.dart:35-53`):
  `SSML` magic (4 bájt) | `u32 version` (== 1) | `u32 count` | tömbök.
  A `CrnnStrumNet.nClasses` (`:32`) a `dense_b` első dimenziója — **ez** a
  3-osztályosság mért forrása, nem a fájlnév.

**Kötés:** a `strumModelId` az asset FÁJLNEVE (a manifest `filename` kulcsával
egyező sztring, út NÉLKÜL — lásd R4), a `strumModelVersion` a **bájtokból**
olvasott `format_version`. Egyik sem a manifestből átvett érték (§5.5).
Az 1. acceptance-pont „3-osztályos CRNN"-je a live assetre
(`strum_crnn_live_3c.bin`, `nClasses == 3`) vonatkozik.

### R8 — A hibakód-osztályozás determinisztikus, nem kivétel-szövegre illesztés

Az öt kód mért előállítási szabálya (§5.2 tiltja a kivétel-szöveg
továbbadását, tehát a `FormatException` üzenetére illeszteni is tilos):

| Kód | Mikor |
|---|---|
| `assetMissing` | a bájtok nem állnak elő: a fájl nem létezik, vagy a hívó `null` bájtsort adott |
| `assetUnreadable` | a fájl létezik, de az olvasás dob (jogosultság, könyvtár, csonka I/O) |
| `parseFailed` | a fejléc rossz: a magic nem `SSML`, vagy a `version != 1` — a `strum_crnn.dart` a saját maga olvasott 4+4 bájtjából dönti el, a `parse` hívása ELŐTT |
| `shapeMismatch` | a fejléc rendben van, de a `CrnnStrumNet.parse` dob (hiányzó tömb, rossz dimenzió) |
| `disabledByFlag` | a hívó KIFEJEZETTEN letiltotta a modellt — a `ModelActivation.disabled(info)` gyártófüggvénnyel |

A fejléc 8 bájtjának ellenőrzése a `strum_crnn.dart`-ban a bináris szerződés
tudatos, dokumentált mini-duplikációja (ADR 0355 „Negatív / ár").

**A `disabledByFlag` bekötése NEM ezé a köré:** a `lib/app/config/feature_flags.dart`
és a `lib/core/feature_flags/**` a tilos zónában van, a három recovery-flag
(`recognitionRecoveryEnabled`, `recognitionShadowModeEnabled`,
`newLiveStageEnabled`) pedig az `ADR 0271` szerint `false` marad. A kör a
**stabil kódot és a gyártófüggvényt** vezeti be és méri; a flag-olvasást egy
későbbi kör köti be.

### R9 — Sorszám-drift a §2-ben (nem tartalmi)

Mérve `main @ 4f293403`-on: `strum_crnn.dart` `tryLoad` **26-36** (a brief 28-35-öt
ír); `live_pipeline.dart` `_tryLiveCrnn` **21-31** (a brief 21-30-at ír), a
`classifier:` mező a **60.** sor (a brief `:58-60`-at ír).
Változatlanul igaz: `live_frame.dart` **11 mező**;
`strum_direction_classifier.dart:54` `abstract class StrumDirectionClassifier`.

### R10 — ADR-szám: `0355` marad

`docs/adr/0355-*.md` nem létezik (a sávban `0353` a legmagasabb kiadott), a
foglaló (`tools/round-slots.py reserve-adr`) pedig `0504`-től ad számot, tehát a
queue-ban a Chapter 14 sávnak előre kiosztott `0354`–`0361` tartomány gépileg
elérhetetlen bármely másik kör számára — ütközés kizárva. A queue-sor, a brief
§5 és a kör-prompt egyaránt `0355`-öt mond, ezért az marad. A pre-flight során
véletlenül létrejött `0504`/`0505` foglaló-markerek törölve.
**Az ADR megírva:** `docs/adr/0355-fail-visible-model-activation-telemetry.md`.

### R11 — S12 brief-lint (strict): a §7 gate-parancs tükrözi a `gate_tests`-t

A `.pipeline/brief-lint-E14-R03.md` egyetlen leletét a §7 átírása oldja fel; a
`gate_tests` mindkét eleme szó szerint szerepel a parancsban, kiegészítve a
`test/features/live` regressziós útvonallal (a kör a `live_pipeline.dart`-hoz és
a Lab-hoz nyúl, amelyeket a `test/features/live/dsp/*` és
`test/features/live/ml/*` tesztek pinnelnek).

### R12 — Párhuzamos kör

Az `E14-R02` egyidejűleg fut (`.pipeline/inflight/`). A két `allowed_paths`
halmaz **mérve diszjunkt** (az R02 az `evaluation/`, `tool/benchmarks/`,
`test/tooling/`, `docs/eval/recognition-baseline-index.md` és a SAJÁT briefje
alatt dolgozik). A másik kör ágát, PR-jét és munkapéldányát nem érintjük.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

**Legyen megfigyelhető, melyik felismerő fut.** Ma a Live pipeline némán
visszaesik a heurisztikus irányosztályozóra, ha a CRNN-súly nem tölthető be —
a fejlesztő és a tesztelő nem tudja megmondani, mit mért (SDD Ch14 Kör 3).

Ez a kör **nem javít felismerési pontosságot**, és **nem cserél modellt**: a
fallback VISELKEDÉSE bitre marad. Csak láthatóvá tesszük.

**Kockázat = high, indoklás:** a kör telemetriát és strukturált naplózást vezet
be a modellbetöltés köré, tehát a diffje közvetlenül érinti azt a határt, ahol
fájlrendszer-út, kivétel-szöveg vagy audio-metaadat kiszivároghat egy exportba
(§5.2, §5.4). A router `high_risk_path_fragments` listája ezt az útvonalat
névből nem fogja meg, ezért az indoklás itt, explicit módon áll.

### 1.1 Visszakeresett előzmény (ADR 0312)

- **L06 — „az elnyelt hiba néma no-op"**, és **L28** (a zöld gate mellett
  becsempészett néma osztályok): ez a kör pontosan ennek a hibaosztálynak a
  felismerési oldala.
- **ADR 0271 §1** (`UNKNOWN > CONFIDENTLY WRONG`): a hiányzó bemenet sosem
  álcázható sikeres eredménynek — a fallback tény, amit ki kell mondani.

**Pre-flight visszakeresés (2026-09-04, `node tools/knowledge-rag.mjs`,
szűkített → teljes sorrendben):**

- `lessons/L06` — „minden csendes fallback gyanús" (bm25#1 emb#2 a
  `--corpus lessons,halts,adr` ágon) — ez a kör tárgya.
- `adr/0292` — „Modell csak igazolt integritással aktiválható" (bm25#3 emb#1):
  a szomszédos, szigorúbb döntés. A §5.5 mért hash-e ennek a mérési oldala;
  ez a kör NEM lazítja (a hiány/sérülés után továbbra sincs aktiválás).
- `lessons/L260` — „a kulcsnév-listás redakciós teszt vakon zöld marad; a
  szivárgás az ÉRTÉK-oldalon van, és csak célzott kanári-próba fogja meg"
  (bm25#1 emb#2 a `--corpus lessons,halts` ágon) — a 4. acceptance-pont
  mércéjét ez írja elő, lásd az R4 revíziót.

## 2. Jelenlegi állapot — mért tények

- `lib/features/live/engine/ml/strum_crnn.dart:28-35` — `StrumCrnn.tryLoad`:
  `try { … } catch (_) { return null; }`. A hívó „fall back to the heuristic,
  never crash" kommenttel él; **az OK sehol nem marad meg**.
- `lib/features/live/engine/dsp/live_pipeline.dart:21-30` — `_tryLiveCrnn`:
  ugyanez a minta (`catch (_) { return null; // fall back to the heuristic,
  never fail the pipeline }`), a `classifier:` mező null lesz (`:58-60`).
- **Nincs egyetlen mező sem** a `LiveFrame`-ben (`lib/features/live/model/
  live_frame.dart`, 11 mező), amely megmondaná, melyik osztályozó adta a
  verdiktet, vagy hogy fallback fut-e.
- `lib/features/live/providers/live_lab_provider.dart` — a Lab az
  `AnalyzeResult`-ot mutatja (`LiveLabState.result`), runtime-információt nem.
- `StrumDirectionClassifier` absztrakt (`…/dsp/strum_direction_classifier.dart:54`),
  tehát a „melyik implementáció aktív" kérdés a típusból megválaszolható —
  ma senki nem kérdezi meg.

## 3. Scope

**Benne:**

1. `RecognitionRuntimeInfo` — Flutter-független, immutable modell: `strumModelId`,
   `strumModelVersion`, `strumModelSha256`, `chordEngineId`, `fallbackReason`
   (nullable), `sampleRate`, `frontendVersion`.
2. `ModelActivation` — a betöltés eredménye TÍPUSOSAN: `activated(model, info)`
   vagy `fallback(reason, info)`. Az ÚJ `StrumCrnn.activate` és a privát
   `_tryLiveCrnn` ezt adja vissza `null` helyett; a **hívó viselkedése
   változatlan** (fallback esetén a heurisztika fut). **A `tryLoad` MEGMARAD**
   `StrumCrnn?`-t adó delegálásként — lásd az R1 revíziót (hat, a listán kívüli
   teszt pinneli).
3. A `fallbackReason` **stabil, gépi hibakód-halmazból** jön:
   `assetMissing`, `assetUnreadable`, `parseFailed`, `shapeMismatch`,
   `disabledByFlag`. Nem szabad szöveget továbbadni a kivételből.
4. A pipeline a `RecognitionRuntimeInfo`-t közzéteszi (a Lab és a lokális
   accuracy-export számára).
5. Lab-felület: a `LiveLabState` hordozza a runtime infót.

**Nincs benne (TILOS):** a heurisztika vagy a CRNN döntési logikájának bármely
módosítása; DSP/ML konstans, küszöb, modell-bináris (AGENTS.md §9); a
`LiveFrame` mezőinek átszabása (az az `E14-R04` dolga); UI-redesign; új asset;
`docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/live/model/recognition_runtime_info.dart` | új, Flutter-független modell |
| `lib/features/live/engine/ml/model_activation.dart` | a típusos betöltési eredmény |
| `lib/features/live/engine/ml/strum_crnn.dart` | `tryLoad` → typed eredmény (viselkedés változatlan) |
| `lib/features/live/engine/dsp/live_pipeline.dart` | `_tryLiveCrnn` + a runtime info közzététele |
| `lib/features/live/providers/live_lab_provider.dart` | a Lab megmutatja a runtime infót |
| `lib/features/live/public.dart` | additív export |
| `test/features/live/model_activation_test.dart` | aktiváció + fallback mátrix |
| `test/features/live/recognition_runtime_info_test.dart` | modell-szerződés, redakció |
| `docs/rounds/e14-r03-model-activation-telemetry.md` | §10 handoff |

**Tilos zóna:** minden más — kiemelten `lib/features/live/engine/dsp/*.dart` a
felsoroltakon kívül, `assets/**`, `ml/**`, `docs/adr/**`, `docs/rag/chunks/**`,
`.github/workflows/**`, `tools/round-gate.sh`.

## 5. Kötött architekturális döntések (ADR 0355)

### 5.1 A fallback VISELKEDÉSE nem változik

A modell hiánya vagy sérülése után továbbra is a heurisztika fut, kivétel nélkül.
**NEM elfogadható gyengítés:** a hiba „fail-fast" dobássá alakítása, vagy a
fallback kivétele azzal az indokkal, hogy „így legalább látszik a hiba". A
fail-visible ≠ fail-fast: a felhasználó élménye változatlan, a *diagnosztika*
javul.

### 5.2 A hibaok gépi kód, nem szöveg

A `fallbackReason` zárt enumból jön. **NEM elfogadható gyengítés:** a
`catch (e)` kivétel `toString()`-jének továbbadása — az platform- és
lokalizáció-függő, és titkot (útvonalat) szivárogtathat.

### 5.3 Production nem mutat technikai hibaszöveget

A `fallbackReason` a Labban és a lokális accuracy-exportban jelenik meg; a
production Live UI **változatlan** marad ebben a körben.

### 5.4 Nincs PII, token vagy audio a logban/exportban

A `RecognitionRuntimeInfo` kizárólag modell-metaadatot hordoz. A teszt
kimondottan ellenőrzi, hogy a `toString()`/JSON nem tartalmaz fájlrendszer-utat.

### 5.5 A modellazonosság MÉRT, nem feltételezett

A `strumModelSha256` a ténylegesen betöltött bájtokból számolt hash — nem a
manifestből átvett érték.

## 6. Acceptance criteria

1. **Teszt bizonyítja, hogy a valós asset betöltésekor a 3-osztályos CRNN
   aktív:** `StrumCrnn.activate('assets/ml/strum_crnn_live_3c.bin')` →
   `activated`, a betöltött háló `nClasses == 3`, a `strumModelId`
   `'strum_crnn_live_3c.bin'`, a `strumModelSha256` a fájl bájtjaiból számolt
   hash, és a `fallbackReason` `null` (R7).
2. **Hibás asset → `fallback`**: mind az öt hibakódra van cella (hiányzó fájl,
   olvashatatlan fájl, parse-hiba, alak-eltérés, flag-tiltás), és mindegyik
   STABIL kódot ad.
3. Fallback esetén a pipeline **továbbra is verdiktet ad** (a heurisztika fut) —
   a teszt ugyanazt a kimenetet méri, mint a kör előtt.
4. A `RecognitionRuntimeInfo` JSON round-trip zöld, és a szerializált alak
   **nem tartalmaz** abszolút útvonalat, tokent vagy audiomintát — a mércéje a
   **kanári-próba** (R4), nem kulcsnév-lista.
5. A `LiveLabState` hordozza a runtime infót (additív, nullable mező +
   `reportRuntimeInfo` belépő, R3); a teszt megkülönbözteti az `activated` és a
   `fallback` infót hordozó állapotot, és az alapállapot `runtimeInfo`-ja `null`.
   A tényleges izolátum → Lab bekötés az `E14-R04` köre.
6. `lib/features/live/public.dart` additívan exportál — meglévő export nem
   tűnik el.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `catch (_)` marad, a typed eredmény csak „ismeretlen hiba"-t ad | 2. pont: az öt hibakód mátrixa (mind ugyanazt a kódot adná) |
| A `fallbackReason` a kivétel `toString()`-je | 4. pont: a redakciós cella (útvonal szivárog a JSON-be) |
| A fallback ág fail-fast dobásra cserélve | 3. pont: a heurisztikus verdikt-cella (nincs kimenet) |
| A hash a manifestből másolva, nem a bájtokból | 1. pont: a sérült-de-parse-olható asset esetén a hash nem változik |
| A `public.dart` újraírva (nem additív) | 6. pont: a meglévő export eltűnésének cellája |
| A runtime info csak a pipeline privát mezője | 5. pont: a Lab-állapot cellája |

**Numerikus küszöb — nincs, és ez szándékos.** A betöltés kimenete BINÁRIS (a
súly betölthető vagy nem), ezért a küszöb-hármas itt **degenerált**: nincs
„alatta / rajta / fölötte" harmadik eset, a határ két oldala maga a
`activated` / `fallback` cella, amit a 2. acceptance-pont mátrixa mér. Küszöböt
ez a kör nem vezet be és nem hangol (AGENTS.md §9).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/live/model_activation_test.dart test/features/live/recognition_runtime_info_test.dart test/features/live
```

A parancs a `gate_tests` **mindkét** elemét szó szerint tartalmazza (S12), és
utánuk a `test/features/live` regressziós útvonalat — a kör a
`live_pipeline.dart`-hoz nyúl, amit a `test/features/live/dsp/live_pipeline_test.dart`,
`.../dsp/tonalness_test.dart`, `.../dsp/voice_rejection_test.dart` és
`.../ml/live_pipeline_ml_wiring_test.dart` pinnel.

Külön processzben futó `format` → `analyze` → célzott teszt → `architecture`
(AGENTS.md §12). `&&` láncolás tilos (L05/L09). CI-dispatch/PR/merge
Claude-oldal.

### 7.1 Falszifikációs cella

A 3. ponthoz: a §10-ben dokumentáld, hogy a heurisztikus ág ideiglenes
elrontásával (pl. a classifier null-ellenőrzés megfordítása) a cella **PIROS**,
majd visszaállítva **ZÖLD** — a fallback-viselkedés tehát ténylegesen mérve van,
nem csak állítva.

## 8. Implementációs sorrend

1. `RecognitionRuntimeInfo` + teszt (szerződés, redakció).
2. `ModelActivation` típus + az öt hibakód.
3. `strum_crnn.dart` / `live_pipeline.dart` átkötése (viselkedés változatlan).
4. Lab-állapot.
5. `public.dart` additív export.
6. `tools/round-gate.sh test/features/live`.

## 9. Kockázatok

- A `live_pipeline.dart` a Live út forró kódja: a typed eredmény **nem
  kerülhet** a per-frame útvonalra (betöltéskor egyszer fut). Ha a mérés
  CPU-növekedést mutat, az blokkoló.
- A `public.dart` barrel generált lehet — ha igen, a generátort kell futtatni,
  nem kézzel írni (lásd a repó `tool/gen_public_barrel.dart` eszközét).
- Az asset-fixture-ök mérete: sérült asset szimulálásához **ne** kerüljön új
  bináris a repóba — bájtmódosítást futásidőben, ideiglenes fájlban végezz.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), 2026-09-04, ág:
`sonnet-impl/e14-r03-model-activation-telemetry`.

### Mit vezettünk be

- `lib/features/live/model/recognition_runtime_info.dart` (ÚJ) —
  `FallbackReason` (5 zárt kód) + `RecognitionRuntimeInfo` (Flutter-független,
  `==`/`hashCode`/`toJson`/`fromJson`/`toString`), plusz a
  `RecognitionRuntimeInfo.fallback(reason, sampleRate:)` gyártófüggvény — az
  EGYETLEN hely, ahol a "nincs aktivált modell" alak (`strumModelId: 'none'`,
  `strumModelVersion: 0`, `strumModelSha256: ''`) előáll, így egyetlen
  fallback-ág sem tud útszegmenst szivárogtatni (R4).
- `lib/features/live/engine/ml/model_activation.dart` (ÚJ) —
  `ModelActivation<T>` (`activated`/`fallback`/`disabled` gyártófüggvények,
  konzisztencia-`assert`-ekkel).
- `lib/features/live/engine/ml/strum_crnn.dart` — `StrumCrnn.activate(path)`
  (ÚJ, típusos), `StrumCrnn.activateBytes(bytes, modelId:, sampleRate:)` (ÚJ,
  a fájl- és a bájt-alapú betöltés közös magja — a fejléc 8 bájtját saját
  maga ellenőrzi a `CrnnStrumNet.parse` hívása ELŐTT, R8), `nClasses` getter
  (ÚJ, a betöltött háló osztályszáma), `tryLoad` MEGMARADT
  `StrumCrnn?`-t adó delegálásként (`activate(path).model`) — a hat, listán
  kívüli tesztfájl (R1) érintetlen.
- `lib/features/live/engine/dsp/live_pipeline.dart` — a korábbi
  `_tryLiveCrnn` helyett `_activateLiveCrnn` (típusos, `ModelActivation`-t ad
  vissza); a `LivePipeline` konstruktora `factory`-vá vált, ami az
  aktivációt EGYSZER számolja ki és egy privát `LivePipeline._`
  konstruktornak adja tovább (a publikus hívási alak — névvel ellátott
  paraméterek — változatlan, a 6 érintett regressziós tesztfájl nem
  módosult); ÚJ `RecognitionRuntimeInfo get runtimeInfo` getter (szinkron,
  a konstruktorban egyszer kiszámolt értéket adja vissza).
- `lib/features/live/providers/live_lab_provider.dart` — `LiveLabState`
  additív `runtimeInfo` mező, `LiveLabController.reportRuntimeInfo(info)` ÚJ
  belépő (csak az állapotot frissíti). A tényleges izolátum → Lab bekötés
  KIMONDOTTAN elhalasztva E14-R04-re (R3).
- `lib/features/live/public.dart` — additív `export
  'model/recognition_runtime_info.dart';` (a meglévő 3 export
  változatlan).

### Falszifikációs bizonyíték (§7.1, a 3. acceptance-ponthoz)

A `LivePipeline._` konstruktorban a `classifier: crnnActivation.model,` sort
ideiglenesen `classifier: crnnActivation.model!,` alakra írtam (a
null-ellenőrzés megfordítása — a fallback ág "elrontása" úgy, hogy sikertelen
aktivációkor a heurisztika helyett kivétel repedjen ki). Futtatás:
`flutter test test/features/live/model_activation_test.dart
test/features/live/ml/live_pipeline_ml_wiring_test.dart`:

```
00:00 +8 -1: .../model_activation_test.dart: 3. fallback preserves pipeline behaviour (heuristic still verdicts) garbage weights bytes -> heuristic still verdicts a real strum [E]
  Null check operator used on a null value
  package:strumsight/features/live/engine/dsp/live_pipeline.dart 108:42  new LivePipeline._
...
Failing tests:
  .../ml/live_pipeline_ml_wiring_test.dart: garbage bytes -> heuristic, never a crash (model is an upgrade)
  .../ml/live_pipeline_ml_wiring_test.dart: no bytes -> heuristic (mock mode, stripped builds)
  .../model_activation_test.dart: 3. ... garbage weights bytes -> heuristic still verdicts a real strum
  .../model_activation_test.dart: 3. ... no weights -> heuristic, runtimeInfo says assetMissing
```

— PIROS, pontosan a fallback-cellákon (4 teszt bukott, a nem-fallback
tesztek zöldek maradtak). A sort visszaállítottam
(`classifier: crnnActivation.model,`), `git diff` üres volt utána, és a
gate újrafutása (lásd lent) ZÖLD.

### A gate tényleges kimenete

```
tools/round-gate.sh test/features/live/model_activation_test.dart test/features/live/recognition_runtime_info_test.dart test/features/live
```

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD
    → [3] test test/features/live/model_activation_test.dart: ZÖLD  (12/12)
    → [4] test test/features/live/recognition_runtime_info_test.dart: ZÖLD  (9/9)
    → [5] test test/features/live: ZÖLD  (204 passed, 2 golden ~skip)
    → [6] architecture: ZÖLD
    → [7] secrets: ZÖLD
    → [8] l10n: ZÖLD

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

### Amit szándékosan NEM tettünk meg

- A `disabledByFlag` bekötése a feature-flag olvasásához (R8) — a gyártófüggvény
  (`ModelActivation.disabled`) létezik és tesztelt, de semmilyen production hívó
  nem használja még.
- Az izolátum → Lab tényleges bekötés (`real_strum_engine.dart`,
  `strum_engine.dart` — mindkettő tilos zóna, R3) — `LiveLabController.
  reportRuntimeInfo` létezik és tesztelt, de production hívó még nincs.
- A `strumModelId` a live (isolate) úton `'live-crnn'` placeholder marad
  (nem a valódi asset fájlnév) — az izolát-határ ma nem hordozza a nevet
  (R3); a `StrumCrnn.activate(path)` úton (batch/Analyze, teszt 1.
  acceptance-pont) a valódi fájlnév megy át.

## 11. Review — a Claude tölti ki
