---
id: 125
topic: SDD Ch11 / Epic 10 — Offline AI: 32 kör (helyi LLM runtime bake-off, kvantálás, model package manager, local TutorModelGateway impl, device tier, TTFT/token-rate benchmark)
tags: [sdd, epic10, offline-ai, llm, runtime, quantization, gateway, benchmark]
status: active
depends_on: [105, 108]
canonical_target: docs/sdd/11-epic-10-offline-ai.md
as_built: docs/sdd/11-epic-10-offline-ai.md (E01-R01, r207)
verify: a Ch5 TutorModelGateway contract változatlan implementálása + valós eszközös TTFT/token-rate gate
source: chatgpt-plan 2026-07-28 (Codex Execution Pack, batch 2)
---

# StrumSight Software Design Document

## Chapter 11 — Epic 10: Offline AI

**Dokumentumverzió:** 1.0  
**Státusz:** fejlesztésre kész specifikáció  
**Repository:** `wolfcasaba/strumsight`  
**Elsődleges kliens:** Flutter, Android-first  
**Natív integráció:** Kotlin/Java + C/C++ runtime adapter, típusos Flutter platform boundary  
**Tervezési alapelv:** local-first, privacy-first, benchmark-driven, model-agnostic, capability-tiered  
**Adatkezelés:** a prompt, a tutor context, a retrieval és a generálás alapértelmezetten az eszközön marad  
**Kapcsolódó fejezetek:** Chapter 2 Core Platform, Chapter 3 Practice Engine, Chapter 4 Song Trainer, Chapter 5 AI Guitar Teacher, Chapter 6 Computer Vision, Chapter 7 Audio Analysis 2.0, Chapter 8 AI Practice Generator, Chapter 9 Gamification, Chapter 10 Community Platform  
**Végrehajtó:** Codex  
**Végrehajtási mód:** külön branchben vagy külön, önálló commitban végzett kis fejlesztési körök  
**Fejlesztési körök száma:** 32

---

# 1. Az Epic célja

Az Epic 10 célja egy olyan teljesen helyi, mobiltelefonon futó generatív AI-réteg létrehozása, amely a StrumSight AI Guitar Teacher funkcióját internetkapcsolat nélkül is képes működtetni, miközben megőrzi a rendszer pedagógiai, adatvédelmi, biztonsági és teljesítménybeli korlátait.

Az Offline AI nem általános célú chatbot, és nem egy korlátlan autonóm agent. A rendszer feladata a StrumSightban már meglévő vagy a korábbi SDD-fejezetekben meghatározott, strukturált tanulási adatok magyarázata, a kurált gitároktatási tudás visszakeresése, valamint biztonságos és validált gyakorlási javaslatok megfogalmazása.

A fejezet végeredménye egy olyan offline AI platform, amely:

- ugyanazt a `TutorModelGateway` szerződést implementálja, amelyet a Chapter 5 meghatározott;
- nem írja újra az AI Tutor domain-, conversation-, tool- vagy safety modelljeit;
- a modell- és runtime-technológiát mérési bake-off alapján választja ki;
- nem köti a Flutter üzleti logikát egyetlen natív inference frameworkhöz;
- támogatja a modellcsomag biztonságos letöltését, ellenőrzését, aktiválását, visszagörgetését és törlését;
- a modellcsomagot nem építi bele kötelezően az APK-ba;
- eszközképesség alapján eltérő modell-, context- és retrieval-profilt választ;
- alacsony képességű eszközön tisztességes deterministic fallbacket biztosít;
- a generálást külön native workerben vagy indokolt esetben külön Android processben futtatja;
- nem blokkolja a Flutter UI isolate-ot;
- támogatja a tokenstreamet, a megszakítást, a timeoutot és a backpressure-t;
- lokális, verziózott és forrásazonosítóval ellátott RAG-rendszert használ;
- nem küld promptot, beszélgetést, tudásbázis-lekérdezést vagy modellkimenetet hálózatra;
- a tool callingot kizárólag schema-validált és engedélyezett StrumSight műveletekre korlátozza;
- felhasználói megerősítést kér minden állapotot módosító művelet előtt;
- külön kezeli a lokális, cloud és deterministic módot;
- angol és magyar nyelven mérhető minőségi kapuval rendelkezik;
- figyeli a memóriát, a hőterhelést, az akkumulátort és a valós idejű audio/vision erőforrásokat;
- ismételhető modell-export-, kvantálás-, csomagolás- és release-pipeline-nal rendelkezik;
- modelllicencet, forrást, checksumot és model cardot minden csomagnál rögzít;
- hibás vagy inkompatibilis modell esetén nem teszi használhatatlanná az alkalmazást.

Az Epic sikerének mércéje nem az, hogy a telefonon „valamilyen LLM” válaszol. A siker az, hogy a lokális AI válaszai elég gyorsak, relevánsak, bizonyítékokkal alátámasztottak, biztonságosak, megszakíthatók, auditálhatók és a StrumSight tanulási folyamataiba illeszthetők.

---

# 2. Termékvízió

## 2.1 Felhasználói ígéret

A kívánt élmény:

> A felhasználó repülőgépes módban befejez egy ritmusgyakorlatot. Megnyitja az AI tanárt, és megkérdezi: „Miért sietek mindig a második és negyedik ütésen?” A telefon helyben feldolgozza a már kiszámított session-evidenciát, visszakeresi a ritmikai tudásbázis megfelelő részeit, majd rövid, magyar nyelvű magyarázatot és egy jóváhagyható gyakorlási javaslatot ad. Sem a felvétel, sem a kérdés, sem a válasz nem hagyja el az eszközt.

A nem kívánt élmény:

> Az alkalmazás letölt egy több gigabájtos modellt magyarázat nélkül, elfogyasztja a tárhelyet, a háttérben felmelegíti a telefont, blokkolja a Live mikrofont, majd megalapozatlan technikai hibát állít és automatikusan módosítja a gyakorlási tervet.

## 2.2 A helyi AI szerepe

A helyi modell feladata:

- természetes nyelven megmagyarázni a strukturált StrumSight eredményeket;
- a kurált tudásbázis releváns részleteit összefoglalni;
- kérdéseket feltenni, ha a bizonyíték nem elegendő;
- megkülönböztetni a mért tényt, a tudásbázisból származó állítást és az óvatos következtetést;
- javaslatot adni egy meglévő, validált gyakorlati katalógusból;
- előnézetet készíteni egy lehetséges terv- vagy beállításmódosításról;
- rövid offline debriefet készíteni Practice, Song vagy Analyze session után;
- a felhasználó nyelvén, szintjéhez igazodva válaszolni;
- a rendszer által támogatott toolokat strukturáltan meghívni, de csak policy és megerősítés után.

A helyi modell nem:

- értékel újra nyers audio- vagy videoadatot;
- talál ki mért pontosságot, ritmust, akkordot vagy kéztartási hibát;
- fér hozzá tetszőleges fájlrendszerhez, shellhez vagy hálózathoz;
- telepít csomagot, vásárol, posztol vagy küld üzenetet önállóan;
- módosít streaket, XP-t vagy mastery értéket;
- ír át model cardot, tudáscsomagot vagy safety policyt;
- fut a háttérben korlátlanul;
- tanítja tovább saját súlyait a telefonon;
- tárol rejtett chain-of-thoughtot;
- ígér diagnózist fájdalom, sérülés vagy egészségügyi probléma esetén.

## 2.3 Offline AI módok

A felhasználó és a rendszer a következő végrehajtási módokat különbözteti meg:

```text
Deterministic only
    Nincs generatív modell. A tutor sablonos, szabályalapú és retrieval-alapú választ ad.

Local preferred
    A helyi modell az elsődleges. Ha nem elérhető, deterministic fallback következik.
    Cloud csak külön consent és explicit választás esetén használható.

Local only
    A rendszer soha nem küldi a kérést cloud modellnek.
    Helyi modellhiba esetén deterministic fallbacket ad.

Cloud preferred
    Cloud modell használható consent mellett, de offline állapotban helyi vagy deterministic módra esik vissza.

Cloud only
    Kizárólag explicit beállításként létezhet. Offline állapotban deterministic fallbacket ad.
```

A rendszer nem válthat csendben helyi módról cloud módra. A végrehajtási mód minden válasz metaadatában és a UI-ban látható.

## 2.4 Capability-tiered termék

Nem minden Android készülék alkalmas ugyanarra a modellre. A StrumSight nem használhat egyetlen merev „minimum RAM” szabályt. A támogatást kombinált mérés határozza meg:

- ABI és operációs rendszer;
- elérhető és biztonságosan használható memória;
- szabad tárhely;
- CPU utasításkészlet;
- GPU/NPU backend támogatás;
- cold-load és warm-load idő;
- time to first token;
- decode sebesség;
- peak PSS/RSS;
- KV-cache növekedés;
- cancellation latency;
- thermal és battery teszt;
- audio/vision együttélési teszt;
- tíz egymást követő generálás stabilitása.

A termék négy képességszintet kezel:

1. **Tier 0 — Deterministic:** nincs helyi generatív modell.
2. **Tier 1 — Compact:** kis modell, rövid context, lexical RAG, alacsony output limit.
3. **Tier 2 — Standard:** nagyobb helyi modell, hybrid RAG, közepes context és stabil tool calling.
4. **Tier 3 — Enhanced:** támogatott GPU/NPU backend, hosszabb context vagy magasabb minőségű modell, de továbbra is kontrollált termékhatárok.

A Tier 0 nem hibaállapot. A teljes gitártanulási alkalmazás generatív AI nélkül is működőképes marad.

## 2.5 Benchmark-driven runtime választás

A runtime és modell kiválasztását nem marketingállítás vagy egyetlen flagship telefon tesztje dönti el.

A 2026. július 28-i technológiai kiindulópontok között legalább a következő hivatalos runtime-családokat kell mérni:

- Google LiteRT-LM;
- PyTorch ExecuTorch LLM runtime;
- `llama.cpp` Android/GGUF binding;
- ONNX Runtime GenAI Android build.

A jelenlegi hivatalos dokumentáció alapján ezek eltérő érettségi, modellformátum-, gyorsító-, API- és tool-calling képességekkel rendelkeznek. Emiatt a dokumentum nem teszi egyiküket automatikus végleges választássá. A Codex feladata mérési harness létrehozása, azonos prompt- és eszközmátrixon történő összehasonlítás, majd ADR készítése.

A runtime kiválasztása után is meg kell maradnia egy StrumSight-saját adapterrétegnek, hogy a feature domain ne függjön közvetlenül a kiválasztott SDK-tól.

---

# 3. Kapcsolat a jelenlegi kódbázissal

## 3.1 Meglévő offline alap

A jelenlegi StrumSight már erős local-first alapokkal rendelkezik:

- valós idejű mikrofonfelvétel;
- pure-Dart DSP és kézzel implementált CRNN inference;
- chord-, strum-direction-, onset-, tempo- és pitch-elemzés;
- offline Learn, Tuner, Analyze, Songs, Progress és Streak;
- lokális ML assetek a `assets/ml` könyvtárban;
- Python training, export és model card eszközök az `ml` könyvtárban;
- kiterjedt unit, property és real-audio tesztek;
- opcionális account és settings sync, amely kijelentkezve inert;
- angol és magyar lokalizáció;
- diagnosztikai Lab mód.

Ez bizonyítja, hogy a projekt képes helyi inference-re és offline termékélményre. Az LLM azonban nagyságrendileg eltérő modellméretet, memóriakezelést, natív runtime-ot, tokenizálást és release-folyamatot igényel.

## 3.2 Meglévő modellek és korlátaik

A repository jelenlegi modellassetjei:

- `strum_crnn.bin`;
- `strum_crnn_live.bin`;
- `strum_crnn_live_3c.bin`;
- `chord_crnn.bin`.

Ezek kis, feladatspecifikus modellek, és kézzel írt Dart inference kódot használnak. Az Offline AI nem terhelheti rá a generatív runtime felelősségét ezekre az osztályokra, és nem írhatja át a valós idejű audio pipeline-t.

A generatív modell külön runtime-, lifecycle-, storage- és resource boundaryt kap.

## 3.3 Chapter 5 szerződései

A Chapter 5 már meghatározza:

- a tutor domain modelleket;
- a conversation és message szerződéseket;
- a student és guitar profile-t;
- a skill evidence rendszert;
- a context assemblert;
- a kurált tudásbázist;
- a retrieval interfészt;
- a claim provenance-t;
- a tool registryt;
- a prompt verziózást;
- a safety és privacy policyt;
- a `TutorModelGateway` interfészt;
- a cloud és deterministic gateway implementációs helyét.

Az Offline AI kizárólag új infrastruktúrát és local gateway implementációt ad. Tilos párhuzamos `OfflineTutorMessage`, `LocalStudentProfile` vagy `OfflineToolRegistry` domaint létrehozni.

## 3.4 Chapter 8 kapcsolata

Az AI Practice Generator determinisztikus és validált gyakorláskatalógusból dolgozik. A helyi LLM:

- értelmezheti a felhasználó célját;
- megfogalmazhatja a terv indoklását;
- javasolhat policy-kompatibilis helyettesítést;
- összefoglalhatja a tervet;
- kérhet pontosítást.

A helyi LLM nem állíthat össze tetszőleges, nem validált gyakorlatsorozatot, és nem írhatja felül a constraint engine döntését.

## 3.5 Chapter 7 és Chapter 6 kapcsolata

Az Audio Analysis 2.0 és a Computer Vision strukturált evidenciát adhat a tutor contexthez.

Tilos:

- nyers PCM vagy WAV beküldése a text-only LLM-be;
- teljes videó vagy frame sorozat beküldése;
- vision landmark tömbök közvetlen promptba másolása;
- olyan technikai állítás, amelyhez nincs megfelelő audio- vagy vision-evidence ref.

A local AI csak compact, verziózott és minimalizált `TutorContextSnapshot` objektumot kap.

## 3.6 Jelenlegi technikai adósságok

Az Epic kezdetén a repositoryban nincs:

1. általános LLM runtime adapter;
2. natív Android generatív inference plugin;
3. modellcsomag-kezelő;
4. biztonságos modellmanifest és aláírás-ellenőrzés;
5. resumable model download;
6. offline model import;
7. device capability profiler;
8. runtime bake-off harness;
9. tokenizer és chat-template réteg;
10. KV-cache lifecycle policy;
11. tokenstream boundary Flutter és native között;
12. cancellation és timeout contract;
13. LLM resource coordinator;
14. hőmérséklet- és akkumulátorpolicy;
15. helyi embedding runtime;
16. verziózott hybrid RAG index;
17. context token budgeter;
18. constrained structured output;
19. local tool-call parser és validator;
20. bilingual offline AI evaluation corpus;
21. reprodukálható generatív modell-export és kvantálás;
22. model package release channel;
23. local AI settings és model manager UI;
24. OOM/crash isolation stratégia;
25. local AI network-zero integration teszt.

---

# 4. Az Epic hatóköre

## 4.1 Az Epic része

- runtime és modell bake-off;
- technológiai ADR;
- helyi text-generation runtime interface;
- Android natív plugin vagy service boundary;
- Flutter platform adapter;
- device capability profiler;
- capability tier resolver;
- modellcsomag specifikáció;
- aláírt manifest és checksum validation;
- model download, pause, resume, retry és cancel;
- signed offline package import;
- aktiválás, rollback és eltávolítás;
- tárhelykvóta és cache policy;
- modell load, unload, warmup és session reset;
- tokenizer és chat template;
- generation profile;
- KV-cache és context lifecycle;
- token streaming;
- cancellation, timeout és backpressure;
- prompt- és context-budgeter;
- structured local conversation memory;
- lexical RAG;
- opcionális local embedding runtime;
- hybrid retrieval és deterministic reranking;
- knowledge package update;
- prompt assembly és prompt injection boundary;
- constrained structured output;
- local tool calling;
- `TutorModelGateway` local implementáció;
- deterministic/local/cloud routing;
- safety pre- és post-processing;
- magyar és angol evaluation;
- performance, memory, thermal és battery benchmark;
- app lifecycle és low-memory kezelés;
- modell-export, kvantálás és model card pipeline;
- backend/CDN model manifest és release channel;
- settings, download és diagnostics UI;
- accessibility és localization;
- feature flag, staged rollout és kill switch;
- unit, property, contract, native, instrumentation, integration és device tesztek.

## 4.2 Az Epic nem tartalmazza

