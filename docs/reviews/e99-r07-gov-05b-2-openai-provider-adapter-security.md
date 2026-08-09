# E99-R07 (GOV-05b-2) biztonsági review — OpenAI provider-adapter a tutor-proxyban

- **Kör:** E99-R07 · branch `codex/e99-r07-gov-05b-2-openai-provider-adapter` · HEAD `d9146e0`
- **Diff:** `f1dacb7..d9146e0` (5 fájl, +351/−25 — `git diff --shortstat origin/main...HEAD`)
- **Reviewer:** `security-reviewer` ágens (READ-ONLY, AGENTS.md §15.1 — kötelező, `risk=high`)
- **Referencia-kontraktus:** `docs/rounds/e99-r07-gov-05b-2-openai-provider-adapter.md`, `docs/adr/0214-openai-provider-adapter.md`, AGENTS.md §5 / §5.1
- **Verifikációs környezet:** friss izolált klón `/tmp/security-review-e99-r07`; httpx **0.28.1** (a pin teteje) telepítve venv-be; a leletek reprodukálhatók az alábbi parancsokkal.
- **Verdikt:** **PASS — nincs CRITICAL, nincs BLOCKER, nincs MAJOR, nincs MINOR.** 4 × NOTE (mind ELŐRE-MUTATÓ / defense-in-depth: az adapter ebben a körben egyetlen éles helyen sincs példányosítva; a boot csak `FakeProviderGateway`-t épít). A biztonsági oldal a merge-et **nem blokkolja.**

## Osztályozás

| Súlyosság | Darab | Blokkol? |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 0 | — |
| NOTE | 4 | nem (a bekötő körre szóló follow-up) |

**Miért nincs MINOR sem:** a fegyelmi szabály szerint csak reprodukálható lelet jelenthető. Az adaptert ez a kör **nem köti be** (`main.py` érintetlen, `tutor_provider="fake"`, `tutor_enabled=False`), így az `OpenAiProviderGateway` production úton **soha nem példányosul**. Minden megfigyelésem ezért vagy (a) bizonyítottan zárt ebben a körben, vagy (b) a KÖVETKEZŐ, bekötő körre szóló előre-mutató NOTE. „Elvileg veszélyes, de nincs éles hívó" = NOTE, nem MINOR.

---

## 1. A kör legkritikusabb állításának FÜGGETLEN, MÉRT megerősítése — nulla titok/prompt-szivárgás mind a 7 hibaágon

Ez a kör kritikus állítása (ADR 0214 Döntés 3, brief §5.3/§5.4): az API-kulcs és a prompt **semmilyen** kivételüzenetben, tracebackben vagy naplószinten nem jelenhet meg. A kör saját tesztje (`test_complete_normalizes_failures_without_leaking_details`, 135–147. sor) **csak a `str(raised.value)`-t** vizsgálja. A reális upstream fenyegetés viszont az, hogy a service-réteg `logging.exception("...")`-t hív, ami a **teljes kivétel-láncot** (`__context__`/`__cause__` + traceback) rendereli. Ezt a kör tesztje nem fedi, ezért **magam mértem meg**, a klónból importált **valódi** `OpenAiProviderGateway` modult hajtva mind a 7 hibaágon, a titkot/promptot/válasz-törzset szándékosan a httpx-rétegbeli kivételbe **beültetve** (worst case), majd a láncot úgy renderelve, ahogy `logging.exception()` tenné (`traceback.format_exception(...)` + valós `logging` handler):

