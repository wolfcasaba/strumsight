# E10-R12 — Local AI resource coordinator

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 12
- **Kör-azonosító:** `E10-R12`
- **Branch:** `<motor>/e10-r12-local-ai-resource-coordinator`
- **Előfeltétel:** `E10-R11` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0427` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Chapter 2 `AudioSessionCoordinator` (`lib/core/audio/audio_session_coordinator.dart`, E01-R09) PUBLIC állapotait/lease-mintáját — ez a kör UGYANEZT a mintát alkalmazza a generatív AI-ra, nem talál ki új lease-szemantikát. Eltérésnél §0.0 brief-revízió.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "resource lease acquire release exception not freed race"` → **L100** (E03-R20, bm25#2 emb#1) — az erőforrás-tulajdonlást a TÉNYLEGES hívási láncon kell mérni, nem a réteg-diagramból feltételezni; ez a brief §2-je pontosan ezt teszi (a lease-mintát a valós `AudioSessionCoordinator.acquire` hívóláncból veszi, nem a SDD absztrakt leírásából). **ADR 0056** (exclusive microphone session, bm25#1 emb#2) — a "busy failure, not steal" minta közvetlen precedens az 5.1 kötött döntéshez.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/ai/local_ai_resource_coordinator.dart",
  "lib/features/offline_ai/application/local_ai_resource_policy.dart",
  "test/features/offline_ai/local_ai_resource_coordinator_test.dart",
  "docs/rounds/e10-r12-local-ai-resource-coordinator.md",
]
gate_tests = [
  "test/features/offline_ai/local_ai_resource_coordinator_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

## 1. Cél

A generatív helyi AI ne versenyezhessen kontrollálatlanul a mikrofonnal, kamerával, audio playbackkel vagy az Analyze recordinggal — a lease-alapú koordináció ugyanazt a mintát követi, mint a Chapter 2 audio session.

## 2. Jelenlegi állapot — mért tények

- Az `AudioSessionCoordinator` (Chapter 2, E01-R09) MÁR MEGVAN, és egy owner-alapú lease-mintát valósít meg mikrofonra — ez a kör ugyanezt a MINTÁT (nem osztályt) alkalmazza a generatív AI-ra, egy ÚJ, `LocalAiResourceCoordinator` néven.
- A Kör 2 (E10-R02) `LocalAiResourceCoordinator` interfészt már definiálta — ez a kör az implementációt adja.
- A projekt MA nem ismer semmilyen "vision lifecycle" public state-et Chapter 6-ból, mert a Computer Vision Epic (5) a repo state szerint a vision modellek `deferred` státuszban vannak (`assets/ml/model_manifest.json`) — ez a kör ezért a mikrofonos/Analyze-integrációt köti be ELSŐDLEGESEN, a vision-integrációt egy FUTURE-PROOF, de MA nem éles interfész-ponton hagyja (a `visionOwner` mező opcionális, `null`-lal alapértelmezett).

## 3. Scope

**Benne van:** `acquireGenerationLease`/release contract · tierenkénti szabály, hogy mi engedélyezett aktív mic/camera mellett · thermal severe/critical és low-memory kezelés · a model download és a generation KÜLÖN resource-osztálya · generation lease nélkül a runtime NEM indíthat generálást · minden elutasítás lokalizálható reason code-ot ad.

**NINCS benne (tilos):**

- A natív thermal/memory JELZÉS forrása (a Kör 27 dolga) — ez a kör egy INJEKTÁLHATÓ thermal/memory status streamet fogyaszt, nem hozza létre a valós natív forrást.
- `docs/adr/**` — az ADR 0427-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/ai/local_ai_resource_coordinator.dart` | a Kör 2 interfész IMPLEMENTÁCIÓJA |
| `lib/features/offline_ai/application/local_ai_resource_policy.dart` | ÚJ — tierenkénti szabálytábla |
| `test/features/offline_ai/local_ai_resource_coordinator_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/core/audio/**` (csak OLVASSA a public állapotot, nem módosítja) · `android/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0427)

### 5.1 Generation lease nélkül a runtime nem indíthat generálást — ez a KIZÁRÓLAGOS belépési pont

A Kör 23 gateway-nek KÖTELEZŐ `acquireGenerationLease`-t hívnia MINDEN generálás előtt; a lease hiánya blokkolja a hívást a hívó oldalon, nem csak dokumentációs ajánlás.

**NEM elfogadható gyengítés:** egy "gyors debug módban a lease kihagyható" ág — ez pontosan az a race-forrás, amit a koordinátor kiküszöbölni hivatott.

### 5.2 A lease minden exit pathon felszabadul — siker, hiba, cancel és exception egyaránt

**NEM elfogadható gyengítés:** egy `try`-blokk lease-acquire-rel, aminek a `catch`-ága nem hívja a release-t "mert a hiba már jelezve van" — ez pontosan az a mért hibaosztály (elnyelt erőforrás-felszabadítás), amit az AGENTS.md §7 explicit tilt.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Aktív mikrofon mellett Tier 1 eszközön a generálás `ResourceBusyFailure` | `local_ai_resource_coordinator_test.dart` |
| A2 | Analyze recording alatt a generálás elutasított | `local_ai_resource_coordinator_test.dart` |
| A3 | Thermal severe állapotban új generálás nem indul | `local_ai_resource_coordinator_test.dart` |
| A4 | Alacsony memória esetén a lease megtagadott | `local_ai_resource_coordinator_test.dart` |
| A5 | Kétszeri release ugyanarra a lease-re nem crashel és nem enged dupla acquire-t | `local_ai_resource_coordinator_test.dart` |
| A6 | Race: acquire és cancel egyidejűleg — a végállapot konzisztens (nincs "lebegő" lease) | `local_ai_resource_coordinator_test.dart` |
| A7 | Minden elutasítás lokalizálható reason code-dal tér vissza | `local_ai_resource_coordinator_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A koordinátor csak a mikrofont nézi, az Analyze recording állapotot nem | A2 |
| A `catch`-ág nem hívja a release-t hiba esetén | A6 (a következő acquire "foglaltnak" látná a lease-t, holott fel kellett volna szabadulnia) |
| A severe thermal állapotot a koordinátor figyelmen kívül hagyja | A3 |
| A kétszeri release dupla számlálást okoz, engedve egy harmadik, jogosulatlan acquire-t | A5 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** távolítsd el a `release()` hívást a hibaágból, futtasd a tesztet → az **A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/local_ai_resource_coordinator_test.dart
```

## 8. Implementációs sorrend

1. `local_ai_resource_policy.dart` — tierenkénti szabálytábla (mi engedélyezett mic/camera/analyze mellett).
2. `local_ai_resource_coordinator.dart` — `acquireGenerationLease`/release, thermal/memory bemenet fogyasztása.
3. A race és double-release védelem.
4. Reason code minden elutasításhoz.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **Az elnyelt release hiba esetén.** A legvalószínűbb, ismétlődő hibaosztály ebben a projektben (AGENTS.md §7) — itt EXPLICIT teszttel védve (A6).
- **A vision-integráció hiánya.** Mivel a vision modellek MA `deferred` státuszban vannak, a `visionOwner` mező jelenleg mindig `null` — ha egy jövőbeli kör aktiválja a vision-t, ennek a koordinátornak a policy-ját újra kell mérni.
- **A tierenkénti szabály túl megengedő Tier 3-on.** A SDD explicit figyelmeztet: "Tier 3 eszközön is csak külön mérés és policy alapján engedhető egyidejű vision és LLM" — ez a kör konzervatív (tiltó) alapértéket ad, amíg nincs mérés.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