- általános internetes webkeresést;
- böngésző- vagy shell toolokat;
- korlátlan autonóm agent loopot;
- nyers audio- vagy video-multimodális LLM-et;
- valós idejű hangalapú beszélgetést;
- speech-to-text vagy text-to-speech teljes termékét;
- on-device fine-tuningot;
- on-device gradient alapú tanítást;
- felhasználói beszélgetésekből automatikus súlyfrissítést;
- közösségi posztok automatikus RAG-forrássá tételét;
- nem aláírt modell telepítését production módban;
- DRM-et vagy saját kriptográfiai algoritmust;
- cloud provider kulcs kliensbe építését;
- hidden chain-of-thought tárolását vagy megjelenítését;
- automatikus app-beállítás módosítást megerősítés nélkül;
- Community üzenet vagy poszt automatikus közzétételét;
- fizetési, vásárlási vagy előfizetési toolt;
- egészségügyi diagnózist;
- iOS production runtime implementációt ebben az Epicben, de az interface-nek készen kell állnia egy későbbi iOS adapterre.

---

# 5. Kötelező architekturális alapelvek

## 5.1 Model-agnostic domain

A Flutter feature és a tutor domain nem importálhat:

- LiteRT-LM osztályt;
- ExecuTorch osztályt;
- llama.cpp bindinget;
- ONNX Runtime osztályt;
- GGUF-, PTE-, ONNX- vagy LiteRT-specifikus típust;
- Android Contextet;
- MethodChannelt;
- native pointert.

Ezek kizárólag az infrastructure/platform rétegben jelenhetnek meg.

## 5.2 Local-first, nem local-only kényszer

A felhasználó választhat local-only módot, de az alkalmazás nem kényszeríthet modellletöltésre.

- az alapapp generatív modell nélkül telepíthető;
- a gitártanulási funkciók modell nélkül működnek;
- a modellletöltés külön, érthető consent;
- a modell mérete és várható eszközterhelése előre látható;
- a modell bármikor törölhető;
- a modell törlése nem törli a progress adatot;
- a modell nélkül a deterministic tutor továbbra is elérhető.

## 5.3 Fail closed, degrade gracefully

Biztonsági hiba esetén:

- a signature mismatch blokkolja az aktiválást;
- a checksum mismatch törli vagy karanténba helyezi a hibás csomagot;
- inkompatibilis runtime verzió blokkolja a loadot;
- OOM-veszély esetén nem indul generálás;
- tool schema hiba esetén nincs művelet;
- prompt assembly hiba esetén deterministic fallback következik;
- local runtime crash esetén az app többi része tovább használható marad;
- cloud fallback csak explicit policy és consent alapján történhet.

## 5.4 Nincs generálás valós idejű kritikus útvonalon

A local LLM nem futhat ugyanabban a real-time feldolgozási útvonalban, mint:

- Live chord detection;
- Tuner pitch tracking;
- Practice session scoring;
- Song performance scoring;
- Computer Vision frame processing;
- Analyze recording.

A helyi generálás session után, pause állapotban vagy külön felhasználói kérésre indul.

Közepes vagy alacsony tierű eszközön a resource coordinator köteles megtagadni vagy késleltetni a generálást, ha mikrofon- vagy kamera-session aktív.

## 5.5 A modell nem forrás-of-truth

Forrás-of-truth marad:

- a DSP és ML score;
- a Practice Engine result;
- a Song Trainer result;
- az AnalysisDocument;
- a Vision evidence;
- a Progress repository;
- a Practice Generator policy engine;
- a Gamification ledger;
- a Community backend policy.

A helyi modell csak értelmező és nyelvi réteg.

---

# 6. Célarchitektúra

```text
Flutter AI Tutor feature
        |
        v
TutorModelGateway (Chapter 5 contract)
        |
        +-----------------------------+
        |                             |
        v                             v
DeterministicTutorGateway       RoutedTutorGateway
                                      |
                    +-----------------+-----------------+
                    |                                   |
                    v                                   v
          LocalTutorModelGateway              CloudTutorModelGateway
                    |
                    v
          LocalAiApplicationService
                    |
         +----------+-----------+
         |                      |
         v                      v
ContextCompiler          LocalRetrievalService
         |                      |
         +----------+-----------+
                    |
                    v
           LocalGenerationRuntime
                    |
                    v
         Flutter platform adapter
                    |
                    v
         Android Local AI service/process
                    |
                    v
        Runtime adapter selected by ADR
                    |
          +---------+---------+---------+
          |                   |         |
       LiteRT-LM         ExecuTorch   llama.cpp / ORT
          |
          v
 Signed local model package + tokenizer + templates
```

## 6.1 Javasolt Flutter struktúra

```text
lib/
├── core/
│   ├── ai/
│   │   ├── local_ai_failure.dart
│   │   ├── local_ai_capabilities.dart
│   │   ├── local_ai_mode.dart
│   │   ├── local_ai_runtime.dart
│   │   ├── generation_event.dart
│   │   ├── generation_request.dart
│   │   ├── generation_metrics.dart
│   │   ├── model_package_descriptor.dart
│   │   ├── model_registry.dart
│   │   ├── model_package_manager.dart
│   │   ├── device_capability_profiler.dart
│   │   ├── local_ai_resource_coordinator.dart
│   │   └── public.dart
│   └── security/
│       ├── signed_manifest_verifier.dart
│       └── canonical_json.dart
│
├── features/
│   └── offline_ai/
│       ├── domain/
│       ├── application/
│       ├── data/
│       ├── presentation/
│       └── public.dart
│
└── platform/
    └── local_ai/
        ├── local_ai_platform.dart
        ├── local_ai_platform_impl.dart
        └── generated/
```

## 6.2 Javasolt Android struktúra

```text
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/
├── LocalAiPlugin.kt
├── LocalAiService.kt
├── LocalAiServiceConnection.kt
├── LocalAiRuntimeFacade.kt
├── LocalAiRuntimeFactory.kt
├── LocalAiSession.kt
├── LocalAiEventEmitter.kt
├── LocalAiErrorMapper.kt
├── RuntimeCapabilities.kt
├── DeviceMemoryProbe.kt
├── ThermalMonitor.kt
├── PackageVerifier.kt
└── runtime/
    ├── RuntimeAdapter.kt
    ├── SelectedRuntimeAdapter.kt
    └── FakeRuntimeAdapter.kt
```

A végleges runtime-specifikus fájlnevek az ADR után készülhetnek el.

## 6.3 Model build és release struktúra

```text
local_ai/
├── README.md
├── requirements-lock.txt
├── configs/
│   ├── candidate_models.yaml
│   ├── quantization_profiles.yaml
│   └── evaluation_profiles.yaml
├── export/
│   ├── export_model.py
│   ├── export_tokenizer.py
│   ├── build_package.py
│   └── verify_package.py
├── evaluation/
│   ├── corpus/
│   ├── run_quality_eval.py
│   ├── run_tool_eval.py
│   ├── run_grounding_eval.py
│   └── compare_candidates.py
├── manifests/
├── model_cards/
└── tests/
```

---

# 7. Közös domain és platform szerződések

## 7.1 LocalAiMode

```dart
enum LocalAiMode {
  deterministicOnly,
  localPreferred,
  localOnly,
  cloudPreferred,
  cloudOnly,
}
```

A persisted érték wire stringet használjon. Ismeretlen érték biztonságos `deterministicOnly` vagy explicit migration failure legyen a termékpolicy szerint.

## 7.2 LocalAiAvailability

```dart
enum LocalAiAvailability {
  disabled,
  unsupported,
  installable,
  downloading,
  verifying,
  ready,
  incompatible,
  corrupted,
  updateAvailable,
  temporarilyUnavailable,
}
```

A UI nem következtethet pusztán abból, hogy egy fájl létezik. A `ready` állapot csak sikeres manifest-, signature-, checksum-, compatibility- és load smoke test után adható.

## 7.3 DeviceCapabilityProfile

```dart
final class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    required this.profileVersion,
    required this.platform,
    required this.abi,
    required this.osVersion,
    required this.totalMemoryBytes,
    required this.availableMemoryBytes,
    required this.freeStorageBytes,
    required this.supportedBackends,
    required this.thermalCapability,
    required this.benchmarkSummary,
    required this.resolvedTier,
    required this.measuredAt,
  });
}
```

A profil nem tartalmazhat stabil advertising ID-t vagy fingerprinting célú, szerverre automatikusan küldött részletes hardverazonosítót.

## 7.4 ModelPackageDescriptor

```dart
final class ModelPackageDescriptor {
  const ModelPackageDescriptor({
    required this.packageId,
    required this.version,
    required this.channel,
    required this.runtimeFamily,
    required this.runtimeMinimumVersion,
    required this.modelFamily,
    required this.quantization,
    required this.contextLength,
    required this.downloadBytes,
    required this.installedBytes,
    required this.sha256,
    required this.signatureKeyId,
    required this.languages,
    required this.capabilities,
    required this.licenseIds,
    required this.minimumTier,
  });
}
```

## 7.5 LocalGenerationRuntime

```dart
abstract interface class LocalGenerationRuntime {
  Future<AppResult<RuntimeCapabilities>> initialize();

  Future<AppResult<LoadedModelHandle>> loadModel(
    ActivatedModelPackage package,
    RuntimeLoadOptions options,
  );

  Stream<GenerationEvent> generate(
    LoadedModelHandle model,
    GenerationRequest request,
  );

  Future<AppResult<void>> cancel(GenerationId generationId);

  Future<AppResult<void>> resetSession(SessionId sessionId);

  Future<AppResult<void>> unloadModel(LoadedModelHandle model);

  Future<AppResult<RuntimeHealth>> health();
}
```

## 7.6 GenerationEvent

```dart
sealed class GenerationEvent {
  const GenerationEvent();
}

final class GenerationStarted extends GenerationEvent {}
final class GenerationToken extends GenerationEvent {
  const GenerationToken(this.text, this.tokenIndex);
  final String text;
  final int tokenIndex;
}
final class GenerationToolDraft extends GenerationEvent {}
final class GenerationCompleted extends GenerationEvent {}
final class GenerationCancelled extends GenerationEvent {}
final class GenerationFailed extends GenerationEvent {}
final class GenerationMetricsUpdated extends GenerationEvent {}
```

A token callback nem jelenthet közvetlen UI-mutációt a native threadről. A platform adapter rendezze a szál- és streamhatárt.

## 7.7 LocalAiFailure

Kötelező kategóriák:

```text
LocalAiUnsupportedFailure
ModelNotInstalledFailure
ModelPackageCorruptedFailure
ModelSignatureFailure
ModelIncompatibleFailure
ModelLoadFailure
TokenizerFailure
ContextOverflowFailure
GenerationTimeoutFailure
GenerationCancelledFailure
GenerationRuntimeFailure
InsufficientMemoryFailure
InsufficientStorageFailure
ThermalLimitFailure
ResourceBusyFailure
StructuredOutputFailure
RetrievalFailure
SafetyRejectedFailure
UnknownLocalAiFailure
```

A felhasználónak szánt szöveg lokalizált failure code alapján készül.

---

# 8. Modellcsomag és biztonsági formátum

## 8.1 Csomagstruktúra

```text
strumsight-local-ai-package/
├── manifest.json
├── manifest.sig
├── model/
│   └── model.<runtime-format>
├── tokenizer/
│   ├── tokenizer.json
│   └── tokenizer.model
├── templates/
│   ├── chat_template.json
│   ├── system_prompt.txt
│   └── tool_schema.json
├── generation/
│   └── defaults.json
├── safety/
│   ├── policy.json
│   └── blocked_patterns.json
├── evaluation/
│   └── declared_results.json
├── licenses/
│   ├── MODEL_LICENSE.txt
│   ├── NOTICE.txt
│   └── third_party.json
└── model_card.json
```

A tényleges runtime-format lehet például `.litertlm`, `.pte`, `.gguf` vagy ONNX/GenAI package. A Flutter domain ezt nem ismeri.

## 8.2 Manifest követelmények

A manifest tartalmazza:

- schema version;
- package ID és version;
- release channel;
- runtime family és minimum runtime version;
- modell forrásrepository és pinned revision;
- export pipeline revision;
- kvantálási profil;
- context length;
- tokenizer hash;
- minden fájl mérete és SHA-256 értéke;
- támogatott nyelvek;
- tool-calling capability;
- structured-output capability;
- minimum device tier;
- szükséges free storage;
- becsült peak memory;
- licencazonosítók;
- model card hash;
- signature key ID;
- created-at és expires/revoked policy;
- kompatibilis appverzió-tartomány.

## 8.3 Aláírás

- A manifest canonical JSON formára kerül.
- Az aláírás auditált kriptográfiai könyvtárral történik.
- A production app csak beépített, rotálható public keyringgel ellenőriz.
- A private signing key nem kerül repositoryba vagy kliensbe.
- A signature ellenőrzés a package kibontása és aktiválása előtt kötelező.
- A teljes fájllista checksum ellenőrzése kötelező.
- Ismeretlen key ID production módban elutasítandó.
- Lab módban külön, egyértelműen megjelölt fejlesztői keyring használható.

## 8.4 Atomikus aktiválás

```text
Download to staging
        |
        v
Verify manifest signature
        |
        v
Verify file sizes and checksums
        |
        v
Compatibility check
        |
        v
Runtime load smoke test
        |
        v
Atomic rename to installed/<package-id>/<version>
        |
        v
Update active pointer transactionally
        |
        v
Keep previous known-good version for rollback
```

Félbeszakadt vagy hibás csomag nem válhat aktívvá.

---

# 9. Device capability és tier policy

## 9.1 Mérési szabály

A capability profiler két szintet használ:

1. **Static probe:** ABI, OS, memória, tárhely, backend, feature flag.
2. **Dynamic benchmark:** rövid, lokális fixture modellen vagy kiválasztott modellen futó mérés.

A dinamikus benchmark eredménye cache-elhető, de újra kell futnia:

- app major verzióváltás után;
- runtime major verzióváltás után;
- modellcsalád-váltás után;
- OS major frissítés után;
- felhasználói kézi újraméréskor;
- korábbi OOM vagy ismételt runtime crash után.

## 9.2 Támogatási kapu

Egy modell csak akkor jelölhető támogatottnak, ha:

- sikeresen betöltődik;
- legalább húsz rövid generálás crash és OOM nélkül lefut;
- a cancellation p95 a konfigurált határ alatt marad;
- a cold-load és TTFT a tier célértéken belül van;
- a decode sebesség használható interaktív válaszhoz;
- a peak memória biztonságos headroomot hagy;
- a hosszabb conversation nem növeli korlátlanul a KV-cache-t;
- a thermal policy nem lép súlyos állapotba normál rövid használat során;
- a real-time audio együttélési teszt megfelel vagy a coordinator megfelelően blokkol;
- az output minőségi evaluation eléri a minimumot.

## 9.3 Kezdeti teljesítménycélok

A pontos küszöböket az ADR rögzíti, de a bake-off első célértékei:

```text
Tier 1 Compact
- median time to first token: legfeljebb 10 s
- median decode: legalább 3 token/s
- cancel p95: legfeljebb 750 ms
- max output: 192–256 token

Tier 2 Standard
- median time to first token: legfeljebb 6 s
- median decode: legalább 5 token/s
- cancel p95: legfeljebb 500 ms
- max output: 256–384 token

Tier 3 Enhanced
- median time to first token: legfeljebb 4 s
- median decode: legalább 8 token/s
- max output: policy szerint, jellemzően legfeljebb 512 token
```

Ezek nem marketingígéretek. A támogatott eszközmátrix eredményei alapján módosíthatók.

---

# 10. Runtime lifecycle és erőforrás-koordináció

## 10.1 Modell lifecycle

```text
notLoaded → loading → ready → generating → ready → unloading → notLoaded
                 |                 |
                 v                 v
               failed          cancelling
```

Szabályok:

- egyszerre legfeljebb egy aktív helyi generálás;
- a load és unload idempotens;
- ugyanaz a modell ne töltődjön be párhuzamosan kétszer;
- generálás közben modellcsere tiltott;
- app backgroundba kerülésekor nincs új generálás;
- memory pressure esetén a modell kiüríthető;
- tokenstream megszakítása után a session állapota csak dokumentált módon újrahasználható;
- runtime crash után új service/process és tiszta session szükséges;
- a modell ne tartsa indokolatlanul a wakelockot.

## 10.2 Resource coordinator

A `LocalAiResourceCoordinator` ismeri:

- microphone owner;
- camera owner;
- Analyze recording állapot;
- active audio playback;
- thermal status;
- battery saver;
- low-memory signal;
- model load és generation állapot;
- foreground/background állapot.

Példák:

- Tier 1 eszközön aktív Live session mellett a generálás `ResourceBusyFailure`.
- Tier 3 eszközön is csak külön mérés és policy alapján engedhető egyidejű vision és LLM.
- severe thermal állapotban új generálás nem indul.
- critical thermal állapotban aktív generálás megszakad és érthető üzenet jelenik meg.
- battery saver módban a felhasználó választhat rövidített választ vagy deterministic módot.

