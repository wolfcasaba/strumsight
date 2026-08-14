# E99-R10 (GOV-30c-2) — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** `E99-R10` (GOV-30c-2) — a V2 elemzőlánc értékelő fele
- **Branch:** `codex/e99-r10-gov-30c-2-evaluation-stage-composition`
- **Diff:** `8c41612d..e49c5ee0` (6 fájl, +934/−3) — 2 production Dart, 3 teszt, 1 brief
- **ADR:** 0251 · **Reviewer:** Claude (security-reviewer, READ-ONLY) · **Dátum:** 2026-08-14
- **A review kötelező:** a brief `ai-router` blokkja `risk = "high"` (AGENTS.md §15.1) — a diff hálózat/tárolás-érintettségétől függetlenül

## Verdikt: **PASS** — merge biztonsági alapon nem blokkolt

| Súlyosság | Darab |
|---|---|
| CRITICAL | 0 |
| BLOCKER | 0 |
| MAJOR | 0 |
| MINOR | 0 |
| NOTE (előremutató, GOV-30c-3) | 2 |

A kör tisztán in-memory, pure-Dart adaptereket ad egy már review-zott `AnalysisWorkState`-hez. **Nincs futásidejű elérési útja:** az `analysisV2RunnerProvider` a kör után is `StateError`-t dob (`lib/features/audio_analysis/application/analysis_providers.dart:213-218`, a fájl nincs a diffben), a `buildEvaluationStages()` és az új stage-osztályok egyetlen production hívóval sem rendelkeznek (grep: kizárólag a két tesztfájl hivatkozik rájuk). A kód halott a GOV-30c-3 bekötő körig.

---

## Önálló ellenőrzés 1 — az üres-referencia invariáns (ADR 0251 §2)

**Állítás, amit függetlenül igazoltam:** nincs kódút, ahol `target.expectedEvents.isEmpty` mellett az injektált `_align` meghívódna, vagy ahol hamis/üres illesztés „sikeresként" jutna tovább `hasReferenceTarget=false` jelzés nélkül.

**Bizonyíték (`engine/stages/evaluation_stages.dart`):**
- `AlignmentEvaluationStage.run()` :138-146 — a kapu `if (target == null || target.expectedEvents.isEmpty) return input;` (:139) az egyetlen `_align(...)` hívási hely (:140) **elé** kerül. A `_align` mező pontosan egyszer hivatkozott, a kapun belül — más elérési út nincs.
- `_hasReferenceTarget()` :472-473 → `target?.expectedEvents.isNotEmpty ?? false`, tehát **null-target ÉS üres-expected esetén is `false`**. Ez az érték jut a `CapabilityResolver`-hez (:414), amely a target-capability-ket `unavailable` / `noReferenceTarget` okkal jelöli (`confidence/capability_resolver.dart:189-195`).

**Miért kritikus a kapu (mért, nem elhitt):** az `EventAligner.align()` **nem véd önmagában**. Üres `expected`-del meghívva (`engine/alignment/event_aligner.dart:22-145`) nem dob, hanem hihető `AlignmentResult`-ot ad `confidence == 0.0`-val (:119-125), `missedExpected == []`, `extraObserved == observed` — pontosan az ADR által tiltott „hamis 0%". A stage kapuja tehát az **egyetlen** védelem, és a helyén van.

**Teszt-fedettség (nem dekoratív):** `evaluation_stages_test.dart:14-37` (A6) — injektált illesztő **hívás-számlálóval**, `practiceTarget` mód + üres-expected target, assert `callCount == 0` és `alignment == null`. A brief §10 handoff (:420-424) rögzíti: a kapu ideiglenes eltávolításakor a teszt `Failure<AnalysisWorkState>`-szel **pirosra váltott**, majd a kapu visszaállt — a guard valódi sértést fog.

**Failure scenario, amit ez kizár:** `practiceTarget` mód hiányos gyakorlat-tervvel (üres `expectedEvents`) → a felhasználó NEM lát hamis 0%-os pontosságot; az illesztés `null` marad, a timing-capability `noReferenceTarget` okkal `unavailable`. **Tartja magát.**

