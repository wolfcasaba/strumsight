# E99-R07 (GOV-05b-2) — OpenAI provider-adapter a tutor-proxyban

- **Státusz:** PLANNING (pre-flight lezárva 2026-08-09)
- **Típus:** **governance-kör** — a `HANDOFF.md` §3 „Az AI Tutor rollout
  BLOKKOLT" tétel **második** feloldó köre (a `E99-R06` az első)
- **Kör-azonosító:** `E99-R07` (`E99` = governance pszeudo-epic, nem valódi
  epic). Emberi neve **GOV-05b-2**.
- **Branch:** `codex/e99-r07-gov-05b-2-openai-provider-adapter`
- **Előfeltétel:** nincs — **független** az `E99-R06`-tól (az Dart, ez Python)
- **Brief szerzője:** Claude (Opus 5) · **Implementáció:** Codex (Terra)
- **Előre kiosztott ADR:** [`0214`](../adr/0214-openai-provider-adapter.md)
  — **MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "backend/app/tutor/provider_gateway.py",
  "backend/app/config.py",
  "backend/requirements.txt",
  "backend/tests/tutor/test_openai_provider_gateway.py",
  "docs/rounds/e99-r07-gov-05b-2-openai-provider-adapter.md",
]
gate_tests = [
  "test/app",
]
native_gate = false
```

> **Egy ÚJ fájl:** `backend/tests/tutor/test_openai_provider_gateway.py`.
>
> **A backend-sáv MAGÁTÓL bekapcsol** a `tools/round-gate.sh`-ban, ha a kör
> hozzáér a `backend/`-hez (ADR 0173) — `ruff check`, `ruff format --check`
> és `pytest` külön processzként fut. A `gate_tests` Dart-oldali listája
> ezért minimális: a kör egyetlen Dart sort sem ír.

## 0.0 Pre-flight revízió (mérve 2026-08-09, a kör indítása előtt)

**Talált: a `tutor_*` settings blokk duplikálva a `config.py`-ban —
előfeltétel-kockázat, nem a kör hibája.**

Mérve: `git blame -L 56,86 backend/app/config.py` → a `tutor_enabled`…
`tutor_timeout_seconds` mezőcsoport **kétszer** szerepel (56–70. és 72–86.
sor), **byte-azonos** tartalommal, egyetlen commitból (`c1c0a7716`, E04-R14,
2026-08-05 — ZÁRT kör, ezért ez a duplikáció H2 alá esne, HA a viselkedést
módosítanánk; a puszta törlés nem teszi, lásd lent). Python osztálytörzsben
egy attribútum második definíciója felülírja az elsőt — a ténylegesen
érvényes érték tehát a MÁSODIK (72–86. sorbeli) blokké, bár a két blokk ma
byte-azonos, ezért nincs tényleges viselkedéskülönbség.

**Kockázat, ha figyelmen kívül marad:** a brief §2.2 a mezőket
`config.py:58–70` címkével hivatkozza. Ha az implementer az OD-01 OpenAI
allowlist-bejegyzést (vagy az OD-03 végpont-URL mezőt) **csak** ebbe az
(első) blokkba írja be, a változás **némán hatástalan marad**, mert a 72–86.
sor felülírja — az A1/A5/A7 tesztek megmagyarázatlanul pirosra futnának.

**Feloldás (a kör hatáskörében, §2 szerinti önálló döntés — a `config.py`
már engedélyezett fájl ebben a körben, és a duplikátum törlése nem
változtatja meg egyetlen lezárt kör viselkedését, mert a két blokk
byte-azonos):** a `config.py` módosításakor az implementer ELŐSZÖR törölje a
**második** (72–86. sor) duplikátum-blokkot — a brief §2.2 sor-hivatkozása
így is stabil marad —, majd az OD-01/OD-03 bővítést az egyetlen megmaradó
(56–70. sor) blokkba írja.

**Az A8 mérce pontosítása erre az esetre:** az A8 („a `config.py` diffjében
[a `tutor_enabled`/`tutor_provider` sor] nem változik") az ÉRTÉKRE
vonatkozik, nem a sorok puszta jelenlétére. A duplikátum-blokk törlése miatt
a diff mutatni fogja a második (holt) `tutor_enabled: bool = False` /
`tutor_provider: str = "fake"` sor törlését is — ez **elfogadott és várt**,
amíg az egyetlen megmaradó blokk értéke változatlanul `False`/`"fake"` marad.

Fenti méréssel a brief az `allowed_paths`/`gate_tests` listát **változatlanul**
hagyja — a feloldás a már engedélyezett `config.py` fájlon belül fér el,
csak annak belső tartalmára ad pontosabb utasítást.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"  ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A tutor-proxynak ma **nincs valódi provider-adaptere** — csak
`FakeProviderGateway`. Ez a kör megírja az **OpenAI**-adaptert
(user-döntés 2026-08-09: „open ai legyen"), hogy a proxy valódi választ tudjon
adni, amint van kulcs és hosztolás.

**A kör NEM kapcsolja át az éles providert** (ADR 0214 Döntés 2): a config
alapértéke `fake` marad. Az átkapcsolás üzemeltetési döntés.

## 2. Jelenlegi állapot (mérve 2026-08-09)

### 2.1 A szerződés, amit implementálni kell

`backend/app/tutor/provider_gateway.py`:

```python
class ProviderGateway:
    async def complete(self, messages: list[dict[str, str]], model: str,
                       api_key: str, timeout_seconds: float) -> str: ...