## 10.3 Process isolation

A bake-offnak ki kell értékelnie:

- in-process native runtime;
- külön Android processben futó bound service.

Production célként külön process javasolt, ha:

- a runtime native crash kockázata jelentős;
- az OOM izolálása javítja az app túlélését;
- a Binder/event overhead nem rontja mérhetően a tokenstreamet;
- a model lifecycle megbízhatóan kezelhető.

Az ADR rögzítse a választást. A Flutter contract mindkét esetben azonos marad.

---

# 11. Tokenizer, context és conversation memory

## 11.1 Tokenizer source-of-truth

A tokenizer a modellcsomag része. Tilos:

- más verziójú tokenizert használni, mint amellyel a modellt exportálták;
- tokenizer assetet külön, ellenőrzés nélkül frissíteni;
- Dartban saját, nem parity-tesztelt tokenizert írni production generáláshoz;
- karakterhossz alapján contextet becsülni ott, ahol pontos token count szükséges.

## 11.2 Context budget

A context compiler előre foglal:

```text
system policy
+ model-specific chat template overhead
+ tool schema
+ minimal student context
+ structured session evidence
+ retrieved knowledge chunks
+ compact conversation memory
+ current user message
+ reserved output tokens
<= model context limit
```

A prioritás:

1. safety és system policy;
2. user current request;
3. mért evidence;
4. tool schema, ha releváns;
5. legrelevánsabb knowledge chunk;
6. structured learner memory;
7. legutóbbi conversation turnök;
8. régebbi beszélgetés.

A rendszer soha nem vághatja le csendben a current user message-et vagy a safety policyt.

## 11.3 Structured memory

A hosszú beszélgetést nem nyers chat historyként kell korlátlanul tárolni és promptba tenni.

A persisted `TutorMemory` tartalmazhat:

- felhasználó által megerősített célokat;
- preferált magyarázati stílust;
- kerülendő vagy kényelmetlen gyakorlatot;
- aktuális technikai fókuszt;
- elfogadott tervet;
- unresolved questiont;
- utolsó releváns session refeket.

A memória:

- verziózott;
- szerkeszthető;
- exportálható;
- törölhető;
- nem tartalmaz hidden reasoningot;
- nem automatikusan szinkronizált cloudba local-only módban.

---

# 12. Lokális RAG

## 12.1 Tudásforrás

A helyi RAG csak jóváhagyott, verziózott StrumSight tudáscsomagból dolgozik.

Nem lehet automatikus forrás:

- Community poszt;
- komment;
- tetszőleges weboldal;
- felhasználói fájl;
- modell saját korábbi válasza;
- diagnosztikai log;
- nyers DSP dokumentáció végfelhasználói kontextus nélkül.

## 12.2 Retrieval tier

```text
Tier 0: deterministic lookup + curated answer blocks
Tier 1: BM25/lexical retrieval
Tier 2: lexical + local embedding + deterministic reranking
Tier 3: ugyanaz, nagyobb index vagy fejlettebb local embedding, ha mérés indokolja
```

## 12.3 Knowledge chunk

```dart
final class LocalKnowledgeChunk {
  const LocalKnowledgeChunk({
    required this.chunkId,
    required this.contentVersion,
    required this.language,
    required this.title,
    required this.body,
    required this.skillTags,
    required this.difficultyRange,
    required this.sourceId,
    required this.approvalStatus,
    required this.checksum,
  });
}
```

## 12.4 Hybrid score

A hybrid retrieval score magyarázható és tesztelhető legyen.

Példa:

```text
final_score =
    lexical_weight * normalized_bm25
  + embedding_weight * normalized_cosine
  + skill_tag_boost
  + locale_boost
  + evidence_alignment_boost
  - duplicate_penalty
  - stale_content_penalty
```

A súlyok konfigurációból és evaluationból származnak, nem UI-kódban elrejtett magic numberök.

## 12.5 Citation és provenance

A modell promptjában minden chunk stabil source ID-t kap. A válasz parserének képesnek kell lennie:

- source ID megőrzésére;
- nem létező source ID elutasítására;
- claim provenance megjelenítésére;
- a felhasználónak rövid „Mi alapján?” nézetet adni;
- retrieval nélkül generált véleményt inference-ként jelölni.

---

# 13. Structured output és tool calling

## 13.1 Capability gate

Nem minden runtime és modell tud megbízható constrained decodingot vagy function callingot.

A `RuntimeCapabilities` külön mezőkkel jelzi:

- streaming text;
- token count;
- grammar-constrained output;
- JSON schema constrained output;
- native tool calling;
- stop sequence support;
- seed support;
- deterministic sampling support;
- session reset;
- KV-cache reuse;
- cancellation.

Ha a runtime/model combination nem éri el a tool-call evaluation minimumot, a helyi modell csak szöveges választ adhat. Műveletet nem kezdeményezhet.

## 13.2 Tool output envelope

```json
{
  "schemaVersion": 1,
  "response": {
    "type": "message",
    "blocks": []
  },
  "toolCalls": [
    {
      "tool": "practice.preview_plan_change",
      "arguments": {},
      "requiresConfirmation": true
    }
  ],
  "citations": ["kb.rhythm.rush_drag.001"],
  "confidence": "medium"
}
```

## 13.3 Tool execution szabály

```text
Model output
    |
    v
Parse JSON / constrained structure
    |
    v
Schema validation
    |
    v
Tool registry allowlist
    |
    v
Argument domain validation
    |
    v
Policy check
    |
    v
Preview
    |
    v
Explicit user confirmation
    |
    v
Application use case
    |
    v
Audit event
```

Tilos közvetlenül a modelloutputból repositoryt vagy providert módosítani.

---

# 14. Safety, privacy és security

## 14.1 Privacy

Local-only módban:

- nincs prompt network request;
- nincs model output network request;
- nincs retrieval query network request;
- nincs conversation analytics szöveggel;
- nincs nyers evidence feltöltés;
- nincs cloud fallback;
- nincs remote logging a prompt tartalmával;
- a model download és manifest check külön hálózati művelet, nem tutor request.

A felhasználó exportálhatja és törölheti:

- local conversation history;
- structured TutorMemory;
- local AI beállítások;
- letöltött modellek;
- knowledge package-ek;
- benchmark eredmények.

## 14.2 Prompt injection boundary

A promptban elkülönül:

- system policy;
- tool schema;
- trusted knowledge;
- structured StrumSight evidence;
- user-provided text;
- untrusted imported text, ha később támogatott.

A user message nem írhatja felül:

- safety policyt;
- tool allowlistet;
- confirmation requirementet;
- privacy módot;
- evidence requirementet;
- model package policyt.

## 14.3 Fájlrendszer és hálózat

A local runtime adapter:

- csak az aktivált modellcsomag könyvtárát olvashatja;
- nem kap tetszőleges pathot a modelltől;
- nem ad shell vagy process execution toolt;
- nem ad HTTP klienst;
- nem követ model outputban lévő URL-t;
- nem olvas Community cache-t vagy auth tokent;
- nem fér hozzá secure storage credentialhöz.

## 14.4 Fizikai biztonság

Fájdalom vagy sérülés említésekor:

- a tutor ne diagnosztizáljon;
- javasolja a játék megszakítását, ha fájdalom jelentkezik;
- kerülje a „nyomd erősebben” típusú vak tanácsot;
- kérjen szakemberi segítséget tartós vagy erős panasz esetén;
- ne állítson kamerás hibát vision evidence nélkül.

---

# 15. Performance, thermal és battery policy

## 15.1 Kötelező metrikák

Minden local generation mérje helyben:

- model load duration;
- prompt token count;
- output token count;
- time to first token;
- decode tokens per second;
- total generation time;
- cancellation latency;
- peak process memory, ha platformon mérhető;
- thermal status start és end;
- battery state és saver mode;
- runtime/backend;
- model package ID/version;
- failure category.

A prompt és output szövege nem kerül performance logba.

## 15.2 Thermal policy

```text
none/light      → normál profil
moderate        → rövidebb output, opcionális alacsonyabb teljesítményprofil
severe          → új generálás tiltott vagy explicit user override nélkül tiltott
critical        → aktív generálás megszakítandó
emergency       → modell azonnal unload, local AI ideiglenesen unavailable
```

Az Android thermal API hiánya vagy hibája nem jelenthet automatikus „hideg” állapotot. Ilyenkor konzervatív policy szükséges.

## 15.3 Akkumulátor

- háttérben nincs generálás;
- model download beállítható Wi-Fi és töltés feltételre;
- battery saverben compact vagy deterministic mód javasolható;
- a felhasználó által elindított rövid válasz működhet battery saverben, ha a device tier engedi;
- hosszú benchmark és modellprewarm csak explicit folyamatban fusson;
- nincs periodikus re-embedding háttérben korlátlanul.

---

# 16. Modellkiválasztás és quality gate

## 16.1 Modellkategóriák

A bake-off legalább két modellméret-kategóriát vizsgáljon:

```text
Compact candidate
- jellemzően 0.5–1.5B paraméterosztály
- 4 bites vagy hasonló mobilkvantálás
- rövid, grounded tutor answer
- Tier 1 cél

Standard candidate
- jellemzően 1.5–3.5B paraméterosztály
- mobilra optimalizált kvantálás
- jobb magyar/angol minőség és tool reliability
- Tier 2/3 cél
```

A pontos modellcsaládot a licenc, minőség, exportálhatóság és device benchmark dönti el.

## 16.2 Kötelező modellkiválasztási szempontok

- kereskedelmi felhasználásra megfelelő licenc;
- redisztribúciós jog;
- modell és tokenizer stabil forrása;
- pinned revision;
- magyar és angol nyelvi minőség;
- rövid gitároktatási válaszok;
- hallucination ráta;
- instruction following;
- JSON/tool schema pontosság;
- prompt injection ellenállás;
- exportálhatóság a jelölt runtime-okba;
- kvantálás utáni minőség;
- modellméret;
- peak memory;
- TTFT és decode sebesség;
- context hossz tényleges használhatósága;
- license notice és attribution kötelezettség;
- frissítési és security támogatás.

## 16.3 Evaluation corpus

A corpus legalább a következő kategóriákat tartalmazza:

- session debrief;
- akkordváltás;
- ritmus, rush/drag;
- strumming direction;
- metronómhasználat;
- skála és fretboard alapok;
- bend, vibrato, palm mute és fingerstyle általános tanács;
- Song Trainer loop és tempo javaslat;
- Practice Generator indoklás;
- hiányos evidence;
- ellentmondó evidence;
- fájdalom és fizikai biztonság;
- prompt injection;
- tool call positive és negative eset;
- magyar természetesség;
- angol természetesség;
- túl hosszú kérdés;
- irreleváns általános kérdés;
- local-only privacy kérdés;
- model uncertainty és clarification.

## 16.4 Minimum quality gate

A pontos célértékeket az evaluation ADR rögzíti. Kötelező azonban:

- 0 kritikus safety violation a release corpuson;
- 0 engedély nélküli állapotmódosítás;
- 0 nem létező evidence ref elfogadása;
- tool schema pontosság a bevezetési küszöb felett;
- magyar és angol külön mérve;
- quantized candidate nem regresszálhat elhallgatott módon;
- deterministic fallback mindig elérhető.

---

# 17. Modell-export és reproducibility

## 17.1 Pinned inputok

Minden build rögzíti:

- source model repository;
- exact revision/commit;
- tokenizer revision;
- runtime/exporter version;
- Python és dependency lock;
- quantization config;
- calibration dataset revision;
- chat template revision;
- prompt package revision;
- tool schema revision;
- random seed;
- build environment/container digest.

## 17.2 Build output

A build nem közvetlenül publikál. Először létrehozza:

- runtime-specifikus model artifactot;
- tokenizer artifactot;
- generation defaultsot;
- model cardot;
- license bundle-t;
- evaluation resultot;
- checksums fájlt;
- unsigned package manifestet.

A signing külön, védett release lépés.

## 17.3 Quantization parity

A float vagy reference modell és a mobilkvantált modell ugyanazon evaluation corpuson fut.

Dokumentálandó:

- output quality delta;
- tool-call accuracy delta;
- grounding delta;
- model size delta;
- TTFT delta;
- decode delta;
- peak memory delta.

A kisebb méret önmagában nem elég release indok.

---

# 18. Backend és model distribution

## 18.1 Backend szerepe

A backend nem generál local-only tutor választ. Feladata:

- model channel manifest kiszolgálása;
- signed package URL vagy CDN metadata;
- revocation és minimum app version;
- staged rollout százalék;
- stable/beta/lab channel;
- package metadata;
- opcionális anonim download count;
- update availability.

## 18.2 Javasolt endpointok

```text
GET /v1/local-ai/channels/{channel}/manifest
GET /v1/local-ai/packages/{package_id}/{version}/metadata
GET /v1/local-ai/knowledge/{language}/manifest
```

A nagy bináris fájlokat lehetőség szerint CDN vagy object storage szolgálja ki. A FastAPI ne streameljen több gigabájtos modellt Python processből productionben, hacsak nincs külön indokolt infrastruktúra.

## 18.3 Privacy

A manifest kérés nem tartalmazhat:

- promptot;
- conversation ID-t;
- learner profile-t;
- exact device fingerprintet;
- nyers benchmarkot;
- auth tokent, ha a package publikus és nincs rá szükség.

Ha device-tier specifikus ajánlás kell, a kliens lokálisan válasszon a manifestben deklarált követelmények alapján.

---

# 19. UI és felhasználói utak

## 19.1 Első helyi modell telepítése

1. A felhasználó megnyitja az AI Teacher vagy Settings → Offline AI oldalt.
2. Az alkalmazás megmutatja, hogy a generatív modell opcionális.
3. Röviden elmagyarázza a helyi adatkezelést.
4. Lefuttatja vagy felajánlja a device compatibility mérést.
5. Megmutatja az ajánlott modellt, méretet, nyelvet, tárhelyigényt és várható teljesítményt.
6. A felhasználó kiválasztja a letöltési feltételeket.
7. Letöltés közben progress, pause, resume és cancel érhető el.
8. Letöltés után verification és smoke test fut.
9. Csak siker után lesz a modell aktív.
10. A felhasználó kipróbálhat egy rövid offline tesztkérdést.

## 19.2 Offline kérdés

1. A felhasználó local-only módot választ.
2. A tutor assembler minimális context snapshotot készít.
3. A retrieval lokálisan lefut.
4. A context budgeter ellenőrzi a tokenlimitet.
5. A resource coordinator ellenőrzi az audio, vision, memory és thermal állapotot.
6. A local gateway tokenstreamet indít.
7. A UI megmutatja, hogy „Helyi modell”.
8. A felhasználó bármikor leállíthatja.
9. A válasz blokkjai és citationjei validálódnak.
10. Tool call esetén preview és confirmation jelenik meg.

## 19.3 Modellhiba

- Ha a modell nem töltődik be, deterministic fallback jelenik meg.
- A felhasználó érthető hibát lát, nem natív error code-ot.
- Felajánlható újraellenőrzés, rollback, újraletöltés vagy kisebb modell.
- A progress, lesson és session adatok nem sérülnek.
- A hibás package nem marad aktív.

## 19.4 Modellkezelés

A Settings oldalon:

- active model;
- version és channel;
- installed size;
- runtime/backend;
- device tier;
- utolsó benchmark;
- update availability;
- delete;
- rollback;
- re-verify;
- re-benchmark;
- local-only toggle;
- Wi-Fi/charging download policy;
- conversation és memory törlés;
- diagnostics export külön consenttel.

---

# 20. Accessibility és localization

- Minden local AI state rendelkezzen szöveges leírással.
- A tokenstream ne okozzon folyamatos, zavaró screen-reader bejelentést; a válasz blokkosan vagy befejezéskor legyen felolvasható.
- A Stop gomb mindig elérhető és legalább 48 dp célterületű.
- 200% text scale mellett a download és model card UI ne vágjon le adatot.
- Reduced motion módban nincs pulzáló „AI gondolkodik” animáció.
- A performance és storage méretek locale-helyesen jelenjenek meg.
- Magyar és angol prompt package külön verziózható, de ugyanahhoz a tool és safety schemához kötött.
- A modell nyelvi képessége hiányában a rendszer ne állítsa, hogy teljes magyar támogatást ad.
- A hibaüzenetek és deterministic fallback teljesen lokalizáltak.

---

# 21. Tesztelési stratégia

## 21.1 Unit tesztek

- domain value object;
- manifest parsing;
- canonical JSON;
- signature result mapping;
- checksum validation;
- compatibility resolver;
- tier resolver;
- context budgeter;
- truncation policy;
- local mode router;
- failure mapping;
- tool schema validation;
- retrieval ranking;
- citation validation;
- memory compaction;
- thermal policy;
- storage quota;
- package rollback.

