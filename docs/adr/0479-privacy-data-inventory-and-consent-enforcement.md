# ADR 0479 — Privacy adat-leltár: a kibocsátási felület a FÁBÓL mérve, a visszavonás a MÉRT kapcsolón

- **Státusz:** elfogadva
- **Dátum:** 2026-08-29
- **Kör:** `E12-R17` (Chapter 12, Kör 17)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Kapcsolódó:**
  [`0247`](0247-analysis-export-share-and-delete-contract.md) (export/share/delete
  szerződés — a leltár retention-oszlopa ennek a MÁR MÉRT szerződésének a
  tükrözése, nem új fogalom),
  [`0132`](0132-ai-tutor-privacy-and-consent.md) (Tutor privacy & consent — a
  „nyers audio nincs a contextben" boundary és a granuláris `TutorConsent`
  forrása; ez a kör NEM vezet be új consent-fogalmat),
  [`0410`](0410-media-upload-contract-and-object-store.md) (Community media
  upload — a presigned PUT út, ma még bekötetlen)

## Kontextus — a pre-flight MÉRT tényei (2026-08-29, `main @ 34aff7fd`)

A kör tárgya nem egy új felület, hanem a MÁR SZÁLLÍTOTT adatáramlások
leltározása és a visszavonás kikényszerítésének bizonyítása. A pre-flight
ezért a tényleges hívási láncot mérte ki, nem a réteg-diagramot.

### A kibocsátási (egress) felület — négy osztály, kettő élő

| # | Út | Konstruktor | Kapu | Élő ma? |
|---|---|---|---|---|
| 1 | Account API | `DioFactory.createAccountClient` (`lib/core/network/dio_factory.dart:32`) | `FeatureFlags.accountEnabled` + auth session-generáció | **igen** |
| 2 | Diagnostics upload | `DioFactory.createDiagnosticsClient` (`dio_factory.dart:51`) | `FeatureFlags.diagnosticsEnabled` **és** `diagnosticsConsentProvider` | **igen** |
| 3 | Tutor SSE stream | `HttpTutorStreamTransport` (`lib/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart:16`), `POST /tutor/stream` | `TutorConsent.modelUseGranted` a turn-úton | **nem** — nincs konstrukciós hely a `lib/**` fában |
| 4 | Community media PUT | `CommunityMediaUploader` (`lib/features/community/data/api/community_media_uploader.dart`), presigned PUT | — | **nem** — „a HTTP wiring Kör 19+ feladat" |

A 3. és 4. út **injektált** `Dio`-t fogad, tehát nem a `DioFactory`-n megy
keresztül. A meglévő `test/tooling/dio_factory_guard_test.dart` csak a `Dio(`
**konstruktor-hívást** tiltja a `lib/**`-ban — egy injektált klienst fogadó
transport-osztályt nem lát, és nem is dolga látni.

### Miért ez a döntés gyökere

