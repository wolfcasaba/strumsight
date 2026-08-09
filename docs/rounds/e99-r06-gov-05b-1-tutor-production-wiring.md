# E99-R06 (GOV-05b-1) — Az AI Tutor production-drótozása és SSE transport

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09, kód olvasva a
  GOV-06 utáni friss `main`-en)
- **Típus:** **governance-kör** — a `HANDOFF.md` §3 „Az AI Tutor rollout
  BLOKKOLT" tétel **első** feloldó köre
- **Kör-azonosító:** `E99-R06`. Az `E99` a governance-körök fenntartott
  pszeudo-epic kódja. Emberi neve **GOV-05b-1**.
- **Branch:** `codex/e99-r06-gov-05b-1-tutor-production-wiring`
- **Előfeltétel:** GOV-05a (`E99-R01`) merge-elve
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0213`](../adr/0213-ai-tutor-production-wiring-and-sse-transport.md)
  — **MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.**
- **⚠ NINCS a `pipeline-queue.tsv`-ben — KÉZI indítás, Terrával.** Ok: a
  `tools/tests/test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule`
  szabálya az `allowed_paths`-ból számolja a motort, és itt
  **ui=3 > core=2 → `minimax`**-ot írna elő. A számláló proxy azonban ezen a
  körön félremér: a három „UI"-találat a `presentation/providers/` alatti
  **Riverpod-drótozás** és annak tesztje, nem képernyő-kód — a kör érdemi
  része az SSE-transport és a boot-kompozíció, ami ítéletigényes (ADR 0069
  „Codex" sor). A user álló utasítása szintén Terra. A queue-sor felvétele
  `codex` motorral pirosra váltaná a Router CI-t (mért eset: E05-R24 H5),
  ezért a kör a GOV-05a mintájára a **queue-n kívül**, kézzel indul:
  `ROUND_ENGINE=terra tools/codex-round.sh <munkapéldány> <prompt> <log>`.
  A proxy-szabály finomítása külön governance-kör tárgya.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/main.dart",
  "lib/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_providers.dart",
  "lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart",
  "test/features/ai_tutor/data/http_tutor_stream_transport_test.dart",
  "test/features/ai_tutor/presentation/tutor_production_wiring_test.dart",
  "test/app/feature_flags_test.dart",
  "docs/rounds/e99-r06-gov-05b-1-tutor-production-wiring.md",
]
gate_tests = [
  "test/features/ai_tutor",
  "test/app",
  "test/core",
]
native_gate = false
```

> **Három ÚJ fájl** (`http_tutor_stream_transport.dart` és a két tesztfájl).
> Ezek explicit engedélyezettek; minden más új fájl scope-sértés.
>
> **A `gate_tests` az [L203](../LESSONS.md) szerint:** a kör a `main.dart`
> boot-ját módosítja, ezért a `test/app` és a `test/core` (bootstrap,
> storage, network) is bent van, nem csak a feature-fa.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"  ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

Az `aiTutorEnabled` bekapcsolása ma **crash**-t okozna. Ez a kör ezt szünteti
meg: bedrótozza a három hiányzó production providert, és megírja az egyetlen
hiányzó kliensoldali darabot, a konkrét `TutorStreamTransport`-ot.

**A kör NEM kapcsolja be a flaget** (ADR 0213 Döntés 1) — azt éri el, hogy a
flag *bekapcsolható legyen*.

## 2. Jelenlegi állapot (mérve 2026-08-09)

### 2.1 A három dobó provider

| Provider | Fájl | Ma |
|---|---|---|
| `tutorOrchestratorProvider` | `tutor_providers.dart:337` | `throw UnimplementedError` |
| `tutorConversationRepositoryProvider` | `tutor_providers.dart:345` | `throw UnimplementedError` |
| `tutorMemoryRepositoryProvider` | `tutor_privacy_providers.dart` | `throw UnimplementedError` |

