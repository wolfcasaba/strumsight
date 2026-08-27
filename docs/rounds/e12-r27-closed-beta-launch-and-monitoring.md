# E12-R27 — Closed Beta launch és monitoring

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 27
- **Kör-azonosító:** `E12-R27`
- **Branch:** `<motor>/e12-r27-closed-beta-launch-and-monitoring`
- **Előfeltétel:** `E12-R22`, `E12-R25` és `E12-R26` merge-elve (terjesztés, RC-csomag, bizonyított rollback)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör indítási eljárást és mérő-eszközt szállít; a hivatkozott szerződéseket korábbi ADR-ek rögzítik.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "closed beta launch monitoring triage kill switch dry run"` → **[ADR 0395](../adr/0395-community-baseline-feature-flags-and-threat-model-scope.md)** (a kill switch operábilis marad, a hardcode-false lezárás külön GOV-kör). A béta-indítás flag-profilja tehát MŰKÖDŐ kapcsolókra épül, és a visszakapcsolás nem igényel új buildet.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy a Kör 22 `docs/beta/` csomagja, a Kör 25 RC-workflow-ja és a Kör 26 jegyzőkönyve MEGVAN, és hogy a Kör 5 flag-katalógus tartalmazza a béta-profilhoz szükséges MINDEN kapcsolót. Hiány esetén a kör nem indítható (`blocked` jelzés).

## 0.0 EMBERI KAPU — mit csinál az implementer, és mit a user

A Closed Beta INDÍTÁSA (tesztelők meghívása, artefaktum publikálása, cohort megnyitása) **user-döntés és user-művelet** — ugyanaz a kapu-típus, mint a valós gitáros APK-teszt. Az implementer terméke ezért:

1. a béta-profil KONFIGURÁCIÓJA (flag-profil fájl + ellenőrzés),
2. a napi triage sablon és a hozzá tartozó, gépileg ellenőrizhető metrika-lista,
3. a kill-switch **száraz próbája** (dry-run) egy biztonságos feature-en, bizonyított kimenettel,
4. az indítási ellenőrzőlista, amelynek minden pontja a fán MÉRT bizonyítékra hivatkozik.

A kör NEM jelenti azt, hogy a béta elindult; a `docs/beta/closed-beta-launch.md` „indításra kész / elindult" mezőjét a user tölti ki.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/beta/closed-beta-launch.md",
  "docs/beta/daily-triage-template.md",
  "docs/beta/cohort-profiles.yaml",
  "tool/release/verify_beta_profile.py",
  "test/tooling/beta_profile_test.dart",
  "docs/rounds/e12-r27-closed-beta-launch-and-monitoring.md",
]
gate_tests = [
  "test/tooling/beta_profile_test.dart",
  "test/core/feature_flags/feature_flag_registry_test.dart",
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

**STOP-protokoll:** ha az ellenőrzőlista egy pontjához nincs a fán MÉRHETŐ bizonyíték, a kimenet a `stopped` jelzés — „majd a béta alatt megnézzük" típusú pont nem kerülhet a listára.

## 1. Cél

A Closed Beta indítása legyen egyetlen, ellenőrzött konfigurációval és bizonyított vészkapcsolóval előkészítve, napi triage-eljárással — az indítás pillanata pedig maradjon explicit emberi döntés.

## 2. Jelenlegi állapot — mért tények

- `docs/beta/`: a Kör 22 után `enrollment.md`, `tester-consent.md`, `feedback-triage.md`; `closed-beta-launch.md` és `cohort-profiles.yaml` **nincs**.
- A flag-katalógus (Kör 5) és a kill-switch dokumentáció (Kör 5) MEGVAN; a flagek dart-define/env úton felülírhatók (ADR 0395).
- Telemetria: a Kör 19 SZERZŐDÉST szállított, tényleges gyűjtést NEM — a béta-monitoring ezért a diagnosztikai bundle-re és a manuális visszajelzésre épül. Ezt a `closed-beta-launch.md` mondja ki.
- A repóban MA nincs publikált béta-csatorna (Kör 1 audit).

## 3. Scope

**Benne van:** `docs/beta/cohort-profiles.yaml` (cohortonként: engedélyezett feature-flagek, verzió-tartomány, létszám-korlát) · `tool/release/verify_beta_profile.py` (a profil MINDEN flagje létezik a Kör 5 katalógusban; a magas kockázatú flagek alapból KI vannak kapcsolva; ismeretlen flag → nem-nulla kilépés) · `test/tooling/beta_profile_test.dart` · `docs/beta/daily-triage-template.md` (kategóriák, súlyosság, döntési szabály: nyitott P0/P1 mellett NINCS cohort-bővítés) · `docs/beta/closed-beta-launch.md` (indítási ellenőrzőlista MÉRT bizonyíték-hivatkozásokkal, a kill-switch dry-run kimenetével, és az EMBERI indítási mezővel).

**NINCS benne (tilos):**

- Tényleges tesztelő-meghívás, publikálás vagy cohort-megnyitás.
- `lib/**` vagy `.github/**` módosítás.
- Új flag bevezetése (csak a MEGLÉVŐK profilba rendezése).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/beta/cohort-profiles.yaml` | ÚJ — cohort↔flag profil |
| `tool/release/verify_beta_profile.py` | ÚJ — profil-ellenőrző |
| `test/tooling/beta_profile_test.dart` | a §6 cellái |
| `docs/beta/daily-triage-template.md` | ÚJ — napi triage |
| `docs/beta/closed-beta-launch.md` | ÚJ — indítási ellenőrzőlista + emberi kapu |

**Tilos zóna:** `lib/**` · `.github/**` · `docs/beta/` meglévő fájljai · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A profil MINDEN flagje létező katalógus-bejegyzés

**NEM elfogadható gyengítés:** „majd a build define-ja úgyis eldönti" — egy elgépelt flag-név némán semmit nem kapcsolna.

### 5.2 Magas kockázatú capability a béta-profilban alapból KI

**NEM elfogadható gyengítés:** „a tesztelők úgyis mindent látni akarnak" — a kockázati besorolás a Kör 5 katalógusából jön, nem a szándékból.

### 5.3 A kill-switch dry-run BIZONYÍTOTT kimenettel kerül a listára

**NEM elfogadható gyengítés:** „a mechanizmus tesztelt a Kör 5-ben" hivatkozás önmagában — ez a kör a béta-profilon futtatja le.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A cohort-profil minden flagje létezik a Kör 5 katalógusban | `beta_profile_test.dart` |
| A2 | Ismeretlen flag-név → `verify_beta_profile.py` nem-nulla kilépés | `beta_profile_test.dart` |
| A3 | Magas kockázatú flag a béta-profilban alapból `false` | `beta_profile_test.dart` |
| A4 | A kill-switch dry-run kimenete szerepel a `closed-beta-launch.md`-ben, és a kikapcsolt feature NEM tört adatot | `beta_profile_test.dart` + a dokumentum |
| A5 | Az indítási lista MINDEN pontja MÉRT bizonyítékra hivatkozik (fájl, futás vagy jegyzőkönyv) | a dokumentum + a teszt hivatkozás-cellája |
| A6 | A dokumentum kimondja: az indítás EMBERI döntés, és a kör azt nem hajtja végre | a dokumentum |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A profil elgépelt flag-nevet tartalmaz | A1/A2 |
| Egy magas kockázatú capability alapból bekapcsolva kerül a profilba | A3 |
| Az indítási lista „a béta alatt ellenőrizzük" pontot tartalmaz bizonyíték nélkül | A5 |
| A dokumentum úgy fogalmaz, mintha a kör elindította volna a bétát | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írj a profilba egy nem létező flag-nevet, futtasd a §7 gate-et → az **A1**/**A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/beta_profile_test.dart test/core/feature_flags/feature_flag_registry_test.dart
```

A profil-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
python3 tool/release/verify_beta_profile.py --profile docs/beta/cohort-profiles.yaml
```

## 8. Implementációs sorrend

1. `docs/beta/cohort-profiles.yaml` a MÉRT flag-katalógusból.
2. `tool/release/verify_beta_profile.py`.
3. `test/tooling/beta_profile_test.dart`.
4. A kill-switch dry-run futtatása és a kimenet rögzítése.
5. `daily-triage-template.md` + `closed-beta-launch.md` (emberi kapuval) + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Látszat-indítás.** A dokumentum azt sugallhatja, hogy a béta elindult, holott az emberi lépés (A6).
- **Néma flag-elgépelés.** Egy nem létező kapcsoló profilban semmit nem kapcsol (A1).
- **Monitoring-illúzió.** Telemetria-gyűjtés nélkül a „monitoring" a diagnosztikai bundle-re és a visszajelzésre korlátozódik — ezt a dokumentum mondja ki, nem hallgatja el.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