```

Kivételek: `ProviderError`, `ProviderTimeoutError`. Az ABC docstringje:
„Errors are normalized to provider-neutral exceptions — **no provider details
leak into logs or responses**."

Egyetlen konkrét implementáció ma: `FakeProviderGateway` (30. sor).

### 2.2 A regisztrációs pont

`backend/app/tutor/provider_registry.py` — allowlist-alapú:
`ProviderRegistry(allowed: dict[str, list[str]], provider: str, model: str)`,
`resolve()` → `ResolvedProvider(name, model_id)`, különben
`ProviderNotAllowedError`.

`backend/app/config.py:58–70`: `tutor_enabled: bool = False`,
`tutor_provider: str = "fake"`, `tutor_model: str = "fake-model"`,
`tutor_api_key: str = "dev-tutor-key"`,
`tutor_allowed_providers: dict[str, list[str]] = {"fake": ["fake-model"]}`,
`tutor_max_output_bytes: int = 2000`, `tutor_timeout_seconds: float = 30.0`,
`tutor_rate_limit_max: int = 30`, `tutor_daily_token_limit: int = 50000`.

`backend/app/main.py:63–67` **fail-closed**: `tutor_enabled` mellett üres vagy
fejlesztői alapértékű kulcs → a boot elhasal. `main.py:147–184` építi a
registry-t, a `FakeProviderGateway`-t és a service-t.

### 2.3 A meglévő invariáns-teszt

`backend/tests/tutor/test_tutor_proxy.py:554` — `test_no_prompt_in_log`:
a napló nem tartalmazhatja a promptot. Ez az adapterre is érvényes.

### 2.4 A HTTP-kliens hiánya

`httpx>=0.27,<0.29` **csak** a `requirements-dev.txt`-ben van; a production
`requirements.txt`-ben nincs. Az `openai` SDK sehol.

### 2.5 Az OpenAI szerződése (a hivatalos API-referenciából, 2026-08-09)

- `POST https://api.openai.com/v1/chat/completions`
- fejlécek: `Authorization: Bearer <kulcs>`, `Content-Type: application/json`
- body: `{"model": <str>, "messages": [{"role": <str>, "content": <str>}], "max_tokens": <int>}`
- válasz: `choices[0].message.content` (a szöveg), és
  `usage.{prompt_tokens, completion_tokens, total_tokens}`

