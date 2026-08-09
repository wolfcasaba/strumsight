# E99-R06 (GOV-05b-1) — kör-review

- **Dátum:** 2026-08-09
- **Reviewer:** Claude (Opus 5), orchesztrátor — READ-ONLY review
- **Implementer:** Codex (Terra, `gpt-5.6-terra`) — 1 `blocked` (környezeti,
  az orchesztrátor hibája) + 1 implementációs forduló
- **Branch:** `codex/e99-r06-gov-05b-1-tutor-production-wiring`
- **Diff:** `cb7d4cd9...6923e121` — 7 fájl, +445 / −9
- **Verdikt:** ✅ **APPROVED** — 0 BLOCKER, 0 MAJOR, 1 MINOR (a brief hibája),
  2 NOTE

## 1. Scope-audit

A diff **pontosan** a nyolc engedélyezett útvonalból hetet érint (a
`feature_flags_test.dart` nem kellett — lásd MINOR-1). Nulla listán kívüli
fájl. A wrapper `scope_audit=ok`-ot jelzett, `scope_audit_changed=7`.

```
docs/rounds/e99-r06-...-tutor-production-wiring.md                |  57 ++++
lib/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart | 135 +++++
lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart |   6 +
lib/features/ai_tutor/presentation/providers/tutor_providers.dart         |  42 ++-
lib/main.dart                                                             |  34 ++
test/features/ai_tutor/data/http_tutor_stream_transport_test.dart         | 127 ++++
test/features/ai_tutor/presentation/tutor_production_wiring_test.dart     |  53 ++
```

