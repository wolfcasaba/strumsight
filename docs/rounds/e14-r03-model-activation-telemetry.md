# E14-R03 — Model activation telemetry és fail-visible működés

- **Státusz:** PREPARED (előre megírva 2026-08-20, kód olvasva: `main @ 7b5315b`)
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
   vagy `fallback(reason, info)`. A `tryLoad`/`_tryLiveCrnn` ezt adja vissza
   `null` helyett; a **hívó viselkedése változatlan** (fallback esetén a
   heurisztika fut).
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
   aktív:** az aktiváció `activated`, a `strumModelId` a valós modell id-je, és
   a `fallbackReason` `null`.
2. **Hibás asset → `fallback`**: mind az öt hibakódra van cella (hiányzó fájl,
   olvashatatlan fájl, parse-hiba, alak-eltérés, flag-tiltás), és mindegyik
   STABIL kódot ad.
3. Fallback esetén a pipeline **továbbra is verdiktet ad** (a heurisztika fut) —
   a teszt ugyanazt a kimenetet méri, mint a kör előtt.
4. A `RecognitionRuntimeInfo` JSON round-trip zöld, és a szerializált alak
   **nem tartalmaz** abszolút útvonalat, tokent vagy audiomintát.
5. A `LiveLabState` hordozza a runtime infót; a Lab-teszt megkülönbözteti az
   `activated` és `fallback` esetet.
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
tools/round-gate.sh test/features/live
```

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

## 11. Review — a Claude tölti ki
