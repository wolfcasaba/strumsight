# ADR 0503 — Élő backend smoke: a mért felület FORRÁSA a szerződés-artefaktum, az eszköz-profil titok-határa gépi

- **Státusz:** Elfogadva
- **Kör:** `E16-R04` (Chapter 16, Kör 4)
- **Dátum:** 2026-09-04
- **Kapcsolódó:** [ADR 0395](0395-community-baseline-feature-flags-and-threat-model-scope.md)
  (Community kill-switch), [ADR 0448](0448-production-signing-policy-and-secret-hardening.md)
  (secret hardening), [ADR 0497](0497-community-router-mounting-and-client-contract-parity.md)
  (kliens↔backend szerződés-paritás), E12-R31 (`tool/release/production_smoke.py`)

## Kontextus — a pre-flight MÉRT tényei (2026-09-04, `main @ 17df4ed7`)

A kör-brief négy premisszája mérésre megdőlt. Mind a négyet a `main` fáján
mértem, nem a brief szövegéből vettem át:

1. **„Élő smoke-eszköz nincs" — TÉVES.** `tool/release/production_smoke.py`
   (E12-R31, 23 484 bájt) létezik, és MA is méri a `/health/ready`,
   `POST /auth/login`, `GET /auth/me`, `GET /settings`, `GET /community/feed`
   utakat, plusz a Lab-route-hiány, a signing-fingerprint és a
   model-manifest ellenőrzéseket. A szerződését hálózat nélkül a
   `backend/tests/test_production_smoke_contract.py` méri egy valódi
   `fastapi.testclient.TestClient`-tel.
2. **„`docs/operations/device-backend-runbook.md` ÚJ" — TÉVES.** A fájl
   létezik és **trackelt** (`git ls-files` → találat), 153 sor, az E15-R12
   köré, §1–§7 szakaszokkal (LAN-bind, IP-keresés, elérhetőség, dart-define,
   end-to-end ellenőrzés, flag-tábla, ismert kliens↔szerver rések).
3. **A kliensnek NINCS feed-repository-ja.** `lib/features/community/data/repositories/`
   három fájlt tartalmaz: `challenge_repository_impl.dart`,
   `profile_repository_impl.dart`, `relationship_repository_impl.dart`.
   A `production_smoke.py` `/community/feed` ellenőrzése tehát egy olyan
   utat mér, amit **a kliens sosem hív**.
4. **A `lab_build.json` — a brief által mintaként hivatkozott precedens —
   TRACKELT, és valódi alakú titkot tartalmaz:**
   `"STRUMSIGHT_DIAG_TOKEN": "lab-qc-6vofaJntx4dRvW9hZRA"`. A profil-fájlba
   szivárgó titok tehát nem hipotetikus kockázat: ezen a fán **már
   megtörtént** egyszer, pontosan ezzel a fájl-mintával.

Egy ötödik mérés a bizonyítási utat érinti:
`test/tooling/check_secrets_test.dart` a scanner SAJÁT tesztje — ideiglenes
repókat épít (`Directory.systemTemp.createTempSync`), és a saját kommentje
mondja ki (181–190. sor), hogy „a git-fa scannelését a build-apk méri — nem
duplikáljuk ide". **Az élő fát tehát nem méri**, így önmagában nem bizonyítja
egyetlen valódi repó-fájl titokmentességét sem.

Végül a mért felület: `docs/contracts/client-backend-endpoints.json`
(E15-R12, ADR 0497 D5) **34** végpontot sorol — 31 `mounted`, 3 `known_gap`
—, mindegyiknél a `lib/**`-beli hívási hellyel. Ez a fán az EGYETLEN
gépi listája annak, mit hív a kliens.

## Döntés

### D1 — A mért felület forrása a szerződés-artefaktum, nem kézzel írt lista

A `tool/release/live_backend_smoke.py` a mérendő végpontok halmazát a
`docs/contracts/client-backend-endpoints.json`-ből **olvassa be**, és nem
tartalmazhat hardkódolt végpont-listát. Minden bejegyzéshez besorolást ad:

- `exercised` — a smoke a bring-up láncban ténylegesen meghívja;
- `not_exercised` — nem hívja, **kimondott, gépileg jelen lévő indokkal**
  (pl. második fiókot igényel, destruktív, előfeltétel-erőforrást kíván);
- `known_gap` — a szerződés szerint szándékosan hiányzó út (ADR 0497 D5);
  a smoke elvárja a `404`-et, és a jelenlétét hibaként jelenti.

**Fail-closed:** ha a szerződés bármely bejegyzése egyik besorolást sem kapja
meg, a smoke nem-nulla kilépéssel áll meg. Így a „a smoke kihagyja a
community felületet" hibaosztály nem elfelejthető, hanem szerkezetileg
lehetetlen: egy új kliens-végpont a szerződésbe kerülve azonnal fedetlenné
teszi a smoke-ot.