A doc-comment „production boot wires it via `tutorMain()`"-t ígér, de
`grep -rn "tutorMain" lib/` → **csak maga a doc-comment**. A `lib/main.dart`
ProviderScope override-listája (56–66. sor) `appConfigProvider`,
`keyValueStoreProvider`, `songRepositoryProvider`,
`songAssetRepositoryProvider`, `diagnosticsConsentProvider`,
`onboardingSeenProvider` — a három tutor provider **nincs benne**.

Fogyasztók: a `TutorChatScreen` a `tutorChatControllerProvider`-en át
(`tutor_chat_screen.dart:44`), a `TutorDataScreen` közvetlenül
(`tutor_data_screen.dart:51–52`). A `TutorHomeScreen` stateless — az működne.

### 2.2 Minden építőelem létezik

| Szükséglet | Meglévő | Függőség |
|---|---|---|
| conversation repo | `LocalTutorConversationRepository({keyValueStore})` | `KeyValueStore` |
| memory repo | `LocalTutorMemoryRepository({keyValueStore})` | `KeyValueStore` |
| context assembler | `TutorContextAssembler({budget})` | — |
| knowledge index | `KnowledgeIndex.fromDocuments(...)` (`knowledge_index.dart:49`) | dokumentumok |
| knowledge retriever | `KnowledgeRetriever({index})` | `KnowledgeIndex` |
| prompt template loader | `AssetPromptTemplateLoader` (`prompt_template.dart:59`) | assetek |
| prompt builder | `TutorPromptBuilder({templateLoader})` | loader |
| orchestrator | `TutorOrchestrator({contextAssembler, knowledgeRetriever, promptBuilder, gatewayForAttempt})` | a fentiek |

`keyValueStoreProvider` létezik (`storage_providers.dart:13`) és a `main.dart`
**már felülírja**. Az assetek megvannak és a `pubspec.yaml` deklarálja
(`assets/tutor_knowledge/` + `assets/tutor_prompts/`, 60–63. sor).

**Riverpod provider viszont MÉG NINCS** a knowledge-indexre, a retrieverre és
a prompt-builderre (`grep` → 0 találat) — ezeket a kör hozza létre a
`tutor_providers.dart`-ban.

### 2.3 A transport — az egyetlen hiányzó kliensdarab

`TutorStreamTransport` (`tutor_stream_dto.dart:337`) absztrakt interfész,
**konkrét implementáció nélkül**. Három metódus:

```dart
Future<AppResult<Stream<String>>> openTurnStream({
  required String requestId, required int sequence,
  required String conversationId, required String message});
void cancelActiveStream();
Future<AppResult<void>> health();
```

A `RemoteTutorModelGateway` kész, és ezt az interfészt fogyasztja.

### 2.4 A szerveroldal KÉSZ

`backend/app/tutor/`: `GET /tutor/capability`, `POST /tutor/turn`, és
**`POST /tutor/stream`** (`stream.py:217`) — SSE, soronként egy `data:` JSON
frame, közös monoton `seq`, sorrend `started → delta* → usage → complete`
vagy `started → failure` (ADR 0142). A Dart DTO-réteg ezt **már modellezi**.

A backend a `tutor_enabled` flag mögött van (`main.py:147`), alapértéke
`False`, és a provider `"fake"` (`config.py:58–62`).

`lib/core/network/api_client.dart` `getJson`/`postJson`/`put`/`post`-ot ad —
**streamelést nem**.

## 3. Scope

**Benne:**

1. `http_tutor_stream_transport.dart` (ÚJ) — konkrét `TutorStreamTransport`
   Dio `ResponseType.stream`-mel a `POST /tutor/stream`-re; a `data:` sorokat
   nyers `String`-ként adja tovább.
2. `tutor_providers.dart` — a knowledge-index / retriever / prompt-builder
   providerek + az orchestrator és a conversation repo **production
   factory**-ja; az avult `tutorMain()` doc-comment javítása.
