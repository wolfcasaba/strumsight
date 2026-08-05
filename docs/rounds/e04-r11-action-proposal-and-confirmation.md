# E04-R11 — Action proposal, validáció és confirmation service

- **Státusz:** PLANNING (pre-flight mérve 2026-08-05, main @ `fa76d20`; §0.0 revízió lent)
- **SDD-kör:** [`docs/sdd/05-epic-04-ai-guitar-teacher.md`](../sdd/05-epic-04-ai-guitar-teacher.md) Kör 11; §35
- **Branch:** `codex/e04-r11-action-proposal-and-confirmation`
- **Előfeltétel:** Epic 3 (E03-R22) lezárva; **E04-R10 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/ai_tutor/domain/models/tutor_action.dart",
  "lib/features/ai_tutor/application/orchestration/tutor_action_validator.dart",
  "lib/features/ai_tutor/application/orchestration/action_confirmation_service.dart",
  "lib/features/ai_tutor/application/orchestration/fake_action_executors.dart",
  "test/features/ai_tutor/domain/tutor_action_test.dart",
  "test/features/ai_tutor/application/action_confirmation_service_test.dart",
  "docs/adr/0139-ai-tutor-action-proposal-confirmation.md",
  "docs/rounds/e04-r11-action-proposal-and-confirmation.md",
]
gate_tests = [
  "test/features/ai_tutor/domain",
  "test/features/ai_tutor/application",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZVE, mérve 2026-08-05, main @ `fa76d20`):** `origin/main`
> == HEAD, E04-R10 merge kész (`2f7fffc`). Új ADR **0139** (0138 volt a legmagasabb),
> az orchestrátor írta a pre-flightban — az ADR 0133 döntésének mechanizmus-
> megvalósítása. A route-katalógus mérve: `lib/app/routing/app_route.dart` →
> `AppRoutes` **String-konstans** gyűjtemény, **nincs** route-enum; a typed capability
> greenfield, az action-domain **nem** importálja az `lib/app/routing/*`-ot.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl/contract → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**Mért baseline:** main @ `fa76d20`, `origin/main` == HEAD, working tree tiszta.
E04-R10 merge kész (`2f7fffc`, ADR 0137). Az `ai_tutor` feature létezik
(domain/models, application/{context,tools,…}); az R10 read-only tool-rendszer
csak olvas. **Greenfield action-rendszer** — nincs meglévő action-kód.

**Pre-flight mérések (ADR 0087 §1):**

- **Elérhetetlen cél-státusz (mérés-szabály 1):** az acceptance-cellák státuszai
  (stale-blocked, capability-lost, deleted-session, confirm-state) **greenfield**
  kód — nincs meglévő reducer/állapotgép, amiből ki kellene mérni; az implementer
  definiálja őket az új fájlokban, a tesztek pedig az inputból bizonyítják.
- **Erőforrás-tulajdonlás (mérés-szabály 2):** `rg "\.acquire\(" lib` → **egyetlen**
  találat (`lib/core/audio/mic_capture.dart` mic-lease). Az action/confirmation
  réteg **semmilyen** meglévő lease-t/lockot nem szerez; a confirmation-service
  providerfüggetlen, erőforrás-mentes (ADR 0139 §5).
- **Route-katalógus:** `lib/app/routing/app_route.dart` → `AppRoutes` **String-
  konstans** gyűjtemény; **nincs** route-enum. A typed capability greenfield; a
  capability → `AppRoutes` kötés a modell-bemeneten kívül, R19-re halasztott
  (production-nav TILOS itt). Az action-domain nem importál `lib/app/routing/*`-ot.

**§0.0 revíziós döntések (ADR 0087 §2 — a kör saját, még nem merge-elt artefaktuma):**

