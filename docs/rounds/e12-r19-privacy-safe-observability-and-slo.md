# E12-R19 — Privacy-safe observability, SLO és release dashboard

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 19
- **Kör-azonosító:** `E12-R19`
- **Branch:** `<motor>/e12-r19-privacy-safe-observability-and-slo`
- **Előfeltétel:** `E12-R17` merge-elve (a telemetria-mezők a data-inventory bejegyzései)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0459` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "telemetry redaction opt-out SLO dashboard cohort unknown not success"` → a `halts/halted-20260813T040134.txt` (E06-R23 H-INDEP) és **[ADR 0418](../adr/0418-leaderboards-and-opt-in-competition.md)** (opt-in verseny-nézet, `verified`-only projekció). A telemetria opt-in/opt-out logikája ugyanezt a mintát követi: az alapállapot a NEM-küldés.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/logging/log_redactor.dart` és a `lib/core/network/redacted_log_interceptor.dart` MÉRT redakciós szabályait — az esemény-redakció ezeket ÚJRAHASZNÁLJA, nem ír melléjük második listát.

## 0.0 A kör határa: szerződés és redakció, nem szolgáltató

A kör NEM köt be külső analytics-szolgáltatót és nem küld semmit hálózatra. Amit szállít: a typed esemény-katalógus, a redakciós és consent-kapu, valamint a dashboard/SLO BEMENETI sémája. A tényleges gyűjtés bekapcsolása a rollout-körök (31–33) user-döntése, és feature-flag mögött marad.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/telemetry/telemetry_event.dart",
  "lib/core/telemetry/telemetry_redactor.dart",
  "lib/core/telemetry/telemetry_sink.dart",
  "lib/core/telemetry/public.dart",
  "test/core/telemetry/telemetry_redaction_test.dart",
  "docs/analytics/event-catalog.md",
  "docs/operations/slo.yaml",
  "docs/operations/release-dashboard.md",
  "docs/rounds/e12-r19-privacy-safe-observability-and-slo.md",
]
gate_tests = [
  "test/core/telemetry/telemetry_redaction_test.dart",
  "test/privacy/consent_enforcement_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a telemetria a felhasználói tanulási tartalom közelében dolgozik (prompt, hang, videó, szabad szöveg) — egy hiányos redakció érzékeny adatot vinne ki. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a bekötés a `lib/features/**` érintését igényelné (esemény-kibocsátás beépítése), a kimenet a `stopped` jelzés — a feature-oldali kibocsátás külön kör.

## 1. Cél

Olyan telemetria-szerződés, amely érzékeny tartalmat elvileg sem tud kivinni, opt-out mellett bizonyíthatóan no-op, és amelyből SLO/dashboard-bemenet készíthető — az `unknown` állapot pedig sosem számít sikernek.

## 2. Jelenlegi állapot — mért tények

- `lib/core/telemetry/` **nem létezik**. A meglévő rokon réteg: `lib/core/logging/{app_logger,debug_app_logger,log_redactor,logger_provider}.dart` és `lib/core/network/redacted_log_interceptor.dart`.
- `lib/features/diagnostics/` MA opt-in, Lab-módhoz kötött diagnosztikai feltöltést végez (`diagnostics_uploader.dart`) — ez a MÉRT precedens az „alapból nem küld" mintára.
- `docs/analytics/` és `docs/operations/slo.yaml` **nem létezik**; `docs/operations/` MA egy Community runbookot tartalmaz.
- `backend/app/telemetry/` **nem létezik** — ez a kör a KLIENS-oldali szerződést szállítja; a backend-oldali gyűjtés külön kör.
- `test/privacy/` a Kör 17 után létezik.

## 3. Scope

**Benne van:** `telemetry_event.dart` (typed esemény: név, kategória, művelet-eredmény, időtartam-BUCKET, capability-metaadat — szabad szöveges mező NEM megengedett a típusban) · `telemetry_redactor.dart` (a `log_redactor.dart` szabályainak újrahasználata + a nyers prompt/audio/videó/„felhasználói szöveg" mezők STRUKTURÁLIS tiltása) · `telemetry_sink.dart` (interfész; az alapértelmezett implementáció opt-out mellett NO-OP, hálózat nélkül) · `docs/analytics/event-catalog.md` · `docs/operations/slo.yaml` (a core SLO-k és küszöbeik) · `docs/operations/release-dashboard.md` (bemeneti séma, cohort-szűrő, `unknown` kezelés).

**NINCS benne (tilos):**

- Külső analytics SDK vagy hálózati küldés.
- `lib/features/**` érintése (esemény-kibocsátás bekötése).
- Backend-oldali telemetria-végpont.
- `docs/adr/**` — az ADR 0459-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/core/telemetry/telemetry_event.dart` | ÚJ — typed esemény |
| `lib/core/telemetry/telemetry_redactor.dart` | ÚJ — redakció a MEGLÉVŐ szabályokra építve |
| `lib/core/telemetry/telemetry_sink.dart` | ÚJ — sink-interfész, no-op alapértelmezéssel |
| `lib/core/telemetry/public.dart` | ÚJ — barrel |
| `test/core/telemetry/telemetry_redaction_test.dart` | a §6 cellái |
| `docs/analytics/event-catalog.md` | ÚJ — esemény-katalógus |
| `docs/operations/slo.yaml` | ÚJ — SLO-k |
| `docs/operations/release-dashboard.md` | ÚJ — dashboard-bemenet |

**Tilos zóna:** `lib/features/**` · `lib/core/logging/**` · `lib/core/network/**` · `backend/**` · `.github/**` · `docs/adr/**`

## 5. Kötött architekturális döntések (ADR 0459)

### 5.1 A tiltás STRUKTURÁLIS, nem szűrő

A typed eseményben nincs olyan mező, amibe nyers prompt, hang, kép vagy szabad felhasználói szöveg beleférne — a redakció a második védelmi vonal, nem az első. **NEM elfogadható gyengítés:** általános `Map<String, dynamic> payload` mező „a rugalmasság kedvéért".

### 5.2 Opt-out mellett a sink NO-OP, nem pufferel

**NEM elfogadható gyengítés:** „gyűjtsük, és majd ha hozzájárul, elküldjük" — az a hozzájárulás előtti gyűjtés.

### 5.3 Az `unknown` NEM zöld

A dashboard-sémában a hiányzó metrika `unknown`, és a release-döntésben ez NEM sikeres állapot (a Kör 14 §5.2 szabályával egyezően). **NEM elfogadható gyengítés:** hiányzó metrika kihagyása az összesítésből.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A typed eseménybe szabad szöveges/nyers tartalom szerkezetileg nem tehető | `telemetry_redaction_test.dart` (típus-szintű cella) |
| A2 | A redaktor a MEGLÉVŐ `log_redactor` szabályait alkalmazza (token, e-mail, útvonal) | `telemetry_redaction_test.dart` |
| A3 | Opt-out mellett a sink NO-OP: nem tárol és nem pufferel | `telemetry_redaction_test.dart` |
| A4 | Időtartam bucket-ként, nem nyers ezredmásodpercként kerül az eseménybe | `telemetry_redaction_test.dart` |
| A5 | A dashboard-séma hiányzó metrikát `unknown`-ként jelöl, és ez nem `success` | `telemetry_redaction_test.dart` séma-cellája |
| A6 | A Kör 17 consent-cellái VÁLTOZATLANUL zöldek | a §7 gate |

**Küszöb-cellahármas az időtartam-bucketre** (a bucket-határ INKLUZÍV az ALSÓ oldalon, pl. `1000 ms` határ mellett a `[1000, 3000)` bucket): a küszöb **alatt** (999 ms) → az alacsonyabb bucket; **pontosan rajta** (1000 ms) → a magasabb bucket ALSÓ eleme; a küszöb **fölött** (1001 ms) → ugyanaz a magasabb bucket.

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Az esemény kap egy általános `payload` mapet | A1 |
| Opt-out mellett a sink memóriában gyűjt | A3 |
| A nyers ezredmásodperc kerül az eseménybe | A4 |
| A hiányzó metrika kimarad, és a dashboard zöld | A5 |
| A bucket-határ kizáró, így a pontosan 1000 ms rossz bucketbe esik | a küszöb-cellahármas „pontosan rajta" cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a sink opt-out ágát (mindig gyűjtsön), futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/telemetry/telemetry_redaction_test.dart test/privacy/consent_enforcement_test.dart
```

## 8. Implementációs sorrend

1. `telemetry_event.dart` — a strukturális tiltással.
2. `telemetry_redactor.dart` — a meglévő szabályok újrahasználata.
3. `telemetry_sink.dart` — no-op alapértelmezés.
4. `telemetry_redaction_test.dart` — a küszöb-cellahármassal.
5. `docs/analytics/event-catalog.md`, `docs/operations/slo.yaml`, `release-dashboard.md`.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A rugalmas payload csapdája.** Egy `Map<String, dynamic>` minden strukturális védelmet kinyit (A1).
- **Kettős redakciós lista.** A `log_redactor` mellé írt második lista szétcsúszik (A2).
- **A hiányzó metrika zöldre fordítása.** Ugyanaz a hibaosztály, mint a Kör 14-ben és 16-ban (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
