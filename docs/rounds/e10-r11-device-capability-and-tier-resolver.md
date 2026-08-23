# E10-R11 — Device capability profiler és tier resolver (Dart-oldali resolver)

- **Státusz:** PREPARED (előre megírva 2026-08-22, kód olvasva: `main @ 194b48c4`)
- **Típus:** Chapter 11 (Epic 10 — Offline AI), Kör 11
- **Kör-azonosító:** `E10-R11`
- **Branch:** `<motor>/e10-r11-device-capability-and-tier-resolver`
- **Előfeltétel:** `E10-R10` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0426` — a szám FOGLALT (Epic 10 batch-tartomány, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "device capability tier resolver conservative fallback unknown platform"` → **ADR 0237** (Analysis confidence combiner and capability resolver, emb#1) — más domain (audio-analysis confidence), de a mintázat közvetlen precedens: EGYETLEN belépő pont rendel állapotot egy capabilityhez, állapotmentes és determinisztikus bemenetből. Ez a brief ugyanezt az "egyetlen belépő, determinisztikus döntés" elvet alkalmazza a device-tier resolverre (5. §), nem talál ki új mintát.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 2 `DeviceCapabilityProfiler` interfészét és a SDD §7.3 `DeviceCapabilityProfile` mezőit. Eltérésnél §0.0 brief-revízió.

## 0.0 Hardver/scope-korlát — miért PENDING (narrowed)

A SDD Kör 11 eredeti fájllistája natív Kotlin próbákat is tartalmaz (`DeviceMemoryProbe.kt`, `ThermalMonitor.kt`) — ezek **KIMARADNAK** ebből a brief-ből (ugyanaz a korlát, mint Kör 6/7/13-nál). A TIER RESOLVER LOGIKA (melyik `DeviceCapabilityProfile` bemenetre melyik `Tier` a kimenet, milyen reason code-dal) tisztán Dart-oldali, FÜGGVÉNY a bemeneti profilon — ez a kör egy INJEKTÁLHATÓ, teszt-oldalon FAKE profilokkal vezérelt resolvert szállít. A valós natív próbák (memory/thermal API hívás) egy jövőbeli, natív-infrastruktúrájú körnek (Kör 7/13 mellett) maradnak nyitott tartozásként.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/core/ai/device_capability_profiler.dart",
  "lib/features/offline_ai/application/device_tier_resolver.dart",
  "test/features/offline_ai/application/device_tier_resolver_test.dart",
  "docs/rounds/e10-r11-device-capability-and-tier-resolver.md",
]
gate_tests = [
  "test/features/offline_ai/application/device_tier_resolver_test.dart",
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

A tier-választás legyen tiszta, mérésből (bemeneti `DeviceCapabilityProfile`-ból) származó FÜGGVÉNY, konfigurálható küszöbökkel és magyarázható reason code-dal — fingerprinting-mentesen.

## 2. Jelenlegi állapot — mért tények

- A Kör 2 `DeviceCapabilityProfiler` interfészt már definiálta — ez a kör a RESOLVER logikát adja (a profil MÉRÉSE, azaz a valós natív probe-hívás, egy jövőbeli natív kör dolga marad, lásd §0.0).
- `lib/core/ai/` a Kör 2 óta stabil, tesztelt domain — ez a kör bővíti a resolver-logikával.

## 3. Scope

**Benne van:** `DeviceCapabilityProfile` → `Tier` resolver, konfigurálható küszöbökkel · reason code minden nem-legjobb tier választáshoz (unsupported ABI, low storage, benchmark slow, memory unsafe, backend unavailable) · Tier 0 mint teljes értékű fallback · manual re-benchmark / reset capability funkció (a resolver oldala, ami a "stale" jelzést kezeli) · ismeretlen platform API esetén konzervatív (alacsonyabb) tier.

**NINCS benne (tilos):**

- Natív Android memory/thermal/ABI PROBE — nyitott tartozás, lásd §0.0.
- Bármilyen adat szerverre küldése — a resolver TISZTÁN lokális függvény.
- `docs/adr/**` — az ADR 0426-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/ai/device_capability_profiler.dart` | a Kör 2 interfész BŐVÍTÉSE a `Tier` enummal |
| `lib/features/offline_ai/application/device_tier_resolver.dart` | ÚJ — a resolver logika |
| `test/features/offline_ai/application/device_tier_resolver_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/features/offline_ai/data/**` (a VALÓS profil-repository egy jövőbeli kör dolga) · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0426)

### 5.1 A profil nem tartalmazhat fingerprinting-célú adatot, és nem küldhető szerverre automatikusan

A `DeviceCapabilityProfile` mezői (SDD §7.3) kimondottan NEM tartalmaznak stabil advertising ID-t; a resolver maga sosem indít hálózati kérést.

**NEM elfogadható gyengítés:** egy "anonim" hardver-hash hozzáadása a profilhoz "jobb támogatás céljából" — ez a §18.3 SDD-tiltás (nincs exact device fingerprint a manifest-kérésben) elvi megsértése lenne már a resolver szintjén is.

### 5.2 Ismeretlen platform API vagy hiányzó mérés → konzervatív tier, sosem optimista

Ha egy mező hiányzik vagy mérhetetlen (pl. nincs thermal API), a resolver az ALACSONYABB tier felé dönt, sosem a magasabb felé.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Alacsony memória → Tier 0/1, sosem Tier 2/3 | `device_tier_resolver_test.dart` |
| A2 | Hiányzó thermal API → konzervatív tier, nem crash és nem optimista tier | `device_tier_resolver_test.dart` |
| A3 | Elégtelen tárhely → Tier 0, explicit `lowStorage` reason code-dal | `device_tier_resolver_test.dart` |
| A4 | Elavult (stale) benchmark → a resolver jelzi az újramérés szükségességét, nem hallgatólagosan a régi eredményt használja | `device_tier_resolver_test.dart` |
| A5 | A resolver kimenete determinisztikus ugyanarra a bemenetre | `device_tier_resolver_test.dart` |
| A6 | A resolver sosem hív hálózati kódot | `test/tooling/architecture_dependency_offline_ai_test.dart` (Kör 2 bővítve, `dart:io`/`package:dio` import tiltás) |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A resolver alacsony memória mellett is Tier 2-t ad, mert csak az ABI-t nézi | A1 |
| A hiányzó thermal API `Tier 3`-ra esik vissza "optimista alapértékként" | A2 |
| Az elégtelen tárhely csak figyelmeztetést ad, a tier nem csökken | A3 |
| A stale benchmark ugyanúgy viselkedik, mint a friss, jelzés nélkül | A4 |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a hiányzó-thermal-API ágat `Tier 3`-ra optimista alapértékkel, futtasd a tesztet → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

### 6.2 Küszöb-hármas — `availableMemoryBytes` konfigurálható tier-küszöbe (illusztratív alapérték, Kör 6 mérése finomítja)

A küszöb konfigurálható konstans, alapértéke 2 GiB (`python3 -c "print(2*1024**3)"` = 2147483648), a `rajta` cella a MAGASABB tierhez tartozik (inkluzív):

| Cella | `availableMemoryBytes` | Elvárt |
|---|---|---|
| alatta | 2147483647 (2 GiB − 1) | Tier 0 (nem elég memória Tier 1-hez) |
| rajta | 2147483648 (pontosan 2 GiB) | Tier 1 (a küszöb a magasabb tieré) |
| fölötte | 2147483649 (2 GiB + 1) | Tier 1 (vagy magasabb, ha más mérés is engedi) |

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/offline_ai/application/device_tier_resolver_test.dart
```

## 8. Implementációs sorrend

1. `Tier` enum + reason code enum a `device_capability_profiler.dart`-ban.
2. `device_tier_resolver.dart` — a küszöb-alapú döntési logika.
3. Konzervatív-fallback ágak minden hiányzó/mérhetetlen mezőre.
4. A stale-benchmark jelzés.
5. A valódi-sértés próba §10-be.

## 9. Kockázatok

- **A natív probe hiányának elfelejtése.** A HANDOFF-nak és a Kör 13 pre-flightjának explicit rögzítenie kell, hogy a VALÓS memory/thermal mérés még nem készült el (nyitott tartozás).
- **Az optimista fallback.** Egy hiányzó mérésre adott túl jó tier valós eszközön OOM-ot vagy thermal problémát okozna, amíg a natív probe el nem készül (A2).
- **A fingerprinting-kísértés.** Egy "jobb támogatás" ürüggyel bevezetett részletes hardveradat sértené az adatvédelmi elvet (5.1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