## Önálló ellenőrzés 2 — gyenge confidence nem álcázható biztos állításnak (AGENTS.md §5)

**Bizonyíték (`CapabilityConfidenceEvaluationStage.run()` :390-427):**
- Hiányzó `signalQuality` → `throw StateError(...)` (:395-398) → `_runSafely` elkapja (:458) → `Failure` → `classifyEvaluationStageFailure` a capability stage-re **`StageFailure.fatal`** (:51-52) → a lánc **megáll**, `capabilityReports`/`overallConfidence` nem keletkezik. Fail-closed. (Teszt A8: `evaluation_pipeline_composition_test.dart:98-113` — fatális capability megállítja a szekvenciát.)
- A resolvernek átadott bizonyíték őszinte: `alignmentQuality: input.alignment?.confidence ?? 0` (:412, 0 ha nincs illesztés), `hasReferenceTarget` mért (:414), `modelConfidence` valódi átlag, 0.0 ha nincs esemény (:403-406).
- A resolver a küszöbök szerint degradál (`_statusFor` :285-293), üres alkalmazható-halmaznál `overallConfidence: 0` / `notApplicable` (:114-122). Tehát gyenge bizonyíték → `degraded`/`unavailable`, nem `available`.

**Teszt-fedettség:** A3-A5 (`evaluation_pipeline_composition_test.dart:44-96`) — az üres-referencia cella assertje: `capabilityReports[timingAccuracy].reason == noReferenceTarget` (nem magabiztos státusz), és a referencia-független metrikák (dynamics, rhythm) minden cellában kiszámolódnak.

**Mellékesen ellenőrizve (nem lelet):** a `copyWith` `?? this` szemantikája (`analysis_work_state.dart:175-178`) nem tudja `null`-ra visszaállítani az `alignment`/`overallConfidence` mezőt — de ez ártalmatlan: minden futás friss `seed`-ből indul (`alignment == null`, `overallConfidence == null`), és a stage-ek csak egyszer, valós nem-null értékre állítják őket. Nincs futások közti confidence-szennyeződés.

## Standard StrumSight biztonsági lista — amit mértem

| Terület | Eredmény | Bizonyíték |
|---|---|---|
| Titok/token/kulcs a diffben | **tiszta** | szemantikus grep: az egyetlen „token" a `cancellationToken` (megszakítási API); fixture-ök apró szintetikus PCM (`[0.1, -0.1]`) — valóban fake |
| Nyers audio kiszivárgás | **tiszta** | `preprocessedAudio` in-memory marad, csak a már review-zott `buildDynamicsMetrics(audio:)`-nak adódik át; sehol nem logolt/fájlba írt/hálózatra küldött; a `capabilityReports.details` csak skalárt tartalmaz (`capability_resolver.dart:247-255`) |
| Logolás/stdout | **nincs** | `print`/`debugPrint`/`developer.log`/`logger`/`stderr` grep: nulla — nincs csatorna audio/state kiszivárgásához |
| Hálózat (Dio/HTTP/Supabase) | **nincs** | szóhatáros grep a production fájlon: nulla; a korábbi „dio" találat az „au**dio**" részszó volt |
| Fájl/tároló/SecureStore I/O | **nincs** | `File`/`Directory`/`SecureStorage`/`SharedPreferences`/`dart:io` grep: nulla |
| Prompt-injection / AI-provider | **felület hiányzik** | nincs provider-hívás; az `AnalysisTarget.expectedEvents` numerikus/enum timing-adatként fogy (idő-összehasonlítás, `direction`/`type` enum-egyenlőség az alignerben), sosem utasításként értelmezett szövegként |
| Importált tartalom (zip/mxl/midi) | **nincs** | a kör nem dolgoz fel külső fájlt |
| Ellátási lánc (dep/asset) | **tiszta** | `pubspec`/`lock`/`assets` a diffben nincs — nincs új függőség vagy provenance-t igénylő asset |
| Consent-megkerülés | **N/A** | nincs hálózati/telemetriai hívás; a kód nem fut production úton (`StateError` runner) |

---

## Leletek