3. `tutor_privacy_providers.dart` — a memory repo production factory-ja +
   doc-comment.
4. `main.dart` — a három override bekötése a meglévő listába.
5. A két ÚJ tesztfájl + a `feature_flags_test.dart` kerítése (A6).
6. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **A flagek értéke.** `aiTutorEnabled` és `aiTutorCloudEnabled` **`false`
  marad minden környezetben** (ADR 0213 Döntés 1). A `feature_flags.dart` a
  **tilos zónában** van.
- **A `FakeTutorModelGateway` production-drótozása** (Döntés 3).
- `backend/` bármely fájlja — a valódi provider-adapter külön kör.
- Az `ApiClient` bővítése streameléssel (Döntés 4).
- A `RemoteTutorModelGateway`, a DTO-réteg, a domain vagy az application
  bármely fájlja — a kör csak drótoz, nem tervez újra.
- UI-változás, belépési pont, ARB-kulcs, route.
- `.github/`, `tool/`, `tools/`, `assets/`, `docs/adr/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `lib/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart` | **ÚJ** — a konkrét SSE transport |
| `lib/features/ai_tutor/presentation/providers/tutor_providers.dart` | production factory-k + doc-comment |
| `lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart` | memory repo factory + doc-comment |
| `lib/main.dart` | a három override |
| `test/features/ai_tutor/data/http_tutor_stream_transport_test.dart` | **ÚJ** |
| `test/features/ai_tutor/presentation/tutor_production_wiring_test.dart` | **ÚJ** |
| `test/app/feature_flags_test.dart` | a flag-kerítés (A6) |
| `docs/rounds/e99-r06-gov-05b-1-tutor-production-wiring.md` | §10 handoff |

**Tilos zóna:** `lib/app/config/` (MINDEN — a flagek!), `backend/`,
`lib/core/network/`, `lib/features/ai_tutor/` a fenti három fájlon kívül,
`lib/features/**/screens|widgets`, `lib/l10n/`, `assets/`, `tool/`, `tools/`,
`.github/`, `docs/adr/`.

## 5. Kötött architekturális döntések

Forrás: [ADR 0213](../adr/0213-ai-tutor-production-wiring-and-sse-transport.md).

### 5.1 A flag NEM kapcsol be

`aiTutorEnabled` / `aiTutorCloudEnabled` `false` marad. A kör a flaget
*bekapcsolhatóvá* teszi. A `feature_flags.dart` tilos zóna — ha úgy éreznéd,
hozzá kell nyúlni, az `stopped`.

### 5.2 Az alapértelmezett átjáró a STUB

A `gatewayForAttempt` production-alapértelmezése a
`LocalTutorModelGatewayStub` (kontrollált `tutor.model_gateway.unavailable`).

**A `FakeTutorModelGateway` NEM kerülhet a production-drótozásba** — az egy
`script`-tel hajtott teszt-duplikátum; szállítva minden üzenetre ugyanazt
adná. Ez a kör legfontosabb tiltása.

Az ÚJ transport **létezik és tesztelt lesz**, de a production orchestrator
alapértelmezésben nem a `RemoteTutorModelGateway`-t kapja — az a valódi
provider-adapter körének dolga.

### 5.3 A transport nem értelmez protokollt

A `data:` sorokat nyers `String` payloadként adja tovább. Parse, `seq`-
sorrendezés, normalizálás **nem** a transport dolga — az a
`RemoteTutorModelGateway` felelőssége (ADR 0142). Ha a transportba
frame-értelmezést írnál, az réteg-sértés.

### 5.4 Providerfüggetlenség

[ADR 0131](../adr/0131-ai-tutor-provider-boundary.md) érvényben: a kliens
sehol nem hivatkozhat konkrét model-provider SDK típusra. A transport csak a
StrumSight backendet ismeri.

### 5.5 Nyitott döntések (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Honnan jön a KnowledgeIndex dokumentum-halmaza?
    blocking: false
    resolution_policy: use_default
    default: >
      Az assets/tutor_knowledge/ manifestjéből, a MEGLÉVŐ betöltő úton
      (KnowledgeIndex.fromDocuments). Ha a betöltés hibázik, a retriever
      ÜRES indexszel épül és a hiba naplózódik — a boot NEM eshet el egy
      tutor-asset miatt, mert a Tutor flagje amúgy is OFF.

  - id: OD-02
    question: A transport hogyan kezelje a hiányzó/elérhetetlen backendet?
    blocking: false
    resolution_policy: use_default
    default: >
      Kontrollált `AppResult.failure`, NEM dobás. A csendes try/catch
      no-op (CLAUDE.md mért csapdája) szintén tilos: a hibának a
      visszatérési értékben kell megjelennie.

  - id: OD-03
    question: Kell-e a transportnak a base URL-t honnan vennie?
    blocking: false
    resolution_policy: use_default
    default: >
      `AppConfig.apiBaseUrl` (a meglévő STRUMSIGHT_API_URL define), a többi
      hálózati hívás mintája szerint. Új define NEM vezetendő be.

  - id: OD-04
    question: Mi legyen, ha egy provider bekötéséhez a tilos zónába kellene nyúlni?
    blocking: true
    resolution_policy: stop_and_ask
    default: >
      `stopped`, a fájl és az ok megnevezésével. A pre-flight megmérte, hogy
      minden építőelem létezik és konstruálható (§2.2) — ha mégsem, az ÚJ
      információ, ami a kör alakját érinti.
```

