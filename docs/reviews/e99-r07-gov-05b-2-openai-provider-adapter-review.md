# E99-R07 (GOV-05b-2) — Review

Brief: `docs/rounds/e99-r07-gov-05b-2-openai-provider-adapter.md`
ADR: `docs/adr/0214-openai-provider-adapter.md`
Diff: `git diff origin/main...codex/e99-r07-gov-05b-2-openai-provider-adapter`
(base `f1dacb7`, head `d9146e0`)
Reviewer: Claude (Opus 5, orchestrátor) · Dátum: 2026-08-09
Implementer: Terra (`gpt-5.6-terra`), 1 forduló, javító kör nélkül, 0 automatikus folytatás
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

Öt fájl változott, pontosan az `allowed_paths` listája (0 sértés). A gate-et
**saját kézzel, izolált `/tmp/review-e99-r07` klónban** újrafuttattam —
mind a 9 lépés zöld. A §6.1 valódi-sértés próbát **saját kézzel, egy
MÁSODIK izolált klónban (`/tmp/mutation-e99-r07`) kétszer** megismételtem
(a brief előírt mutációja + egy saját, kulcs-szivárgásra célzó mutáció) —
mindkettő a várt módon buktatta meg a megfelelő teszt-cellát, majd zöldre
állt vissza.

