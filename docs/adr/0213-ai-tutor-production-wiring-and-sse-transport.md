# ADR 0213 — Az AI Tutor production-drótozása és a konkrét SSE transport

- **Státusz:** Elfogadva (GOV-05b-1 pre-flight, 2026-08-09)
- **Kör:** GOV-05b-1 / `E99-R06` (governance-kör)
- **Implementer motor:** Terra · az ADR-t az orchesztrátor (Claude Opus 5) írta
- **Kontext-ADR-ek:** [0131](0131-ai-tutor-provider-boundary.md)
  (providerfüggetlenség), [0142](0142-ai-tutor-streaming-transport-protocol.md)
  (a frame-protokoll), [0197](0197-song-trainer-shipping-rollout-boundary.md)
  (a rollout-alak)
- **User-döntés:** 2026-08-09 „előbb a drótozás, kulcs nélkül", majd
  „a négy konkrét darab is csináljuk meg".

## Kontextus

**Mért 2026-08-09-én:** az `aiTutorEnabled` bekapcsolása ma **crash**-t
okozna, nem degradált élményt.

1. **Három provider `throw UnimplementedError`-ral indul, és a production
   boot EGYIKET SEM írja felül:**
   - `tutorOrchestratorProvider` (`tutor_providers.dart:337`)
   - `tutorConversationRepositoryProvider` (`tutor_providers.dart:345`)
   - `tutorMemoryRepositoryProvider` (`tutor_privacy_providers.dart`)

   A doc-comment „production boot wires it via `tutorMain()`"-t ígér, de a
   **`tutorMain()` nem létezik** (`grep -rn "tutorMain" lib/` → csak maga a
   doc-comment), és a `lib/main.dart` ProviderScope override-listája nem
   tartalmazza őket. A `TutorChatScreen` és a `TutorDataScreen` megnyitása
   dobna; a `TutorHomeScreen` stateless, az működne.

   Ugyanaz a hibaosztály, amit a Practice V2-nél az E02-R21 pótolt.

2. **Minden konkrét implementáció LÉTEZIK és konstruálható:**

   | Szükséglet | Meglévő implementáció | Függősége |
   |---|---|---|
   | conversation repo | `LocalTutorConversationRepository` | `KeyValueStore` |
   | memory repo | `LocalTutorMemoryRepository` | `KeyValueStore` |
   | context assembler | `TutorContextAssembler({budget})` | — |
   | knowledge retriever | `KnowledgeRetriever({index})` | `KnowledgeIndex` |
   | prompt builder | `TutorPromptBuilder({templateLoader})` | `PromptTemplateLoader` |
   | orchestrator | `TutorOrchestrator` | a fenti három + `gatewayForAttempt` |

   A `keyValueStoreProvider` létezik és a `main.dart` már felülírja. Az
   assetek megvannak és a `pubspec.yaml` deklarálja őket:
   `assets/tutor_knowledge/` (manifest + `en`/`hu`) és `assets/tutor_prompts/`
   (6 sablon).

3. **A modell-átjáró a hiányzó láncszem.** A `TutorOrchestrator` minden
   fordulóhoz kötelezően igényel egy `TutorModelGateway`-t
   (`gatewayForAttempt` required). Három átjáró létezik:
   `LocalTutorModelGatewayStub` (mindig `tutor.model_gateway.unavailable`),
   `FakeTutorModelGateway` (`script`-tel hajtott **teszt-duplikátum**),
   `RemoteTutorModelGateway` (kész, de **`TutorStreamTransport`-ot igényel**).

4. **`TutorStreamTransport`-nak NINCS konkrét implementációja** — csak az
   absztrakt interfész (`tutor_stream_dto.dart:337`), három metódussal:
   `openTurnStream({requestId, sequence, conversationId, message})`,
   `cancelActiveStream()`, `health()`.

5. **A szerveroldal viszont KÉSZ.** `backend/app/tutor/` teljes modul, a
   `main.py`-ba kötve a `tutor_enabled` flag mögé: `GET /tutor/capability`,
   `POST /tutor/turn`, és — ami itt számít — **`POST /tutor/stream`**
   (`backend/app/tutor/stream.py`, ADR 0142): SSE, soronként egy `data:` JSON
   frame, közös monoton `seq`, sorrend `started → delta* → usage → complete`
   vagy `started → failure`. A Dart DTO-réteg ezt a protokollt **már
   modellezi**.