## 3. Scope

**Benne:**

1. `provider_gateway.py` — ÚJ `OpenAiProviderGateway(ProviderGateway)`
   osztály, injektálható HTTP klienssel (ADR 0214 Döntés 5).
2. `config.py` — az `tutor_allowed_providers` **bővítése** egy OpenAI
   bejegyzéssel (a `fake` MARAD); szükség esetén a végpont-URL
   konfigurálhatóvá tétele dokumentált alapértékkel.
3. `requirements.txt` — a `httpx` áthozatala production függőségnek,
   ugyanazzal a major-pinneléssel, ami a dev fájlban van.
4. `test_openai_provider_gateway.py` (ÚJ) — `httpx.MockTransport`-tal.
5. A brief §10 handoff.

**Kívül (ebben a körben TILOS):**

- **Az éles provider bekapcsolása.** `tutor_provider` marad `"fake"`,
  `tutor_enabled` marad `False` (ADR 0214 Döntés 2).
- **`main.py` módosítása.** A registry/gateway kiválasztásának bekötése a
  boot-ba a KÖVETKEZŐ kör dolga — ez a kör az adaptert szállítja, nem a
  bekötést. Ha úgy tűnik, `main.py` nélkül nem tesztelhető, az `stopped`.
- **A `FakeProviderGateway` törlése vagy módosítása** (ADR 0214 Döntés 6).
- Az `openai` SDK bevezetése (Döntés 1).
- Bármely Dart fájl (`lib/`, `test/`, `tool/`).
- A tutor service, router, stream, redaction, usage moduljai.
- `.github/`, `tools/`, `docs/adr/`.

## 4. Engedélyezett fájlok

| Útvonal | Miért |
|---|---|
| `backend/app/tutor/provider_gateway.py` | az ÚJ `OpenAiProviderGateway` |
| `backend/app/config.py` | az allowlist bővítése |
| `backend/requirements.txt` | `httpx` production függőségként |
| `backend/tests/tutor/test_openai_provider_gateway.py` | **ÚJ** — a teszt |
| `docs/rounds/e99-r07-gov-05b-2-openai-provider-adapter.md` | §10 handoff |

**Tilos zóna:** `backend/app/main.py`, `backend/app/tutor/` a
`provider_gateway.py`-on kívül, `backend/tests/` a fenti egy ÚJ fájlon kívül,
`backend/alembic/`, `lib/` (MINDEN), `test/` (MINDEN Dart teszt), `tool/`,
`tools/`, `.github/`, `docs/adr/`.

## 5. Kötött architekturális döntések

Forrás: [ADR 0214](../adr/0214-openai-provider-adapter.md).

### 5.1 Nyers HTTP `httpx`-szel, nem SDK-val

`httpx.AsyncClient`. Az `openai` SDK nem kerül be. A `httpx` a
`requirements-dev.txt`-beli **azonos major-pinnelést** kapja a production
fájlban.

### 5.2 Nincs hard-kódolt modellnév

Az adapter a kapott `model` sztringet használja. Modellnév a kódban **nem
szerepelhet** — se alapértékként, se fallbackként. A választás az allowlisten
és a configon át történik.

### 5.3 Hibanormalizálás, szivárgás nélkül

| Eset | Elvárt kivétel |
|---|---|
| `httpx.TimeoutException` | `ProviderTimeoutError` |
| HTTP 4xx | `ProviderError` |
| HTTP 5xx | `ProviderError` |
| kapcsolati hiba (`httpx.ConnectError`) | `ProviderError` |
| nem JSON törzs | `ProviderError` |
| hiányzó `choices[0].message.content` | `ProviderError` |
| `content` nem string | `ProviderError` |