## 6. Acceptance criteria

- [ ] **A1 — A három provider többé nem dob.** Egy `ProviderContainer`-ben,
  a production override-okkal (valós `KeyValueStore` teszt-duplikátummal),
  mindhárom provider olvasása **értéket ad**, nem `UnimplementedError`-t:
  `tutorOrchestratorProvider`, `tutorConversationRepositoryProvider`,
  `tutorMemoryRepositoryProvider`.

- [ ] **A2 — A `main.dart` override-listája mindhármat tartalmazza.**
  Gépi mérce: a `tutor_production_wiring_test.dart` a `main.dart`-ból
  exportált/kiemelt override-építő függvényt hívja (nem a `main()`-t), és
  ellenőrzi mind a hármat. Ha a `main.dart` szerkezete ezt nem engedi, a
  helyes lépés a **kiemelés egy tesztelhető függvénybe** — nem a mérce
  elhagyása.

- [ ] **A3 — Az alapértelmezett átjáró a stub, NEM a fake.** Teszt-cella: a
  production orchestrator `gatewayForAttempt`-je `LocalTutorModelGatewayStub`
  példányt ad, és egy forduló indítása `tutor.model_gateway.unavailable`
  hibát eredményez — **nem** `fake-tutor-response`-t.
  Gépi kerítés: `grep -c "FakeTutorModelGateway" lib/` → **0**.

- [ ] **A4 — A transport `data:` sorokat ad, értelmezés nélkül.** Teszt-cella
  egy hamis SSE-válaszfolyamon: a bemenet három `data: {...}` sora →
  a kimenet **pontosan három `String`**, a `data: ` prefix nélkül, a JSON
  **változatlanul**, parse nélkül. Üres sorok és `:` kommentsorok
  eldobandók.

- [ ] **A5 — A transport hibái kontrolláltak, nem dobások.** Mátrix:

  | Eset | Elvárt |
  |---|---|
  | a backend nem elérhető (connection error) | `AppResult.failure`, nem dobás |
  | HTTP 500 a stream megnyitásakor | `AppResult.failure` |
  | `health()` elérhetetlen backenden | `AppResult.failure` |
  | `cancelActiveStream()` aktív stream nélkül | no-op, nem dobás |

  **Csendes `try/catch` no-op TILOS** — a hibának a visszatérési értékben
  kell megjelennie (CLAUDE.md mért csapdája).

