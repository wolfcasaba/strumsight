# ADR 0486 — Béta-terjesztés, rétegzett tesztelői hozzájárulás és redaktált diagnosztikai csomag

- **Státusz:** elfogadva (2026-09-01, E12-R22 pre-flight)
- **Kontextus:** SDD Chapter 12, Kör 22;
  [`docs/rounds/e12-r22-beta-distribution-and-feedback.md`](../rounds/e12-r22-beta-distribution-and-feedback.md)
- **Kapcsolódó:** [ADR 0447](0447-release-manifest-provenance-and-sbom.md) (release-manifest,
  kanonikus JSON determinizmus — a béta-jegyzet BEMENETE),
  [ADR 0479](0479-privacy-data-inventory-and-consent-enforcement.md) (adat-leltár és
  consent-határ — a tesztelői tájékoztató FORRÁSA),
  [ADR 0481](0481-program-threat-model-and-release-security-scan.md) (release
  security-scan; a `backend/tests/test_security_release.py` importlib-mintája),
  [ADR 0484](0484-privacy-safe-telemetry-contract-and-release-slo-schema.md)
  (privacy-safe telemetria-szerződés)

> **Számozás:** a `docs/execution/pipeline-queue.tsv` E12-R22 sora a Chapter 12
> batch-előkészítésekor a `0461`-et jegyezte elő. A foglaló
> (`tools/round-slots.py reserve-adr --round E12-R22`, ADR 0171 §1.0.1) a
> pre-flightban **0486**-ot adott — a lemezen lévő legmagasabb szám ekkor a
> `0485` (E12-R21) volt. A foglaló a mérvadó (a queue előjegyzése a batch óta
> elavult, ugyanúgy, ahogy az E12-R21-nél a `0460` → tényleges `0485`).

## Kontextus

A Kör 22 kontrollált béta-terjesztést, tájékozott tesztelői hozzájárulást és
reprodukálható, redaktált visszajelzés-csomagot ír elő. A pre-flight MÉRÉS
(2026-09-01, `main @ 1f09d56c`) a következőket adta:

| Mért tény | Hol |
|---|---|
| `DiagnosticsUploader.maxWavBytes = 5 * 1024 * 1024` (= 5 242 880 bájt), a túl hosszú klip **decimálódik** a korlát alá | `lib/features/diagnostics/data/diagnostics_uploader.dart:40,104` |
| A backend a feltöltést **bájtra verbatim** tárolja (`store-bytes`, egy fájl / session + index-sor), tartalmi transzformáció nélkül | `backend/app/routers/diagnostics.py` fejléc + `_unique_session_path` |
| Az `X-Diag-Token` a router saját fejléce szerint **eldobható spam-gate**, nem felhasználói adatot védő titok | `.github/workflows/lab-apk.yml:8-10`, `backend/app/routers/diagnostics.py` |
| A `diagnostics_upload` útvonal 3 leltározott mezője: `ml_dsp_comparison_events (…)`, `audio_clip (raw 16-bit WAV, base64, decimated…)`, `device_metadata (appVersion, device platform string)` — mindhárom `legal_basis: consent`, `leaves_device: true` | `docs/privacy/data-inventory.yaml:80-104` |
| A leltárban **három** útvonalnak van `leaves_device: true` mezője: `account_api` (6), `diagnostics_upload` (3), `share_export` (3); a `tutor_stream` és a `community_media` mezői `false`-ok, az öt `rides:` sor pedig mező nélküli, hivatkozó bejegyzés | `docs/privacy/data-inventory.yaml` |
| A release-manifest **nincs commitolva** — futásidőben áll elő, kulcsai: `schemaVersion`, `app.{version,buildNumber,shortSha,channel}`, `modelPackage.{schemaVersion,manifestSha256,modelCount}`, `knowledgePackage.{schemaVersion,manifestSha256,documentCount}`, `artifacts[].{name,path,sha256}` | `tool/generate_release_manifest.dart:206-272` |
| `tool/release/` MA öt Python eszközt tart (`build_ai_report.py`, `generate_sbom.py`, `security_scan.py`, `verify_artifacts.py`, `verify_signing_policy.py`); `docs/beta/` **nem létezik** | fa |
| Egy Dart tooling-teszt `python3`-ra shell-elve méri a Python eszközöket (`ai_release_report_test.dart`, `release_manifest_test.dart`), egy backend pytest pedig `importlib`-bel tölti be a `tool/release/*.py` modult (`test_security_release.py`) — mindkét minta SZÁLLÍTOTT | `test/tooling/`, `backend/tests/test_security_release.py` |