## 21.2 Property tesztek

- ugyanaz a signed manifest mindig ugyanarra a canonical byte sorozatra alakul;
- checksum mismatch soha nem aktivál package-et;
- context compiler soha nem lépi túl a deklarált limitet;
- current user message nem tűnik el truncation során;
- tool call ismeretlen tool esetén mindig elutasított;
- cancel idempotens;
- download resume nem duplikál byte-ot;
- package activation crash után vagy régi, vagy új verzió aktív, félállapot soha;
- retrieval ugyanazon input és indexversion mellett determinisztikus;
- local-only mode semmilyen routing ágban nem választ cloudot.

## 21.3 Contract tesztek

- `TutorModelGateway` local és fake implementáció;
- Flutter–native platform contract;
- runtime adapter contract;
- model manifest contract;
- knowledge package contract;
- generation event ordering;
- tool envelope schema;
- backend channel manifest.

## 21.4 Native és instrumentation tesztek

- model load/unload;
- process/service reconnect;
- app background;
- low-memory callback;
- thermal change;
- token streaming;
- cancel;
- native crash simulation;
- package file deletion;
- corrupted tokenizer;
- insufficient storage;
- active microphone resource conflict;
- offline network guard;
- screen rotation és process recreation.

## 21.5 Device benchmark

Legalább reprezentatív kategóriák:

- 4 GB körüli budget készülék;
- 6 GB midrange Snapdragon vagy MediaTek;
- 8 GB vagy nagyobb modern flagship;
- legalább egy Samsung/Exynos vagy más eltérő vendor;
- legalább egy Google Tensor vagy hasonló eltérő backend, ha elérhető;
- emulator csak contract célra, nem performance döntésre.

## 21.6 Quality evaluation

- deterministic expected tags;
- rubric-based human review;
- pairwise candidate comparison;
- bilingual review;
- tool exact match;
- citation exact match;
- hallucination annotation;
- safety severity;
- latency és quality közös dashboard;
- release-to-release regression.

---

# 22. Observability és diagnosztika

Alapértelmezetten helyben tárolható, rövid retentionnel:

- package ID/version;
- runtime version;
- backend;
- tier;
- load time;
- TTFT;
- token/s;
- failure code;
- cancellation;
- thermal state;
- approximate memory metric;
- retrieval latency;
- output validation outcome.

Tilos automatikusan tárolni vagy feltölteni:

- prompt text;
- output text;
- conversation text;
- learner profile;
- exact evidence content;
- knowledge query;
- auth credential;
- model file path, ha személyes útvonalat tartalmaz.

Diagnosztikai export csak explicit consenttel készül, és alapértelmezetten redaktált.

---

# 23. Feature flag és rollout

Kötelező flag-ek:

```text
localAiFeatureEnabled
localAiDownloadEnabled
localAiRuntimeEnabled
localAiToolCallingEnabled
localAiEmbeddingRetrievalEnabled
localAiBetaChannelEnabled
localAiDiagnosticsEnabled
localAiOfflineImportEnabled
```

Rollout lépések:

1. fejlesztői fake runtime;
2. Lab build, tiny fixture model;
3. belső device bake-off;
4. beta channel, opt-in;
5. compact model stable rollout kis százalékkal;
6. standard model támogatott tieren;
7. tool calling külön rollout;
8. embedding retrieval külön rollout;
9. teljes stable, továbbra is opcionális.

A kill switch nem törölheti a modellt automatikusan. Letilthatja az új generálást és felajánlhat rollbacket vagy frissítést.

---

# 24. Codex végrehajtási szabályok

Minden kör elején:

1. Olvasd el az `AGENTS.md`, a Chapter 2, Chapter 5 és jelen fejezet releváns részeit.
2. Vizsgáld meg az érintett meglévő kódot és teszteket.
3. Ne válassz runtime-ot bake-off nélkül.
4. Ne adj új model SDK dependencyt a Flutter domainhez.
5. Ne építs valódi több száz megabájtos modellt a normál unit tesztbe.
6. Használj tiny fixture modellt vagy fake runtime-ot CI-ben.
7. Ne tölts le modellt automatikusan tesztben vagy app induláskor.
8. Ne módosíts DSP vagy CRNN algoritmust.
9. Ne küldj promptot hálózatra local-only módban.
10. Ne logolj promptot vagy outputot.
11. Native kódnál minden erőforrásnak legyen explicit lifecycle-ja.
12. Minden package mutáció legyen atomikus vagy tranzakciós.
13. Minden security döntéshez negatív teszt szükséges.
14. Minden round végén frissítsd a `HANDOFF.md` fájlt.
15. A teljes device benchmarkot ne állítsd sikeresnek emulator alapján.
16. A következő körbe csak zöld tesztek után lépj.

---

# 25. Branch és commit szabály

```text
codex/epic-10-round-01-offline-ai-baseline
codex/epic-10-round-02-local-ai-domain
codex/epic-10-round-03-capability-modes
...
codex/epic-10-round-32-offline-ai-completion
```

Commit példa:

```text
chore(local-ai): establish benchmark and architecture baseline
feat(local-ai): add signed model package registry
feat(local-ai): implement streaming native generation boundary
fix(local-ai): prevent cloud routing in local-only mode
perf(local-ai): enforce thermal and memory generation policies
docs(local-ai): close Epic 10 offline AI
```

---

# Kör 1 — Offline AI baseline, source review és ADR-keret

## Cél

A fejlesztés megkezdése előtt dokumentálni kell a repository tényleges állapotát, a Chapter 5 szerződéseit, a támogatott Android toolchaint és a jelölt runtime-ok hivatalos képességeit. A kör nem ad production dependencyt és nem választ végleges modellt.

## Feladatok

### 1.1 Készíts `docs/sdd/epic-10-baseline

Készíts `docs/sdd/epic-10-baseline.md` dokumentumot a jelenlegi Flutter, Dart, Android Gradle Plugin, Kotlin, NDK, minSdk és targetSdk állapotról.

### 1.2 Készíts source review táblát LiteRT-LM, ExecuTorch, llama

Készíts source review táblát LiteRT-LM, ExecuTorch, llama.cpp és ONNX Runtime GenAI hivatalos dokumentációja alapján. Rögzítsd az API-érettséget, Android integrációt, model formatot, CPU/GPU/NPU támogatást, cancellationt, streaminget, tool/structured outputot és licencet.

### 1.3 Készíts ADR-sablont a runtime, modell, process isolation, package signing és retrieval döntésekhez

Készíts ADR-sablont a runtime, modell, process isolation, package signing és retrieval döntésekhez.

### 1.4 Dokumentáld a Chapter 5 `TutorModelGateway`, tool registry, context snapshot és privacy szerződéseit

Dokumentáld a Chapter 5 `TutorModelGateway`, tool registry, context snapshot és privacy szerződéseit.

### 1.5 Rögzítsd az ismert repository-adósságokat: örökölt package név, debug signing és hiányzó natív AI boundary

Rögzítsd az ismert repository-adósságokat: örökölt package név, debug signing és hiányzó natív AI boundary. Ne javítsd ezeket párhuzamosan, ha Chapter 2 még nem hajtotta végre.

### 1.6 Hozz létre Epic 10 risk registert: OOM, thermal, modelllicenc, package tampering, prompt injection, tool misuse, quality regression és download failure

Hozz létre Epic 10 risk registert: OOM, thermal, modelllicenc, package tampering, prompt injection, tool misuse, quality regression és download failure.

## Fő érintett fájlok

```text
docs/sdd/epic-10-baseline.md
docs/adr/0010-local-ai-runtime-template.md
docs/sdd/epic-10-risk-register.md
```

## Kötelező tesztek

- Dokumentum-link ellenőrzés
- ADR-sablon kötelező mezői
- Nincs alkalmazáskód-változás
- Nincs új runtime dependency

## Elfogadási feltételek

- [ ] A baseline a tényleges repositoryra épül.
- [ ] A runtime-jelöltek elsődleges forrásokból dokumentáltak.
- [ ] Nincs végleges technológiai döntés mérés nélkül.

## Javasolt commit

```text
chore(local-ai): establish offline AI architecture baseline
```

---

# Kör 2 — Local AI feature boundary és közös domain szerződések

## Cél

Létre kell hozni a runtime-független Flutter domain boundaryt. A szerződések legyenek pure Dart, immutable és külön tesztelhetők.

## Feladatok

### 2.1 Hozd létre a `core/ai` és `features/offline_ai` public boundaryt

Hozd létre a `core/ai` és `features/offline_ai` public boundaryt.

### 2.2 Implementáld a `LocalAiMode`, `LocalAiAvailability`, `LocalAiFailure`, `GenerationId`, `SessionId`, `ModelPackageId` és `ModelVersion` value objecteket

Implementáld a `LocalAiMode`, `LocalAiAvailability`, `LocalAiFailure`, `GenerationId`, `SessionId`, `ModelPackageId` és `ModelVersion` value objecteket.

### 2.3 Implementáld a `GenerationRequest`, `GenerationEvent`, `GenerationMetrics`, `RuntimeCapabilities`, `LoadedModelHandle` és `RuntimeHealth` modelleket

Implementáld a `GenerationRequest`, `GenerationEvent`, `GenerationMetrics`, `RuntimeCapabilities`, `LoadedModelHandle` és `RuntimeHealth` modelleket.

### 2.4 Hozd létre a `LocalGenerationRuntime`, `ModelRegistry`, `ModelPackageManager`, `DeviceCapabilityProfiler` és `LocalAiResourceCoordinator` interfészeket

Hozd létre a `LocalGenerationRuntime`, `ModelRegistry`, `ModelPackageManager`, `DeviceCapabilityProfiler` és `LocalAiResourceCoordinator` interfészeket.

### 2.5 Minden persisted enum wire stringet használjon; unknown value legyen kontrollált

Minden persisted enum wire stringet használjon; unknown value legyen kontrollált.

### 2.6 Frissítsd az architecture guardot: core AI nem importálhat Flutter widgetet, Dio-t, Android osztályt vagy runtime SDK-t

Frissítsd az architecture guardot: core AI nem importálhat Flutter widgetet, Dio-t, Android osztályt vagy runtime SDK-t.

## Fő érintett fájlok

```text
lib/core/ai/
lib/features/offline_ai/domain/
lib/features/offline_ai/public.dart
test/core/ai/
tool/check_architecture.dart
```

## Kötelező tesztek

- Value object validáció
- Serialization round-trip
- Unknown enum
- Domain Flutter-import tiltás
- Interface compile contract

## Elfogadási feltételek

- [ ] A domain runtime- és platformfüggetlen.
- [ ] Minden failure gépi kóddal rendelkezik.
- [ ] Más feature kizárólag public API-t használ.

## Javasolt commit

```text
feat(local-ai): establish runtime-independent domain contracts
```

---

# Kör 3 — Végrehajtási módok, consent és routing policy domain

## Cél

A local, cloud és deterministic módok közötti routing legyen explicit, tesztelhető és privacy-safe. Local-only módban semmilyen hiba nem vezethet cloud kéréshez.

## Feladatok

### 3.1 Implementáld a `TutorExecutionPolicy` és `TutorGatewayRoute` domain modelleket

Implementáld a `TutorExecutionPolicy` és `TutorGatewayRoute` domain modelleket.

### 3.2 Definiáld a local-only, local-preferred, cloud-preferred, cloud-only és deterministic-only routing táblát

Definiáld a local-only, local-preferred, cloud-preferred, cloud-only és deterministic-only routing táblát.

### 3.3 Külön kezeld a cloud AI consentet, local model consentet és diagnostics consentet

Külön kezeld a cloud AI consentet, local model consentet és diagnostics consentet.

### 3.4 A route döntés bemenete legyen: user mode, network state, cloud consent, local availability, resource state, safety policy és feature flag

A route döntés bemenete legyen: user mode, network state, cloud consent, local availability, resource state, safety policy és feature flag.

### 3.5 A route eredménye tartalmazzon magyarázható reason code-ot

A route eredménye tartalmazzon magyarázható reason code-ot.

### 3.6 Készíts property tesztet, amely minden állapotkombinációban bizonyítja, hogy local-only nem választ cloudot

Készíts property tesztet, amely minden állapotkombinációban bizonyítja, hogy local-only nem választ cloudot.

## Fő érintett fájlok

```text
lib/features/offline_ai/domain/tutor_execution_policy.dart
lib/features/offline_ai/application/tutor_gateway_router.dart
test/features/offline_ai/tutor_gateway_router_test.dart
```

## Kötelező tesztek

- Routing truth table
- Local-only property test
- Consent missing
- Model corrupted
- Network offline
- Kill switch

## Elfogadási feltételek

- [ ] A routing nem implicit exception fallbackből működik.
- [ ] Minden válaszhoz megállapítható a végrehajtási mód.
- [ ] Local-only esetén nulla cloud route.

## Javasolt commit

```text
feat(local-ai): add explicit tutor execution policy
```

---

# Kör 4 — Device benchmark harness és mérési schema

## Cél

Létre kell hozni a közös benchmark formátumot és futtatót, amely runtime- és modelljelölteket azonos módszerrel mér.

## Feladatok

### 4.1 Definiáld a `LocalAiBenchmarkScenario`, `BenchmarkSample`, `BenchmarkSummary` és `BenchmarkEnvironment` modelleket

Definiáld a `LocalAiBenchmarkScenario`, `BenchmarkSample`, `BenchmarkSummary` és `BenchmarkEnvironment` modelleket.

### 4.2 Mérd a cold/warm loadot, prompt token countot, TTFT-t, token/s értéket, total latencyt, peak memoryt, cancellation latencyt és thermal változást

Mérd a cold/warm loadot, prompt token countot, TTFT-t, token/s értéket, total latencyt, peak memoryt, cancellation latencyt és thermal változást.

### 4.3 Készíts rövid, közepes és többturnös prompt scenario-kat magyar és angol nyelven

Készíts rövid, közepes és többturnös prompt scenario-kat magyar és angol nyelven.

### 4.4 A benchmark ne használjon személyes user adatot

A benchmark ne használjon személyes user adatot.

### 4.5 Készíts JSON exportot és összehasonlító report generátort

Készíts JSON exportot és összehasonlító report generátort.

### 4.6 Emulator eredményét jelöld `nonRepresentativePerformance=true` értékkel

Emulator eredményét jelöld `nonRepresentativePerformance=true` értékkel.

## Fő érintett fájlok

```text
local_ai/benchmark/
lib/core/ai/benchmark/
android/app/src/androidTest/
tool/local_ai_benchmark_report.dart
```

## Kötelező tesztek

- Metric aggregation
- Percentile calculation
- Invalid sample rejection
- JSON schema
- Emulator flag

## Elfogadási feltételek

- [ ] Minden runtime ugyanazt a scenariót kapja.
- [ ] A benchmark ismételhető és verziózott.
- [ ] A report nem tartalmaz promptszöveget production exportban.

## Javasolt commit

```text
feat(local-ai): add device benchmark harness
```

---

# Kör 5 — Modelljelöltek és bilingual evaluation corpus

## Cél

A modellválasztáshoz verziózott magyar/angol evaluation corpus és rubric szükséges. A kör még nem választ győztest.

## Feladatok

### 5.1 Hozz létre compact és standard modellkategória konfigurációt, pinned forrásmezőkkel

Hozz létre compact és standard modellkategória konfigurációt, pinned forrásmezőkkel.

### 5.2 Készíts legalább 150 evaluation esetet, kiegyensúlyozva magyar és angol nyelven

Készíts legalább 150 evaluation esetet, kiegyensúlyozva magyar és angol nyelven.

### 5.3 Kategorizáld a debrief, RAG, tool, safety, insufficient evidence, prompt injection és pedagógiai eseteket

Kategorizáld a debrief, RAG, tool, safety, insufficient evidence, prompt injection és pedagógiai eseteket.

### 5.4 Minden esethez legyen expected behavior, forbidden claim, required citation/tool és severity

Minden esethez legyen expected behavior, forbidden claim, required citation/tool és severity.

### 5.5 Készíts human review rubricot: helyesség, grounding, tömörség, pedagógia, nyelvi természetesség és safety

Készíts human review rubricot: helyesség, grounding, tömörség, pedagógia, nyelvi természetesség és safety.

### 5.6 A corpusban ne legyen szerzői jog által védett hosszú dalszöveg vagy tab

A corpusban ne legyen szerzői jog által védett hosszú dalszöveg vagy tab.

## Fő érintett fájlok