**NEM elfogadható gyengítés:** a végpontlista lemásolása a Python fájlba
(az artefaktum ettől elavulhat anélkül, hogy bármi pirosra váltana).

### D2 — Az ELSŐ szerződés-eltérésnél megáll, nem összegez

A bring-up **lánc** (`/health` → `register` → `login` → `/auth/me` →
settings olvasás/írás → community olvasás/írás): egy korai lépés hibája
minden későbbi lépés eredményét értelmetlenné teszi. A smoke tehát az első
eltérésnél nem-nulla kóddal kilép, és megnevezi a diffet (várt vs. mért
státusz/mező/út).

Ez **szándékos eltérés** a `production_smoke.py`-tól, amely minden
ellenőrzést függetlenül futtat (`run_checks`: *„Runs every check
independently — one failing does not skip the rest"*), mert ott a cél egy
deploy teljes képe, nem egy lánc bejárása.

**NEM elfogadható gyengítés:** figyelmeztetés-szintre sorolt eltérés, vagy
„N/M ellenőrzés rendben" összegzés nem-nulla kilépés nélkül.

### D3 — Elhatárolás a `production_smoke.py`-tól: kiegészítés, nem csere

A `live_backend_smoke.py` nem váltja le és nem módosítja a
`production_smoke.py`-t (az a kör TILOS zónájában van). A mért különbség:

| | `production_smoke.py` (E12-R31) | `live_backend_smoke.py` (E16-R04) |
|---|---|---|
| Cél | production/internal-cohort deploy állapota | eszköz-bringup lánca fejlesztői/lab példány ellen |
| Séma | `https` kötelező, fail-closed (exit 2) | `http` is megengedett (LAN/tunnel cél) |
| Fiók | meglévő fiókkal **login** | **register**-rel indul |
| Settings | csak olvasás | olvasás **és** írás (`PUT /settings`) |
| Community | `GET /community/feed`, a `404` PASS | a szerződés kliens-útjai, a `404` HIBA |
| Hibakezelés | minden ellenőrzés függetlenül fut | D2: első eltérésnél megáll |

A közös örökség a **duck-typed kliens**: a `production_smoke.py`
`run_checks()`-e bármit elfogad, ami `.get(path, headers=)` /
`.post(path, json=, headers=)` felületet ad, ezért ugyanaz a kód hajtható
`urllib`-bel élőben és `TestClient`-tel hálózat nélkül. A `live_backend_smoke.py`
ezt a bevált alakot követi — ez a D4 előfeltétele.

### D4 — A gate-ben futó cellák hálózat NÉLKÜL mérnek

A szerződés-cellák (`backend/tests/test_live_smoke_contract.py`) a valódi
`create_app()` köré húzott `TestClient`-tel hajtják ugyanazokat a
függvényeket, amiket a CLI élőben hív. Élő hálózatot igénylő cella a
merge-kapuba nem kerülhet (flaky, és a kaput fogná).

**NEM elfogadható gyengítés:** `skip`-elt vagy hálózatra váró cella.

### D5 — Az eszköz-profil titok-határa GÉPI, nem dokumentált ígéret

1. A repóban csak `device_build.example.json` él, kizárólag placeholder
   értékekkel.
2. A valódi `device_build.json` **gitignore-olt** — a `.gitignore` a kör
   engedélyezett fájlja, pontosan ezért (lásd a brief §0.0 R5 revízióját).
3. Mindkettőt a `test/tooling/device_profile_test.dart` méri az **élő fából**
   (a fájlt beolvasva), nem ideiglenes repóból — a Kontextus 5. pontja
   szerint a `check_secrets_test.dart` erre nem alkalmas.

A mért indok a Kontextus 4. pontja: a `lab_build.json` precedens-fájl
trackelt, és titkot tartalmaz. A doku-szintű „ne írj bele titkot" előírás
ezen a fán **már bizonyítottan nem elég**.

**NEM elfogadható gyengítés:** „fejlesztői" vagy „csak lokális" token a
példa-profilban; a gitignore-szabály elhagyása azzal az indokkal, hogy a
runbook úgyis figyelmeztet rá.

## Következmények

- Egy új kliens-végpont (a szerződésbe felvéve) a smoke-ot azonnal
  fedetlenné teszi → a besorolást pótolni kell. Ez szándékos súrlódás.
- A `known_gap` bejegyzések (`GET /community/challenges*`) a smoke-ban
  **elvárt 404-ként** jelennek meg; ha egy jövőbeli kör megépíti őket, a
  szerződés-paritás cellája (ADR 0497 D5) és a smoke besorolása egyszerre
  jelez.
- A kör `lib/**`-t és `backend/app/**`-t nem módosít: a kliens `AppConfig`
  production fail-closed ágai változatlanok maradnak (A6).