**Az első forduló `blocked` jelzése helyes volt** („flutter is not available
on PATH"), és **az orchesztrátor hibáját** fogta meg: a kézi indítás nem
örökölte a cron PATH-ját. Az implementer nem próbálta megkerülni.

## 2. A három kötött tiltás — külön ellenőrizve

| Tiltás | Ellenőrzés | Eredmény |
|---|---|---|
| A flag nem kapcsol be | `git diff --name-only \| grep -E "feature_flags.dart\|/l10n/\|app/routing/\|screens\|widgets"` | **üres** ✅ |
| A fake gateway nincs bedrótozva | `grep -rn "FakeTutorModelGateway" lib/ \| grep -v fake_tutor_model_gateway.dart` | **nincs találat** ✅ |
| A transport nem értelmez protokollt | a `http_tutor_stream_transport.dart` doc-commentje és törzse: „only removes the SSE envelope"; nincs `jsonDecode` a frame-payloadon | ✅ |

A production orchestrator átjárója (`tutor_providers.dart:350`):
`gatewayForAttempt: (_) => LocalTutorModelGatewayStub()` — a kötött döntés
szerint.

## 3. A reviewer SAJÁT mérései (izolált `/tmp/review-E99-R06` klón)

### 3.1 Valódi-sértés próba

A `gatewayForAttempt`-et ideiglenesen `throw UnimplementedError('probe')`-ra
írtam:

```
00:00 +0 -1: production overrides construct all Tutor dependencies with the stub gateway [E]
  UnimplementedError: probe
  ...tutor_providers.dart 350:29  createProductionTutorOrchestrator.<fn>
```

**A wiring-teszt PIROS lett** — a mérce mér. Visszaállítva.

### 3.2 Független gate-újrafuttatás

```
tools/round-gate.sh test/features/ai_tutor test/app test/core
```

**Mind a 8 lépés ZÖLD:** format, analyze, három tesztútvonal, architecture,
secrets, l10n (en → hu, 1019 üzenet).

### 3.3 Szerződés-ellenőrzés a backend ellen (amit a mockolt teszt NEM foghat meg)

A transport kérés-törzse:
`{request_id, sequence, conversation_id, message}` az `/tutor/stream`-re.
A backend `TutorStreamRequest` (`backend/app/tutor/stream.py:68–84`,
`extra="forbid"`): `message`, `history=[]`, `context=""`,
`request_id`, `sequence`, `conversation_id`.

**Illeszkedik:** minden kötelező mező megvan, a két opcionálisnak van
alapértéke, és nincs extra mező, ami az `extra="forbid"`-ba ütközne. ✅

## 4. Acceptance-teljesülés

| Pont | Verdikt | Bizonyíték |
|---|---|---|
| A1 a három provider nem dob | ✅ | wiring-teszt; a 3.1 próba pirosra váltotta |
| A2 a `main.dart` mindhármat átadja | ✅ | `buildTutorProductionOverrides` kiemelve tesztelhető függvénybe — pontosan a brief által kért út |
| A3 a stub az alapértelmezés, nem a fake | ✅ | `tutor_providers.dart:350` + a 2. szakasz grepje |
| A4 nyers `data:` payload | ✅ | transport-teszt |
| A5 hibák kontrolláltak | ✅ | `AppResult.failure` minden ágon, `DioException` és általános `Object` catch is; nincs csendes no-op |
| A6 flagek nem mozdultak | ✅ | a diff nem érinti a `feature_flags.dart`-ot |
| A7 nincs UI/route/ARB | ✅ | a 2. szakasz grepje |
| A8 `tutorMain` eltűnt | ✅ | `grep -rn "tutorMain" lib/` → 0 |
| A9 gate zöld | ✅ | 3.2, a reviewer saját futása |

## 5. Leletek

### MINOR-1 — a brief A3 gépi mércéje kivihetetlen volt (orchesztrátor-hiba)

A brief azt írta: `grep -c "FakeTutorModelGateway" lib/` → **0**. Ez
**teljesíthetetlen**: az osztály maga a `lib/features/ai_tutor/data/
model_gateway/fake_tutor_model_gateway.dart`-ban él, tehát a név
szükségszerűen szerepel a `lib/` fában (2 találat a saját fájljában).

A helyes mérce — amit a review futtatott — a **saját definíciós fájlján
kívüli** hivatkozás hiánya. Az implementáció ezt teljesíti.

Ugyanaz a hibaosztály, mint a GOV-05a MINOR-1 (hiányos `gate_tests`): a
brief gépi mércéjét **le kell futtatni a brief írásakor**, nem csak leírni.
Tanulság rögzítendő.

A brief `feature_flags_test.dart` bejegyzése emiatt (és mert az A6 a
diff-üresség mérésével teljesül) érintetlen maradt — ez **nem** scope-sértés,
csak fölöslegesen tág lista volt.

### NOTE-1 — a `/tutor/stream` HITELESÍTÉST kér; a transport ma nem küld tokent

A végpont szignatúrája `current_user: CurrentUser` (`stream.py:218`), tehát
JWT-t vár. A `HttpTutorStreamTransport` a kapott `Dio` példányt használja —
ha az nem hordoz auth-interceptort, minden hívás 401 lesz.

**Ma nem blokkoló:** a transport nincs bedrótozva (az orchestrator a stubot
kapja), tehát production úton nem hívódik. **A KÖVETKEZŐ kör**, amelyik a
`RemoteTutorModelGateway`-t élesíti, köteles authentikált `Dio`-t átadni —
ezt a bekötő kör briefjének acceptance-pontként kell tartalmaznia.

### NOTE-2 — a knowledge-index betöltése boot-időben, aszinkron

A `buildTutorProductionOverrides` `await`-el asset-indexet tölt a boot alatt.
A doc-comment szerint hiba esetén naplózott üres indexre esik vissza, tehát a
boot nem hasal el (OD-01 szerint) — ez helyes. Érdemes lesz mérni, hogy a
betöltés mennyivel tolja a hidegindítást, ha a Tutor flag egyszer bekapcsol.

## 6. Merge-döntés

Minden acceptance teljesül, a scope sértetlen, a mérce próbán bizonyítottan
mér, a gate a reviewer saját izolált klónjában is zöld, és a
kliens–backend szerződés kézzel összevetve illeszkedik.
**A merge a zöld CI-kapu mellett engedélyezett.**