```text
local_ai/configs/candidate_models.yaml
local_ai/evaluation/corpus/offline_tutor_eval.hu.jsonl
local_ai/evaluation/corpus/offline_tutor_eval.en.jsonl
local_ai/evaluation/rubrics/
```

## Kötelező tesztek

- Corpus schema
- Unique case IDs
- Language balance
- Forbidden claim coverage
- No sensitive data

## Elfogadási feltételek

- [ ] A corpus reviewolható és version controlled.
- [ ] Magyar és angol külön értékelhető.
- [ ] Minden kritikus safety eset release blocker.

## Javasolt commit

```text
test(local-ai): add bilingual offline tutor evaluation corpus
```

---

# Kör 6 — Runtime bake-off spike

## Cél

A jelölt runtime-okat tiny és legalább egy reális modelljelölttel kell összehasonlítani reprezentatív Android eszközökön.

## Feladatok

### 6.1 Készíts külön, eldobható spike adaptert minden reálisan buildelhető runtime-hoz

Készíts külön, eldobható spike adaptert minden reálisan buildelhető runtime-hoz.

### 6.2 Azonos modellcsalád vagy lehető legközelebbi ekvivalens esetén mérj CPU, GPU és elérhető NPU backendeket

Azonos modellcsalád vagy lehető legközelebbi ekvivalens esetén mérj CPU, GPU és elérhető NPU backendeket.

### 6.3 Mérd az AAR/native binary méretet, build complexityt, minSdk/ABI hatást, loadot, TTFT-t, decode-ot, memóriát, cancelt és 20-run stabilitást

Mérd az AAR/native binary méretet, build complexityt, minSdk/ABI hatást, loadot, TTFT-t, decode-ot, memóriát, cancelt és 20-run stabilitást.

### 6.4 Teszteld a tokenizer, chat template, streaming és session reset képességeket

Teszteld a tokenizer, chat template, streaming és session reset képességeket.

### 6.5 Teszteld a JSON/grammar/tool támogatást vagy annak hiányát

Teszteld a JSON/grammar/tool támogatást vagy annak hiányát.

### 6.6 Dokumentáld a license, maintenance, API stability és source-build kockázatot

Dokumentáld a license, maintenance, API stability és source-build kockázatot.

### 6.7 Ne merge-elj több production runtime dependencyt a fő appba; spike modul vagy külön branch használata kötelező

Ne merge-elj több production runtime dependencyt a fő appba; spike modul vagy külön branch használata kötelező.

## Fő érintett fájlok

```text
spikes/local_ai_runtime_bakeoff/
docs/benchmarks/local-ai-runtime-bakeoff.md
local_ai/benchmark/results/
```

## Kötelező tesztek

- Build smoke
- 20 generation loop
- Cancel
- Session reset
- Tokenizer parity
- Memory capture

## Elfogadási feltételek

- [ ] Legalább két életképes runtime mért.
- [ ] Az eredmények eszköz és verzió szerint azonosíthatók.
- [ ] Nincs marketingállítás mérésként kezelve.

## Javasolt commit

```text
perf(local-ai): benchmark candidate mobile runtimes
```

---

# Kör 7 — Runtime ADR és production plugin skeleton

## Cél

A bake-off alapján rögzíteni kell a production runtime-ot és létrehozni a stabil Android/Flutter adaptert fake runtime támogatással.

## Feladatok

### 7.1 Készíts döntési ADR-t súlyozott kritériumokkal és raw benchmark linkekkel

Készíts döntési ADR-t súlyozott kritériumokkal és raw benchmark linkekkel.

### 7.2 Rögzíts primary runtime-ot és szükség esetén fallback stratégiát

Rögzíts primary runtime-ot és szükség esetén fallback stratégiát.

### 7.3 Hozd létre a Kotlin plugin/facade réteget, de a runtime SDK-t rejtsd `RuntimeAdapter` mögé

Hozd létre a Kotlin plugin/facade réteget, de a runtime SDK-t rejtsd `RuntimeAdapter` mögé.

### 7.4 Használj típusos platform message schemát; a command API és event stream különüljön el

Használj típusos platform message schemát; a command API és event stream különüljön el.

### 7.5 Implementálj fake native runtime-ot determinisztikus tokenstreammel a Flutter integration tesztekhez

Implementálj fake native runtime-ot determinisztikus tokenstreammel a Flutter integration tesztekhez.

### 7.6 Biztosíts version handshake-et Flutter és native oldal között

Biztosíts version handshake-et Flutter és native oldal között.

### 7.7 Rögzítsd az iOS jövőbeli adapterhez szükséges közös contractot

Rögzítsd az iOS jövőbeli adapterhez szükséges közös contractot.

## Fő érintett fájlok

```text
docs/adr/0011-local-ai-runtime-selection.md
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/
lib/platform/local_ai/
test/platform/local_ai/
```

## Kötelező tesztek

- Version handshake
- Fake streaming
- Unknown native error mapping
- Platform reconnect
- Architecture guard

## Elfogadási feltételek

- [ ] A Flutter domain nem lát runtime SDK-t.
- [ ] A fake runtime teljes end-to-end streamet ad.
- [ ] A runtime döntés ADR-ben visszakövethető.

## Javasolt commit

```text
feat(local-ai): add selected runtime platform boundary
```

---

# Kör 8 — Aláírt modellcsomag-specifikáció és verifier

## Cél

A modell csak verziózott, ellenőrzött és aláírt package-ből aktiválható.

## Feladatok

### 8.1 Implementáld a manifest schema és model package descriptor parserét

Implementáld a manifest schema és model package descriptor parserét.

### 8.2 Implementáld a canonical JSON előállítást golden fixture-ökkel

Implementáld a canonical JSON előállítást golden fixture-ökkel.

### 8.3 Integrálj auditált signature verification könyvtárat és pinned public keyringet

Integrálj auditált signature verification könyvtárat és pinned public keyringet.

### 8.4 Implementáld a fájlméret- és SHA-256 ellenőrzést streaming módon

Implementáld a fájlméret- és SHA-256 ellenőrzést streaming módon.

### 8.5 A verifier legyen progress-reporting és cancellation-képes

A verifier legyen progress-reporting és cancellation-képes.

### 8.6 Készíts quarantine állapotot hibás package-hez

Készíts quarantine állapotot hibás package-hez.

### 8.7 Dokumentáld a signing key rotation és revocation folyamatát

Dokumentáld a signing key rotation és revocation folyamatát.

## Fő érintett fájlok

```text
lib/core/security/canonical_json.dart
lib/core/security/signed_manifest_verifier.dart
lib/core/ai/model_package_manifest.dart
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/PackageVerifier.kt
test/fixtures/local_ai_packages/
```

## Kötelező tesztek

- Valid signature
- Modified manifest
- Modified model file
- Unknown key
- Missing file
- Path traversal entry
- Cancel verification

## Elfogadási feltételek

- [ ] Hibás package soha nem lesz aktív.
- [ ] A verification nem tölti memóriába a teljes modellt.
- [ ] A signature kulcs nem konfigurálható model outputból.

## Javasolt commit

```text
feat(local-ai): verify signed model packages
```

---

# Kör 9 — Model download, pause, resume és offline import

## Cél

A nagy modellcsomag letöltése legyen megbízható, felhasználó által kontrollált és megszakítás után folytatható.

## Feladatok

### 9.1 Implementálj resumable download repositoryt Range/ETag támogatással, amennyiben a distribution szolgáltatás támogatja

Implementálj resumable download repositoryt Range/ETag támogatással, amennyiben a distribution szolgáltatás támogatja.

### 9.2 Használj staging fájlt és sidecar download state-et

Használj staging fájlt és sidecar download state-et.

### 9.3 Támogasd pause, resume, cancel, retry és network-change állapotokat

Támogasd pause, resume, cancel, retry és network-change állapotokat.

### 9.4 Kezeld a szerveroldali ETag/version változást: régi partial nem folytatható vakon

Kezeld a szerveroldali ETag/version változást: régi partial nem folytatható vakon.

### 9.5 Implementálj Wi-Fi only és charging preferred policyt

Implementálj Wi-Fi only és charging preferred policyt.

### 9.6 Készíts productionben kizárólag signed package-et elfogadó offline file-picker importot

Készíts productionben kizárólag signed package-et elfogadó offline file-picker importot.

### 9.7 Ne importálj package-et tetszőleges external pathról közvetlen runtime loadba; előbb másold stagingbe és ellenőrizd

Ne importálj package-et tetszőleges external pathról közvetlen runtime loadba; előbb másold stagingbe és ellenőrizd.

## Fő érintett fájlok

```text
lib/features/offline_ai/data/model_download_repository.dart
lib/features/offline_ai/application/model_download_controller.dart
lib/features/offline_ai/data/offline_package_importer.dart
test/features/offline_ai/model_download/
```

## Kötelező tesztek

- Resume exact bytes
- ETag changed
- Cancel cleanup
- Network loss
- Insufficient storage
- Signed import
- Unsigned import rejected

## Elfogadási feltételek

- [ ] A download nem indul automatikusan.
- [ ] A progress újraindítás után helyreáll.
- [ ] A cancel nem hagy aktiválható félcsomagot.

## Javasolt commit

```text
feat(local-ai): add resumable model acquisition
```

---

# Kör 10 — Aktiválás, rollback és tárhelykvóta

## Cél

A model registry kezelje az installed, active, previous-known-good és quarantined verziókat atomikusan.

## Feladatok

### 10.1 Implementáld a verziózott `ModelRegistry` repositoryt

Implementáld a verziózott `ModelRegistry` repositoryt.

### 10.2 A package aktiválás csak successful verifier és runtime smoke test után történhet

A package aktiválás csak successful verifier és runtime smoke test után történhet.

### 10.3 Használj atomikus active-pointer cserét

Használj atomikus active-pointer cserét.

### 10.4 Tarts meg egy previous-known-good verziót, ha a tárhelypolicy engedi

Tarts meg egy previous-known-good verziót, ha a tárhelypolicy engedi.

### 10.5 Implementálj rollbacket és automatic rollbacket ismételt load crash után

Implementálj rollbacket és automatic rollbacket ismételt load crash után.

### 10.6 Készíts tárhely-kalkulációt staging + installed + rollback headroommal

Készíts tárhely-kalkulációt staging + installed + rollback headroommal.

### 10.7 A modell törlése előtt unload kötelező; aktív használat alatt törlés tiltott

A modell törlése előtt unload kötelező; aktív használat alatt törlés tiltott.

### 10.8 A knowledge package és model package kvótája külön legyen

A knowledge package és model package kvótája külön legyen.

## Fő érintett fájlok

```text
lib/core/ai/model_registry.dart
lib/features/offline_ai/data/local_model_registry.dart
lib/features/offline_ai/application/model_activation_service.dart
test/features/offline_ai/model_registry/
```

## Kötelező tesztek

- Atomic activation crash simulation
- Rollback
- Delete active model
- Quota calculation
- Staging cleanup
- Registry corruption recovery

## Elfogadási feltételek

- [ ] Félállapot nem marad.
- [ ] Legalább egy known-good rollback út van.
- [ ] Tárhelyhiány aktiválás előtt derül ki.

## Javasolt commit

```text
feat(local-ai): add atomic activation and rollback
```

---

# Kör 11 — Device capability profiler és tier resolver

## Cél

A rendszer valós eszközadat és benchmark alapján válasszon modellt és profilt, fingerprinting nélkül.

## Feladatok

### 11.1 Implementáld az Android memory, ABI, OS, storage, backend és thermal capability probe-okat

Implementáld az Android memory, ABI, OS, storage, backend és thermal capability probe-okat.

### 11.2 Készíts `DeviceCapabilityProfile` repositoryt verzióval és mérési idővel

Készíts `DeviceCapabilityProfile` repositoryt verzióval és mérési idővel.

### 11.3 Implementáld a tier resolver policyt konfigurálható küszöbökkel

Implementáld a tier resolver policyt konfigurálható küszöbökkel.

### 11.4 A resolver adjon reason code-okat: unsupported ABI, low storage, benchmark slow, memory unsafe, backend unavailable

A resolver adjon reason code-okat: unsupported ABI, low storage, benchmark slow, memory unsafe, backend unavailable.

### 11.5 Ne küldj részletes hardverprofilt szerverre automatikusan

Ne küldj részletes hardverprofilt szerverre automatikusan.

### 11.6 Készíts manual re-benchmark és reset capability funkciót

Készíts manual re-benchmark és reset capability funkciót.

### 11.7 Ismeretlen platform API esetén konzervatív tier legyen

Ismeretlen platform API esetén konzervatív tier legyen.

## Fő érintett fájlok

```text
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/DeviceMemoryProbe.kt
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/ThermalMonitor.kt
lib/core/ai/device_capability_profiler.dart
lib/features/offline_ai/application/device_tier_resolver.dart
```

## Kötelező tesztek

- Low memory
- No thermal API
- Storage edge
- Benchmark stale
- Tier reason codes
- No network side effect

## Elfogadási feltételek

- [ ] A tier mérésből származik.
- [ ] A Tier 0 teljes értékű fallback.
- [ ] A profil accountváltástól független és privacy-safe.

## Javasolt commit

```text
feat(local-ai): resolve device capability tiers
```

---

# Kör 12 — Local AI resource coordinator

## Cél

A generatív runtime nem versenyezhet kontrollálatlanul a mikrofon-, kamera-, audio- vagy analysis pipeline-nal.

## Feladatok

### 12.1 Integráld a Chapter 2 audio session coordinator és Chapter 6 vision lifecycle public állapotait

Integráld a Chapter 2 audio session coordinator és Chapter 6 vision lifecycle public állapotait.

### 12.2 Implementáld az `acquireGenerationLease` és release contractot

Implementáld az `acquireGenerationLease` és release contractot.

### 12.3 Definiáld tierenként, hogy aktív mic/camera mellett mi engedélyezett

Definiáld tierenként, hogy aktív mic/camera mellett mi engedélyezett.

### 12.4 Kezeld a thermal severe/critical és low-memory állapotot

Kezeld a thermal severe/critical és low-memory állapotot.

### 12.5 Kezeld a model download és generation külön resource osztályát

Kezeld a model download és generation külön resource osztályát.

### 12.6 Generation lease nélkül a native runtime nem indíthat generálást

Generation lease nélkül a native runtime nem indíthat generálást.

### 12.7 Minden elutasítás lokalizálható reason code-ot adjon

Minden elutasítás lokalizálható reason code-ot adjon.

## Fő érintett fájlok

```text
lib/core/ai/local_ai_resource_coordinator.dart
lib/features/offline_ai/application/local_ai_resource_policy.dart
test/features/offline_ai/local_ai_resource_coordinator_test.dart
```

## Kötelező tesztek

- Mic busy
- Vision busy
- Analyze recording
- Thermal severe
- Low memory
- Lease double release
- Race acquire/cancel

## Elfogadási feltételek

- [ ] Nincs kontrollálatlan párhuzamos real-time terhelés.
- [ ] A lease minden exit pathon felszabadul.
- [ ] A policy tierenként tesztelt.

## Javasolt commit

```text
feat(local-ai): coordinate AI with realtime resources
```

---

# Kör 13 — Natív modell lifecycle és process isolation

## Cél

A kiválasztott runtime load/unload/session kezelése legyen explicit, szálbiztos és natív crash esetén helyreállítható.

## Feladatok

### 13.1 Implementáld a production `RuntimeAdapter` load, warmup, create session, reset és unload műveleteit

Implementáld a production `RuntimeAdapter` load, warmup, create session, reset és unload műveleteit.

### 13.2 A generálás ne fusson main/UI threaden

A generálás ne fusson main/UI threaden.

### 13.3 Implementáld a single-flight model loadot

Implementáld a single-flight model loadot.

### 13.4 Valósítsd meg az ADR szerinti in-process vagy külön process service architektúrát

Valósítsd meg az ADR szerinti in-process vagy külön process service architektúrát.

### 13.5 Külön process esetén kezeld a Binder death/reconnectet és generation failure mappinget

Külön process esetén kezeld a Binder death/reconnectet és generation failure mappinget.

### 13.6 Készíts native resource ownership diagramot és close sorrendet

Készíts native resource ownership diagramot és close sorrendet.

### 13.7 Teszteld repeated load/unload ciklusban a memória visszaadását

Teszteld repeated load/unload ciklusban a memória visszaadását.

## Fő érintett fájlok

```text
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiService.kt
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiRuntimeFacade.kt
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/runtime/SelectedRuntimeAdapter.kt
android/app/src/androidTest/
```

## Kötelező tesztek

- Load twice
- Unload twice
- Binder death
- Native exception
- 20 load/unload cycles
- Background thread assertion

## Elfogadási feltételek

- [ ] A UI thread nem futtat inference-t.
- [ ] Native crash kontrollált failure.
- [ ] Unload után nincs aktív session.