A kivétel üzenete **nem tartalmazhat**: provider-nevet, végpont-URL-t,
API-kulcsot (sem részletet belőle), sem a válasz nyers törzsét.

### 5.4 A prompt és a kulcs SOHA nem naplózódik

Semmilyen naplószinten, és kivételüzenetben sem. Ez a `FakeProviderGateway`
docstringje által rögzített és a `test_no_prompt_in_log` által mért invariáns
kiterjesztése.

### 5.5 A teszt SOHA nem hív hálózatot

`httpx.MockTransport` vagy injektált kliens. **Valós OpenAI-hívás a
tesztekben tilos** — a CI offline és determinisztikus, és egy éles hívás
pénzbe kerülne.

### 5.6 Nyitott döntések (ADR 0138)

```yaml
open_decisions:
  - id: OD-01
    question: Milyen kulccsal kerüljön be az OpenAI az allowlistbe?
    blocking: false
    resolution_policy: use_default
    default: >
      `"openai"` provider-név. A modell-lista a configban ÜRES-nem-lehet,
      de a konkrét modellnevet NEM a kód dönti el: az alapértelmezett
      allowlist maradjon `{"fake": ["fake-model"]}` + egy `"openai": []`
      bejegyzés HELYETT inkább dokumentált példa a config docstringjében,
      hogy üzemeltetéskor tölthető. Üres lista esetén a registry helyesen
      `ProviderNotAllowedError`-t ad — ez fail-closed, tehát elfogadható.

  - id: OD-02
    question: Honnan jöjjön a max_tokens?
    blocking: false
    resolution_policy: use_default
    default: >
      A meglévő `tutor_max_output_bytes`-ból származtatva, vagy hívói
      paraméterként. ÚJ Settings mezőt csak akkor vezess be, ha a meglévő
      bizonyíthatóan nem elég — és akkor dokumentált alapértékkel.

  - id: OD-03
    question: Konfigurálható legyen-e a végpont URL-je?
    blocking: false
    resolution_policy: use_default
    default: >
      IGEN, dokumentált alapértékkel (`https://api.openai.com/v1`), mert
      enélkül a teszt csak transport-injektálással működik, és egy
      kompatibilis proxy sem használható. A kulcs NEM kerülhet URL-be.

  - id: OD-04
    question: Mi legyen, ha az adapter bekötéséhez a main.py-hoz kellene nyúlni?
    blocking: true
    resolution_policy: stop_and_ask
    default: >
      `stopped`. A bekötés szándékosan a KÖVETKEZŐ kör dolga; az adapter
      önmagában, injektált klienssel teljes mértékben tesztelhető.