- **D1 — ADR 0139 kiosztva (pipeline-direktíva: „te írod meg a pre-flightban").**
  Az előre megírt brief „Nincs ÚJ ADR"-t feltételezett; a mérés szerint az R11
  konkrét mechanizmus-döntései (idempotencia `clientActionId`-vel, stale-policy,
  capability-nem-nyers-route, no-auto-execute kódút) **rögzítendő normatív tartalom**.
  Ezt az ADR 0139 tartalmazza, az ADR 0133 döntésének megvalósításaként. Az ADR-t
  az orchestrátor írta és commitolja a pre-flightban (R10 precedens, ADR 0137).
- **D2 — `public.dart` LEKERÜLT az engedélyezett-listáról (lista-SZŰKÍTÉS).** A
  fagyott `test/features/ai_tutor/ai_tutor_boundary_test.dart` invariánsa: a
  boundary **nulla import/export**. Mérve: `public.dart`-ot **semmi nem importálja**
  (csak maga a boundary-teszt olvassa fájlként), az `ai_tutor` tesztek a belső
  fájlokat **közvetlenül** importálják. Egy additív export a `public.dart`-ba a
  boundary-tesztet **pirosra** váltaná — az pedig **nincs** az R11 scope-jában
  (tilos zóna). Az R11 kimenetét a domain/application fájlok közvetlen importja
  fogyasztja; a public export egy későbbi (R19) kör dolga. Ugyanaz a döntés, mint
  R10 D2. Ez **szűkítés**, az autonómia-határon belül.

Nincs más brief-revízió. A scope és az acceptance változatlan.

## 1. Cél

Navigációs és állapotmódosító műveletek **kétlépcsős, felhasználó által
megerősített** rendszere — automatikus write/launch soha.

## 2. Jelenlegi állapot

- Nincs tutor action-rendszer (SDD §3.2/12). Az R10 read-only toolok csak olvasnak;
  a write/launch itt, confirmation mögött jelenik meg.
- A route-katalógus/`app_route.dart` typed route-okat definiál — a modell nem adhat
  nyers route-stringet.

## 3. Scope

**Benne:** támogatott action sealed hierarchia (source/expiry/capability/clientActionId),
proposal-validator, stale-action policy, confirmation-state + reject-flow,
profile-update/plan-save/session-launch → confirmation-kötelező, idempotens execution
clientActionId alapján, fake executorok.

**Kívül — TILOS:** UI (R19), tényleges navigáció/write végrehajtás production-ben,
nyers route-string, cloud.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/models/tutor_action.dart` | ÚJ | sealed action hierarchia |
| `.../application/orchestration/tutor_action_validator.dart` | ÚJ | proposal-validator |
| `.../application/orchestration/action_confirmation_service.dart` | ÚJ | kétlépcsős confirm |
| `.../application/orchestration/fake_action_executors.dart` | ÚJ | teszt-executor |
| `test/features/ai_tutor/{domain,application}/*` | ÚJ | action/confirm tesztek |
| `docs/adr/0139-ai-tutor-action-proposal-confirmation.md` | ÚJ (orchestrátor) | mechanizmus-döntések |
| `docs/rounds/e04-r11-*.md` | meglévő | §0.0 revízió + §10 handoff |

> **§0.0/D2:** `lib/features/ai_tutor/public.dart` **LEKERÜLT** — a fagyott
> boundary-teszt nulla-export invariánsa miatt (tilos zóna); a kimenetet a
> belső fájlok közvetlen importja fogyasztja.

**Tilos zóna:** minden más fájl, más feature belső contractja, `docs/rag`,
más kör briefje. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Nincs automatikus write/launch** — profile-update/plan-save/session-launch
   kötelezően confirmation mögött (ADR 0133). **NEM elfogadható:** „biztonságosnak
   ítélt" action auto-futása.
2. A **route-név soha nem nyers model-string** — typed action + capability.
3. **Idempotens** execution clientActionId alapján; **stale action blokkolt**.
4. Az action-domain **providerfüggetlen**.

## 6. Acceptance criteria

- [ ] valid proposal; unknown action reject; **stale** (song-revision/expiry) blokkolt
      (alatta/rajta/fölötte az expiry mátrix); deleted-session; capability-lost.
- [ ] **Double confirm idempotens** (clientActionId); reject-flow tiszta.
- [ ] **Arbitrary route blocked:** nyers route-stringből nem lesz navigáció — teszt;
      reviewer eldobható mutációval (nyers string átengedése) pirosra váltja.
- [ ] profile-update preview elérhető confirm előtt.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/application
```

Külön processzek, nincs `&&`/pipe/`tail`. CI = orchestrátor.

## 8. Implementációs sorrend

1. RED stale/idempotens/arbitrary-route/confirm-kötelező tesztek.
2. Action hierarchia + validator.
3. Confirmation-service + fake executorok.
4. Additív export; gate.

## 9. Kockázatok

- A nyers-route csábítás (kényelmi deep-link) — TILOS; typed action + capability.
- Idempotencia: a double-tap/retry nem duplikálhat write-ot (clientActionId).

**STOP:** auto-write, nyers route, nem-idempotens execution vagy mércegyengítés
helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e04-r11-action-proposal-and-confirmation-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
