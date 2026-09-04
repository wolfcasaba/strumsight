# E16-R04 — Élő backend end-to-end: fiók, szinkron, közösség egy eszközön

- **Státusz:** PREPARED (előre megírva 2026-09-02, kód olvasva: `main @ 11d0d2bb`)
- **Típus:** Chapter 16 (Kompozíció és rollout), Kör 4
- **Kör-azonosító:** `E16-R04`
- **Branch:** `<motor>/e16-r04-live-backend-end-to-end`
- **Előfeltétel:** `E15-R12` (a Community routerek felcsatolása) és `E16-R03` merge-elve
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0503`](../adr/0503-live-backend-smoke-contract-source-and-device-profile-secret-boundary.md)
  — a pre-flight foglalta le (§0.0 R1; az előre kiosztott `0493` MÉRTEN ütközött).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "backend account login settings sync community end-to-end device profile"` → **[ADR 0400](../adr/0400-profile-onboarding-service-and-community-gate-ui.md)** (profil-onboarding és Community gate UI) és az `E12-R08` staging-runbookja. A kör ezekre épül: nem új backendet ír, hanem a MEGLÉVŐT teszi egy valódi eszközről használhatóvá és méri.

**Pre-flight visszakeresés (ADR 0312, 2026-09-04, szűkített → teljes):**
`--corpus lessons,halts,adr "live backend smoke tool device profile dart-define secret leak"`
→ **[ADR 0448](../adr/0448-production-signing-policy-and-secret-hardening.md)**
(secret hardening: a tanúsítvány/titok MIBENLÉTÉT gépi mérce nélkül semmi nem
méri — ez a §5.2 mintája). `--corpus lessons,halts "duplicate release tool
overlap existing smoke script scope"` → **`round-status-E12-R31`** (a
`production_smoke.py` köre: „a pre-flight KÉT hamis brief-premisszát cáfolt
meg… a review 3 MAJOR-t mért TELJESEN ZÖLD gate mellett — fail-open ág,
vákuum titok-szivárgási cella, hiányzó séma-kikényszerítés"). Ez a kör
ugyanabban a családban van, ezért a §6.1 mátrix a fail-open és a
vákuum-cella hibaosztályt nevesítve méri.

> ✅ **Pre-flight ELVÉGEZVE (2026-09-04, `main @ 17df4ed7`).** Az `E15-R12`
> MEGTÖRTÉNT: `backend/app/main.py:238–241` felcsatolja a Community routert
> (`if settings.community_enabled: … app.include_router(community_router …)`).
> Az előfeltétel teljesül, a kör indítható. A kód-mérés hat brief-állítást
> döntött meg — lásd a **§0.0.1** revíziókat, azok KÖTELEZŐEK.

## 0.0.1 Pre-flight revíziók — MÉRT tények (2026-09-04, `main @ 17df4ed7`)

A brief 2026-09-02-án készült; hat állítása mérésre megdőlt. Minden alábbi
pont a fán mért, reprodukáló paranccsal együtt. A `brief-lint` (strict) nem
adott leletet — ezek a revíziók a §1 kötelező kód-mérésből jönnek.

**R1 — ADR `0493` → `0503`.** A foglaló (`tools/round-slots.py reserve-adr
--round E16-R04`) **`0503`**-at adott. A `0493` a lemezen szabad, de HÁROM
brief hivatkozik rá (`grep -rln "0493" docs/rounds/` → `e08-r18`, `e16-r01`,
`e16-r04`) — pontosan az az ütközés-osztály, amit a foglaló
(`O_CREAT|O_EXCL`) megelőz, és amit a `tools/tests/test_adr_numbering.py`
mér. A kör ADR-je tehát **0503**, a §5 döntései oda kerültek.

**R2 — a §2 „Élő smoke-eszköz **nincs**" MÉRTEN TÉVES.**
`tool/release/production_smoke.py` (E12-R31, 23 484 bájt) létezik, és MA is
méri a `/health/ready`, `POST /auth/login`, `GET /auth/me`, `GET /settings`,
`GET /community/feed` utakat; a szerződését hálózat nélkül a
`backend/tests/test_production_smoke_contract.py` méri `TestClient`-tel. A
kör terméke tehát **nem** az első smoke, hanem egy elhatárolt, eszköz-bringup
irányú társ — a különbség-tábla az [ADR 0503 D3](../adr/0503-live-backend-smoke-contract-source-and-device-profile-secret-boundary.md).
A `run_checks()` **duck-typed kliens**-alakját (`.get(path, headers=)` /
`.post(path, json=, headers=)`) a kör KÖVESSE: ez teszi az A5-öt (hálózat
nélküli gate-cella) egyáltalán elérhetővé.

**R3 — a §4 „`docs/operations/device-backend-runbook.md` | ÚJ" MÉRTEN
TÉVES.** A fájl létezik és trackelt (`git ls-files
docs/operations/device-backend-runbook.md` → találat), **153 sor**, az
E15-R12 köré, §1–§7 szakaszokkal (LAN-bind, IP-keresés, elérhetőség,
`--dart-define`, end-to-end ellenőrzés, flag-tábla, ismert kliens↔szerver
rések). A kör tehát **KIEGÉSZÍTI**, nem létrehozza: a profil-fájlos
(`--dart-define-from-file`) út és a smoke lépése kerül bele, a meglévő §1–§7
tartalmát **nem törli és nem írja át**. Az A4 ehhez igazodik.

**R4 — az A1 „teljes hálózati felület" forrása gépi artefaktum, nem kézzel
írt lista.** `docs/contracts/client-backend-endpoints.json` (E15-R12,
ADR 0497 D5) **34** végpontot sorol (31 `mounted`, 3 `known_gap`), mindnél a
`lib/**`-beli hívási hellyel — ez a fán az EGYETLEN gépi lista arról, mit hív
a kliens. Két mért következmény:

- A kliensnek **nincs feed-repository-ja** (`ls
  lib/features/community/data/repositories/` → `challenge_`, `profile_`,
  `relationship_`). A `production_smoke.py` `/community/feed` ellenőrzése
  olyan utat mér, amit a kliens sosem hív — a kör NE másolja át.
- A három `known_gap` (`GET /community/challenges`,
  `…/{challenge_public_id}`, `…/{challenge_public_id}/me`) egy egészséges
  szerveren is **404** (ADR 0497 D5). A smoke ezekre a 404-et VÁRJA; a
  jelenlétüket jelenti hibaként.

A besorolási szerződés (`exercised` / `not_exercised` + indok / `known_gap`)
és a fail-closed teljesség az [ADR 0503 D1](../adr/0503-live-backend-smoke-contract-source-and-device-profile-secret-boundary.md).
A szerződés-JSON a kör TILOS zónájában marad: a smoke **olvassa**, nem írja.

**R5 — `.gitignore` felvéve az `allowed_paths`-ba.** A §3 „gitignore-olt
valódi párral" ígéretet tesz, de `grep -n "device_build" .gitignore` → **nulla
találat**, és a `.gitignore` nem volt a listán: az implementer a §3-at H3
nélkül nem tudta volna teljesíteni. A MÉRT indok, hogy ez nem formalitás:
a brief precedensként hivatkozott **`lab_build.json` TRACKELT**
(`git ls-files lab_build.json` → találat), és valódi alakú titkot tartalmaz
(`"STRUMSIGHT_DIAG_TOKEN": "lab-qc-6vofaJntx4dRvW9hZRA"`). A szivárgás ezen a
fán ezzel a fájl-mintával **már megtörtént**. A `.gitignore`-on a kör
KIZÁRÓLAG a `device_build.json` + `device_build.*.json` sorokat fűzheti
hozzá; meglévő sort nem módosít és nem töröl. A `lab_build.json` a TILOS
zónában marad (nem ennek a körnek a dolga).

**R6 — az A3 bizonyíték-hivatkozása félrevezető volt.**
`test/tooling/check_secrets_test.dart` a scanner SAJÁT tesztje: ideiglenes
repókat épít (`Directory.systemTemp.createTempSync`), és a saját kommentje
mondja ki (181–190. sor), hogy az élő git-fa scannelését a `build-apk` méri,
„nem duplikáljuk ide". **Az élő fát tehát nem méri**, így nem bizonyítja a
példa-profil titokmentességét. Az A3 őre ezért a
`test/tooling/device_profile_test.dart` cellája, amely a **valódi**
`device_build.example.json`-t olvassa be a fából, és a `.gitignore` lefedését
is méri (ADR 0503 D5).

## 0.0 Mi gépi és mi emberi

A backend TÉNYLEGES futtatása (a boxon vagy felhőben) és a telefon ráállítása **operátori (user-) lépés** — ugyanaz a kapu, mint a valós gitáros APK-teszt. Az implementer terméke: (a) egy `device_build.json` profil-sablon és a hozzá tartozó dokumentált build-parancs, (b) egy `tool/release/live_backend_smoke.py`, ami egy MEGADOTT URL ellen végigméri a kliens által használt teljes felületet (health → regisztráció → login → `/auth/me` → settings-szinkron → community olvasás/írás), (c) a hibák emberi-olvasható diagnózisa. A kör NEM indít szervert és nem oszt titkot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/release/live_backend_smoke.py",
  "device_build.example.json",
  ".gitignore",
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

> A lenti lista a §0.0.1 R2–R5 revíziói UTÁNI, mért állapot.

- A kliens hálózati felülete **gépi artefaktumként**:
  `docs/contracts/client-backend-endpoints.json` — **34** végpont, 31
  `mounted` + 3 `known_gap`, mindegyiknél a `lib/**`-beli hívási hellyel
  (E15-R12, ADR 0497 D5). Ez az A1 forrása (R4).
- `lib/app/config/app_config.dart`: `devApiBaseUrl = 'http://10.0.2.2:8000'`
  (52. sor, emulátor-loopback) — **valódi telefonról nem elérhető**; a
  `STRUMSIGHT_API_URL` dart-define (`apiUrlDefine`, 47. sor) írja felül. A
  production ág fail-closed elutasítja a loopbackot (143. sor).
- `lab_build.json` MÁR létező minta a `--dart-define-from-file` úthoz (a Lab
  APK ezt használja) — **de TRACKELT és titkot tartalmaz** (R5): mintaként a
  formája követendő, a titok-kezelése NEM.
- `backend/` futtatás: `E12-R08` runbook + `Dockerfile`; a `/health`,
  `/health/live`, `/health/ready` végpont létezik
  (`backend/app/main.py:243–251`). Az E15-R12 óta a Community router
  felcsatolása is mért (`main.py:238–241`) — a kör előfeltétele teljesül.
- **Élő smoke-eszköz VAN** (R2): `tool/release/production_smoke.py` +
  `backend/tests/test_production_smoke_contract.py`. A kör terméke ettől
  elhatárolt társ (ADR 0503 D3), nem az első ilyen eszköz.
- **A runbook LÉTEZIK** (R3): `docs/operations/device-backend-runbook.md`,
  153 sor, §1–§7 — a kör kiegészíti.
- `device_build.example.json` **nincs**; `tool/release/live_backend_smoke.py`
  **nincs**; `backend/tests/test_live_smoke_contract.py` **nincs**;
  `test/tooling/device_profile_test.dart` **nincs**. Ez a négy a kör ÚJ
  terméke.

## 3. Scope

**Benne van:** `device_build.example.json` — kitöltendő PÉLDA profil
(`STRUMSIGHT_ENV`, `STRUMSIGHT_API_URL`, `STRUMSIGHT_ACCOUNT`, community
flagek), titok NÉLKÜL · `.gitignore` — a valódi `device_build.json` +
`device_build.*.json` kizárása, KIZÁRÓLAG hozzáfűzéssel (R5) ·
`tool/release/live_backend_smoke.py --base-url <URL>` — a
szerződés-artefaktumból vezérelt mérés (ADR 0503 D1), emberi-olvasható
riporttal és nem-nulla kilépéssel az első eltérésnél (D2) ·
`backend/tests/test_live_smoke_contract.py` — a szerződés cellái a beépített
teszt-klienssel (hálózat nélkül, CI-ban is fut) ·
`test/tooling/device_profile_test.dart` — a profil-séma, a „nincs benne
titok" invariáns és a `.gitignore`-lefedettség az ÉLŐ fából (R6) ·
`docs/operations/device-backend-runbook.md` — a meglévő §1–§7 KIEGÉSZÍTÉSE a
profil-fájlos build- és smoke-lépéssel (R3).

**NINCS benne (tilos):**

- Valódi titok, jelszó vagy token a repóban (a példa-profil placeholder értékeket tartalmaz).
- `lib/**` és `backend/app/**` módosítás.
- `tool/release/production_smoke.py` és
  `backend/tests/test_production_smoke_contract.py` módosítása — a kör
  elhatárolt társat épít, nem cserél le (ADR 0503 D3).
- `docs/contracts/client-backend-endpoints.json` módosítása — a smoke
  **olvassa**; írása az ADR 0497 D5 paritás-őrét gyengítené.
- A meglévő runbook-szakaszok (§1–§7) törlése vagy átírása; a `.gitignore`
  meglévő sorainak módosítása; `lab_build.json`.
- Szerver indítása vagy tunnel nyitása a körben.
- `docs/adr/**` — az ADR 0503-at a Claude írta meg a pre-flightban.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/release/live_backend_smoke.py` | ÚJ — az élő mérés |
| `device_build.example.json` | ÚJ — profil-sablon (titok nélkül) |
| `.gitignore` | **hozzáfűzés** — `device_build.json`, `device_build.*.json` (R5); meglévő sor nem módosul |
| `docs/operations/device-backend-runbook.md` | **LÉTEZŐ, 153 sor** — kiegészítés a profil + smoke lépéssel (R3) |
| `backend/tests/test_live_smoke_contract.py` | ÚJ — a szerződés-cellák hálózat nélkül |
| `test/tooling/device_profile_test.dart` | ÚJ — a profil-séma cellái |

**Tilos zóna:** `lib/**` · `backend/app/**` · `lab_build.json` ·
`tool/release/production_smoke.py` ·
`backend/tests/test_production_smoke_contract.py` ·
`docs/contracts/client-backend-endpoints.json` · `.github/**` ·
`docs/adr/**` · `tools/**`

## 5. Kötött architekturális döntések ([ADR 0503](../adr/0503-live-backend-smoke-contract-source-and-device-profile-secret-boundary.md))

A teljes szöveg és a mért indoklás az ADR-ben; itt a kötelező összefoglaló.

### 5.1 A mért felület FORRÁSA a szerződés-artefaktum (D1)

A smoke a `docs/contracts/client-backend-endpoints.json` mind a **34**
bejegyzését beolvassa, és mindegyikhez besorolást ad: `exercised` /
`not_exercised` (kimondott indokkal) / `known_gap` (elvárt 404). Ha bármely
bejegyzés besorolatlan marad → **nem-nulla kilépés**. **NEM elfogadható
gyengítés:** hardkódolt végpont-lista a Python fájlban.

### 5.2 A profil-fájl SOSEM tartalmaz titkot (D5)

A repóban csak `device_build.example.json` él, placeholderekkel; a valódi
`device_build.json` gitignore-olt; mindkettőt az **élő fából** mérő Dart
cella őrzi. **NEM elfogadható gyengítés:** „fejlesztői" token a példában,
vagy a gitignore-szabály elhagyása doku-figyelmeztetésre hivatkozva.

### 5.3 A smoke az ELSŐ eltérésnél megáll és diagnosztizál (D2)

Nem folytat és nem összegez „nagyjából jó" eredményt; a diffet (várt vs.
mért út/státusz/mező) megnevezi. **NEM elfogadható gyengítés:**
figyelmeztetés-szintre sorolt szerződés-eltérés, vagy „N/M rendben"
összegzés nem-nulla kilépés nélkül.

### 5.4 A CI-ban futó cellák hálózat NÉLKÜL mérnek (D4)

A szerződést a valódi `create_app()` köré húzott `TestClient` méri — ezért a
smoke a `production_smoke.py` duck-typed kliens-alakját követi (`.get(path,
headers=)` / `.post(path, json=, headers=)`). **NEM elfogadható gyengítés:**
hálózatot igénylő vagy `skip`-elt cella a gate-ben.

### 5.5 Elhatárolás, nem csere (D3)

A `production_smoke.py` érintetlen marad. A különbség-tábla az ADR 0503 D3;
a `/community/feed` ellenőrzése NEM másolható át (a kliensnek nincs
feed-repository-ja, R4).

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték (gépi cella) |
|---|---|---|
| A1 | A smoke a `client-backend-endpoints.json` **mind a 34** bejegyzését besorolja (`exercised` / `not_exercised` + indok / `known_gap`); besorolatlan bejegyzés → nem-nulla kilépés | `test_live_smoke_contract.py` — a cella a szerződést a fájlból olvassa, nem másolt listából |
| A2 | Szerződés-eltérésnél nem-nulla kilépés, a diff megnevezésével, és a lánc **megáll** (a további lépések NEM futnak le) | `test_live_smoke_contract.py` |
| A3 | A példa-profil séma-valid, NEM tartalmaz titkot, ÉS a `.gitignore` kizárja a valódi `device_build.json`-t | `device_profile_test.dart` — az ÉLŐ fából olvas (R6) |
| A4 | A runbook a meglévő §1–§7-et megőrizve tartalmazza a profil-fájlos build- és a smoke-lépést, mindkettőhöz ellenőrző paranccsal | `device_profile_test.dart` szerkezeti cellája (a §1–§7 címek megléte + az új szakaszok) |
| A5 | A gate-ben futó cellák hálózat nélkül futnak le | a §7 gate (offline környezetben) |
| A6 | A kliens `AppConfig` production fail-closed ágai VÁLTOZATLANOK | `test/app/app_config_test.dart` |
| A7 | A `production_smoke.py`, a szerződés-JSON és a `lab_build.json` VÁLTOZATLAN | `git diff --stat origin/main..HEAD` → e három útvonalon üres + gépi scope-audit |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A smoke kihagyja a community felületet | **A1** — a community bejegyzések besorolatlanok maradnak |
| A smoke hardkódolt listát használ a szerződés helyett | **A1** — a cella egy szerződésbe felvett próba-bejegyzést vár besorolva |
| Eltérésnél csak figyelmeztet (nulla kilépési kód) | **A2** |
| Eltérés után is végigfut a lánc | **A2** — a megállás cellája |
| A példa-profilba valódi token kerül | **A3** |
| A `.gitignore` nem fedi a `device_build.json`-t | **A3** |
| A runbook meglévő szakasza törlődik | **A4** |
| A szerződés-cella élő hálózatot hív | **A5** |
| A `known_gap` utakat a smoke hibának veszi (egészséges szerveren bukik) | **A1/A2** — a `known_gap` besorolás cellája |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva), három ág:**

1. Nevezd át az egyik végpontot a szerződés-**fixture**-ben (NEM az éles
   JSON-ban), futtasd a backend-cellákat → az **A2** cellának PIROSNAK kell
   lennie → állítsd vissza.
2. Vegyél fel egy próba-bejegyzést a szerződés-fixture-be besorolás nélkül →
   az **A1** cellának PIROSNAK kell lennie → állítsd vissza.
3. Írj egy valódi alakú tokent a `device_build.example.json`-ba → az **A3**
   cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/device_profile_test.dart test/app/app_config_test.dart
```

Backend sáv (külön processzként, hálózat nélkül):

```bash
cd backend && python -m pytest tests/test_live_smoke_contract.py -q
```

## 8. Implementációs sorrend

1. `device_build.example.json` + `.gitignore` hozzáfűzés +
   `test/tooling/device_profile_test.dart` (A3).
2. `backend/tests/test_live_smoke_contract.py` — a szerződés RED-ből (A1/A2).
3. `tool/release/live_backend_smoke.py` — a `production_smoke.py`
   duck-typed kliens-alakját követve (ADR 0503 D3/D4).
4. `docs/operations/device-backend-runbook.md` — a meglévő §1–§7 UTÁN
   fűzött szakaszok (A4).
5. A három valódi-sértés próba a §10-be.

**A brief §8 a terved — nincs külön task-lista.** Doc-commentben csak
tesztben bizonyított állítás szerepeljen.

## 9. Kockázatok

- **Titok-szivárgás.** A profil-fájl a legvalószínűbb hely (A3).
- **Flaky gate.** Hálózatot hívó cella a merge-kapuban (A5).
- **Hamis „működik".** Részleges smoke, ami a community ágat kihagyja (A1).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