```

## 6. Acceptance criteria

- [ ] **A1 — A boldog út.** Mockolt válaszra
  (`choices[0].message.content == "hello"`) a `complete(...)` **pontosan**
  `"hello"`-t ad vissza, és a kimenő kérés: `POST` a
  `/v1/chat/completions` útvonalra, `Authorization: Bearer <kulcs>` fejléccel,
  a body `model` mezőjében a **kapott** modellnévvel, a `messages` a kapott
  listával.

- [ ] **A2 — Hibamátrix.** A §5.3 **mind a hét** sora külön teszt-cella,
  mindegyik a megnevezett kivételt várja. Egyik sem hagyható el.

- [ ] **A3 — Nincs szivárgás a kivételüzenetben.** Mind a hét hibaágra: a
  kivétel `str()`-je **nem tartalmazza** a kulcsot, a végpont hosztnevét, a
  „openai" szót, sem a nyers válasz-törzset. Teszt-cella felismerhető
  szentinel-értékekkel (pl. kulcs `sk-SENTINEL-KEY`, törzs
  `SENTINEL-BODY`), és `assert "sk-SENTINEL-KEY" not in str(exc)`.

- [ ] **A4 — A prompt és a kulcs nem naplózódik.** `caplog`-gal, a
  `test_no_prompt_in_log` mintájára: egy szentinel promptot és szentinel
  kulcsot tartalmazó hívás után **sem** a prompt, **sem** a kulcs nem
  szerepel a `caplog.text`-ben — sikeres ÉS hibás ágon egyaránt.

- [ ] **A5 — Nincs hard-kódolt modellnév.** Gépi mérce:
  `grep -nE "gpt|o[0-9]|chatgpt" backend/app/tutor/provider_gateway.py` →
  **0 találat**. (A kapott `model` paraméter használata nem találat.)

- [ ] **A6 — Nincs hálózat a tesztekben.** Gépi mérce: a tesztfájl
  `httpx.MockTransport`-ot (vagy injektált klienst) használ, és
  `grep -c "api.openai.com" backend/tests/tutor/test_openai_provider_gateway.py`
  legfeljebb a **mock URL-egyeztetés** miatt fordul elő — valódi hívás nincs.
  A pytest futás hálózat nélkül is zöld.

- [ ] **A7 — A `fake` provider érintetlen.** A `FakeProviderGateway`
  osztály diffje **üres**, és a `tutor_allowed_providers` továbbra is
  tartalmazza a `{"fake": ["fake-model"]}` bejegyzést.

- [ ] **A8 — Az éles provider NEM kapcsol be.** `tutor_enabled` alapértéke
  `False`, `tutor_provider` alapértéke `"fake"` marad. Gépi mérce: a
  `config.py` diffjében ez a két sor nem változik.

- [ ] **A9 — A `main.py` érintetlen.**
  `git diff --name-only origin/main...HEAD | grep 'backend/app/main.py'`
  → **üres**.

- [ ] **A10 — Nulla Dart-változás.**
  `git diff --name-only origin/main...HEAD | grep -E '^(lib|test|tool)/'`
  → **üres**.

- [ ] **A11 — A gate zöld**, beleértve az automatikusan bekapcsoló
  backend-sávot (`ruff check`, `ruff format --check`, `pytest`).

- [ ] **A12 — A `timeout_seconds` változatlanul jut el a HTTP klienshez.**
  Három **különböző** értékkel (pl. `0.5`, `5.0`, `30.0`) hívva az adaptert,
  a mockolt kliens **pontosan azt** a számot kapja meg, amit a hívó adott —
  se kerekítés, se saját alapérték, se felülírás.

> **Miért NINCS alatta/rajta/fölötte cellahármas — és miért fogadom el a
> `brief-lint` S3 leletét:** a `tools/brief-lint.py` S3 szabálya a `timeout`
> szóra illeszkedik, és numerikus küszöb-mátrixot kér. Itt azonban az adapter
> a küszöböt **nem értékeli ki**, hanem **delegálja** a `httpx` kliensnek: nincs
> olyan `<` vagy `<=` összehasonlítás a kódban, aminek a két oldalát meg
> lehetne különböztetni. A helyes mérce ezért nem küszöb-hármas, hanem a
> **pass-through** (A12) és a **kivétel-leképezés** (A2 timeout-sora).
> A kör minden más mércéje logikai (kivétel-típus, szivárgás hiánya, fájl
> érintettsége, string jelenléte). Az S3 lelet tehát **tudatosan elfogadott
> hamis pozitív**, nem elmulasztott pre-flight teendő.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A timeout `ProviderError`-ként jön vissza `ProviderTimeoutError` helyett | **A2** timeout-sora |
| A HTTP-hiba felbuborékol nyers `httpx` kivételként | **A2** 4xx/5xx sorai |
| A kivételüzenet tartalmazza a válasz törzsét vagy a kulcsot | **A3** |
| A hibaág naplózza a promptot vagy a kulcsot | **A4** |
| Alapértelmezett modellnév a kódban | **A5** |
| A teszt valódi hálózatot hív | **A6** (offline futásban piros) |
| A `fake` provider lecserélve/törölve | **A7** |
| A `tutor_provider` alapértéke `"openai"`-ra írva | **A8** |
| A bekötés a `main.py`-ba is bekerül | **A9** |
| Hiányzó `content` esetén `None`/üres string visszaadása kivétel helyett | **A2** utolsó két sora |

**Valódi-sértés próba (kötelező, §10-ben dokumentálandó):** vedd ki
ideiglenesen a `httpx.TimeoutException` ágat (essen bele az általános
`ProviderError`-ba) → az **A2 timeout-cellájának PIROSNAK kell lennie** →
állítsd vissza, és idézd a nyers kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app
```