**Dedikált security-review (risk=high) KÉSZ:**
[`docs/reviews/e99-r07-gov-05b-2-openai-provider-adapter-security.md`](e99-r07-gov-05b-2-openai-provider-adapter-security.md)
— **PASS, 0 CRITICAL/BLOCKER/MAJOR/MINOR, 4 NOTE** (mind a KÖVETKEZŐ, bekötő
körre szóló előre-mutató follow-up: `exc.__context__` defense-in-depth,
`tutor_openai_base_url` validáció, `AsyncClient` lifecycle, válasz-méret
korlát — egyik sem reprodukálható éles hiba ebben a körben, mert az adapter
ma sehol nincs példányosítva). A security-reviewer a kör saját `str(exc)`
tesztjén TÚLMENVE a teljes traceback + valós `logging.exception()` szintjén
is megmérte mind a 7 hibaágat szándékosan beültetett titokkal — 7/7 tiszta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Boldog út — pontos request/response alak | ✅ | `test_complete_posts_configured_model_and_messages` — saját olvasással ellenőrizve: `POST .../chat/completions`, `Authorization: Bearer sk-SENTINEL-KEY`, body `{model: "configured-model", messages: [...], max_tokens: 500}` pontosan a kapott értékekkel |
| A2 | 7-soros hibamátrix | ✅ | `test_complete_normalizes_failures_without_leaking_details` 7 paraméterezett esettel (`timeout`, `http_4xx`, `http_5xx`, `connect_error`, `invalid_json`, `missing_content`, `non_string_content`); a `timeout` ágat **saját kézzel kimutáltam** (`/tmp/mutation-e99-r07`, `httpx.TimeoutException` ág törölve) → a cella pirosra fordult (`ProviderError` jött `ProviderTimeoutError` helyett), visszaállítás után zöld |
| A3 | Nincs szivárgás a kivételüzenetben | ✅ | Ugyanaz a teszt mind a 7 ágra ellenőrzi (kulcs/host/„openai"/sentinel-body nem szerepel); **saját kézzel** egy MÁSODIK mutációt is futtattam — az `api_key`-t belefűztem az egyik `ProviderError` üzenetbe → 5/7 cella azonnal pirosra váltott, a hibaüzenet szó szerint idézte a szivárgó kulcsot (`AssertionError: assert 'sk-sentinel-key' not in ...`); visszaállítás után 13/13 zöld |
| A4 | Prompt/kulcs sosem naplózódik | ✅ | `test_complete_never_logs_prompt_or_api_key`, 2 eset (siker + hiba); az `OpenAiProviderGateway` osztály forráskódjában **nincs egyetlen logolás-hívás sem** — saját olvasással megerősítve |
| A5 | Nincs hard-kódolt modellnév | ✅ | Saját futtatás: `grep -nE "gpt\|o[0-9]\|chatgpt" backend/app/tutor/provider_gateway.py` → 0 találat (grep exit 1) |
| A6 | Nincs hálózat a tesztekben | ✅ | Saját futtatás: `grep -c "api.openai.com" backend/tests/tutor/test_openai_provider_gateway.py` → **0** (a teszt egy fiktív `provider.example` base_url-t injektál); a fájlban egyetlen `httpx.AsyncClient(` konstrukció van, `transport=httpx.MockTransport(handler)`-rel |
| A7 | `FakeProviderGateway` diffje üres | ✅ | Saját `git diff origin/main...HEAD -- backend/app/tutor/provider_gateway.py` — a `FakeProviderGateway` osztály teste karakterre változatlan, a diff kizárólag utána ÉPÍT (`OpenAiProviderGateway` új osztály) |
| A8 | Az éles provider default-ja változatlan | ✅ | Saját olvasással: a megmaradt (egyetlen) `tutor_*` blokkban `tutor_enabled: bool = False` / `tutor_provider: str = "fake"` sor változatlan. (A diff MUTATJA a duplikátum-blokk törlését — ez a §0.0 pre-flight revízió szerint elvárt, nem A8-sértés, lásd lent) |
| A9 | `main.py` érintetlen | ✅ | Saját futtatás: `git diff --name-only origin/main...HEAD \| grep 'backend/app/main.py'` → nincs találat |
| A10 | Nulla Dart-változás | ✅ | Saját futtatás: `git diff --name-only origin/main...HEAD \| grep -E '^(lib\|test\|tool)/'` → nincs találat |
| A11 | A gate zöld (backend-sávval) | ✅ | **Saját, izolált `/tmp/review-e99-r07` klónban újrafuttatva**: mind a 9 lépés (format, analyze, test/app, architecture, secrets, l10n, backend ruff format, backend ruff check, backend pytest 157 teszt) ZÖLD |
| A12 | `timeout_seconds` változatlanul terjed | ✅ | `test_complete_passes_timeout_to_http_client`, 3 különböző érték (`0.5`, `5.0`, `30.0`), a `httpx.Request.extensions["timeout"]` tényleges belső mezőit ellenőrzi — nem csak a Python-hívás argumentumát, hanem a transzport-rétegbe ténylegesen eljutott értéket |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. A diff pontosan öt fájl,
mind az `allowed_paths` listáján:

```
backend/app/config.py
backend/app/tutor/provider_gateway.py
backend/requirements.txt
backend/tests/tutor/test_openai_provider_gateway.py
docs/rounds/e99-r07-gov-05b-2-openai-provider-adapter.md
```

A `.codex-round-status` gépi scope-audit mezője is megerősíti:
`scope_audit=ok`, `scope_audit_changed=5`, `scope_audit_base=f1dacb70…`.

## Megállapítások

Nincs nyitott BLOCKER/MAJOR/MINOR. Két NOTE:

### N1 — NOTE — a `max_tokens` byte→token becslés durva

- **Fájl:** `backend/app/tutor/provider_gateway.py:11,83`
- **Megfigyelés:** `_BYTES_PER_TOKEN_ESTIMATE = 4` egy fix, dokumentálatlan
  arányból számolja a `max_tokens`-t a meglévő `tutor_max_output_bytes`-ból
  (OD-02 „meglévő korlátból származtatva" ága). Ez egy elfogadható, névvel
  ellátott közelítés angol szövegre, de nem méri az adott modell tényleges
  tokenizálását.
- **Hatás:** ma nincs — a gateway nincs bekötve (OD-04, `stopped`-tal védett
  tiltás), tehát ez a kör NEM élesíti ezt a számítást. A bekötő kör
  (HANDOFF §3 „hátra van") pontosítsa vagy dokumentálja tudatos döntésként.
- **Kötelező javítás:** nincs, ebben a körben nem blokkoló — follow-up a
  bekötő körnek.

### N2 — NOTE — a duplikátum-törlés a §0.0 alapján, dokumentálva

- **Fájl:** `backend/app/config.py`
- **Megfigyelés:** a diff egy 13 soros, korábban (E04-R14, `c1c0a771`) a
  `config.py`-ba véletlenül kétszer bekerült `tutor_*` blokk MÁSODIK
  (ténylegesen érvényes, mert Python osztálytörzsben a második definíció
  felülír) példányát törli, majd az OD-01/OD-03 bővítést az egyetlen
  megmaradó blokkba írja. Ez a pre-flight `§0.0` revízióm alapján
  SZÁNDÉKOS és SZÜKSÉGES volt — enélkül az OpenAI allowlist-bejegyzés
  némán hatástalan maradt volna (a második, korábban érvényes blokk
  felülírta volna). A törlés bizonyítottan nem változtat viselkedést: a
  két blokk byte-azonos volt.
- **Hatás:** pozitív — egy rejtett csapdát szüntet meg. Nem blokkoló,
  csak dokumentálom, hogy a review ezt tudatosan, nem véletlenül találta
  helyesnek.
- **Kötelező javítás:** nincs.

## Architektúra és termékhatárok (AGENTS.md §5/§6/§8)

- **Üres `catch` tilalma:** nincs — minden `except` ág egy ÚJ, típusos
  kivételt dob (`ProviderError`/`ProviderTimeoutError`), sosem nyel el
  csendben (`from None` csak a lánc-linket törli, nem az újradobást).
- **Secret sosem logba/commitba:** nincs logolás a `OpenAiProviderGateway`
  osztályban egyáltalán; a `sk-SENTINEL-KEY` teszt-szentinel egyszer sem
  szerepel a valódi kódban.
- **Route vékony, service tesztelhető (§8):** ez a kör nem route-ot ír; az
  adapter önmagában, DI-vel (`client`/`base_url` konstruktor-paraméter)
  tesztelhető `main.py` nélkül — igazolva, hogy az OD-04 „stopped, ha
  main.py kellene" döntés valóban tartható volt.
- **Nincs rejtett `create_all`, nincs insecure production-default:** a kör
  nem érinti a boot-ot; `tutor_enabled`/`tutor_provider` alapértéke
  változatlan (A8).
- **Nincs cross-module szivárgás:** az új osztály kizárólag a
  `provider_gateway.py` fájlon belül él, nem importál `service.py`/
  `router.py`/`stream.py`/`redaction.py`/`usage.py`-t.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futtatás, izolált klón |
| analyze | zöld (No issues found) | ✅ saját futtatás |
| test test/app | zöld (67 teszt) | ✅ saját futtatás |
| architecture | zöld (12 allowlistelt eltérés, változatlan) | ✅ saját futtatás |
| secrets | zöld (2112 fájl, 0 lelet) | ✅ saját futtatás |
| l10n | zöld (1019 üzenet) | ✅ saját futtatás |
| backend ruff format | zöld (37 fájl) | ✅ saját futtatás |
| backend ruff check | zöld | ✅ saját futtatás |
| backend pytest | zöld (157 teszt) | ✅ saját futtatás |
| CI — Backend CI | success | ✅ [31330073314](https://github.com/wolfcasaba/strumsight/actions/runs/31330073314) |
| CI — Router CI | success | ✅ [31330073316](https://github.com/wolfcasaba/strumsight/actions/runs/31330073316) |
| CI — Full Gate (no APK) | success (Coverage 11m32s + full-gate 6m52s) | ✅ [31330077422](https://github.com/wolfcasaba/strumsight/actions/runs/31330077422) |

A jelentett `gate_shape=VIOLATION` jelzőt kivizsgáltam: a Terra-log
`sed -n '1,280p' tools/round-gate.sh && git status --short` sorát találta
meg a mintaillesztés (a SCRIPT FÁJL tartalmának olvasása `sed`-del, nem a
gate tényleges, csővezeték nélküli futtatása) — **hamis pozitív**, a tényleges
`tools/round-gate.sh test/app` hívások (a logban 4 helyen) mind önálló,
csővezeték/lánc nélküli futtatások.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Full Gate CI zöld, Router CI zöld, Backend CI zöld, security-review PASS,
scope-audit tiszta, mind a 12 acceptance criteria bizonyítékkal teljesül —
**a merge feltételei teljesülnek, külön jóváhagyás nélkül.**

Ez a review-jelentés és a security-jelentés ÚJ commitként kerül a branchre
(dokumentáció-only, gate-releváns fájlt nem érint) — az AGENTS.md exact-SHA
szabálya miatt a Full Gate/Router CI-t **erre az új tipre újra
dispatch-elem**, mielőtt a squash-merge megtörténik.