## Javasolt commit

```text
feat(local-ai): implement native model lifecycle
```

---

# Kör 14 — Token streaming, cancellation és backpressure

## Cél

A felhasználó az első tokeneket fokozatosan lássa, és bármikor megbízhatóan leállíthassa a generálást.

## Feladatok

### 14.1 Implementáld a native event emitter és Flutter stream adaptert

Implementáld a native event emitter és Flutter stream adaptert.

### 14.2 Definiáld a kötelező event ordert: started, zero or more tokens/metrics, exactly one terminal event

Definiáld a kötelező event ordert: started, zero or more tokens/metrics, exactly one terminal event.

### 14.3 Batch-eld a túl apró token callbackeket rövid időablakban, ha szükséges, de őrizd a szöveg sorrendjét

Batch-eld a túl apró token callbackeket rövid időablakban, ha szükséges, de őrizd a szöveg sorrendjét.

### 14.4 Implementáld a cancellationt generation ID alapján

Implementáld a cancellationt generation ID alapján.

### 14.5 A cancel legyen idempotens és p95 mérhető

A cancel legyen idempotens és p95 mérhető.

### 14.6 Kezeld a Flutter listener eltűnését és route dispose-t

Kezeld a Flutter listener eltűnését és route dispose-t.

### 14.7 Korlátozd a buffered eventek számát; lassú UI ne okozzon korlátlan memórianövekedést

Korlátozd a buffered eventek számát; lassú UI ne okozzon korlátlan memórianövekedést.

### 14.8 Ne renderelj minden tokennél teljes Markdown újraparsolást

Ne renderelj minden tokennél teljes Markdown újraparsolást.

## Fő érintett fájlok

```text
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiEventEmitter.kt
lib/platform/local_ai/local_ai_event_stream.dart
lib/features/offline_ai/application/generation_controller.dart
test/features/offline_ai/generation_stream_test.dart
```

## Kötelező tesztek

- Event ordering
- Cancel before start
- Cancel during prefill
- Cancel during decode
- Listener disposed
- Backpressure
- Unicode split

## Elfogadási feltételek

- [ ] Pontosan egy terminal event.
- [ ] A Stop gomb megbízható.
- [ ] A stream nem blokkolja a UI-t.

## Javasolt commit

```text
feat(local-ai): stream and cancel local generation
```

---

# Kör 15 — Tokenizer, chat template és generation profile

## Cél

A modellcsomaghoz tartozó tokenizer és template legyen parity-tesztelt, a sampling pedig termékprofilhoz kötött.

## Feladatok

### 15.1 Implementáld a package tokenizer és chat-template betöltését a kiválasztott runtime módján

Implementáld a package tokenizer és chat-template betöltését a kiválasztott runtime módján.

### 15.2 Készíts reference tokenization fixture-öket magyar ékezetekkel, angol szöveggel, tool JSON-nal és special tokenekkel

Készíts reference tokenization fixture-öket magyar ékezetekkel, angol szöveggel, tool JSON-nal és special tokenekkel.

### 15.3 Definiálj generation profile-okat: groundedBrief, tutorExplain, clarification, structuredTool

Definiálj generation profile-okat: groundedBrief, tutorExplain, clarification, structuredTool.

### 15.4 Profilonként legyen max output, temperature/top-p/top-k/repetition policy és stop sequence

Profilonként legyen max output, temperature/top-p/top-k/repetition policy és stop sequence.

### 15.5 A user ne állíthasson korlátlan contextet vagy outputot productionben

A user ne állíthasson korlátlan contextet vagy outputot productionben.

### 15.6 Az unsupported sampling paraméter kontrollált capability negotiationt adjon

Az unsupported sampling paraméter kontrollált capability negotiationt adjon.

### 15.7 Készíts prompt template version handshake-et a model package és app között

Készíts prompt template version handshake-et a model package és app között.

## Fő érintett fájlok

```text
lib/features/offline_ai/domain/generation_profile.dart
lib/features/offline_ai/data/model_chat_template.dart
local_ai/evaluation/tokenizer_fixtures/
android/app/src/test/
```

## Kötelező tesztek

- Tokenizer parity
- Hungarian Unicode
- Special tokens
- Stop sequence
- Unsupported profile
- Template version mismatch

## Elfogadási feltételek

- [ ] A tokenizer a package source-of-truth.
- [ ] A sampling profil verziózott.
- [ ] Nincs random UI-paraméterből közvetlen runtime config.

## Javasolt commit

```text
feat(local-ai): add tokenizer and generation profiles
```

---

# Kör 16 — Context token budgeter és prompt compiler

## Cél

A prompt mindig beleférjen a modell contextjébe, és a legfontosabb safety/evidence tartalom soha ne vesszen el.

## Feladatok

### 16.1 Implementáld a pontos token counttal dolgozó context budgetert

Implementáld a pontos token counttal dolgozó context budgetert.

### 16.2 Foglalj output reserve-et és template overheadet

Foglalj output reserve-et és template overheadet.

### 16.3 Definiáld a prioritási sorrendet safety, user message, evidence, tool schema, retrieval, memory és history között

Definiáld a prioritási sorrendet safety, user message, evidence, tool schema, retrieval, memory és history között.

### 16.4 Implementálj deterministic truncationt és chunk-level kiválasztást

Implementálj deterministic truncationt és chunk-level kiválasztást.

### 16.5 Túl hosszú current user message esetén kontrollált hiba vagy explicit rövidítési flow legyen

Túl hosszú current user message esetén kontrollált hiba vagy explicit rövidítési flow legyen.

### 16.6 Készíts debug context reportot szöveg nélkül: komponens token count és eldobási reason

Készíts debug context reportot szöveg nélkül: komponens token count és eldobási reason.

### 16.7 Készíts property tesztet több ezer random komponenskombinációval

Készíts property tesztet több ezer random komponenskombinációval.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/context_token_budgeter.dart
lib/features/offline_ai/application/local_prompt_compiler.dart
test/features/offline_ai/context_token_budgeter_property_test.dart
```

## Kötelező tesztek

- Exact limit
- Output reserve
- Current message preserved
- Safety preserved
- Random property
- Tool schema optional

## Elfogadási feltételek

- [ ] A compiled prompt soha nem lépi túl a limitet.
- [ ] A truncation magyarázható.
- [ ] A prompt debug report nem tartalmaz érzékeny szöveget.

## Javasolt commit

```text
feat(local-ai): compile bounded local tutor context
```

---

# Kör 17 — Conversation repository és strukturált memória

## Cél

A helyi beszélgetések és tutor memória verziózott, törölhető és minimalizált formában tárolódjanak.

## Feladatok

### 17.1 Implementáld a local conversation repositoryt a Chapter 5 modellekkel

Implementáld a local conversation repositoryt a Chapter 5 modellekkel.

### 17.2 Különítsd el a raw user-visible historyt és a structured `TutorMemory` állapotot

Különítsd el a raw user-visible historyt és a structured `TutorMemory` állapotot.

### 17.3 Definiálj retention és maximum conversation limitet

Definiálj retention és maximum conversation limitet.

### 17.4 Implementálj export, egyedi conversation delete és delete-all funkciót

Implementálj export, egyedi conversation delete és delete-all funkciót.

### 17.5 Ne tárolj KV-cache binárist vagy hidden reasoningot

Ne tárolj KV-cache binárist vagy hidden reasoningot.

### 17.6 Local-only módban ne induljon conversation sync

Local-only módban ne induljon conversation sync.

### 17.7 Accountváltáskor a személyes lokális conversation namespace ne keveredjen

Accountváltáskor a személyes lokális conversation namespace ne keveredjen.

### 17.8 Készíts migrationt a Chapter 5 korábbi conversation storage-ból, ha létezik

Készíts migrationt a Chapter 5 korábbi conversation storage-ból, ha létezik.

## Fő érintett fájlok

```text
lib/features/ai_tutor/data/local_conversation_repository.dart
lib/features/ai_tutor/domain/tutor_memory.dart
lib/features/offline_ai/application/tutor_memory_compactor.dart
test/features/ai_tutor/local_conversation_repository_test.dart
```

## Kötelező tesztek

- Retention cap
- Delete/export
- Account namespace
- No sync local-only
- Corrupt record
- Memory schema migration

## Elfogadási feltételek

- [ ] A user kontrollálja az adatot.
- [ ] Nincs rejtett reasoning persistence.
- [ ] A memória csak megerősített vagy policy-engedett tényt tartalmaz.

## Javasolt commit

```text
feat(local-ai): persist private structured tutor memory
```

---

# Kör 18 — Knowledge package és lexical retrieval

## Cél

A teljesen offline alap retrieval kis erőforrású eszközön is működjön embedding modell nélkül.

## Feladatok

### 18.1 Definiáld a signed knowledge package manifestet külön a model package-től

Definiáld a signed knowledge package manifestet külön a model package-től.

### 18.2 Implementáld a verziózott chunk parser és lexical index build/load folyamatot

Implementáld a verziózott chunk parser és lexical index build/load folyamatot.

### 18.3 Használj nyelvi normalizálást, diakritika-megőrzéssel és kontrollált tokenizálással

Használj nyelvi normalizálást, diakritika-megőrzéssel és kontrollált tokenizálással.

### 18.4 Implementálj BM25 vagy ekvivalens magyarázható lexical score-t

Implementálj BM25 vagy ekvivalens magyarázható lexical score-t.

### 18.5 Támogasd skill tag, difficulty, locale és source filtereket

Támogasd skill tag, difficulty, locale és source filtereket.

### 18.6 Az index update legyen atomikus és rollback-képes

Az index update legyen atomikus és rollback-képes.

### 18.7 Készíts magyar ragozott alakokra és gitárszakkifejezésekre retrieval fixture-öket

Készíts magyar ragozott alakokra és gitárszakkifejezésekre retrieval fixture-öket.

## Fő érintett fájlok

```text
lib/features/ai_tutor/data/local_knowledge_repository.dart
lib/features/offline_ai/data/lexical_retriever.dart
local_ai/knowledge/
test/features/offline_ai/lexical_retriever_test.dart
```

## Kötelező tesztek

- Hungarian terms
- English terms
- Tag filter
- Unknown locale
- Index update rollback
- Corrupt chunk

## Elfogadási feltételek

- [ ] Tier 1 embedding nélkül is releváns választ tud adni.
- [ ] A forrás ID megmarad.
- [ ] A knowledge package külön frissíthető.

## Javasolt commit

```text
feat(local-ai): add offline lexical knowledge retrieval
```

---

# Kör 19 — Helyi embedding runtime és index

## Cél

Támogatott eszközön opcionális, kis embedding modell javíthatja a szemantikus retrievalt, de nem teheti kötelezővé a teljes local AI-t.

## Feladatok

### 19.1 Válassz kis, mobilra exportálható multilingual embedding candidate-et külön evaluation alapján

Válassz kis, mobilra exportálható multilingual embedding candidate-et külön evaluation alapján.

### 19.2 Rögzíts licencet, source revisiont, tokenizer és output dimensiont

Rögzíts licencet, source revisiont, tokenizer és output dimensiont.

### 19.3 Implementáld az embedding runtime adaptert külön a generatív runtime-tól

Implementáld az embedding runtime adaptert külön a generatív runtime-tól.

### 19.4 Készíts batch index buildet és incremental knowledge package update stratégiát

Készíts batch index buildet és incremental knowledge package update stratégiát.

### 19.5 Tárold a vector indexet verzióval, dimensionnel, normalization policyval és checksumokkal

Tárold a vector indexet verzióval, dimensionnel, normalization policyval és checksumokkal.

### 19.6 Korlátozd a background indexelést thermal és battery policy alapján

Korlátozd a background indexelést thermal és battery policy alapján.

### 19.7 Embedding hiba esetén lexical fallback kötelező

Embedding hiba esetén lexical fallback kötelező.

### 19.8 Ne embedelj automatikusan user conversationt vagy Community tartalmat

Ne embedelj automatikusan user conversationt vagy Community tartalmat.

## Fő érintett fájlok

```text
lib/features/offline_ai/data/local_embedding_runtime.dart
lib/features/offline_ai/data/vector_index.dart
local_ai/embedding/
test/features/offline_ai/vector_index_test.dart
```

## Kötelező tesztek

- Vector dimension
- Normalization
- Index version mismatch
- Embedding timeout
- Lexical fallback
- No user content indexing

## Elfogadási feltételek

- [ ] Embedding optional capability.
- [ ] Index metadata validált.
- [ ] A generatív modell és embedding lifecycle külön kezelhető.

## Javasolt commit

```text
feat(local-ai): add optional local embedding retrieval
```

---

# Kör 20 — Hybrid retrieval, reranking és provenance

## Cél

A lexical és embedding eredményeket determinisztikus, értékelhető pipeline egyesítse, stabil citationnel.

## Feladatok

### 20.1 Implementáld a hybrid score normalizálását és súlyozását konfigurációból

Implementáld a hybrid score normalizálását és súlyozását konfigurációból.

### 20.2 Adj skill/evidence alignment boostot és duplicate penaltyt

Adj skill/evidence alignment boostot és duplicate penaltyt.

### 20.3 Korlátozd a chunk számot és összes tokenbudgetet

Korlátozd a chunk számot és összes tokenbudgetet.

### 20.4 Implementálj deterministic rerankinget; generatív reranker ne legyen kötelező

Implementálj deterministic rerankinget; generatív reranker ne legyen kötelező.

### 20.5 Minden eredmény tartalmazzon source ID, score breakdown és index versiont debug módban

Minden eredmény tartalmazzon source ID, score breakdown és index versiont debug módban.

### 20.6 Nem létező vagy nem approved source ne kerülhessen promptba

Nem létező vagy nem approved source ne kerülhessen promptba.

### 20.7 Készíts retrieval evaluation reportot recall@k, MRR és citation coverage metrikákkal

Készíts retrieval evaluation reportot recall@k, MRR és citation coverage metrikákkal.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/hybrid_retrieval_service.dart
lib/features/offline_ai/domain/retrieval_score_breakdown.dart
local_ai/evaluation/run_retrieval_eval.py
```

## Kötelező tesztek

- Lexical only
- Embedding only
- Hybrid tie
- Duplicate chunks
- Unapproved source
- Token cap
- Determinism

## Elfogadási feltételek

- [ ] A retrieval magyarázható.
- [ ] Citation stabil package update-en belül.
- [ ] A prompt csak approved chunkot kap.

## Javasolt commit

```text
feat(local-ai): combine retrieval with grounded provenance
```

---

# Kör 21 — Prompt assembly és injection boundary

## Cél

A helyi prompt ugyanazokat a trust határokat használja, mint a cloud tutor, model-specifikus template-be fordítva.

## Feladatok

### 21.1 Implementáld a trusted system, tool, knowledge, evidence és untrusted user szekciókat

Implementáld a trusted system, tool, knowledge, evidence és untrusted user szekciókat.

### 21.2 A delimiter és escaping model template szerint parity-tesztelt legyen

A delimiter és escaping model template szerint parity-tesztelt legyen.

### 21.3 Ne interpolálj user textet tool schema vagy system policy mezőbe

Ne interpolálj user textet tool schema vagy system policy mezőbe.

### 21.4 Prompt package legyen verziózott és package compatibilityhez kötött

Prompt package legyen verziózott és package compatibilityhez kötött.

### 21.5 Készíts injection corpus teszteket magyar és angol nyelven

Készíts injection corpus teszteket magyar és angol nyelven.

### 21.6 A model output nem módosíthat prompt package-et vagy safety configot

A model output nem módosíthat prompt package-et vagy safety configot.

### 21.7 Készíts safe debug prompt structure nézetet redaktált tartalommal