A backend-sáv **magától bekapcsol**, mert a kör hozzáér a `backend/`-hez
(ADR 0173): `ruff check`, `ruff format --check` és `pytest` külön
processzként. **Tilos** `| tail`, `| head`, `&&`-lánc vagy bármilyen szűrés
(L09).

> Mért csapda (E04-R15 MAJOR-1): a `ruff check` zöld lehet, miközben a
> `ruff format --check` piros. A gate mindkettőt futtatja — ne csak az
> egyiket nézd.

## 8. Implementációs sorrend

1. **RED először:** `test_openai_provider_gateway.py` — A1 boldog út, A2
   hétsoros hibamátrix, A3 szivárgás-cellák, A4 napló-cellák.
2. `OpenAiProviderGateway` injektálható klienssel, amíg a tesztek zöldek.
3. `requirements.txt` — `httpx` production függőségként.
4. `config.py` — az allowlist/URL bővítése (OD-01, OD-03), az alapértékek
   érintetlenül (A8).
5. Gate (backend-sávval együtt).
6. A §6.1 valódi-sértés próba + visszaállítás.
7. Záró gate + §10 handoff + `done`.

## 9. Kockázatok

1. **Új production függőség** (`httpx`) — kicsi, de valós felület.
2. **Az éles hívás pénzbe kerül.** A kör nem kapcsolja be; a költség-kontroll
   (rate limit, napi token-korlát) éles providerrel **még nincs mérve** —
   nevesített follow-up.
3. **Az OpenAI API változhat.** A szerződést (§2.5) a tesztek fixture-jei
   rögzítik, hogy egy jövőbeli eltérés piros legyen, ne néma.
4. **A bekötés külön kör** — e kör után az adapter létezik, de még nincs
   használatban. Ez szándékos.

## 10. Implementation handoff — a Codex tölti ki

### Codex handoff — 2026-08-09

#### Fájlonkénti összefoglaló

- `backend/app/tutor/provider_gateway.py` — az új `OpenAiProviderGateway`
  injektálható `httpx.AsyncClient`-tel küldi a Chat Completions kérést. A
  kapott modellnevet használja, a meglévő kimeneti bájthatárból származtatja
  a `max_tokens` értékét, timeoutot változtatás nélkül továbbítja, és minden
  transport-, HTTP- és válaszsémahibát redacted `ProviderError` vagy
  `ProviderTimeoutError` kivétellé alakít. A kivételláncok `from None`
  elnyomása tracebackből is kizárja a nyers provider-részleteket. A fake
  gateway érintetlen.
- `backend/app/config.py` — a byte-azonos második tutor settings-blokk
  eltávolítva a §0.0 szerint; a megmaradó blokkban dokumentált OpenAI
  allowlist-bővítési példa és `tutor_openai_base_url` (`https://api.openai.com/v1`)
  szerepel. `tutor_enabled=False` és `tutor_provider="fake"` változatlan.
- `backend/requirements.txt` — production `httpx>=0.27,<0.29`, a dev
  requirements-szel azonos major-pinneléssel.
- `backend/tests/tutor/test_openai_provider_gateway.py` — `MockTransport`
  alapú A1, hétcellás A2/A3, sikeres+hibás A4 és háromértékes A12 tesztek;
  valódi hálózatot nem indít.