Ebből két dolog következik, ami a döntéseket írja:

1. **A szerver nem redaktálhat.** A tárolás verbatim, tehát ami a csomagba
   kerül, az már a szerveren is ott van. A redakció egyetlen hatásos helye a
   csomag ÖSSZEÁLLÍTÁSA.
2. **A „Lab mód opt-in" nem hozzájárulás a nyers hangra.** A leltár a
   `ml_dsp_comparison_events`-et és az `audio_clip`-et külön mezőként, külön
   célleírással tartja — a hozzájárulásnak ezt a bontást kell követnie.

## Döntés

### D1 — A nyers hang KÜLÖN, alapból kikapcsolt réteg, két független kapuval

A `tool/release/build_diagnostics_bundle.py` kötelező kapcsolója a
`--consent-diagnostics`; a nyers hang mellékletéhez ezen FELÜL kell a
`--consent-raw-audio`. A rétegek egymást nem helyettesítik:

| Bemenet | Kimenet |
|---|---|
| se `--consent-diagnostics`, se `--consent-raw-audio` | nem-nulla kilépés, **semmilyen** kimeneti fájl nem jön létre |
| csak `--consent-diagnostics` | csomag metaadattal és feature-értékekkel, **hang NÉLKÜL** |
| csak `--consent-raw-audio` | nem-nulla kilépés (a hang-hozzájárulás önmagában nem jogosít fel a csomagolásra) |
| `--consent-diagnostics --consent-raw-audio` | csomag, benne a hang-melléklettel |

**NEM elfogadható gyengítés:** „úgyis opt-in az egész Lab mód, tehát a hang is
mehet"; a hozzájárulás hiányára adott figyelmeztetés a csomagolás folytatásával;
vagy egyetlen, összevont `--consent` kapcsoló.

### D2 — A redakció a csomag összeállításakor történik, REKURZÍVAN, négy osztályra

A redakció a betöltött session-struktúra **minden** mélységi szintjén fut, kulcs-
és sztringérték-szinten egyaránt, mielőtt bármi a kimeneti fájlba kerülne. A
négy osztály és a determinisztikus helyettesítő:

| Osztály | Mit fog meg | Helyettesítő |
|---|---|---|
| token | a `token` részsztringet tartalmazó kulcsok értéke (`diagToken`, `X-Diag-Token`, `authToken`, …), kis/nagybetűtől függetlenül | `[REDACTED:token]` |
| e-mail | e-mail alakú részsztring BÁRMELY sztringértékben, nem csak `email` nevű kulcsban | `[REDACTED:email]` |
| fájl-útvonal | abszolút POSIX (`/…`) és Windows (`C:\…`) útvonal-alakú részsztring | `[REDACTED:path]` |
| eszköz-azonosító | a `deviceId`, `device_id`, `androidId`, `installId`, `udid` kulcsok értéke | `[REDACTED:device-id]` |

A `device_metadata` **platform-sztringje** (`appVersion`, `device`) NEM
redaktálandó: a leltár szerint pontosan a build/platform-korreláció a célja, és
nem azonosít eszközpéldányt.

A helyettesítő állandó sztring: nincs só, nincs hash, nincs sorszám — a
determinizmus (D4) ezen áll.

**NEM elfogadható gyengítés:** szerver-oldali „majd ott maszkoljuk" ág; csak a
legfelső szintre futó redakció; csak kulcsnév-alapú e-mail-keresés; a mintát nem
találó bemenet néma átengedése.

#### D2.1 kiegészítés (a kör review-ja után, 2026-09-01) — a redakció SZÖVEGES mezőkre fut