6. **Valódi provider viszont nincs:** a backend `ProviderGateway` egyetlen
   konkrét implementációja a `FakeProviderGateway`; a config
   `tutor_provider: "fake"`, `tutor_allowed_providers: {"fake": ["fake-model"]}`.
   Az [ADR 0131](0131-ai-tutor-provider-boundary.md) szándékosan nyitva
   hagyta: „provider-integráció még nincs".

7. A `lib/core/network/api_client.dart` `getJson`/`postJson`/`put`/`post`
   metódusokat ad — **streamelést nem**.

## Döntés

### Döntés 1 — Ez a kör drótoz, de NEM kapcsol be

`aiTutorEnabled` és `aiTutorCloudEnabled` **`false` marad minden
környezetben**. A kör azt éri el, hogy a flag *bekapcsolható legyen* — nem
azt, hogy be legyen kapcsolva.

**Indok:** valódi provider nélkül (Kontextus 6) a chat vagy hibát adna, vagy
konzerv választ. Egy chat-feature, ami nem tud csevegni, negatív
felhasználói érték. A flag-flip a valódi provider-adapter után jön, külön
körben.

Ez **eltér** a GOV-05a alakjától, ahol a flag és a belépési pont egy körben
ment — ott a képesség mögött működő kód volt.

### Döntés 2 — A production-drótozás a `main.dart` ProviderScope-jában él

Nem vezetünk be `tutorMain()`-t (a doc-comment ígérete elavult, Kontextus 1).
A három provider override-ja oda kerül, ahol a többi production-override már
él — így egy helyen látszik, mit injektál a boot.

### Döntés 3 — Az alapértelmezett átjáró a STUB, nem a fake

A `gatewayForAttempt` production-alapértelmezése a
`LocalTutorModelGatewayStub`, ami kontrollált
`tutor.model_gateway.unavailable` hibát ad.

**A `FakeTutorModelGateway` NEM kerülhet production-drótozásba.** Az egy
`script`-tel hajtott teszt-duplikátum; szállítva minden üzenetre ugyanazt
adná. Konzerv válasz szállítása félrevezetés — akkor is, ha címkézve van.

### Döntés 4 — A konkrét transport SSE-t olvas, és a hibát is frame-nek látja

Az ÚJ `TutorStreamTransport` implementáció Dio `ResponseType.stream`-mel
nyitja a `POST /tutor/stream` végpontot, és a `data:` sorokat nyers
`String` frame-payloadként adja tovább. **Protokoll-értelmezés (parse,
sorrendezés, normalizálás) NEM a transport dolga** — az a
`RemoteTutorModelGateway` felelőssége (ADR 0142).

A transport az `ApiClient`-et nem bővíti streameléssel (Kontextus 7): az
`ApiClient` a kérés/válasz JSON-határ, a stream külön ügy.

### Döntés 5 — A providerfüggetlenség sértetlen marad

[ADR 0131](0131-ai-tutor-provider-boundary.md) érvényben: a Flutter kliens
sehol nem hivatkozhat konkrét model-provider SDK típusra. A transport csak a
StrumSight backendet ismeri, provider-semleges frame-eket olvas.

## Következmények

**Pozitív**

- Az `aiTutorEnabled` bekapcsolása többé nem crash — a rollout blokkolója
  megszűnik.
- A Tutor Profile / Privacy / Data képernyői valódi, lokális
  implementációkon futnak.
- A teljes csővezeték (kliens → SSE → backend) bizonyíthatóvá válik a
  lokális backenddel, **API-kulcs és hosztolás nélkül**.

**Negatív / kockázat**

- A chat továbbra sem ad valódi választ (Döntés 3) — szándékos, a flag OFF.
- A transport a lokális backend elérhetőségétől függ; hálózat nélkül
  kontrollált hibát ad, nem crasht — ezt tesztelni kell.
- A `tutorMain()` ígéretét hordozó doc-comment javítandó, különben a
  következő olvasó újra nem létező függvényt keres.