#### Futtatott ellenőrzések

```text
$ /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest backend/tests/tutor/test_openai_provider_gateway.py -q
RED: ImportError: cannot import name 'OpenAiProviderGateway' from
     'app.tutor.provider_gateway'

$ /home/ubuntu/music-theory/backend/.venv/bin/python -m pytest backend/tests/tutor/test_openai_provider_gateway.py -q
.............                                                            [100%]

$ /home/ubuntu/music-theory/backend/.venv/bin/python -m ruff format backend/app backend/tests
1 file reformatted, 36 files left unchanged

$ tools/round-gate.sh test/app
format: ZÖLD (1219 fájl, 0 változás)
analyze: ZÖLD (No issues found)
test test/app: ZÖLD (67 teszt)
architecture: ZÖLD
secrets: ZÖLD (2112 fájl, 0 finding)
l10n: ZÖLD (en → hu, 1019 üzenet)
backend ruff format: ZÖLD (37 files already formatted)
backend ruff check: ZÖLD (All checks passed!)
backend pytest: ZÖLD (157 passed)
MINDEN GATE ZÖLD.
```

Az első teljes gate ugyanitt a backend `ruff check` I001 importblokk-rendezési
hibáján állt meg; a kizárólag a saját adapterfájlt érintő automatikus rendezés
után a fenti teljes gate ismétlése zöld lett.

#### Valódi-sértés próba (§6.1)

Ideiglenesen eltávolítottam az `httpx.TimeoutException` külön ágát, ezért a
timeout az általános `ProviderError` ágban végződött. Az A2 timeout-cella nyers
kimenetének döntő része:

```text
______ test_complete_normalizes_failures_without_leaking_details[timeout] ______
E   app.tutor.provider_gateway.ProviderError: Provider request failed
=========================== short test summary info ============================
FAILED backend/tests/tutor/test_openai_provider_gateway.py::test_complete_normalizes_failures_without_leaking_details[timeout]
```

Az `httpx.TimeoutException` → `ProviderTimeoutError` ágát visszaállítottam;
utána a célzott teszt ismét 13/13 zöld.

#### Döntések, mércék és maradékok

- **OD-01:** az alapértelmezett allowlist csak `fake`; a konfigurációs
  megjegyzés dokumentálja az `openai` provider üzemeltetői felvételét, így az
  üres/hiányzó modelllista fail-closed marad.
- **OD-02:** új Settings-mező nélkül a gateway konstruktora a meglévő
  `tutor_max_output_bytes` értékét várja, és azt 4 bájt/token becsléssel
  `max_tokens`-szé alakítja. A következő, bekötő kör ezt a meglévő Settings
  értéket adja át.
- **OD-03:** `tutor_openai_base_url` a dokumentált alapértékkel bekerült.
- **A5/A9/A10 gépi mércék tényleges kimenete:**

  ```text
  $ grep -nE "gpt|o[0-9]|chatgpt" backend/app/tutor/provider_gateway.py
  (nincs találat; grep kilépési kód: 1)

  $ git diff --name-only origin/main...HEAD
  backend/app/config.py
  backend/app/tutor/provider_gateway.py
  backend/requirements.txt
  backend/tests/tutor/test_openai_provider_gateway.py
  ```

  A felsorolásban nincs `backend/app/main.py`, `lib/`, `test/` vagy `tool/`
  útvonal; a handoff dokumentum ekkor még nem volt commitolva.
- **Nem futtatott ellenőrzés:** CI teljes Flutter suite, property gate és
  release APK — ezek az orchestrátor CI-kapujának részei; implementerként nem
  indítottam `gh` workflow-t.
- **Follow-up:** az adapter bekötése a `main.py`-ba, a gateway lifecycle és az
  éles provider költségkorlátainak mérése külön kör feladata.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e99-r07-gov-05b-2-openai-provider-adapter-review.md`
