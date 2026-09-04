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

**Motor:** `sonnet-impl` (Claude Sonnet 5), branch
`sonnet-impl/e16-r04-live-backend-end-to-end`.

### 10.1 Mit épített a kör

Hat fájl, pontosan az `allowed_paths` szerint:

- **`device_build.example.json`** (ÚJ) — placeholder `--dart-define-from-file`
  profil: `STRUMSIGHT_ENV=lab`, `STRUMSIGHT_API_URL` egy dokumentáció-célú LAN
  IP-vel, `STRUMSIGHT_ACCOUNT` + három community flag, mind string érték
  (ahogy a `--dart-define-from-file` megköveteli). Nincs benne
  `STRUMSIGHT_DIAG_TOKEN` — a bring-up láncnak nincs rá szüksége, és minél
  kevesebb kulcs, annál kisebb a titok-szivárgás felülete.
- **`.gitignore`** — KIZÁRÓLAG hozzáfűzés: `device_build.json` +
  `device_build.*.json` (a minta neve is illeszkedik erre a mintára —
  szándékos, ezért a valódi profilt `git add -f`-fel kellett trackelni).
- **`tool/release/live_backend_smoke.py`** (ÚJ) — a `production_smoke.py`
  duck-typed kliens-alakját követő (`.get`/`.post`/`.put`) önálló eszköz.
  `classify_contract()` a `docs/contracts/client-backend-endpoints.json`
  mind a 34 bejegyzését beolvassa és `exercised` (10, a bring-up lánc maga
  hívja) / `not_exercised` (21, kimondott indokkal — jellemzően „második
  fiók kell" vagy „másik alrendszer") / `known_gap` (3, a szerződés saját
  mezője) kategóriába sorolja; besorolatlan bejegyzésnél `main()` a
  hálózati hívás ELŐTT 2-es kóddal kilép (D1). `run_chain()` a láncot az
  ELSŐ eltérésnél megállítja (D2): readiness → register → login → `/auth/me`
  → settings olvasás/írás → community profil create/read/update → community
  `/blocked`/`/muted` → a három `known_gap` út (elvárt 404).
- **`backend/tests/test_live_smoke_contract.py`** (ÚJ) — 6 cella, mind
  `TestClient`-tel, hálózat nélkül (A5): a valódi 34-es szerződés teljes
  besorolás-fedése, fail-closed próba egy szintetikus besorolatlan
  bejegyzésre, `main()` 2-es kilépése hálózat nélkül, a teljes lánc zöld
  futása egy migrált, `env=lab`, `community_enabled=true` appon, a lánc
  megállása az ELSŐ eltérésnél (számlálós kliens bizonyítja, hogy a
  későbbi lépések ténylegesen nem futnak le), és a `known_gap` út
  jelenlétének piros jelzése.
- **`test/tooling/device_profile_test.dart`** (ÚJ) — 7 cella az ÉLŐ fából:
  séma-validáció, a `tool/ci/check_secrets.dart` ÚJRAFELHASZNÁLÁSA
  `Directory.current` ellen (nem temp-repó), `git check-ignore` a valódi
  `.gitignore`-szabály ellen, és a runbook §1–§7 címeinek + az új §8/§9
  jelenlétének strukturális ellenőrzése.
- **`docs/operations/device-backend-runbook.md`** — a meglévő §1–§7
  VÁLTOZATLAN; új **§8** (profil-fájl építése a példából) és **§9** (a live
  smoke futtatása, kilépési kódok) került a végére.

### 10.2 Kötött döntések, amiket a brief nem rögzített

- **A bring-up lánc account-e:** egyetlen, minden futáskor frissen
  regisztrált fiók (`live-smoke-<uuid>@strumsight.app` + random jelszó) —
  nincs `--password-env`, mert nincs mit védeni: a fiók eldobható.