Az [L140](../LESSONS.md#l140) pontosan ezt a vakfoltot mérte ki: az
„offline ⇒ nincs cloud-hívás" garanciát egy olyan próba igazolta, amely
KIZÁRÓLAG az account Dio-factoryt és a diagnostics-klienst nézte, miközben a
tutor cloud-út egy **külön** `TutorStreamTransport`-on megy. A leltár tehát
akkor és csak akkor ér valamit, ha a teljességét a **fa** méri, és a fa-bejárás
a `DioFactory`-n KÍVÜLI transportokat is megtalálja.

### A visszavonási kapcsolók — mi létezik MA a `lib/**`-ban

| Csatorna | Kapcsoló | Kikényszerítés helye (mért) |
|---|---|---|
| Tutor | `TutorConsent.modelUseGranted` | `tutor_orchestrator.dart:47`, `local_tutor_fallback.dart:120` |
| Diagnostics | `diagnosticsConsentProvider` (default `false`, fail-closed) | `diagnostics_providers.dart` (notifier) **és** `diagnostics_uploader.dart:52` |
| Account-hátterű írás-utak (settings sync, Community repók) | auth session-generáció | `_AuthSessionGeneration.advance()` + `_AuthSessionCredentials.clear()`; a `AuthInterceptor` a kérés pillanatában olvassa (`auth_interceptor.dart:50,73`) |

**Community-specifikus consent-kapcsoló a kliensen NINCS.** A
`grep -rn "consent\|Consent" lib/features/community/` **nulla** találatot ad; a
brief által hivatkozott `e09_r04_0004_community_privacy_fields.py` egy
**backend** profil-láthatósági mező, nem kliensoldali adatküldés-kapu, és a
`backend/**` ennek a körnek tiltott zónája. A Community írás-utak
(`challenge_repository_impl`, `profile_repository_impl`,
`relationship_repository_impl`) az `accountApiClientProvider`-en ülnek, tehát a
rájuk ténylegesen ható visszavonás az **account-session visszavonása**.

## Döntés

### D1 — A leltár teljességét a FA méri, és a fa-bejárás nem `DioFactory`-központú

A `tool/check_data_inventory.dart` a `lib/**` fából gyűjti ki a kibocsátási
utakat, és mindegyikhez leltár-bejegyzést követel. A bejárásnak **legalább** a
következő három mintaosztályt kell felismernie, mert a mért fán mindhárom
előfordul:

1. a `DioFactory` kliens-gyártó metódusai;
2. **bármely** olyan `lib/**`-beli osztály, amely `Dio`-t (vagy más HTTP-klienst)
   mezőként/paraméterként fogad **és** kérés-igét hív rajta
   (`.post`/`.get`/`.put`/`.delete`/`.request`) — ez az L140 vakfoltja;
3. közvetlen `HttpClient` / `package:http` használat.

**NEM elfogadható gyengítés:** a checker a leltárból indul és csak azt
ellenőrzi, hogy a felsorolt utak léteznek-e. Egy ilyen checker az első ÚJ
végpont után is zöld marad — pontosan azt a hazugságot engedi át, ami ellen
készül.

**NEM elfogadható gyengítés:** a bekötetlen (3., 4.) utak kihagyása azon az
alapon, hogy „ma úgysem küldenek". A leltárban szerepelniük kell, megjelölt
bekötöttségi állapottal; különben az őket bekötő kör csendben szállít egy
leltáron kívüli adatküldést.

### D2 — A visszavonás AZONNAL hat, és ezt a TURN-ÚTON kell mérni

A visszavonás ugyanabban a session-ben, újraindítás nélkül érvényes. Mindhárom
csatorna cellája a tényleges hívási úton mér — a Tutor esetében az
orchestrátoron áthaladó turnnel és transport-/gateway-kémmel, **nem** a
képernyő statikus renderelésével (L140).

**NEM elfogadható gyengítés:** „a következő app-indításkor lép életbe"
viselkedés elfogadása (ADR 0132).

### D3 — Nincs csendes cloud-fallback

Ha egy helyi út nem elérhető, a rendszer hozzájárulás nélkül NEM esik vissza
hálózati hívásra. **NEM elfogadható gyengítés:** „degradált mód" néven
bevezetett hálózati ág.

### D4 — A kör nem hoz be új consent-fogalmat, és nem nyúl a `lib/**`-hoz

A leltár és a kényszerítési cellák a MÁR MÉRT kapcsolókra épülnek (a fenti
táblázat). Ha egy cella MÉRT szivárgást talál (visszavont hozzájárulás mellett
is megy adat), a kimenet `stopped` jelzés és jelentés — a javítás önálló,
review-zott kör tárgya, mert egy adatvédelmi javítás nem utazhat a saját
bizonyítékával egy diffben.

## Következmények

- A leltár (`docs/privacy/data-inventory.yaml`) géppel olvasható, és a
  teljességét CI-ben futó cella tartja karban — a kézi lista avulása kizárva.
- A bekötetlen utak (Tutor SSE, Community media) leltárban vannak, így a
  bekötésük kötelezően leltár-frissítéssel jár.
- A Community csatorna kényszerítési cellája az account-session
  visszavonásán mér, mert a fán MA ez a rá ható kapcsoló; ha egy későbbi kör
  bevezet Community-specifikus consentet, a cellát arra kell átkötni.
- Ez a döntés nem lazítható azért, hogy egy teszt zöld legyen.
