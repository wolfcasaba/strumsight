# E12-R34 — Post-launch stabilization, hotfix és incident automation

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 34
- **Kör-azonosító:** `E12-R34`
- **Branch:** `<motor>/e12-r34-post-launch-stabilization-and-hotfix`
- **Előfeltétel:** `E12-R33` merge-elve (GA-rekord)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0465` — a szám FOGLALT (Chapter 12 batch-tartomány): a hotfix-út szabálya kötött architekturális döntés.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "post launch stabilization hotfix workflow incident postmortem"` → a `halts/halted-20260813T040134.txt` (E06-R23 H-INDEP) és a `halts/round-status-E{07,08}-R*` merge-elt körök. Release-domain előzmény nincs; a hotfix-út a Kör 25 RC-workflow-jának SZŰKÍTETT változata.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a Kör 25 `release-candidate.yml` szerkezetét (composite gate-hívás + manuális jóváhagyás) — a hotfix-workflow ugyanazt a composite actiont használja, csak szűkebb scope-pal. Ha a Kör 25 workflow-ja időközben változott, a §3 igazodjon.

## 0.0 Mit szállít a kör, és mit a user

A napi health-review és a 7./14. napi riport ADATA a GA utáni valóságból jön (user + support). Az implementer terméke: a hotfix-út (workflow + eszköz + mérce), az incident/postmortem sablon, és a riport-vázak gépi ellenőrzéssel. A riportok KITÖLTÉSE emberi lépés.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  ".github/workflows/hotfix.yml",
  "tool/release/verify_hotfix.py",
  "docs/operations/hotfix-runbook.md",
  "docs/operations/postmortem-template.md",
  "docs/release/post-launch-day7.md",
  "docs/release/post-launch-day14.md",
  "test/tooling/hotfix_policy_test.dart",
  "docs/rounds/e12-r34-post-launch-stabilization-and-hotfix.md",
]
gate_tests = [
  "test/tooling/hotfix_policy_test.dart",
  "test/tooling/rc_assembly_test.dart",
]
native_gate = true
```

**Kockázat = high, indoklás:** a hotfix-út a leggyorsabb út a production felé; ha megkerülhetővé válik a security/signing kapu, az a teljes release-védelmet üresíti ki. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a hotfix-workflow-hoz a merge-kapu (`build-apk.yml` / `full-gate.yml`) módosítása kellene, a kimenet a `stopped` jelzés.

## 1. Cél

Auditálható, gyors, de kapukat NEM megkerülő hotfix-út, incident- és postmortem-eljárás, valamint a 7./14. napi stabilizációs riport váza.

## 2. Jelenlegi állapot — mért tények

- `.github/workflows/`: a Kör 25 után `release-candidate.yml` is; `hotfix.yml` **nincs**.
- `tool/release/`: `assemble_rc.py`, `security_scan.py`, `verify_signing_policy.py`, `verify_artifacts.py`, `build_ai_report.py`, `generate_sbom.py`, `verify_rollback.py`, `verify_freeze.py`, `verify_rollout_decision.py`, `verify_ga_record.py`.
- `docs/operations/`: `backend-deploy.md`, `database-recovery.md`, `disaster-recovery-drill.md`, `capacity-review.md`, `slo.yaml`, `release-dashboard.md`, Community moderation runbook; hotfix-runbook és postmortem-sablon **nincs**.
- A verzió-monotonitás ellenőrzése a Kör 6 `verify_artifacts.py`-jában él — a hotfix-út ezt HÍVJA.

## 3. Scope

**Benne van:** `.github/workflows/hotfix.yml` (hotfix branch-ről indítható, manuális jóváhagyással; a `flutter-gates` composite + az ÉRINTETT terület teljes regressziója; kötelező incident-azonosító input; a Kör 6/7 provenance és signing lépések VÁLTOZATLANUL) · `tool/release/verify_hotfix.py` (kötelező incident-azonosító, verzió-emelés kényszerítése, a security-scan és signing lépés MEGLÉTÉNEK statikus ellenőrzése a workflow-ban) · `docs/operations/hotfix-runbook.md` · `docs/operations/postmortem-template.md` · `docs/release/post-launch-day{7,14}.md` (váz kötelező mezőkkel) · `test/tooling/hotfix_policy_test.dart`.

**NINCS benne (tilos):**

- A merge-kapu workflow-k módosítása.
- Tényleges hotfix kiadása.
- A security/signing lépések kihagyása vagy feltételessé tétele.
- `docs/adr/**` — az ADR 0465-öt a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `.github/workflows/hotfix.yml` | ÚJ — a hotfix-út |
| `tool/release/verify_hotfix.py` | ÚJ — a hotfix-mérce |
| `docs/operations/hotfix-runbook.md` | ÚJ — eljárás |
| `docs/operations/postmortem-template.md` | ÚJ — postmortem sablon |
| `docs/release/post-launch-day7.md` | ÚJ — 7. napi riport váza |
| `docs/release/post-launch-day14.md` | ÚJ — 14. napi riport váza |
| `test/tooling/hotfix_policy_test.dart` | a §6 cellái |

**Tilos zóna:** `.github/workflows/{build-apk,full-gate,release-apk,release-candidate,lab-apk}.yml` · `.github/actions/**` · `lib/**` · `backend/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0465)

### 5.1 A hotfix NEM kerüli meg a security és signing kaput

**NEM elfogadható gyengítés:** „sürgős, ezért kihagyjuk a scant" ág — a gyorsaság a SCOPE szűkítéséből jön (kevesebb változás), nem a kapuk elhagyásából.

### 5.2 Incident-azonosító nélkül nincs hotfix

**NEM elfogadható gyengítés:** opcionális mező.

### 5.3 Minden hotfixhez tartozik regressziós teszt

A javítás mellé a hibát REPRODUKÁLÓ cella kerül. **NEM elfogadható gyengítés:** „a manuális ellenőrzés elég".

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Hiányzó incident-azonosító mellett a workflow megáll | BIZONYÍTOTT PIROS orchesztrátor-dispatch linkje a §10-ben |
| A2 | A workflow tartalmazza a security-scan és a production signing lépést | `hotfix_policy_test.dart` statikus cellája |
| A3 | Verzió-emelés nélkül a `verify_hotfix.py` nem-nulla kóddal lép ki | `hotfix_policy_test.dart` |
| A4 | A hotfix-runbook megköveteli a regressziós cellát a javítás mellé | a runbook + `hotfix_policy_test.dart` |
| A5 | A 7./14. napi riport váza kötelező mezőket definiál (crash, migráció, akku, audio, support) | a dokumentumok + a teszt cellája |
| A6 | ZÖLD hotfix-dispatch a kör-branchen (üres, dokumentáció-szintű változással) | orchesztrátor-dispatch linkje a §10-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A workflow `if: inputs.skip_scan != true` ágat kap | A2 |
| Az incident-azonosító opcionális input lesz | A1 |
| A verzió-emelés ellenőrzése kimarad | A3 |
| A runbook nem követel regressziós cellát | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki a security-scan lépést a `hotfix.yml`-ből, futtasd a §7 gate-et → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/hotfix_policy_test.dart test/tooling/rc_assembly_test.dart
```

A hotfix-mérce közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_hotfix.py --workflow .github/workflows/hotfix.yml
```

A workflow bizonyítéka a KÉT orchesztrátor-dispatch (zöld + bizonyított piros) — az implementer `gh`-t nem hív.

## 8. Implementációs sorrend

1. `tool/release/verify_hotfix.py` — a statikus mérce ELŐSZÖR.
2. `test/tooling/hotfix_policy_test.dart`.
3. `.github/workflows/hotfix.yml` — a composite gate + manuális jóváhagyás + incident-input.
4. `docs/operations/hotfix-runbook.md` és `postmortem-template.md`.
5. A két post-launch riport váza + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Kapu-megkerülés.** A hotfix a legvalószínűbb hely, ahol a „sürgősség" kikapcsolja a védelmet (A2).
- **Regresszió nélküli javítás.** A hiba visszatér a következő kiadásban (A4).
- **Riport-illúzió.** Kitöltetlen váz nem stabilizáció — a dokumentum kimondja, hogy a kitöltés emberi lépés.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