- **`env=lab` a szerződés-cellákban, nem `env=prod`:** az ADR 0503 D3
  táblázata „fejlesztői/lab példány" célt mond; `env=lab` mellett az
  ADR 0449 D1 traffic gate (`_TRAFFIC_GATE_ENVIRONMENTS = {staging, prod}`)
  nem is aktiválódik, és a `community_requires_postgres` ág (csak
  `env=="prod"`-nál mér) sem — így SQLite mellett is tisztán mérhető a teljes
  lánc, hálózat nélkül.
- **10 `exercised` végpont kiválasztása:** minden olyan út, amit EGYETLEN
  fiók valódi hívással bizonyíthat (auth hármas, settings pár, community
  profil hármas, `/blocked`+`/muted`). A social-graph/safety/challenge
  írások mind második fiókot vagy egy előzőleg létrehozott erőforrást
  (challenge id) igényelnek, amihez a szerződésben nincs create-endpoint —
  ezek mind `not_exercised`, kimondott indokkal (részletek a
  `live_backend_smoke.py` `_NOT_EXERCISED` szótárában).
- **A `known_gap` próbák a láncban maradnak, a hitelesített kliensen:** a
  `POST /diagnostics`/`/tutor/**` NEM lett bevonva a láncba (más alrendszer,
  streaming válasz), de a három `known_gap` challenge-út igen — ha egy
  jövőbeli kör megépíti őket a szerződés frissítése nélkül, ez a lánc azonnal
  pirosra vált.

### 10.3 A három valódi-sértés próba (mért, visszaállítva)

**1. Végpont átnevezése a smoke SAJÁT fixtúrájában (NEM az éles JSON-ban) → A2 pirosnak kell lennie.**
A `run_chain()` `/community/blocked` hívási helyét (a hívás ÉS a
`_record` hívás path-ját, a `_EXERCISED_ORDER` besorolási táblát
ÉRINTETLENÜL hagyva) `/community/blocked-renamed-for-breach-probe`-ra
neveztem át, majd:

```
$ python -m pytest tests/test_live_smoke_contract.py -q
FAILED tests/test_live_smoke_contract.py::test_full_chain_passes_against_a_freshly_migrated_lab_app
FAILED tests/test_live_smoke_contract.py::test_known_gap_path_present_turns_the_chain_red_without_running_later_steps
```

Mért diff: `AssertionError: assert [...] == [...] / Right contains 4 more
items, first extra item: 'community_muted'` — a lánc pontosan a
`community_blocked` lépésnél állt meg (404 az átnevezett úton), a
`community_muted` és utána következő lépések (beleértve mindhárom
`known_gap` próbát) NEM futottak le. `test_classify_contract_covers_the_real_contract...`
(A1) ZÖLD maradt — a próba szándékosan csak a láncot, nem a besorolást
érintette. `git checkout -- tool/release/live_backend_smoke.py`-vel
visszaállítva; `git status --short` üres.

**2. Besorolatlan bejegyzés a szerződés-fixtúrában → A1 pirosnak kell lennie.**
A `_NOT_EXERCISED` szótárból ideiglenesen töröltem a
`("POST", "/diagnostics")` bejegyzést (a valódi 34-es szerződésben ez az
út megmarad — csak a Python-oldali besorolás tűnt el):

```
$ python -m pytest tests/test_live_smoke_contract.py::test_classify_contract_covers_the_real_contract_with_no_unclassified_entries -q
FAILED
AssertionError: [EndpointClassification(method='POST', path='/diagnostics',
kind='unclassified', reason='no classification on file for this contract
entry — add one to _EXERCISED_ORDER or _NOT_EXERCISED in
tool/release/live_backend_smoke.py')]
assert 1 == 0
```

`git checkout -- tool/release/live_backend_smoke.py`-vel visszaállítva.

