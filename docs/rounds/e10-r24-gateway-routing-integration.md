# E10-R24 — Deterministic, local és cloud gateway routing integráció

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 24
- **Kör-azonosító:** `E10-R24`
- **Branch:** `<motor>/e10-r24-gateway-routing-integration`
- **Előfeltétel:** `E10-R23` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0438` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 3 `TutorGatewayRouter` és a Kör 23 `LocalTutorModelGateway` TÉNYLEGES kimeneti típusait — ez a kör köti össze őket a `RemoteTutorModelGateway`-jel (MEGLÉVŐ, Chapter 5). Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "routing policy local only never cloud fallback privacy"` (a Kör 3-ban lefuttatva) → nincs közvetlenül alkalmazható korábbi StrumSight-lecke erre a mintára — ez az ELSŐ két-gateway routing-integráció a projektben, lásd Kör 3 §0.0.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/application/routed_tutor_model_gateway.dart",
  "lib/features/ai_tutor/presentation/widgets/execution_origin_badge.dart",
  "test/features/ai_tutor/application/routed_gateway_integration_test.dart",
  "docs/rounds/e10-r24-gateway-routing-integration.md",
]
gate_tests = [
  "test/features/ai_tutor/application/routed_gateway_integration_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** ez a kör köti véglegesen egybe a Kör 3 privacy-kritikus routing-policy-t a TÉNYLEGES gateway-ekkel — egy integrációs hiba (pl. a route figyelmen kívül hagyása) itt VALÓS cloud-hívást indíthatna local-only módban, még ha a Kör 3 önmagában helyesen tesztelt is.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A tutor egyetlen orchestratorból válasszon gateway-t (local/cloud/deterministic), látható execution-mode-dal és kontrollált fallbackkel — a Kör 3 policy-ját TÉNYLEGESEN alkalmazva, nem csak elméletben.

## 2. Jelenlegi állapot — mért tények

- A `RemoteTutorModelGateway` (Chapter 5, MEGLÉVŐ) a cloud-oldali implementáció.
- A Kör 23 `LocalTutorModelGateway` az imént készült el.
- A Kör 3 `TutorGatewayRouter`/`TutorExecutionPolicy` a döntési logika — ez a kör az ELSŐ hely, ahol ez a logika TÉNYLEGESEN két valódi gateway közül választ (a Kör 3-ban még hívó nélkül, tisztán logikailag volt tesztelve).
- Az `ActionConfirmationService`/UI-oldalon MA nincs "execution origin" jelző widget — ez teljesen ÚJ.

## 3. Scope

**Benne van:** a Kör 3 route-policy integrálása a conversation controllerbe · minden assistant message metaadatában látható local/cloud/deterministic origin jelzés, hozzáférhető módon · local runtime hiba esetén `localOnly`/`localPreferred` deterministic fallback · `cloudPreferred` offline állapotban local/deterministic váltás policy szerint · cloud fallback ELŐTT consent-ellenőrzés és explicit jelzés, hogy a kérés elhagyná az eszközt · nincs automatikus, felhasználó tudta nélküli többszöri próbálkozás több modellen · routing integrációs teszt hálózati interceptorral.

**NINCS benne (tilos):**

- A Kör 3 routing-logika módosítása — ez a kör csak BEKÖTI.
- `docs/adr/**` — az ADR 0438-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/ai_tutor/application/routed_tutor_model_gateway.dart` | ÚJ — a route-alapú gateway-választó, MAGA implementálja `TutorModelGateway`-t |
| `lib/features/ai_tutor/presentation/widgets/execution_origin_badge.dart` | ÚJ — a UI-jelző |
| `test/features/ai_tutor/application/routed_gateway_integration_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/features/offline_ai/domain/tutor_execution_policy.dart`, `application/tutor_gateway_router.dart` (Kör 3, csak HÍVJA) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0438)

### 5.1 Nincs csendes cloud fallback — a route-váltás mindig látható és a Kör 3 policy-jából ered

**NEM elfogadható gyengítés:** egy "robusztussági" réteg, ami local hiba esetén AUTOMATIKUSAN cloud-ra próbálkozik anélkül, hogy a `TutorGatewayRouter`-en át menne — MINDEN route-döntésnek a Kör 3 policy-ján KELL átfolynia, kivétel nincs.

### 5.2 A local hiba nem törheti el a teljes tutor-funkciót

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Local success esetén az origin badge "helyi modell"-t mutat | `routed_gateway_integration_test.dart` |
| A2 | Local hiba + `localOnly` mód → deterministic fallback, NEM cloud (hálózati interceptor bizonyítja: 0 kérés) | `routed_gateway_integration_test.dart` |
| A3 | Cloud consent hiánya esetén a `cloudPreferred` mód sosem indít hálózati kérést | `routed_gateway_integration_test.dart` |
| A4 | Hálózat offline → `cloudPreferred` local/deterministic route-ra vált | `routed_gateway_integration_test.dart` |
| A5 | Deterministic fallback mindig elérhető, még minden más mód hibája esetén is | `routed_gateway_integration_test.dart` |
| A6 | Nincs automatikus, ismételt próbálkozás több gateway-en egy kérésen belül felhasználói tudta nélkül | `routed_gateway_integration_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `routed_tutor_model_gateway.dart` local hiba esetén közvetlenül a `RemoteTutorModelGateway`-t hívja, megkerülve a router-t | A2 (a hálózati interceptor kérést lát) |
| A badge mindig "helyi modell"-t mutat, függetlenül a tényleges route-tól | A1 |
| A gateway egy kérésen belül csendben megpróbálja mind a helyi, mind a cloud modellt | A6 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** kösd be a `RemoteTutorModelGateway`-t közvetlenül a local-hiba ágba a router megkerülésével, futtasd a hálózati-interceptoros tesztet → az **A2** cellának PIROSNAK kell lennie (a interceptor kérést regisztrál) → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/application/routed_gateway_integration_test.dart
```

## 8. Implementációs sorrend

1. `routed_tutor_model_gateway.dart` — a Kör 3 router hívása minden `start()`-nál.
2. `execution_origin_badge.dart` — a UI-jelző, `RouteReason`-ból magyarázattal.
3. A hálózati-interceptoros integrációs teszt (helyi/cloud/deterministic minden kombinációra).
4. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A router megkerülése "gyorsítás" céljából.** A legfontosabb integrációs kockázat — pontosan a Kör 3 invariánsát törné meg élesben (5.1, A2).
- **A badge hamis állítása.** Ha a UI rossz origin-t mutat, a felhasználó megalapozatlanul bízna a privacy-ígéretben (A1).
- **A csendes retry-lánc.** Több gateway automatikus, sorban történő próbálgatása többszörös hálózati/erőforrás-terhelést és megtévesztő UX-et okozna (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
