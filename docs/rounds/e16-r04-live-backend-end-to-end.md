# E16-R04 — Élő backend end-to-end: fiók, szinkron, közösség egy eszközön

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 4
- **Kör-azonosító:** `E16-R04`
- **Branch:** `<motor>/e16-r04-live-backend-end-to-end`
- **Előfeltétel:** `E15-R12` (a Community routerek felcsatolása) és `E16-R03` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0493` — a szám FOGLALT (Chapter 16 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend account login settings sync community end-to-end device profile"` → **[ADR 0400](../adr/0400-profile-onboarding-service-and-community-gate-ui.md)** (profil-onboarding és Community gate UI) és az `E12-R08` staging-runbookja. A kör ezekre épül: nem új backendet ír, hanem a MEGLÉVŐT teszi egy valódi eszközről használhatóvá és méri.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd, hogy az `E15-R12` MEGTÖRTÉNT (a `main.py` felcsatolja a Community routert), és olvasd el az `E12-R08` `docs/operations/backend-deploy.md` lépéseit. Ha a felcsatolás hiányzik, a kör nem indítható (`blocked`).

## 0.0 Mi gépi és mi emberi

A backend TÉNYLEGES futtatása (a boxon vagy felhőben) és a telefon ráállítása **operátori (user-) lépés** — ugyanaz a kapu, mint a valós gitáros APK-teszt. Az implementer terméke: (a) egy `device_build.json` profil-sablon és a hozzá tartozó dokumentált build-parancs, (b) egy `tool/release/live_backend_smoke.py`, ami egy MEGADOTT URL ellen végigméri a kliens által használt teljes felületet (health → regisztráció → login → `/auth/me` → settings-szinkron → community olvasás/írás), (c) a hibák emberi-olvasható diagnózisa. A kör NEM indít szervert és nem oszt titkot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/release/live_backend_smoke.py",
  "device_build.example.json",
  "docs/operations/device-backend-runbook.md",
  "backend/tests/test_live_smoke_contract.py",
  "test/tooling/device_profile_test.dart",
  "docs/rounds/e16-r04-live-backend-end-to-end.md",
]
gate_tests = [
  "test/tooling/device_profile_test.dart",
  "test/app/app_config_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör hitelesítési folyamatot és felhasználói adatot mozgató végpontokat hív, és egy eszköz-profil fájlt vezet be, ahová titok kerülhetne. A `security-reviewer` futtatása KÖTELEZŐ.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a smoke a kliens és a szerver közt szerződés-eltérést mér (útvonal, mező, státuszkód), a kimenet a `stopped` jelzés és a diff — a termékkód javítása külön kör.

## 1. Cél

Egyetlen paranccsal mérhető legyen, hogy egy VALÓDI backend-példány ellen a kliens teljes hálózati felülete működik, és egy telefonra telepíthető build ráállítható legyen — titok nélkül, dokumentáltan.

## 2. Jelenlegi állapot — mért tények

- A kliens hálózati felülete: `/auth/register`, `/auth/login`, `/auth/me`, `/settings`, `/diagnostics` + a Community repository-k útvonalai (`lib/features/community/data/`).
- `lib/app/config/app_config.dart`: development alapértelmezés `http://10.0.2.2:8000` (emulátor-loopback) — **valódi telefonról nem elérhető**; a `STRUMSIGHT_API_URL` dart-define írja felül.
- `lab_build.json` MÁR létező minta a `--dart-define-from-file` úthoz (a Lab APK ezt használja).
- `backend/` futtatás: `E12-R08` runbook + `Dockerfile`; a `/health`, `/health/live`, `/health/ready` végpont létezik.
- Élő smoke-eszköz **nincs**; `device_build.example.json` **nincs**.

## 3. Scope

**Benne van:** `device_build.example.json` — kitöltendő PÉLDA profil (`STRUMSIGHT_ENV`, `STRUMSIGHT_API_URL`, `STRUMSIGHT_ACCOUNT`, community flagek), titok NÉLKÜL, `.gitignore`-olt valódi párral · `tool/release/live_backend_smoke.py --base-url <URL>` — a teljes kliens-felület végigmérése, emberi-olvasható riporttal és nem-nulla kilépéssel az első eltérésnél · `backend/tests/test_live_smoke_contract.py` — a smoke által elvárt szerződés cellái a beépített teszt-klienssel (hálózat nélkül, CI-ban is fut) · `test/tooling/device_profile_test.dart` — a profil-séma és a „nincs benne titok" invariáns · `docs/operations/device-backend-runbook.md` — az operátori lépések (indítás, elérhetővé tétel, profil kitöltése, build, ellenőrzés, leállítás).

**NINCS benne (tilos):**

- Valódi titok, jelszó vagy token a repóban (a példa-profil placeholder értékeket tartalmaz).
- `lib/**` és `backend/app/**` módosítás.
- Szerver indítása vagy tunnel nyitása a körben.
- `docs/adr/**` — az ADR 0493-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/live_backend_smoke.py` | ÚJ — az élő mérés |
| `device_build.example.json` | ÚJ — profil-sablon (titok nélkül) |
| `docs/operations/device-backend-runbook.md` | ÚJ — operátori lépések |
| `backend/tests/test_live_smoke_contract.py` | a szerződés-cellák hálózat nélkül |
| `test/tooling/device_profile_test.dart` | a profil-séma cellái |

**Tilos zóna:** `lib/**` · `backend/app/**` · `lab_build.json` · `.github/**` · `docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0493)

### 5.1 A profil-fájl SOSEM tartalmaz titkot

A repóban csak `*.example.json` él; a valódi profil gitignore-olt. **NEM elfogadható gyengítés:** „fejlesztői" token beírása a példába.

### 5.2 A smoke az ELSŐ eltérésnél megáll és diagnosztizál

Nem folytat és nem összegez „nagyjából jó" eredményt. **NEM elfogadható gyengítés:** figyelmeztetés-szintre sorolt szerződés-eltérés.

### 5.3 A CI-ban futó cellák hálózat NÉLKÜL mérnek

A szerződést a beépített teszt-kliens méri; az élő futás operátori. **NEM elfogadható gyengítés:** hálózatot igénylő teszt a gate-ben (flaky és a merge-kaput fogná).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A smoke végigméri a kliens TELJES hálózati felületét (auth, settings, diagnostics, community), és minden lépéshez státuszt ad | `test_live_smoke_contract.py` |
| A2 | Szerződés-eltérésnél nem-nulla kilépés, a diff megnevezésével | `test_live_smoke_contract.py` |
| A3 | A példa-profil séma-valid, és NEM tartalmaz titkot | `device_profile_test.dart` + `test/tooling/check_secrets_test.dart` mintái |
| A4 | A runbook lépései sorrendben végrehajthatók, és minden lépéshez tartozik ellenőrző parancs | a dokumentum + a teszt szerkezeti cellája |
| A5 | A gate-ben futó cellák hálózat nélkül futnak le | a §7 gate (offline környezetben) |
| A6 | A kliens `AppConfig` production fail-closed ágai VÁLTOZATLANOK | `test/app/app_config_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A smoke kihagyja a community felületet | A1 |
| Eltérésnél csak figyelmeztet | A2 |
| A példa-profilba valódi token kerül | A3 |
| A szerződés-cella élő hálózatot hív | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** nevezd át az egyik végpontot a szerződés-fixture-ben, futtasd a backend-cellákat → az **A2** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/device_profile_test.dart test/app/app_config_test.dart
```

Backend sáv (külön processzként, hálózat nélkül):

```bash
cd backend && python -m pytest tests/test_live_smoke_contract.py -q
```

## 8. Implementációs sorrend

1. `device_build.example.json` + `test/tooling/device_profile_test.dart`.
2. `backend/tests/test_live_smoke_contract.py` — a szerződés RED-ből.
3. `tool/release/live_backend_smoke.py`.
4. `docs/operations/device-backend-runbook.md`.
5. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Titok-szivárgás.** A profil-fájl a legvalószínűbb hely (A3).
- **Flaky gate.** Hálózatot hívó cella a merge-kapuban (A5).
- **Hamis „működik".** Részleges smoke, ami a community ágat kihagyja (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