**3. Valódi alakú token a példa-profilba → A3 pirosnak kell lennie.**
`device_build.example.json`-hoz hozzáadtam:
`"STRUMSIGHT_DIAG_TOKEN": "sk-abcdefghijklmnopqrstuvwxyz0123"` (a <!-- strumsight:allow-secret -->
`check_secrets.dart` `providerToken` szabálya szerinti alak). A fenti literál
az ábécé + `0123`, azaz **bizonyítottan nem titok** — a sor végén ezért a
szkenner saját inline markere áll (a Router CI
`tools/tests/test_secret_gate_router_paths.py` cellája ezt írja elő; a
fájl-szintű `allow-secret-file` jelölés itt túl tág lenne):

```
$ flutter test test/tooling/device_profile_test.dart
00:05 +2 -1: ... the live tree has no committed secret in the example profile ... [E]
  Expected: empty
    Actual: WhereIterable<SecretIssue>:[Instance of 'SecretIssue']
  device_build.example.json must contain only placeholder values:
  Secret scan failed (4292 file(s) scanned, 1 finding(s)).
  - device_build.example.json:8: provider token literal
```

A sort eltávolítva visszaállítva; `git diff device_build.example.json`
üres volt a visszaállítás után.

Mindhárom próba után `git status --short` és `git diff --stat` üres volt a
végleges commit előtt — egyik próba sem maradt a fán.

### 10.4 A záró mérce — csonkítatlan kimenet

**`tools/round-gate.sh test/tooling/device_profile_test.dart test/app/app_config_test.dart`** (10 lépés, mind ZÖLD, kilépési kód **0**):

```
═══ [1] format                                                              → ZÖLD
═══ [2] analyze         No issues found! (ran in 6.2s)                      → ZÖLD
═══ [3] test test/tooling/device_profile_test.dart   (+7, All tests passed) → ZÖLD
═══ [4] test test/app/app_config_test.dart          (+21, All tests passed) → ZÖLD
═══ [5] architecture    Architecture dependencies OK (12 allowlisted)       → ZÖLD
═══ [6] secrets         Secret scan OK (4292 file(s) scanned, 0 finding(s)) → ZÖLD
═══ [7] l10n            L10n parity OK (en → hu, 2304 message(s))          → ZÖLD
═══ [8] backend ruff format   140 files already formatted                   → ZÖLD
═══ [9] backend ruff check    All checks passed!                            → ZÖLD
═══ [10] backend pytest       350 passed, 1 xfail (full backend/tests suite) → ZÖLD

MINDEN GATE ZÖLD.
```

**`cd backend && python -m pytest tests/test_live_smoke_contract.py -q`**
(külön processzként, hálózat nélkül, kilépési kód **0**):

```
......                                                                   [100%]
=============================== warnings summary ===============================
tests/test_live_smoke_contract.py::test_full_chain_passes_against_a_freshly_migrated_lab_app
tests/test_live_smoke_contract.py::test_known_gap_path_present_turns_the_chain_red_without_running_later_steps
  .../sqlalchemy/engine/default.py:952: DeprecationWarning: The default
  datetime adapter is deprecated as of Python 3.12; ...
6 passed
```

(`backend ruff format`/`ruff check` a `round-gate.sh` [8]/[9] lépésében már
lefutott a `backend/tests/test_live_smoke_contract.py`-re is — külön
`ruff format backend/app backend/tests` futtatás nem volt szükséges, mert a
gate ezt saját magától, a kör VÉGÉN, a `backend_touched()` észlelés miatt
lefuttatta.)

### 10.5 Amit NEM ez a kör csinált (tudatosan)

- Nem indított élő backendet és nem futtatta a `live_backend_smoke.py`-t
  valódi hálózat ellen (§0.0: az operátori lépés a user dolga).
- Nem módosította a `production_smoke.py`-t, a
  `test_production_smoke_contract.py`-t, a szerződés-JSON-t vagy a
  `lab_build.json`-t — mindhárom TILOS zóna, `git diff --stat
  origin/main..HEAD` üres rájuk.

## 11. Review — a Claude tölti ki
