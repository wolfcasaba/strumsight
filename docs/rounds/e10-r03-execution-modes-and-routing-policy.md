# E10-R03 — Végrehajtási módok, consent és routing policy domain

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 3
- **Kör-azonosító:** `E10-R03`
- **Branch:** `<motor>/e10-r03-execution-modes-and-routing-policy`
- **Előfeltétel:** `E10-R02` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0421` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva — ellenőrizd a `reserve-adr` foglalóval).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 2 TÉNYLEGES `LocalAiMode`/`LocalAiAvailability` mezőit és a `lib/app/config/feature_flags.dart` Kör 1-ben hozzáadott flageit — a routing bemenete ezekre épül. Eltérésnél §0.0 brief-revízió.

## 0.0 Pre-flight kiegészítés

**Miért ez a kör a legfontosabb biztonsági invariáns az egész epicben.** A SDD §2.3/§14.1 kimondja: local-only módban a rendszer SOHA nem küldhet promptot cloudnak. Ez a kör az EGYETLEN hely, ahol ez a szabály KÓDBAN, nem csak dokumentumban létezik — minden későbbi kör (24, routing integráció) erre a policy-ra épít, nem írja újra.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "routing policy local only never cloud fallback privacy"` → nincs közvetlenül alkalmazható korábbi StrumSight-lecke erre a PONTOS mintára (a Chapter 5 `TutorModelGateway` MA egyetlen implementációt köt be egyszerre, routing nélkül) — ez a kör az ELSŐ explicit routing-policy réteg a projektben, ezért a §5 kötött döntése nem egy meglévő mintát véd, hanem egy ÚJAT vezet be.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/offline_ai/domain/tutor_execution_policy.dart",
  "lib/features/offline_ai/domain/local_ai_consent.dart",
  "lib/features/offline_ai/application/tutor_gateway_router.dart",
  "test/features/offline_ai/domain/tutor_execution_policy_test.dart",
  "test/features/offline_ai/application/tutor_gateway_router_property_test.dart",
  "docs/rounds/e10-r03-execution-modes-and-routing-policy.md",
]
gate_tests = [
  "test/features/offline_ai/application/tutor_gateway_router_property_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** egyik `allowed_paths` sem egyezik szó szerint a router `high_risk_path_fragments` listájával, de a kör kimenete egy PRIVACY-kritikus routing döntés — helytelen implementáció esetén a felhasználó tudta nélkül hagyná el a prompt az eszközt local-only módban. A kockázati profil megegyezik a `privacy` kategóriáéval.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Explicit, tesztelhető, magyarázható routing-döntés a local/cloud/deterministic módok között — local-only esetben MATEMATIKAILAG (property teszttel) bizonyítva, hogy a döntés soha nem cloud.

## 2. Jelenlegi állapot — mért tények

- A Kör 2 (E10-R02) létrehozta a `LocalAiMode` (`deterministicOnly`, `localPreferred`, `localOnly`, `cloudPreferred`, `cloudOnly`) és `LocalAiAvailability` enumokat — ez a kör ezekre épít.
- A `TutorModelGateway` MA egyetlen implementációt fogad be közvetlenül (`LocalTutorModelGatewayStub`, bekötve `tutor_providers.dart:350`-ben) — routing réteg MA NINCS a projektben; ez az ELSŐ.
- A Kör 1 (E10-R01) `localAiFeatureEnabled` és hét alkapcsolója MÁR létezik — a routing bemenete ezeket olvassa, de a feature flag maga NEM helyettesíti a felhasználói mód-választást (a flag épületszintű kapu, a `LocalAiMode` felhasználói döntés).

## 3. Scope

**Benne van:** `TutorExecutionPolicy` és `TutorGatewayRoute` domain modellek · a helyi/cloud/deterministic consent külön kezelése · routing tábla bemenete: user mode, network state, cloud consent, local availability, resource state, safety policy, feature flag · magyarázható reason code minden döntéshez · property teszt, ami MINDEN állapotkombinációban bizonyítja, hogy `localOnly` sosem választ cloudot.

**NINCS benne (tilos):**

- A tényleges `TutorModelGateway` implementáció bekötése (ez Kör 23/24 dolga) — ez a kör CSAK a döntési logikát szállítja, hívó nélkül.
- A `LocalTutorModelGatewayStub` vagy a `tutor_providers.dart` módosítása.
- `docs/adr/**` — az ADR 0421-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/offline_ai/domain/tutor_execution_policy.dart` | ÚJ — a policy döntés-modell |
| `lib/features/offline_ai/domain/local_ai_consent.dart` | ÚJ — a három külön consent típus |
| `lib/features/offline_ai/application/tutor_gateway_router.dart` | ÚJ — a router logika |
| `test/features/offline_ai/domain/tutor_execution_policy_test.dart` | a §6 truth-table cellái |
| `test/features/offline_ai/application/tutor_gateway_router_property_test.dart` | a §6 property cellája |

**Tilos zóna:** `lib/features/ai_tutor/**` · `lib/features/offline_ai/data/**`, `presentation/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0421)

### 5.1 `localOnly` mód SOHA nem produkálhat cloud route-ot — bármilyen bemeneti kombináció mellett

A routing tábla explicit felsorolja mind az öt `LocalAiMode` viselkedését hibaállapotokra (local unavailable, consent missing, network offline, kill switch, safety policy blokk) is. `localOnly` módban MINDEN hibaágnak `deterministicOnly` route-ra kell futnia, cloud route SOHA.

**NEM elfogadható gyengítés:** egy "vészhelyzeti" ág, ami `localOnly` alatt is cloudra váltana, ha a helyi modell "túl sokszor" hibázik — ez pontosan az a csendes mód-váltás, amit a SDD §2.3 kizár.

### 5.2 A route eredménye mindig hordoz magyarázható reason code-ot

Egyetlen route-döntés sem lehet "silent" — minden `TutorGatewayRoute` egy explicit, enumerált `RouteReason`-t hordoz (pl. `localOnlyForced`, `cloudConsentMissing`, `networkOffline`, `killSwitchActive`, `localUnavailable`).

**NEM elfogadható gyengítés:** egy generic `RouteReason.other` vagy `RouteReason.unknown` érték bármely elágazásnál "amíg nincs jobb kategória" — minden elágazásnak SAJÁT, névvel azonosítható reason kell.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | `localOnly` minden bemeneti kombinációban `deterministicOnly` vagy helyi route-ot ad, sosem cloudot | `tutor_gateway_router_property_test.dart` |
| A2 | `localPreferred` local hiba esetén deterministic fallbacket ad, NEM cloudot | `tutor_execution_policy_test.dart` |
| A3 | `cloudPreferred` hálózat nélkül local/deterministic route-ra vált | `tutor_execution_policy_test.dart` |
| A4 | Cloud consent hiányában `cloudPreferred`/`cloudOnly` sosem ad cloud route-ot | `tutor_execution_policy_test.dart` |
| A5 | Kill switch (`localAiRuntimeEnabled=false`) esetén helyi route sosem választható | `tutor_execution_policy_test.dart` |
| A6 | Minden route explicit, névvel azonosított `RouteReason`-t hordoz | `tutor_execution_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| `localOnly` egy ismétlődő local hiba után "vészhelyzeti" cloud route-ra vált | A1 (a property teszt véletlenszerű bemenetekkel ezt megtalálja) |
| `localPreferred` local hiba esetén közvetlenül cloudra vált fallback helyett | A2 |
| `cloudPreferred` offline állapotban is cloud route-ot ad | A3 |
| A consent-ellenőrzés csak `cloudOnly`-nál fut, `cloudPreferred`-nél nem | A4 |
| A kill switch csak a UI-t tiltja, a router logika figyelmen kívül hagyja | A5 |
| Egy elágazás `RouteReason.other`-t ad kategória helyett | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** adj hozzá egy ágat, ami `localOnly` módban három egymást követő local hiba után `cloudPreferred`-ként viselkedik, futtasd a property tesztet → az **A1** cellának PIROSNAK kell lennie (a property teszt megtalálja az ellenpéldát) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/domain/tutor_execution_policy_test.dart test/features/offline_ai/application/tutor_gateway_router_property_test.dart
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. `LocalAiConsent` (cloud AI consent, local model consent, diagnostics consent — három külön típus).
2. `TutorExecutionPolicy`, `RouteReason` enum.
3. `TutorGatewayRoute` (a döntés eredménye: melyik gateway-osztály + reason).
4. `tutor_gateway_router.dart` — a routing tábla implementációja mind az öt `LocalAiMode`-ra.
5. Truth-table unit teszt minden elágazásra.
6. Property teszt: több ezer random bemeneti kombináció, `localOnly` invariáns.
7. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A "vészhelyzeti" cloud-fallback kísértése.** Egy jóhiszemű, "jobb felhasználói élményért" hozott kivétel `localOnly` alatt pontosan a §2.3 SDD-invariáns megsértése lenne (A1).
- **A property teszt gyenge bemenet-tere.** Ha a random generátor nem fedi le a ritka kombinációkat (pl. consent visszavonás routing közben), a hiba csak élesben derülne ki — a generátornak explicit fedni kell minden `LocalAiMode` × hiba-kombinációt legalább egyszer, determinisztikus seeddel.
- **A reason code túl általánossá válása.** Ha a router idővel `RouteReason.other`-t kezd használni új elágazásokhoz, a UI (Kör 24) nem tudna magyarázható üzenetet adni.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