- [ ] **A6 — A flagek NEM mozdultak.** Mind a három `AppEnvironment`-re
  `aiTutorEnabled == false` és `aiTutorCloudEnabled == false`. A
  `feature_flags.dart` diffje **üres**:
  `git diff --name-only origin/main...HEAD | grep 'feature_flags.dart'` → üres.

- [ ] **A7 — Nincs UI-, route- vagy ARB-változás.**
  `git diff --name-only origin/main...HEAD` nem tartalmaz `lib/l10n/`,
  `lib/app/routing/`, sem `screens|widgets` útvonalat.

- [ ] **A8 — Az avult `tutorMain()` doc-comment javítva** — a
  `grep -rn "tutorMain" lib/` a kör után **0 találat**.

- [ ] **A9 — A gate zöld**, a §7 szerinti egyetlen artefaktum-hívással.

> **Miért nincs numerikus cellahármas:** a kör egyetlen acceptance-pontja sem
> mér számértékre — minden mérce logikai (provider értéket ad-e,
> frame-darabszám, hibaág visszatérési értéke, fájl érintettsége).

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Bármelyik provider továbbra is dob | **A1** |
| A `main.dart` override kimarad (csak a provider default változik) | **A2** |
| A `FakeTutorModelGateway` bedrótozva | **A3** (a hiba-cella + a `grep`-kerítés) |
| A transport parse-olja a JSON-t / szűri a frame-eket | **A4** (a kimenet nem a nyers JSON) |
| A transport dob elérhetetlen backenden | **A5** 1. sora |
| Csendes `try/catch` no-op a transportban | **A5** (a `failure` helyett `success` üres streammel) |
| A flag „menet közben" bekapcsolva | **A6** |
| Belépési pont / ARB hozzáadva | **A7** |
| A doc-comment érintetlen | **A8** |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** állítsd vissza
ideiglenesen a `tutorOrchestratorProvider`-t `throw UnimplementedError`-ra →
az **A1-nek PIROSNAK kell lennie** → állítsd vissza, és idézd a nyers
kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor test/app test/core
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); az `analyze` és a `test` kézi
láncolása OOM-ot ad (L05).

## 8. Implementációs sorrend

1. **RED először:** a transport tesztje (A4 frame-cella, A5 hibamátrix)
   hamis SSE-folyamon.
2. `http_tutor_stream_transport.dart`.
3. **RED:** a wiring teszt (A1, A2, A3).
4. A knowledge-index / retriever / prompt-builder providerek, majd az
   orchestrator és a két repo production factory-ja.
5. `main.dart` override-ok (+ szükség esetén a lista kiemelése tesztelhető
   függvénybe, A2).
6. Doc-commentek (A8) + a `feature_flags_test.dart` kerítése (A6).
7. Gate.
8. A §6.1 valódi-sértés próba + visszaállítás.
9. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **A chat továbbra sem ad valódi választ** — szándékos (§5.2), a flag OFF.
   A kör értéke: a crash-blokkoló megszűnik.
2. **A `main.dart` boot-ja érzékeny terület.** Ezért van a `test/core` és a
   `test/app` a gate-ben (L203).
3. **A transport a lokális backendtől függ** — a tesztek hamis folyamon
   mérnek, valós backend nélkül.
4. **A knowledge-index betöltése hibázhat** — OD-01: üres index + napló, a
   boot nem eshet el.

## 10. Implementation handoff — a Codex tölti ki