```text
[timeout             ] RAISED ProviderTimeoutError chain={'cause': 'None', 'context': "ReadTimeout('RESPBODY-CANARY-... key=sk-LEAKCANARY-... prompt=USERPROMPT-CANARY-...')", 'suppress_context': True} -> clean
[connect_error       ] RAISED ProviderError   chain={'cause': 'None', 'context': "ConnectError('...key=sk-LEAKCANARY-... prompt=USERPROMPT-CANARY-...')", 'suppress_context': True} -> clean
[http_4xx            ] RAISED ProviderError   chain={'cause': 'None', 'context': 'HTTPStatusError("Client error \'401 ...\' for url \'https://provider.example/v1/chat/completions\'...")', 'suppress_context': True} -> clean
[http_5xx            ] RAISED ProviderError   chain={'cause': 'None', 'context': 'HTTPStatusError("Server error \'500 ...\' for url \'https://provider.example/v1/chat/completions\'...")', 'suppress_context': True} -> clean
[invalid_json        ] RAISED ProviderError   chain={'cause': 'None', 'context': "JSONDecodeError('Expecting value: line 1 column 1 (char 0)')", 'suppress_context': True} -> clean
[missing_content     ] RAISED ProviderError   chain={'cause': 'None', 'context': "KeyError('content')", 'suppress_context': True} -> clean
[non_string_content  ] RAISED ProviderError   chain={'cause': 'None', 'context': 'None', 'suppress_context': False} -> clean
========================================================================
OVERALL: NO LEAK in any of the 7 branches (str, full traceback, and logging.exception)
```

**Amit ez bizonyít:**

1. A hat, `try/except`-en belül dobott ágon a `raise ... from None` **helyesen** `__suppress_context__=True`-t állít (`provider_gateway.py:110` és `:112`). Így bár a titkot hordozó eredeti httpx-kivétel **fizikailag megmarad** `exc.__context__`-ként, azt sem a `traceback` modul, sem a `logging.exception()` **nem rendereli** — a mért kimenet `clean` mindhárom megfigyelési csatornán (`str(exc)`, teljes traceback, valós `logging` handler).
2. A HTTP 4xx/5xx ágon a httpx `raise_for_status()` `HTTPStatusError`-je **eleve nem** tartalmazza a válasz-törzset (csak státusz + URL), és a `response.json()` a 4xx/5xx-nél **le sem fut** (a `raise_for_status()` a `:107` soron előbb dob, a `.json()` a `:108`-on van) — a titkokkal teli hibatörzs sosem kerül változóba.
3. A `non_string_content` ág (`:114–115`) a `try`-on **kívül** dob, ott nincs aktív kivétel-kontextus (`__context__=None`), tehát nincs mit elnyomni — szintén `clean`.

**Statikus megerősítés — a fájlban nincs napló/print/repr sink:**

```text
$ grep -niE "log|print|repr|traceback|\.write|sys\.std" backend/app/tutor/provider_gateway.py
5:leak into logs or responses.                 # docstring
39:...does NOT log messages or API keys...      # FakeProviderGateway docstring
40:tests that verify the no-prompt-log...       # docstring
95:f"{self._base_url}/chat/completions"         # a kimenő URL (base_url, nem titok)
97:"Authorization": f"Bearer {api_key}"         # a kulcs EGYETLEN felhasználása: a kimenő fejléc
```

A modul kizárólag `import httpx`-et használ; **nincs `logging` import, nincs `print`.** Sem a kulcs, sem a prompt nem folyik semmilyen napló/hibaüzenet-felületre. ✔

**Reprodukció:** a modult `importlib`-bel a klónból importálva, mind a 7 hibaágon. A kör saját 13 tesztje szintén zölden fut hálózat nélkül:

```text
$ PYTHONPATH=backend python -m pytest tests/tutor/test_openai_provider_gateway.py -q --noconftest
.............                                                            [100%]
```

## 2. Nincs hard-kódolt modellnév (Property 2) — a kör saját mércéje + egy okosabb ellen-próba

A kör gépi mércéje (A5) reprodukálva:

```text
$ grep -nE "gpt|o[0-9]|chatgpt" backend/app/tutor/provider_gateway.py
$ echo $?
1                                               # 0 találat
```

Mivel a fenti grep **szűk** (egy „claude"/„gemini"/„davinci"/„turbo" alapértéket átengedne), egy tágabb ellen-mérést is futtattam. Az egyetlen találat a `model` **paraméter** használata (`"model": model` a `:101` body-ban, docstringek), **nem** hard-kódolt modellérték:

```text
$ grep -niE "gpt|chatgpt|davinci|turbo|claude|gemini|llama|mistral|text-|babbage|curie|ada|\"model\"" backend/app/tutor/provider_gateway.py
61:        self.calls.append({"messages": messages, "model": model})   # FakeProviderGateway
101:                    "model": model,                                  # a KAPOTT paraméter
```

