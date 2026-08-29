# E12-R17 review — Privacy adat-leltár és consent enforcement

- **Kör:** `E12-R17` · **Ág:** `sonnet-impl/e12-r17-privacy-data-inventory-and-consent-enforcement`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5, orchestrátor) + kötelező `security-reviewer` (kockázat = high)
- **ADR:** [`0479`](../adr/0479-privacy-data-inventory-and-consent-enforcement.md)
- **Pre-flight commit:** `0fbbbad5` · **Implementációs diff #1:** `0fbbbad5..53db4db1` (6 fájl, +1701)

## 1. Kör #1 — VERDIKT: CHANGES REQUESTED (feloldva a javító körben, §3)

**3 MAJOR / 5 MINOR / 0 BLOCKER.** A zöld gate NEM volt elég: mindhárom MAJOR a
kör SAJÁT deklarált célját sérti („hamis biztonságérzet elkerülése"), és
mindhárom javítható a tiltott `lib/**` zóna érintése nélkül.

**Ami a kör #1-ben MÉRHETŐEN JÓ volt** (és a javító körben nem romolhat el):

- A checker valóban a FÁBÓL indul, nem a leltárból (ADR 0479 D1) — a
  falszifikációs cellák (fantom-route, stale `wired: true`) valódiak.
- Az A3 a TURN-ÚTON mér, gateway-számlálóval — nem képernyő-renderrel
  ([L140](../LESSONS.md#l140) helyesen alkalmazva).
- Az A4/A6(diagnostics) és az A5'(Community-profil) cellák a VALÓDI
  transport-határon mérnek (`_WireProbe implements HttpClientAdapter`),
  pozitív kontrollal (bejelentkezve/consenttel 1 kérés átmegy).
- A leltár őszinte ott, ahol nem mérhető („not measurable yet — no production
  construction site").
- Független ellenőrzés: `dart run tool/check_data_inventory.dart` →
  `Data inventory check OK (4 measured egress route(s), 4 inventory route(s))`, exit 0.
- Scope: pontosan a hat engedélyezett fájl (`scope-audit.py` →
  `Legacy scope audit OK (6 changed path(s))`).
- Full Gate `33246586867` a `53db4db1` SHA-n: **success**.

### MAJOR-1 — a leltár kihagy egy ÉLŐ, eszközt elhagyó utat: `ShareService` (share_plus)

`lib/features/share/share_service.dart:7,74,84,102,138`, hat hívóhellyel.
`pubspec.yaml:39` → `share_plus: ^13.2.0`. Az orchestrátor újramérte:
`grep -rnE "package:http/|HttpClient\(|WebSocket|webview_flutter|url_launcher|share_plus" lib`
→ ez az EGYETLEN nem-Dio egress a fán. A `discoverEgressRoutes` három
mintaosztálya közül egyik sem fedi, a leltár négy route-ja mind HTTP — a checker
tehát ZÖLDEN állít teljességet egy olyan úton, amely a redaktált exportot /
PNG-t tetszőleges idegen alkalmazásnak adja át. A brief §3 hatóköre kifejezetten
tartalmazza („elhagyja-e az eszközt").

### MAJOR-2 — a teljesség-ellenőrzés csak TRANSZPORTOT lát, adatmezőt nem

`tool/check_data_inventory.dart:347-382` kizárólag `Dio`-típusú tagot keres. A
fán MA hat `ApiClient`-fogyasztó küldő van (`auth_repository`,
`settings_repository`, `diagnostics_uploader`, és a három Community repository)
— egyik sem „felfedezett route". A `security-reviewer` eldobható klónban
hozzáadott egy új `ApiClient`-alapú, e-mailt küldő repositoryt → a checker
`OK`-t adott, exit 0. A brief §5.1 ezt nevesítve „NEM elfogadható gyengítés"-nek
nevezi: a codebase leggyakoribb küldő-alakjára az A2 cella nem tud pirosra
váltani.

### MAJOR-3 — a tutor consent-kapcsoló nincs bekötve a turn-útra

`lib/features/ai_tutor/presentation/providers/tutor_providers.dart:414,433,438`:
a production `_previewTurnRequest` konstans `consent: const TutorConsent(modelUseGranted: true)`-t
ad, és `grep -rn "tutorConsentControllerProvider" lib` szerint a
consent-controllert a request-építő SOHA nem olvassa (csak a privacy-képernyő).
A `TutorConsentController.build()` alapértéke minden tengelyen `false`. Tehát a
`reduceTutorTurn` kapuja (`tutor_orchestrator.dart:47`) valós felhasználói
visszavonást soha nem lát.

Ez ma **nem** szivárgás — a tutor cloud gateway bekötetlen
(`createProductionTutorOrchestrator` → `LocalTutorModelGatewayStub`,
`tutor_providers.dart:376`), ezért **nem** a brief STOP-protokollja alkalmazandó
(az MÉRT szivárgáshoz köti a `stopped`-ot), és a besorolás MAJOR, nem BLOCKER.
A `consent-enforcement.md:39-44` jelenlegi mondata („a fenti consent-kapu az,
ami a VALÓDI felhő-hívást meg fogja állítani") viszont **félrevezető**, és a
kör célja szerint javítandó — a `lib/**` javítása önálló kört érdemel.

### MINOR-ok (mind mérve, részletek a javító kör leletlistájában)

| # | Lelet | Hely |
|---|---|---|
| MINOR-1 | A fa-bejáró átcsúszik reális alakokon (`.patch`/`.download`/`.postUri`/`extension`/`mixin`/`typedef`); **P10:** egy „class" szót tartalmazó komment kettévágja az osztálytörzset és eltünteti a valódi küldőt | `check_data_inventory.dart:302-312` |
| MINOR-2 | A `dio_factory.dart`/`api_client.dart` teljes kizárása lyuk: nyers `Dio`-t visszaadó factory-metódus láthatatlan | `:282-293`, `:295` |
| MINOR-3 | Fail-open a privacy-kritikus logikai mezőn: `leaves_device: True` némán `false` | `:183`, `:202` |
| MINOR-4 | A `wired: false` állítás gépileg ellenőrizetlen (nincs konstrukciós-hely mérés) | `:504-515` |
| MINOR-5 | Az on-device TÁROLT adat (56 kulcs a `storage_keys.dart`-ban) nincs leltározva, pedig a brief §3 hatóköre tartalmazza | `data-inventory.yaml` |

### NOTE-ok (nem blokkolnak)

- Az A5'(settings-sync) cella a repository-hívásokon mér, nem a wire-en — helyes
  „belt-and-braces" második őr, csak a fájl fejlécének „turn/wire path"
  általánosítása pontatlan rá. A másik A5' cella VALÓDI wire-mérés.
- Titok-szivárgás a diffben: **nincs** (`devDiagnosticsToken` a
  `'strumsight-lab-dev'` placeholder, amit `app_config.dart:165` prodban
  elutasít; base URL az emulátor-loopback).
- WebView / `url_launcher` / socket / analytics / crash-reporting / plugin-csatorna
  egress: **nem létezik** a fán (mérve, 0 találat).

## 2. Javító kör #1

Leletlista átadva az implementernek (ugyanaz a motor, ugyanaz az ág), a
`lib/**` tilalom nyomatékosítva: a MAJOR-3 kimenete leltár- és
dokumentum-őszinteség + **gépi őr**, nem `lib/**`-javítás.

## 3. Javító kör #1 utáni ellenőrzés — VÉGSŐ DÖNTÉS: APPROVED

**Diff:** `53db4db1..fd6d0d3e` (1 commit). Összesen a pre-flight óta:
`0fbbbad5..fd6d0d3e`, 6 fájl, +3093 sor.
**Scope:** `Legacy scope audit OK (6 changed path(s))` — az engedélyezett lista
NEM tágult, `lib/**` érintetlen.

A reviewer NEM bemondásra fogadta el a javításokat: eldobható klónban
(`scratchpad/probe-verify`) újrafuttatta azokat a MÉRÉSEKET, amelyek a kör #1-et
megbuktatták. Kiindulás: `Data inventory check OK (11 measured egress route(s),
11 inventory route(s))` — a kör #1-ben ez 4 volt.

| Próba | Mit injektált a reviewer | Kör #1 (mért) | Kör #2 (mért) |
|---|---|---|---|
| **A — MAJOR-2** | ÚJ `ApiClient`-alapú küldő (`HttpPracticeLogRepository`, e-mailt POST-ol) | `OK`, exit 0 ❌ | `failed … "HttpPracticeLogRepository" … has no data-inventory.yaml entry`, **exit 1** ✅ |
| **B — MAJOR-1** | ÚJ `share_plus` egress (`SneakyExporter` → `SharePlus.instance.share`) | láthatatlan ❌ | `failed … "SneakyExporter" …`, **exit 1** ✅ |
| **C — MINOR-3** | `leaves_device: True` (nagybetűs YAML-igaz) | némán `false`, `OK` ❌ | `FormatException: … must be exactly "true" or "false", got "True"`, **exit 2** ✅ |
| **D — MINOR-1** | `.patch` ige + „class" szót tartalmazó komment az osztálytörzsben (P10) | láthatatlan ❌ | `failed … "CommentSplitUploader" …`, **exit 1** ✅ |

**MAJOR-3 (tutor consent szakadás)** — a `lib/**` érintése nélkül, helyesen
feloldva:
- `data-inventory.yaml` `tutor_stream.gate`/`consent_switch`: kimondja a MÉRT
  szakadást (`_previewTurnRequest` … `tutor_providers.dart:433,438` konstans
  `modelUseGranted: true`, a `tutorConsentControllerProvider` sosem olvasva),
  és kimondja azt is, hogy ez ma miért NEM szivárgás.
- `consent-enforcement.md`: a korábbi félrevezető mondat javítva.
- **Gépi őr:** `test/privacy/consent_enforcement_test.dart:357-395` — pinneli
  mindkét mért tényt, tehát PIROSRA vált abban a pillanatban, amikor valaki
  bekötí a cloud transportot a request-építő javítása nélkül.

**MINOR-5** deklarált korláttá vált (nem csendes vakfolt): a
`data-inventory.yaml` fejléce (`:27-33`) és a `consent-enforcement.md`
kimondja, hogy a dokumentum az EGRESS utakat fedi, az on-device tárolt adat
(56 kulcs a `storage_keys.dart`-ban) pedig nevesített követő feladat.

Az `S1`-ként nem záruló, továbbvitt tétel: **a `_previewTurnRequest` `lib/**`
javítása önálló kört érdemel** (a leltár és az őr most kikényszeríti, hogy ne
felejtődjön el).

### Acceptance-teljesítés

| Cella | Állapot | Bizonyíték |
|---|---|---|
| A1 | ✅ | `data_inventory_test.dart` A1 csoport + két falszifikációs cella |
| A2 | ✅ | fa-bejárás 11 route-tal; a reviewer A/B/D próbái pirosra váltották |
| A3 | ✅ | turn-úton, gateway-számlálóval (L140) |
| A4 | ✅ | `_WireProbe` (`HttpClientAdapter`), pozitív kontrollal |
| A5' | ✅ | account-session visszavonás → Community-profil írás nem éri el a wire-t |
| A6 | ✅ | mindhárom csatorna, ugyanabban a `ProviderContainer`-ben, újraépítés nélkül |
| A7 | ✅ | `ui_inventory_test.dart` `hasLength(96)` változatlan; a kör `lib/**`-ot nem érint |