- Fájlonkénti összefoglaló.
- Futtatott parancsok + **TÉNYLEGES, csonkítatlan** kimenet.
- A §6.1 valódi-sértés próba nyers kimenete + visszaállítás.
- Az **A6/A7** bizonyítéka: a `git diff --name-only` tényleges kimenete.
- Az **A3** `grep -c "FakeTutorModelGateway" lib/` tényleges kimenete.
- Melyik OD-t használtad; eltérések és okuk; nem futtatott ellenőrzések és
  okuk; follow-upok.

> Állítás teszt nélkül = bemondás.

### Codex handoff — 2026-08-09

- `lib/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart`:
  új Dio SSE transport; `POST /tutor/stream` `ResponseType.stream`-mel,
  a `data:` sorok nyers payloadjai, explicit cancellation és kontrollált
  hálózati `AppResult.failure` ágak.
- `tutor_providers.dart` és `tutor_privacy_providers.dart`: explicit
  production factory-k a `LocalTutorConversationRepository`,
  `LocalTutorMemoryRepository`, az asset-alapú prompt builder és a
  szándékos `LocalTutorModelGatewayStub` számára; nincs fake gateway.
- `lib/main.dart`: exportált `buildTutorProductionOverrides`, amely a
  tudás-indexet a manifestből tölti (hibánál a meglévő naplózott üres-index
  fallback), és mindhárom Tutor seamet a boot `ProviderScope`-jába injektálja.
- `http_tutor_stream_transport_test.dart`: A4/A5 SSE payload- és
  hibaág-mátrix. `tutor_production_wiring_test.dart`: A1/A2/A3, a három
  override és a stub `tutor.model_gateway.unavailable` eredménye.

Futtatott ellenőrzések:

```text
flutter test test/features/ai_tutor/data/http_tutor_stream_transport_test.dart
  RED: a hiányzó HttpTutorStreamTransport miatt nem fordult.
  GREEN: 5 teszt zöld.

flutter test test/features/ai_tutor/presentation/tutor_production_wiring_test.dart \
  test/features/ai_tutor/data/http_tutor_stream_transport_test.dart \
  test/app/feature_flags_test.dart
  GREEN: 18 teszt zöld.

flutter analyze
  GREEN: No issues found! (a konstruktor-lint javítása után).

Valódi-sértés próba:
  createProductionTutorOrchestrator ideiglenesen
  throw UnimplementedError('A1 mutation probe')
  → tutor_production_wiring_test PIROS: UnimplementedError: A1 mutation probe
  → az eredeti factory visszaállítva.
```

- A6/A7 bizonyíték: `feature_flags_test.dart` a három environmentben mindkét
  flag OFF állapotát zölden mérte; a diff nem érint `feature_flags.dart`,
  `lib/l10n/`, `lib/app/routing/`, `screens/` vagy `widgets/` útvonalat.
- A3 kerítés: `grep -c "FakeTutorModelGateway" lib/main.dart
  lib/features/ai_tutor/presentation/providers/tutor_providers.dart
  lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart`
  → mindhárom fájlra `0`; a meglévő, változatlan teszt-duplikátum külön
  `data/model_gateway/fake_tutor_model_gateway.dart` fájlban maradt.
- OD-01 alkalmazva: `AssetKnowledgeRepository.fromRootBundle()` a meglévő
  manifest-loader. A `flutter test` `build/unit_test_assets/AssetManifest.bin`
  artefaktuma csak `assets/tutor_knowledge/manifest.json`-t tartalmazza, a
  beágyazott `en/`/`hu/` dokumentumokat nem; ezért a tesztben a dokumentált
  `tutorKnowledge.indexLoad.assetReadFailure` üres-index fallback aktív. A
  hiányzó rekurzív asset-deklaráció `pubspec.yaml`-t érintene, ami ebben a
  körben tilos zóna; follow-up szükséges a valódi tudásindex betöltéséhez.
- Nem futtatott ellenőrzés: CI teljes suite/property/release APK; ez a
  Claude-oldali CI-dispatch és merge-kapu feladata.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r06-gov-05b-1-tutor-production-wiring-review.md`