**Mérve (E12-R22 review, M1):** a base64 ábécé tartalmazza a `/` karaktert, ezért
az abszolút-útvonal minta belemar a `wavBase64` tartalmába, és a consentelt klipet
`exit 0` mellett, csendben megsemmisíti (mért eset: 117 660 → 189 karakter, a
kimenet nem dekódolható). Ez pontosan a D3 tiltotta néma csonkítás lett volna, egy
másik ajtón.

Ezért: az **opaque bináris payload mezők** (a `wavBase64` és a jövőbeli, ugyanilyen
természetű mezők) NEM esnek sztring-redakció alá. Helyettük a csomagoló
**integritás-ellenőrzést** végez: a kimeneti klip base64-ként dekódolható, és a
dekódolt bájthossza megegyezik a bemenetivel — eltérés esetén **nem-nulla kilépés**,
nem csendes kiírás.

Ennek az ára nevesített és vállalt: egy base64-be csomagolt titok nem redaktálódik
(eddig sem redaktálódott — a redakció a base64 szövegére futott, nem a tartalmára).
A hang-melléklet védelme a rétegzett consent (D1) és a méret-korlát (D3), nem a
mintaillesztés.

**A kulcsokra** a redakció ugyanúgy fut, mint az értékekre (D2 első mondata): a
token/device-id osztályozás UTÁN a kulcs sztringje is átmegy az e-mail/útvonal
maszkoláson. Két különböző kulcs azonos maszkra képződése ütközés → `BundleError`,
mert a D4 tiltja a megkülönböztető utótagot (só/hash/sorszám).

### D3 — A méret-korlát INKLUZÍV, a túllépés HIBA, nem csonkolás

A nyers hang melléklet korlátja a MÉRT `DiagnosticsUploader.maxWavBytes`
= **5 242 880 bájt**, a határ **inkluzív**. A korlát fölötti melléklet
nem-nulla kilépést ad, hibaüzenettel, és kimeneti fájl nem keletkezik.

Ez SZÁNDÉKOSAN más viselkedés, mint a kliensé: az uploader decimál (a klip
minősége áldozható), a csomagoló viszont diagnosztikai bizonyítékot állít elő,
ahol a néma csonkítás hibás következtetést okoz.

**NEM elfogadható gyengítés:** csendes csonkolás; figyelmeztetés melletti
folytatás; a korlát exkluzívra vagy „~5 MB"-ra lazítása.

#### D3.1 kiegészítés (a kör review-ja után, 2026-09-01) — a hang-réteg és a korlát TARTALOM-alapú

**Mérve (E12-R22 review, M2):** a legfelső szintű `audioClips` kulcsnévre álló
gate mellett egy `events[0].wavBase64`-be helyezett 8 MB-os klip CSAK
`--consent-diagnostics` mellett bekerült a csomagba, és a méret-korlát rá sem
futott. A szállított kliens ma fix, legfelső szintű kulcsot ír, tehát a rés
latens — de a csomagoló bemenete a szerveren VERBATIM tárolt, tetszőleges JSON.

Ezért a hang-réteg gate-je és a méret-korlát is **rekurzív, tartalom-alapú**:
a csomagoló minden mélységben megkeresi a hang-payload mezőket,
`--consent-raw-audio` nélkül MINDET eltávolítja, és a korlátot az összes
megtalált klip **összegére** alkalmazza.

Ugyanide tartozik a **bemenet-méret** korlátja: a gzip-kicsomagolás nem futhat
felső korlát nélkül (mérve: 2 MB-os feltöltés 2 GB-ra bomlik, `MemoryError`).
A korlát MÉRT konstansból vezetendő le, nem találgatásból.

**NEM elfogadható gyengítés:** kulcsnév-alapú hang-gate; a korlát csak az egyik
lelőhelyre; korlátlan dekompresszió.

### D4 — A csomag és a béta-jegyzet is determinisztikus, időbélyeg NÉLKÜL

Mindkét eszköz kimenete két futás közt bájtazonos ugyanazon a bemeneten. A
csomag JSON-ja kanonikus: minden szinten növekvő kulcsrendezés, UTF-8, egyetlen
záró `\n` — ugyanaz a szerződés, amit az [ADR 0447](0447-release-manifest-provenance-and-sbom.md)
D1 a release-manifestre kimond. Sem a csomagban, sem a jegyzetben nincs
generálási időbélyeg, gépnév, abszolút útvonal vagy környezetfüggő formázás.

