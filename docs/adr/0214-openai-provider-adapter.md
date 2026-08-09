# ADR 0214 — OpenAI provider-adapter a tutor-proxyban

- **Státusz:** Elfogadva (GOV-05b-2 pre-flight, 2026-08-09)
- **Kör:** GOV-05b-2 / `E99-R07` (governance-kör)
- **Implementer motor:** Terra · az ADR-t az orchesztrátor (Claude Opus 5) írta
- **Kontext-ADR:** [0131](0131-ai-tutor-provider-boundary.md) — providerfüggetlenség
- **User-döntés:** 2026-08-09 „open ai legyen".

## Kontextus

**Mért 2026-08-09-én:**

1. Az [ADR 0131](0131-ai-tutor-provider-boundary.md) szándékosan nyitva
   hagyta a szolgáltatót: „provider-integráció még nincs". A user 2026-08-09-én
   **OpenAI**-t választott.
2. A backend `ProviderGateway` ABC egyetlen konkrét implementációja a
   `FakeProviderGateway`. A szerződés:
   `async complete(messages, model, api_key, timeout_seconds) -> str`.
   Az ABC docstringje kimondja: „Errors are normalized to provider-neutral
   exceptions — **no provider details leak into logs or responses**."
3. A `ProviderRegistry` (`provider_registry.py`) allowlist-alapú:
   `allowed: dict[str, list[str]]`, és `ProviderNotAllowedError`-t dob, ha a
   provider vagy a modell nincs a listán. A config alapértéke
   `{"fake": ["fake-model"]}`, `tutor_provider: "fake"`.
4. **Létező invariáns-teszt:** `backend/tests/tutor/test_tutor_proxy.py:554`
   `test_no_prompt_in_log` — a napló nem tartalmazhatja a promptot.
5. A `main.py:63–67` **fail-closed**: ha `tutor_enabled` és az API-kulcs üres
   vagy a fejlesztői alapérték, a boot elhasal.
6. **HTTP-kliens:** a `httpx` ma **csak** a `requirements-dev.txt`-ben van
   (`>=0.27,<0.29`), a production `requirements.txt`-ben nincs. Az `openai`
   SDK sehol nincs.
7. **Az OpenAI Chat Completions szerződése** (a hivatalos API-referenciából
   lekérve 2026-08-09-én, nem emlékezetből):
   `POST https://api.openai.com/v1/chat/completions`,
   `Authorization: Bearer <kulcs>`, `Content-Type: application/json`;
   body `{"model": ..., "messages": [{"role", "content"}], "max_tokens": ...}`;
   válasz `choices[0].message.content`, valamint
   `usage.{prompt_tokens, completion_tokens, total_tokens}`.

## Döntés

### Döntés 1 — Nyers HTTP `httpx`-szel, NEM az `openai` SDK-val

Az adapter `httpx.AsyncClient`-tel hívja a Chat Completions végpontot. Az
`openai` SDK **nem** kerül be.

**Indok:** a `ProviderGateway` szerződése egyetlen kérés-válasz
(`complete(...) -> str`) — egy teljes SDK ehhez aránytalan függőség, és az
[ADR 0131](0131-ai-tutor-provider-boundary.md) provider-semleges határát
vékonyabban tartja a nyers HTTP. A `httpx` már ma is használt (dev), tehát
**át kell tenni a production `requirements.txt`-be**, ugyanazzal a
major-pinneléssel, amit a fájl fejléce előír.

### Döntés 2 — A modell nem az adapterben dől el

Az adapter a kapott `model` sztringet használja, és **nem tartalmaz
hard-kódolt modellnevet**. A választás a `ProviderRegistry` allowlistjén és a
configon keresztül történik (`tutor_provider`, `tutor_model`,
`tutor_allowed_providers`) — így modellváltás **konfiguráció, nem kódváltozás**.

A config alapértéke **változatlanul `fake`** marad. Ez a kör **nem kapcsolja
át** az éles providert; azt üzemeltetési döntés (kulcs + hosztolás) teszi meg.

### Döntés 3 — Hibanormalizálás szivárgás nélkül

Minden hiba `ProviderError`-rá vagy `ProviderTimeoutError`-rá normalizálódik:

| Eset | Kivétel |
|---|---|
| `httpx.TimeoutException` | `ProviderTimeoutError` |
| HTTP 4xx/5xx | `ProviderError` |
| hálózati/kapcsolati hiba | `ProviderError` |
| hiányzó vagy nem string `choices[0].message.content` | `ProviderError` |
| nem JSON válasz | `ProviderError` |

A kivétel üzenete **nem tartalmazhat** provider-nevet, végpont-URL-t,
API-kulcsot, sem a válasz nyers törzsét. A `FakeProviderGateway` docstringje
által rögzített invariáns (Kontextus 4) az OpenAI-adapterre is érvényes: **a
prompt és a kulcs SOHA nem naplózódik**, semmilyen szinten, kivételüzenetben
sem.

### Döntés 4 — A `max_tokens` a meglévő kimeneti korlátból származik

Az adapter nem vezet be új konfigurációs kulcsot a kimeneti hosszra: a
meglévő `tutor_max_output_bytes` határból származtatott értéket használja,
vagy a hívó adja át. Új `Settings` mező **csak akkor**, ha a meglévők
bizonyíthatóan nem elegendők — és akkor is dokumentált alapértékkel.

### Döntés 5 — A teszt SOHA nem hív hálózatot

Az adapter tesztjei `httpx.MockTransport`-tal (vagy azzal egyenértékű,
injektált klienssel) futnak. **Valós OpenAI-hívás a tesztekben tilos** — a CI
determinisztikus és offline kell maradjon, és egy éles hívás pénzbe kerülne.

Ebből következik, hogy az adapter **injektálhatóvá** kell tegye a HTTP
klienst (konstruktor-paraméter, alapértéke a valódi `AsyncClient`).

### Döntés 6 — A `fake` provider marad, nem cserélődik le

A `FakeProviderGateway` **nem törlendő**: a meglévő proxy-tesztek rá épülnek,
és a lokális/offline fejlesztés útja marad. Az allowlist **bővül** az
OpenAI-bejegyzéssel, nem cserélődik.

## Következmények

**Pozitív**

- A tutor-proxy valódi választ tud adni, amint van kulcs és hosztolás.
- A modellváltás konfiguráció (Döntés 2).
- A kulcs a szerveren marad; a kliens sosem látja (ADR 0131 sértetlen).

**Negatív / kockázat**

- **Új production függőség** (`httpx`) — kicsi, de valós felület.
- **Az éles hívás pénzbe kerül.** A kör nem kapcsolja be (Döntés 2); a
  költség-kontroll a meglévő rate limit és napi token-korlát
  (`tutor_rate_limit_max`, `tutor_daily_token_limit`) — ezek működését az
  éles providerrel **még senki nem mérte**, ez follow-up.
- Az OpenAI API változhat; a szerződést (Kontextus 7) a kör rögzíti a
  tesztek fixture-jeiben, hogy egy jövőbeli eltérés piros legyen, ne néma.