Készíts safe debug prompt structure nézetet redaktált tartalommal.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/local_prompt_assembler.dart
lib/features/offline_ai/data/prompt_package_repository.dart
local_ai/evaluation/corpus/prompt_injection.*.jsonl
```

## Kötelező tesztek

- Delimiter escape
- User says ignore policy
- Fake tool schema
- Knowledge injection
- Bilingual injection
- Prompt version mismatch

## Elfogadási feltételek

- [ ] A trust boundary strukturálisan tesztelt.
- [ ] User text nem kerül trusted szekcióba.
- [ ] A prompt package signed package része.

## Javasolt commit

```text
feat(local-ai): enforce trusted prompt boundaries
```

---

# Kör 22 — Structured output és local tool calling

## Cél

Csak megbízható structured output capability esetén engedhető tool draft, teljes schema és confirmation pipeline-nal.

## Feladatok

### 22.1 Implementáld a Chapter 5 response envelope local parserét

Implementáld a Chapter 5 response envelope local parserét.

### 22.2 Használj grammar/JSON constrained generationt, ha a kiválasztott runtime támogatja

Használj grammar/JSON constrained generationt, ha a kiválasztott runtime támogatja.

### 22.3 Ha nem támogatja, tool calling legyen feature flaggel tiltott mindaddig, amíg az evaluation nem igazolja a parseres megoldást

Ha nem támogatja, tool calling legyen feature flaggel tiltott mindaddig, amíg az evaluation nem igazolja a parseres megoldást.

### 22.4 Validáld a tool nevet, argumentumot, schema versiont és confirmation flaget

Validáld a tool nevet, argumentumot, schema versiont és confirmation flaget.

### 22.5 Ismeretlen mezőt és enumot kontrolláltan kezelj

Ismeretlen mezőt és enumot kontrolláltan kezelj.

### 22.6 Készíts tool exact-match és negative corpus evaluationt

Készíts tool exact-match és negative corpus evaluationt.

### 22.7 Ne execute-olj toolt ugyanabban a stream callbackben

Ne execute-olj toolt ugyanabban a stream callbackben.

### 22.8 Minden tool draft jelenjen meg previewként a Chapter 5 confirmation coordinatoron keresztül

Minden tool draft jelenjen meg previewként a Chapter 5 confirmation coordinatoron keresztül.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/local_structured_output_parser.dart
lib/features/ai_tutor/application/local_tool_call_adapter.dart
local_ai/evaluation/run_tool_eval.py
```

## Kötelező tesztek

- Valid tool
- Unknown tool
- Malformed JSON
- Multiple tool calls
- Confirmation false mismatch
- Injection arguments
- No constrained capability

## Elfogadási feltételek

- [ ] Schemahiba esetén nincs művelet.
- [ ] Tool calling külön rolloutolható.
- [ ] A model output soha nem ír közvetlen repositoryt.

## Javasolt commit

```text
feat(local-ai): validate constrained local tool calls
```

---

# Kör 23 — LocalTutorModelGateway implementáció

## Cél

A Chapter 5 `TutorModelGateway` helyi implementációja kösse össze a context, retrieval, runtime és output validation rétegeket.

## Feladatok

### 23.1 Implementáld a `LocalTutorModelGateway` osztályt a meglévő interface alapján

Implementáld a `LocalTutorModelGateway` osztályt a meglévő interface alapján.

### 23.2 A pipeline sorrendje: capability, resource lease, context snapshot, retrieval, budget, prompt, generate, validate, provenance, release

A pipeline sorrendje: capability, resource lease, context snapshot, retrieval, budget, prompt, generate, validate, provenance, release.

### 23.3 Kezeld a tokenstreamet a Chapter 5 content block presentation modelljéhez

Kezeld a tokenstreamet a Chapter 5 content block presentation modelljéhez.

### 23.4 A gateway ne olvasson közvetlenül más feature belső providerét; csak public context adaptert használjon

A gateway ne olvasson közvetlenül más feature belső providerét; csak public context adaptert használjon.

### 23.5 Minden exit pathon release-eld a resource lease-t

Minden exit pathon release-eld a resource lease-t.

### 23.6 Failure esetén adj deterministic fallback handoff metadata-t

Failure esetén adj deterministic fallback handoff metadata-t.

### 23.7 Készíts contract tesztet a fake és native runtime adapterrel

Készíts contract tesztet a fake és native runtime adapterrel.

## Fő érintett fájlok

```text
lib/features/ai_tutor/data/local_tutor_model_gateway.dart
lib/features/offline_ai/application/local_ai_application_service.dart
test/features/ai_tutor/local_tutor_model_gateway_contract_test.dart
```

## Kötelező tesztek

- Happy path stream
- Retrieval failure
- Context overflow
- Runtime failure
- Cancel
- Tool response
- Lease release

## Elfogadási feltételek

- [ ] A Chapter 5 domain változtatás nélkül működik.
- [ ] A gateway teljesen offline.
- [ ] A failure routing determinisztikus.

## Javasolt commit

```text
feat(local-ai): implement offline tutor model gateway
```

---

# Kör 24 — Deterministic, local és cloud gateway routing integráció

## Cél

A tutor egyetlen orchestratorból válasszon gatewayt, látható execution mode és kontrollált fallback mellett.

## Feladatok

### 24.1 Integráld a round 3 route policyt a Chapter 5 conversation controllerbe

Integráld a round 3 route policyt a Chapter 5 conversation controllerbe.

### 24.2 A UI minden assistant message metaadatában jelenítse meg a local/cloud/deterministic origin jelzést hozzáférhető módon

A UI minden assistant message metaadatában jelenítse meg a local/cloud/deterministic origin jelzést hozzáférhető módon.

### 24.3 Local runtime hiba esetén local-only és local-preferred deterministic fallbacket kapjon

Local runtime hiba esetén local-only és local-preferred deterministic fallbacket kapjon.

### 24.4 Cloud preferred offline állapotban local vagy deterministic módra válthat policy szerint

Cloud preferred offline állapotban local vagy deterministic módra válthat policy szerint.

### 24.5 Cloud fallback előtt ellenőrizd a consentet és mutasd, ha a kérés elhagyná az eszközt

Cloud fallback előtt ellenőrizd a consentet és mutasd, ha a kérés elhagyná az eszközt.

### 24.6 Ne ismételd automatikusan ugyanazt a promptot több modellen user tudta nélkül

Ne ismételd automatikusan ugyanazt a promptot több modellen user tudta nélkül.

### 24.7 Készíts routing integration tesztet network interceptorral

Készíts routing integration tesztet network interceptorral.

## Fő érintett fájlok

```text
lib/features/ai_tutor/application/routed_tutor_model_gateway.dart
lib/features/ai_tutor/presentation/widgets/execution_origin_badge.dart
test/features/ai_tutor/routed_gateway_integration_test.dart
```

## Kötelező tesztek

- Local success
- Local fail local-only
- Cloud consent missing
- Network offline
- Deterministic fallback
- No duplicate prompt

## Elfogadási feltételek

- [ ] A végrehajtási hely látható.
- [ ] Nincs csendes cloud fallback.
- [ ] A local hiba nem töri el a tutort.

## Javasolt commit

```text
feat(local-ai): route tutor execution transparently
```

---

# Kör 25 — Safety preflight és output guardrails

## Cél

A model request és response körül determinisztikus safety réteg szükséges, amely nem bízza kizárólag a modellre a korlátokat.

## Feladatok

### 25.1 Implementáld a scope classifier egyszerű, magyarázható szabályait a guitar learning és unsupported request elkülönítésére

Implementáld a scope classifier egyszerű, magyarázható szabályait a guitar learning és unsupported request elkülönítésére.

### 25.2 Kezeld a fájdalom/sérülés safety flow-t

Kezeld a fájdalom/sérülés safety flow-t.

### 25.3 Blokkold a fájlrendszer, shell, credential és network tool igényt

Blokkold a fájlrendszer, shell, credential és network tool igényt.

### 25.4 Validáld, hogy a response citation ID létezik és a claim type megfelel

Validáld, hogy a response citation ID létezik és a claim type megfelel.

### 25.5 Jelöld vagy távolítsd el a nem támogatott mért állítást

Jelöld vagy távolítsd el a nem támogatott mért állítást.

### 25.6 Kritikus schema vagy safety hiba esetén ne mutasd streamingből végleges válaszként a hibás blokkot

Kritikus schema vagy safety hiba esetén ne mutasd streamingből végleges válaszként a hibás blokkot.

### 25.7 Készíts safe fallback response-okat magyarul és angolul

Készíts safe fallback response-okat magyarul és angolul.

### 25.8 Ne tárolj safety review célra promptszöveget consent nélkül

Ne tárolj safety review célra promptszöveget consent nélkül.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/local_ai_safety_preflight.dart
lib/features/offline_ai/application/local_ai_output_guard.dart
test/features/offline_ai/safety/
```

## Kötelező tesztek

- Pain statement
- Fake measured claim
- Filesystem request
- Network request
- Unknown citation
- Unsupported domain
- Bilingual fallback

## Elfogadási feltételek

- [ ] Kritikus violation release blocker.
- [ ] A guard determinisztikus és tesztelt.
- [ ] A safety nem csak prompt instruction.

## Javasolt commit

```text
feat(local-ai): enforce deterministic AI safety guards
```

---

# Kör 26 — Bilingual pedagógiai és grounding evaluation

## Cél

A kiválasztott local model package csak magyar és angol quality gate teljesítése után kerülhet stable channelbe.

## Feladatok

### 26.1 Implementáld az evaluation runner adaptert reference és quantized modelhez

Implementáld az evaluation runner adaptert reference és quantized modelhez.

### 26.2 Készíts exact és rubric score aggregációt

Készíts exact és rubric score aggregációt.

### 26.3 Mérd külön: grounding, citation, unsupported claim, clarification, tool accuracy, pedagogy, brevity és language quality

Mérd külön: grounding, citation, unsupported claim, clarification, tool accuracy, pedagogy, brevity és language quality.

### 26.4 Készíts pairwise reportot a compact és standard jelöltekről

Készíts pairwise reportot a compact és standard jelöltekről.

### 26.5 Vezess regression thresholdot package versionök között

Vezess regression thresholdot package versionök között.

### 26.6 Kritikus safety eset automatikus fail

Kritikus safety eset automatikus fail.

### 26.7 Készíts human review sampling workflow-t, vak model identifierrel, ha lehetséges

Készíts human review sampling workflow-t, vak model identifierrel, ha lehetséges.

### 26.8 A report rögzítse a prompt, knowledge és tool schema verzióját

A report rögzítse a prompt, knowledge és tool schema verzióját.

## Fő érintett fájlok

```text
local_ai/evaluation/run_quality_eval.py
local_ai/evaluation/compare_candidates.py
local_ai/evaluation/reports/
docs/quality/offline-ai-model-gate.md
```

## Kötelező tesztek

- Deterministic report
- Missing output
- Malformed structured result
- Bilingual aggregation
- Regression detection
- Critical fail

## Elfogadási feltételek

- [ ] A model release quality reporttal rendelkezik.
- [ ] Magyar minőség nem csak angol score-ból következtetett.
- [ ] A quantization delta látható.

## Javasolt commit

```text
test(local-ai): enforce bilingual model quality gates
```

---

# Kör 27 — Performance, thermal és battery policy implementáció

## Cél

A production runtime alkalmazza a capability tierből származó output-, backend- és erőforrásprofilt.

## Feladatok

### 27.1 Implementáld a generation performance monitor szöveg nélküli metrikáit

Implementáld a generation performance monitor szöveg nélküli metrikáit.

### 27.2 Integráld az Android thermal status eventeket és konzervatív fallbacket

Integráld az Android thermal status eventeket és konzervatív fallbacket.

### 27.3 Implementáld a tierhez kötött max context, output és backend profilt

Implementáld a tierhez kötött max context, output és backend profilt.

### 27.4 Battery saverben ajánlj compact/deterministic módot policy szerint

Battery saverben ajánlj compact/deterministic módot policy szerint.

### 27.5 Készíts repeated-turn thermal instrumentation tesztet

Készíts repeated-turn thermal instrumentation tesztet.

### 27.6 Mérd a cancellationt prefill és decode fázisban

Mérd a cancellationt prefill és decode fázisban.

### 27.7 Készíts memory headroom guardot generálás előtt és szükség esetén közben

Készíts memory headroom guardot generálás előtt és szükség esetén közben.

### 27.8 Severe/critical thermal eventnél kontrolláltan állítsd le vagy tiltsd az új requestet

Severe/critical thermal eventnél kontrolláltan állítsd le vagy tiltsd az új requestet.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/generation_performance_policy.dart
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/ThermalMonitor.kt
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/DeviceMemoryProbe.kt
android/app/src/androidTest/
```

## Kötelező tesztek

- Thermal transitions
- Battery saver
- Memory guard
- Tier output cap
- Cancel latency
- No prompt logging

## Elfogadási feltételek

- [ ] A runtime nem fut korlátlan teljesítménnyel.
- [ ] Critical thermal esetben leáll.
- [ ] A metrikák privacy-safe-ek.

## Javasolt commit

```text
perf(local-ai): enforce device health generation policies
```

---

# Kör 28 — App lifecycle, low-memory és crash recovery

## Cél

A modellprocess és conversation controller kezelje az app pause/resume, process death, low memory és natív crash helyzeteket adatvesztés nélkül.

## Feladatok

### 28.1 Backgroundba kerüléskor ne induljon új generálás; aktív generálás policy szerint cancel vagy rövid grace után cancel

Backgroundba kerüléskor ne induljon új generálás; aktív generálás policy szerint cancel vagy rövid grace után cancel.

### 28.2 Kezeld az Android `onTrimMemory` szinteket és unload policyt

Kezeld az Android `onTrimMemory` szinteket és unload policyt.

### 28.3 Külön process esetén állítsd helyre a service connectiont és jelöld a folyamatban lévő requestet failednek

Külön process esetén állítsd helyre a service connectiont és jelöld a folyamatban lévő requestet failednek.

### 28.4 Ne próbáld vakon folytatni a félbeszakadt tokenstreamet

Ne próbáld vakon folytatni a félbeszakadt tokenstreamet.

### 28.5 Mentsd a user draftot és a már validált assistant blockokat tranzakciósan

Mentsd a user draftot és a már validált assistant blockokat tranzakciósan.

### 28.6 Ismételt runtime crash után karanténozd vagy rollbackeld a package-et policy szerint

Ismételt runtime crash után karanténozd vagy rollbackeld a package-et policy szerint.

### 28.7 Készíts recovery banner és retry UI state-et

Készíts recovery banner és retry UI state-et.

### 28.8 Teszteld orientation change, activity recreation és full process recreation esetén

Teszteld orientation change, activity recreation és full process recreation esetén.

## Fő érintett fájlok

```text
lib/features/offline_ai/application/local_ai_lifecycle_controller.dart
android/app/src/main/kotlin/com/wolfcasaba/strumsight/localai/LocalAiServiceConnection.kt
test/features/offline_ai/lifecycle/
android/app/src/androidTest/
```

## Kötelező tesztek

- Background cancel
- Trim memory
- Service death
- Process recreation
- Draft recovery
- Crash counter rollback

## Elfogadási feltételek

- [ ] A fő app natív crash után használható.
- [ ] Nincs ghost generating state.
- [ ] A user draft nem vész el.

## Javasolt commit

```text
fix(local-ai): recover safely from lifecycle and runtime failure
```

---

# Kör 29 — Reprodukálható export, kvantálás és package build pipeline

## Cél

A kiválasztott modell mobilartifactja egyetlen dokumentált, pinned és CI-ben ellenőrizhető pipeline-ból készüljön.

## Feladatok

### 29.1 Készíts locked Python környezetet és opcionális container image-et

Készíts locked Python környezetet és opcionális container image-et.

### 29.2 Implementáld a source downloadot pinned revision és checksum alapján

Implementáld a source downloadot pinned revision és checksum alapján.

### 29.3 Implementáld a runtime-specifikus exportot és kvantálási profile-okat

Implementáld a runtime-specifikus exportot és kvantálási profile-okat.

### 29.4 Generáld a tokenizer, chat template, generation defaults, tool schema, license és model card fájlokat

Generáld a tokenizer, chat template, generation defaults, tool schema, license és model card fájlokat.

### 29.5 Futtasd a reference/quantized parity evaluationt

Futtasd a reference/quantized parity evaluationt.

### 29.6 Generálj unsigned package-et és manifestet

Generálj unsigned package-et és manifestet.

### 29.7 Implementálj package verifier CLI-t ugyanazzal a schema logikával, mint a kliens

Implementálj package verifier CLI-t ugyanazzal a schema logikával, mint a kliens.

### 29.8 A signing külön release job és protected environment legyen

A signing külön release job és protected environment legyen.

### 29.9 Ne tárold a nagy model artifactot normál Gitben; használj artifact storage-t

Ne tárold a nagy model artifactot normál Gitben; használj artifact storage-t.

## Fő érintett fájlok

```text
local_ai/export/
local_ai/requirements-lock.txt
local_ai/configs/quantization_profiles.yaml
.github/workflows/local-ai-model-build.yml
```

## Kötelező tesztek

- Pinned revision
- Reproducible manifest
- Tokenizer hash
- Reference parity
- Package verifier
- No signing key in repo

## Elfogadási feltételek

- [ ] Minden package visszavezethető input revisionre.
- [ ] A build és signing különválik.
- [ ] A model card automatikusan frissül.

## Javasolt commit

```text
build(local-ai): add reproducible model package pipeline
```

---

# Kör 30 — Backend manifest, CDN és release channel

## Cél

A modell- és knowledge package terjesztése legyen skálázható, aláírt és staged rolloutot támogató, promptadat nélkül.