**NEM elfogadható gyengítés:** „generated at …" sor; a bemenet bejárási
sorrendjétől függő kimenet; locale-függő szám- vagy dátumformázás.

### D5 — A béta-jegyzet a release-manifesthez KÖTÖTT és fail-closed

A `tool/release/generate_beta_notes.py` egyetlen igazságforrása az
[ADR 0447](0447-release-manifest-provenance-and-sbom.md) release-manifest JSON-ja,
a Kontextus táblájában felsorolt, MÉRT kulcsokkal. A jegyzet kötelezően
tartalmazza a build-azonosítót — `app.version`, `app.buildNumber` és
`app.shortSha` mindhármát —, valamint a `app.channel` értéket.

Hiányzó vagy rossz típusú kötelező kulcs → nem-nulla kilépés, üres/`unknown`
mezővel való továbbmenetel helyett.

**NEM elfogadható gyengítés:** kézzel szerkesztett jegyzet build-azonosító
nélkül; a manifest-kulcsok kitalálása; hiányzó kulcs helyettesítése
alapértelmezéssel.

### D6 — A tesztelői tájékoztató a leltár GÉPI tükre

A `docs/beta/tester-consent.md` egy gépileg olvasható blokkot tart
(`<!-- data-inventory-crosscheck:begin -->` … `:end`, az
`ai_release_report_test.dart` marker-mintája szerint), amely felsorolja a
`docs/privacy/data-inventory.yaml` MINDEN olyan útvonalát, amelynek van
`leaves_device: true` mezője, és minden ilyen mező `name` értékét — szó szerint.

A kereszt-ellenőrzés KÉTIRÁNYÚ: hiányzó sor és a leltárban nem létező
(kitalált) sor egyaránt piros. A leltárt a teszt nem újraparszolja: a
szállított `tool/check_data_inventory.dart` `DataInventory.parseFile`-ját
importálja (kettős igazság elkerülése, ADR 0485 D1 indoklásával azonos okból).

**NEM elfogadható gyengítés:** prózai összefoglaló gépi cella nélkül;
egyirányú (csak dokumentum → leltár) ellenőrzés; a leltár-parszer második
implementációja.

### D7 — Ez a kör csatornát és csomagot szállít, felületet NEM

`lib/**`, `.github/**` és `lab_build.json` érintetlen. A `beta-release.yml`
RC-workflow a Kör 25-é, a cohort-profil (`docs/beta/cohort-profiles.yaml`,
`tool/release/verify_beta_profile.py`) a Kör 27-é — ez a kör egyiket sem előlegzi
meg. A `lib/features/feedback/` felület **nevesített hiány**, a Chapter 13/15 sáv
pótkörébe tartozik (a brief §0.0 indoklásával: a `test/ui/ui_inventory_test.dart`
egzakt képernyőszámot pinnel).

**NEM elfogadható gyengítés:** „egy pici képernyő belefér"; a `lab_build.json`
hozzáigazítása; új CI-workflow.

## Következmények

- A béta-visszajelzés útja auditálható: a csomagban lévő minden mező vagy a
  leltárban szerepel, vagy redaktált.
- A redakció felelőssége EGY helyen van (a csomagoló), így egy jövőbeli
  szerver-oldali változás nem tudja csendben visszavonni.
- A determinizmus miatt két tesztelői beküldés diffelhető: a különbség tartalmi,
  nem generálási zaj.
- Ára: a csomagoló a kliens decimáló viselkedésétől ELTÉR (D3) — ezt a
  `docs/beta/feedback-triage.md`-nek ki kell mondania, hogy a triage tudja,
  a méret-hiba nem adatvesztés, hanem visszautasítás.
- A `docs/beta/tester-consent.md` mostantól a leltár változásaira érzékeny: egy
  új `leaves_device: true` mező a dokumentumot pirosra váltja, amíg át nem írják.
  Ez SZÁNDÉKOS.