Modellnév **sehol**, se alapértékként, se fallbackként. ADR 0214 Döntés 2 **teljesül.** ✔

## 3. Ellátási lánc — a `httpx` pin (Property 3)

```text
$ git diff origin/main...HEAD -- backend/requirements.txt
+httpx>=0.27,<0.29
$ grep -rn "httpx" backend/requirements.txt backend/requirements-dev.txt
backend/requirements.txt:14:httpx>=0.27,<0.29
backend/requirements-dev.txt:3:httpx>=0.27,<0.29
```

A production pin **bájtra azonos** a dev pinnel — nincs drift. A tartomány a venv-ben **httpx 0.28.1**-re oldódott fel. Nincs tudomás a 0.27–0.28 tartományt érintő ismert kritikus/magas CVE-ről — ez tudás-kijelentés, nem authoritatív scan; az authoritatív ellátási-lánc-kapu a CI `pip-audit`/`safety` lépése. ✔

## 4. SSRF-felület és `base_url` (Property 4 és 5)

A `complete()` szignatúrája `(messages, model, api_key, timeout_seconds)` — **nincs benne `base_url` vagy URL**. A `base_url` kizárólag a konstruktor-paraméter, forrása a `tutor_openai_base_url` **config-mező** (üzemeltetői env-változó), alapértéke `https://api.openai.com/v1`. **A felhasználói prompt/`messages`, a `model` és az `api_key` egyike sem éri el az URL-t.** **Felhasználói bemenetből fakadó SSRF nincs.** OD-03 kikötése („a kulcs NEM kerülhet URL-be") **mérve teljesül.** ✔

A `base_url` **nincs validálva** (szabad `str`). Ez egy üzemeltető-kontrollált (nem felhasználói) SSRF-felület — lásd NOTE-2.

## 5. Teszt-fegyelem — nulla valós hálózat (Property 6)

```text
$ grep -nE "api\.openai\.com|https?://" backend/tests/tutor/test_openai_provider_gateway.py
19:_BASE_URL = "https://provider.example/v1"
70:        "url": "https://provider.example/v1/chat/completions",
```

`api.openai.com` a tesztfájlban **egyszer sem** fordul elő. Minden hívó `httpx.MockTransport`-ot injektál — **nincs valós socket**. ADR 0214 Döntés 5 **teljesül.** ✔

## 6. Termékhatárok és fixture-valódiság

- **`main.py` érintetlen / nulla Dart-változás / csak az 5 engedélyezett fájl:** `git diff --name-status origin/main...HEAD` → csak `config.py`, `provider_gateway.py`, `requirements.txt`, az új teszt, a brief §10. Nincs `main.py`, nincs `lib/`/`test/`/`tool/`. ✔ (A9/A10)
- **Alapértékek nem billennek:** `tutor_enabled: bool = False`, `tutor_provider: str = "fake"` — változatlan. A §0.0-ban jelzett byte-azonos duplikátum tutor-blokk összevonva — mérve nincs viselkedésváltozás. ✔ (A8)
- **`FakeProviderGateway` érintetlen:** nulla `+`/`-` sor a Fake-osztályon. ✔ (A7)
- **Nincs valódi titok a repóban:** a `dev-tutor-key` config-alapérték fail-closed-védett; a teszt-sentinelek fake-ek. ✔

## 7. AI-provider szemantika (ADR 0131–0136)

- A `messages` strukturált JSON-adatként megy, nincs prompt-string-konkatenáció ebben az adapterben — prompt-injection felületet nem vezet be.
- A provider válasza sima `str`-ként adódik vissza, nem `eval`-ódik, nem ír állapotot.
- Consent-kapu itt nincs, de az adapter nincs bekötve — consent-megkerülés ebben a körben nem jön létre.

---

## NOTE leletek (előre-mutató — a bekötő körre; egyik sem reprodukálható éles hibaként ebben a körben)

### NOTE-1 — A titok fizikailag megmarad `exc.__context__`-ként, csak a renderelése van elnyomva (defense-in-depth)

- **Hely:** `provider_gateway.py:109–112`.
- **Failure scenario:** a standard `logging.exception()`/`traceback` tiszteletben tartja a `__suppress_context__`-ot → mérve `clean` mind a 7 ágon. Egy nem-standard hibariporter (bizonyos Sentry/APM-integrációk) elvben felszínre hozhatná a `__context__`-et — a gyakorlati kockázat kisebb, mint a próba mutatja, mert a valós httpx-kivétel üzenete titok-mentes (a titkot a próba szándékosan ültette be worst-case-ként).
- **Javasolt irány:** a bekötéskor mérjétek meg, hogy a választott hibariporter tiszteletben tartja-e a `__suppress_context__`-ot.

### NOTE-2 — `tutor_openai_base_url` nincs validálva (üzemeltető-kontrollált SSRF-felület a bekötő körre)

- **Hely:** `config.py:65` → `provider_gateway.py:82,95`.
- **Failure scenario:** operátor-hiba (`http://` vagy rossz hoszt) esetén a kulcs+prompt oda folyna. Operátor-config, nem felhasználói bemenet; az adapter itt nincs bekötve.
- **Javasolt irány:** a bekötéskor érdemes `https`-re szűkíteni, esetleg hoszt-allowlist.

### NOTE-3 — Alapból konstruált `httpx.AsyncClient` életciklusa (erőforrás-szivárgás a bekötő körre)

- **Hely:** `provider_gateway.py:81,118–120`.
- **Failure scenario:** ha a bekötő kör kliens-injektálás/`aclose()` nélkül, per-request példányosítaná, socketek szivárognának.
- **Javasolt irány:** app-élettartamú, injektált kliens, vagy `aclose()` a FastAPI lifespan-be kötve.

### NOTE-4 — A válasz-törzs mérete nincs korlátozva (memória-DoS a bekötő körre, alacsony súlyú)

- **Hely:** `provider_gateway.py:108`. A `max_tokens` a kérést korlátozza, nem a fogadott választ.
- **Javasolt irány:** válasz-méret-korlát vagy stream+limit olvasás megfontolása a bekötéskor.

---

## Amit végignéztem és a bizonyíték (üres-lelet-fegyelem)

| Ellenőrzés | Módszer | Eredmény |
|---|---|---|
| Titok/prompt szivárgás mind a 7 hibaágon | valódi modul importálva, worst-case beültetett titok, `str` + teljes traceback + `logging.exception()` renderelés | **0 szivárgás** (§1) |
| `from None` context-elnyomás | `__suppress_context__` mérve mind a 7 ágon | 6/6 in-except ágon `True`, a 7. kontextus-mentes (§1) |
| Napló/print/repr sink a modulban | grep + string-literál felsorolás | **nincs** sink; csak `import httpx` (§1) |
| Hard-kódolt modellnév | kör-grep (A5) + tágabb ellen-grep | 0 találat; csak a `model` paraméter (§2) |
| `httpx` pin / drift / CVE | requirements diff + dev-pin összevetés + venv-resolve | prod==dev, 0.28.1, nincs ismert kritikus CVE (§3) |
| SSRF felhasználói bemenetből | `complete()` szignatúra + URL-építés követése | **nincs** (§4) |
| Teszt valós hálózat | `api.openai.com` grep + MockTransport-ellenőrzés | 0 valós hálózat (§5) |
| Termékhatárok (main.py, Dart, alapértékek, Fake, duplikátum) | name-status + config grep + Fake-diff | mind tartva (§6) |
| Valódi titok a diffben | kulcs-minta grep + fail-closed boot-elemzés | 0 valódi titok (§6) |
| Prompt-injection / provider-válasz hatása | adatfolyam-követés | adapter nem vezet be felületet (§7) |
| Kör saját 13 tesztje | `pytest --noconftest` a klónban | 13/13 zöld, hálózat nélkül (§1) |

**Következtetés:** a kör mind a hat kötött ADR-döntést és mind a 7 megnevezett biztonsági invariánst **mérve** teljesíti; a titok-nem-szivárgás állítást a kör saját tesztjén túl, teljes-traceback + `logging.exception()` szinten is igazoltam. Nincs CRITICAL/BLOCKER/MAJOR/MINOR. A 4 NOTE kizárólag a KÖVETKEZŐ, bekötő körre szóló előre-mutató teendő. **Biztonsági verdikt: PASS — a merge nem blokkolt biztonsági okból.**