### NOTE-1 — Optimista, hardcode-olt/alapértelmezett resolver-bemenetek (előremutató, GOV-30c-3)
- **Hely:** `lib/features/audio_analysis/engine/stages/evaluation_stages.dart:414-416` (`modelAvailable: true`), és a `CapabilityResolverInput` alapértelmezései: `hypothesesAgree = true`, `isClipTooShort = false` (`confidence/capability_resolver.dart:18-19`), amelyeket a stage nem ad át.
- **Failure scenario (jelenleg NEM reprodukálható):** a jelen körben nincs futási út, és a munkaállapot nem hordoz modell-elérhetőség / hipotézis-egyezés / túl-rövid-klip jelzést, ezért ezeket nem is lehet őszintén forrásolni. Bekötés (GOV-30c-3) után viszont: ha egy valódi modell-betöltési hiba / túl rövid klip / nem-egyező hipotézis áll fenn, a hardcode-olt `modelAvailable: true` és a defaultok miatt a `CapabilityResolver` a `modelUnavailable` / `clipTooShort` ágat (`:173-180`, `:163-169`) **nem** aktiválná, és egy capability tévesen `available`-ként publikálódhatna.
- **Sértett szabály (leendő):** AGENTS.md §5 — „Gyenge confidence nem jelenhet meg biztos állításként."
- **Javítás iránya:** a bekötő kör a `modelAvailable`/`hypothesesAgree`/`isClipTooShort` értékeket a munkaállapot valós bizonyítékából származtassa (ne konstansból); a GOV-30c-3 mérce-mátrixa tartalmazzon egy „modell nem elérhető → capability nem `available`" cellát.

### NOTE-2 — Elkapott hibák becsomagolása `cause`/`stackTrace`-szel (előremutató, GOV-30c-3)
- **Hely:** `lib/features/audio_analysis/engine/stages/evaluation_stages.dart:458-461` — `catch (error, stackTrace) { return Failure(UnknownFailure(cause: error, stackTrace: stackTrace)); }`.
- **Failure scenario (jelenleg NEM reprodukálható):** ebben a körben csak fix-szövegű `StateError`-ök dobódnak, és a `Failure` sehol nem logolódik/továbbítódik (nincs fogyasztó — a runner dob). Egy későbbi körben azonban, ha egy downstream metrika-builder kivétele belső/audio-eredetű adatot tesz a `toString()`-jébe, és a `Failure`-t valaki logba / telemetriába / `AppFailure` felhasználói szövegbe vezeti, az kiszivároghat.
- **Sértett szabály (leendő):** nem tárgyalható termékhatár #3 (titok/nyers audio nem kerülhet logba/hibaüzenetbe).
- **Javítás iránya:** a hibafelszínre vezető kör (GOV-30c-3) igazolja a `cause`/`stackTrace` redakcióját, mielőtt bármely `Failure` felhasználó/log/telemetria felé kerül.

---

## Módszer és a „üres jelentés is bizonyíték" tétel

Amit átnéztem és mértem: a teljes új production fájl (`evaluation_stages.dart`, 499 sor) sorról sorra; a fogyasztott függőségek (`event_aligner.dart`, `capability_resolver.dart`, `analysis_work_state.dart`) a két kritikus invariáns szempontjából; mindhárom tesztfájl (A6 hívás-számláló, A3-A5 referencia-mátrix, A8 fatális cella); szóhatáros biztonsági grep-ek (titok/log/hálózat/IO); a `analysisV2RunnerProvider` érintetlensége és a `buildEvaluationStages()` hívó-hiánya; a pubspec/lock/asset változatlansága. A két kritikus invariáns **kódúttal és teszttel is** tartja magát; a standard biztonsági lista minden tétele üres, mert a kód nem fogyaszt külső szöveget, nem nyit hálózatot/tárolót, és nem fut production úton.

**Megjegyzés a gate-ről:** a `flutter test` futtatása a correctness-reviewer és a CI dolga (ADR 0053, ~15 perc a boxon); a biztonsági verdikt kód-út-elemzésen és a teszt-assertek olvasatán nyugszik, nem a suite lefuttatásán.