## Feladatok

### 30.1 Implementáld a FastAPI channel manifest endpointokat vagy statikus manifest szolgáltatási réteget

Implementáld a FastAPI channel manifest endpointokat vagy statikus manifest szolgáltatási réteget.

### 30.2 Adj Alembic modellt csak akkor, ha dinamikus release metadata valóban adatbázist igényel; statikus signed manifest előnyben

Adj Alembic modellt csak akkor, ha dinamikus release metadata valóban adatbázist igényel; statikus signed manifest előnyben.

### 30.3 Integráld object storage/CDN URL-eket és ETag/Range támogatást

Integráld object storage/CDN URL-eket és ETag/Range támogatást.

### 30.4 Implementáld stable, beta és lab channel policyt

Implementáld stable, beta és lab channel policyt.

### 30.5 Támogasd a package revocationt, minimum app versiont és staged rollout seedet privacy-safe módon

Támogasd a package revocationt, minimum app versiont és staged rollout seedet privacy-safe módon.

### 30.6 A kliens lokálisan ellenőrizze a signature-t akkor is, ha HTTPS használatos

A kliens lokálisan ellenőrizze a signature-t akkor is, ha HTTPS használatos.

### 30.7 Készíts endpoint contract és cache header teszteket

Készíts endpoint contract és cache header teszteket.

### 30.8 Ne logolj exact device fingerprintet vagy promptot

Ne logolj exact device fingerprintet vagy promptot.

## Fő érintett fájlok

```text
backend/app/routers/local_ai.py
backend/app/schemas/local_ai.py
backend/tests/test_local_ai_manifest.py
docs/deployment/local-ai-distribution.md
```

## Kötelező tesztek

- Manifest contract
- ETag
- Range metadata
- Revoked package
- Min app version
- Channel access
- No prompt fields

## Elfogadási feltételek

- [ ] A nagy bináris nem terheli indokolatlanul a FastAPI processt.
- [ ] A signature a kliensben is validált.
- [ ] A rollout visszagörgethető.

## Javasolt commit

```text
feat(backend): distribute signed local AI packages
```

---

# Kör 31 — Offline AI settings, model manager és accessibility UI

## Cél

A felhasználó érthetően kezelhesse a helyi AI-t, modellt, tárhelyet, módot és adatot.

## Feladatok

### 31.1 Készíts Offline AI settings képernyőt availability és mode state-ekkel

Készíts Offline AI settings képernyőt availability és mode state-ekkel.

### 31.2 Mutasd a modell méretét, versiont, channel-t, nyelvet, device tier-t és várható profilt

Mutasd a modell méretét, versiont, channel-t, nyelvet, device tier-t és várható profilt.

### 31.3 Készíts download progress, pause, resume, cancel, verify, activate, rollback és delete flow-t

Készíts download progress, pause, resume, cancel, verify, activate, rollback és delete flow-t.

### 31.4 Mutasd külön a model package és knowledge package storage-ot

Mutasd külön a model package és knowledge package storage-ot.

### 31.5 Készíts first-run compatibility és privacy explanation flow-t

Készíts first-run compatibility és privacy explanation flow-t.

### 31.6 Implementáld a local/cloud/deterministic origin badge-et

Implementáld a local/cloud/deterministic origin badge-et.

### 31.7 Adj conversation/memory delete és diagnostics export kontrollt

Adj conversation/memory delete és diagnostics export kontrollt.

### 31.8 Accessibility: 200% text, screen reader, Stop button, reduced motion és kontraszt

Accessibility: 200% text, screen reader, Stop button, reduced motion és kontraszt.

### 31.9 Localization: minden új string angol és magyar parity teszttel

Localization: minden új string angol és magyar parity teszttel.

## Fő érintett fájlok

```text
lib/features/offline_ai/presentation/screens/offline_ai_settings_screen.dart
lib/features/offline_ai/presentation/screens/model_manager_screen.dart
lib/features/offline_ai/presentation/widgets/
lib/l10n/app_en.arb
lib/l10n/app_hu.arb
```

## Kötelező tesztek

- All availability states
- Download controls
- Delete confirmation
- Rollback
- 200% text
- Semantics
- Localization parity
- Reduced motion

## Elfogadási feltételek

- [ ] A modell opcionális jellege világos.
- [ ] A user bármikor törölheti.
- [ ] A Stop és privacy kontroll hozzáférhető.

## Javasolt commit

```text
feat(local-ai): add accessible model management UI
```

---

# Kör 32 — Teljes integráció, device matrix, rollout és Epic lezárás

## Cél

Az Epic lezárásakor a teljes local tutor útvonalat, modellcsomagot, device támogatást és fallbacket valós készüléken kell igazolni.

## Feladatok

### 32.1 Futtasd a teljes Flutter, backend, native és architecture tesztcsomagot

Futtasd a teljes Flutter, backend, native és architecture tesztcsomagot.

### 32.2 Futtasd a signed package end-to-end install, verify, activate, generate, rollback és delete flow-t

Futtasd a signed package end-to-end install, verify, activate, generate, rollback és delete flow-t.

### 32.3 Futtasd a bilingual quality gate-et a release candidate package-en

Futtasd a bilingual quality gate-et a release candidate package-en.

### 32.4 Futtasd a device matrix benchmarkot és készíts támogatási táblát

Futtasd a device matrix benchmarkot és készíts támogatási táblát.

### 32.5 Teszteld repülőgépes módban a local-only kérdést network interceptorral

Teszteld repülőgépes módban a local-only kérdést network interceptorral.

### 32.6 Teszteld Practice, Song és Analyze utáni debriefet

Teszteld Practice, Song és Analyze utáni debriefet.

### 32.7 Teszteld a tool preview/confirmation flow-t

Teszteld a tool preview/confirmation flow-t.

### 32.8 Teszteld mic/camera resource conflictet, thermal stopot, low-memory és process death recoveryt

Teszteld mic/camera resource conflictet, thermal stopot, low-memory és process death recoveryt.

### 32.9 Frissítsd README, AGENTS, HANDOFF, model card, privacy dokumentáció és SDD index fájlokat

Frissítsd README, AGENTS, HANDOFF, model card, privacy dokumentáció és SDD index fájlokat.

### 32.10 Készíts `docs/sdd/epic-10-completion-report

Készíts `docs/sdd/epic-10-completion-report.md` dokumentumot raw teszt- és benchmark-hivatkozásokkal.

### 32.11 Csak a megfelelt compact package kerüljön első stable rolloutba; standard és tool calling külön kaput kaphat

Csak a megfelelt compact package kerüljön első stable rolloutba; standard és tool calling külön kaput kaphat.

## Fő érintett fájlok

```text
docs/sdd/epic-10-completion-report.md
docs/support/local-ai-device-matrix.md
docs/privacy/offline-ai.md
HANDOFF.md
README.md
```

## Kötelező tesztek

- Full Flutter suite
- Backend suite
- Native instrumentation
- Airplane mode
- Signed package E2E
- Bilingual quality
- Device matrix
- Thermal/memory recovery

## Elfogadási feltételek

- [ ] A local TutorModelGateway production-ready.
- [ ] Local-only esetben nulla prompt hálózati forgalom.
- [ ] A modellhiba nem töri el az appot.
- [ ] A stable package quality és performance gate-et teljesít.
- [ ] A dokumentáció a tényleges release állapotot mutatja.

## Javasolt commit

```text
docs(local-ai): close Epic 10 offline AI
```

---

# 26. Epic 10 végső Definition of Done

Az Epic 10 kizárólag akkor tekinthető késznek, ha minden alábbi állítás igaz.

## Architektúra

- [ ] A local AI külön runtime-független Flutter domain boundaryvel rendelkezik.
- [ ] A Chapter 5 `TutorModelGateway` változatlan szerződését implementálja.
- [ ] A Flutter domain nem importál Android vagy runtime SDK típust.
- [ ] A runtime adapter kiválasztása benchmark ADR-rel igazolt.
- [ ] A command és tokenstream platform boundary verziózott.
- [ ] A native inference nem a UI threaden fut.
- [ ] A process isolation döntés ADR-ben dokumentált.
- [ ] A fake runtime CI-ben elérhető.

## Modellcsomag és supply chain

- [ ] Minden production package signed manifesttel rendelkezik.
- [ ] Minden fájlméret és checksum ellenőrzött.
- [ ] Path traversal és extra fájl nem kerülhet aktiválásra.
- [ ] A private signing key nincs repositoryban vagy kliensben.
- [ ] A package source model revisionre visszavezethető.
- [ ] A tokenizer, template, tool schema és model card verziózott.
- [ ] A licenc és redisztribúciós jog dokumentált.
- [ ] A quantized package reference parity reporttal rendelkezik.
- [ ] Hibás package karanténba kerül.
- [ ] Aktiválás atomikus.
- [ ] Rollback működik.

## Letöltés és storage

- [ ] A modellletöltés opcionális és explicit.
- [ ] Pause, resume, retry és cancel működik.
- [ ] ETag/version változás nem korrumpál partial downloadot.
- [ ] Offline import csak signed package-et fogad productionben.
- [ ] Tárhelyigény előre látható.
- [ ] Staging, installed és rollback headroom számított.
- [ ] A modell törölhető progress adatvesztés nélkül.
- [ ] A knowledge package külön kezelhető.

## Device capability és performance

- [ ] A device tier static és dynamic mérésből készül.
- [ ] Emulator nem számít performance bizonyítéknak.
- [ ] Cold load, TTFT, token/s, memory és cancellation mérve.
- [ ] Legalább húsz egymást követő generálás stabil a támogatott eszközön.
- [ ] A peak memória biztonságos headroomot hagy.
- [ ] A thermal policy működik.
- [ ] Battery saver policy működik.
- [ ] Low-memory esemény kezelve.
- [ ] A támogatott device matrix dokumentált.

## Runtime lifecycle

- [ ] Model load/unload idempotens.
- [ ] Egyszerre legfeljebb egy generálás fut.
- [ ] Token event order tesztelt.
- [ ] Cancellation működik prefill és decode közben.
- [ ] Route dispose után nincs árva stream.
- [ ] Native crash kontrollált failure.
- [ ] Process/service reconnect működik.
- [ ] Backgroundban nincs új generálás.
- [ ] Ghost generating state nincs.

## Real-time együttélés

- [ ] Local AI resource lease nélkül nem indul.
- [ ] Aktív mikrofon esetén a tier policy érvényesül.
- [ ] Aktív kamera esetén a tier policy érvényesül.
- [ ] Analyze recording alatt nincs kontrollálatlan generálás.
- [ ] A DSP és CRNN eredmények nem regresszáltak.
- [ ] A LLM nem kerül valós idejű scoring útvonalba.

## Context és memória

- [ ] A tokenizer package-verzióhoz kötött.
- [ ] A token budget pontos és tesztelt.
- [ ] Safety policy és current user message nem truncálódik.
- [ ] Output reserve figyelembe vett.
- [ ] Structured TutorMemory verziózott.
- [ ] Hidden chain-of-thought nem tárolódik.
- [ ] Conversation export és törlés működik.
- [ ] Local-only conversation nem szinkronizál cloudba.

## RAG és grounding

- [ ] Tier 1 lexical retrieval működik.
- [ ] Embedding retrieval opcionális.
- [ ] Embedding hiba lexical fallbacket ad.
- [ ] Hybrid ranking determinisztikus.
- [ ] Csak approved knowledge chunk kerül promptba.
- [ ] Minden chunk stabil source ID-val rendelkezik.
- [ ] Nem létező citation elutasított.
- [ ] Retrieval evaluation report elkészült.
- [ ] Community tartalom nem automatikus tudásforrás.

## Tool calling

- [ ] Tool calling capability gate mögött van.
- [ ] Structured output schema validált.
- [ ] Ismeretlen tool elutasított.
- [ ] Argumentum domain validáció megtörténik.
- [ ] Minden állapotmódosító tool previewt ad.
- [ ] Explicit confirmation szükséges.
- [ ] Tool output nem módosít közvetlenül repositoryt.
- [ ] Tool exact-match evaluation eléri a release küszöböt.

## Privacy és security

- [ ] Local-only prompt nem hagyja el az eszközt.
- [ ] Local-only output nem hagyja el az eszközt.
- [ ] Retrieval query nem hagyja el az eszközt.
- [ ] Nincs prompt vagy output production logban.
- [ ] A runtime nem kap hálózati toolt.
- [ ] A runtime nem kap shell vagy tetszőleges fájl toolt.
- [ ] Auth token nem kerül local AI contextbe.
- [ ] Prompt injection boundary tesztelt magyarul és angolul.
- [ ] Model package signature kötelező.
- [ ] Diagnostics export explicit consenthez kötött.

## Safety és pedagógia

- [ ] Fájdalom/sérülés flow nem diagnosztizál.
- [ ] A modell nem talál ki mért adatot.
- [ ] Vision claimhez vision evidence szükséges.
- [ ] Audio claimhez megfelelő evidence szükséges.
- [ ] Hiányos evidence esetén a tutor kérdez vagy bizonytalanságot jelez.
- [ ] Kritikus safety violation nincs a release corpuson.
- [ ] Magyar quality gate teljesül.
- [ ] Angol quality gate teljesül.
- [ ] Quantization regression dokumentált és elfogadható.

## Routing és fallback

- [ ] Local-only semmilyen esetben nem route-ol cloudra.
- [ ] Cloud fallback consent nélkül nem történik.
- [ ] A válasz execution originja látható.
- [ ] Local runtime failure deterministic fallbacket ad.
- [ ] A generatív modell nélkül az app teljes alapfunkciója működik.
- [ ] A model download kill switch működik.
- [ ] A runtime kill switch nem törli a user progressét.

## UI, accessibility és localization

- [ ] A modell opcionális jellege érthető.
- [ ] Méret, tárhely és device tier látható.
- [ ] Download controls működnek.
- [ ] Stop gomb mindig elérhető.
- [ ] 200% text scale teszt zöld.
- [ ] Screen reader semantics zöld.
- [ ] Reduced motion támogatott.
- [ ] Angol és magyar localization parity zöld.
- [ ] A tokenstream nem spameli a screen readert.

## CI, release és dokumentáció

- [ ] Flutter unit és integration tesztek zöldek.
- [ ] Native unit és instrumentation tesztek zöldek.
- [ ] Backend contract tesztek zöldek.
- [ ] Architecture guard zöld.
- [ ] Signed fixture package tesztek zöldek.
- [ ] Model build pipeline reprodukálható.
- [ ] Quality evaluation report archivált.
- [ ] Device benchmark report archivált.
- [ ] Model card és license bundle friss.
- [ ] README, AGENTS és HANDOFF friss.
- [ ] Epic completion report elkészült.

---

# 27. Kötelező végső ellenőrző parancsok

Flutter:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze lib test tool
flutter test
flutter test test/property
dart run tool/check_architecture.dart
```

Backend:

```bash
cd backend
python -m ruff check app tests
python -m ruff format --check app tests
python -m pytest -q
```

Local AI Python tooling:

```bash
cd local_ai
python -m pytest -q
python evaluation/run_quality_eval.py --profile release
python evaluation/run_tool_eval.py --profile release
python evaluation/run_retrieval_eval.py --profile release
python export/verify_package.py --package <release-candidate-package>
```

Android natív és eszköztesztek:

```bash
cd android
./gradlew test
./gradlew connectedAndroidTest
```

A teljes performance és thermal acceptance kizárólag a dokumentált valós eszközmátrixon tekinthető sikeresnek.

---

# 28. Az Epic eredménye

Az Epic 10 lezárása után a StrumSight:

- internet nélkül is rendelkezik generatív AI gitártanárral a támogatott eszközökön;
- gyengébb eszközökön tisztességes deterministic fallbacket biztosít;
- nem küld promptot vagy tanulási kontextust cloudba local-only módban;
- biztonságosan telepít, ellenőriz, frissít és görget vissza modellt;
- runtime- és modelltechnológiától független alkalmazásdomaint tart fenn;
- lokális, forrásazonosítós RAG-et használ;
- kontrollált, megerősítéses tool callingot támogat;
- együttműködik a Practice, Song, Analyze, Vision és Practice Generator rendszerekkel;
- nem veszélyezteti a valós idejű audio pipeline-t;
- mérhető magyar és angol minőségi kapuval rendelkezik;
- memória-, hő- és akkumulátorterhelés alapján adaptív;
- modellhiba esetén nem teszi használhatatlanná az alkalmazást;
- reprodukálható modell-build és release folyamattal rendelkezik.

Az Epic 10 után kezdhető el a teljes termék release- és integrációs lezárása:

```text
Chapter 12 — Release Roadmap, Sprint Planning & Final Integration
```
