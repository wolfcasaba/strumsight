# E12-R17 — Privacy data inventory és consent enforcement

- **Státusz:** READY (pre-flight lefutott 2026-08-29, `main @ 34aff7fd`; előre megírva 2026-08-27, `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 17
- **Kör-azonosító:** `E12-R17`
- **Branch:** `<motor>/e12-r17-privacy-data-inventory-and-consent-enforcement`
- **Előfeltétel:** `E13-R35` merge-elve (a Consent Center FELÜLETE ott készül el — ez a kör a mögötte lévő adat-leltárt és kényszerítést méri)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** [`ADR 0479`](../adr/0479-privacy-data-inventory-and-consent-enforcement.md) — a `tools/round-slots.py reserve-adr` foglalótól (§0.0.1). Az előre kiosztott `0457` **elavult**.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "privacy data inventory consent enforcement revoke export deletion"` → **[ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)** (export/share/delete szerződés) és **[ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)** (Tutor privacy & consent). A leltár ezekre a MÉRT szerződésekre épül; új consent-fogalmat nem vezet be.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** mérd meg a MEGLÉVŐ consent-hordozókat (`lib/features/ai_tutor/domain/models/tutor_consent.dart`, `lib/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart`, `lib/features/settings/screens/vision_privacy_screen.dart`, `lib/features/diagnostics/data/diagnostics_uploader.dart`) és nézd meg, mit hozott az E13-R35 Consent Center köre. A leltárnak a MÉRT állapotot kell tükröznie.

## 0.0 A felület NEM ennek a körnek a dolga

A Consent Center és a privacy-felület a Chapter 13 sáv terméke (E13-R35). Ez a kör a felület MÖGÖTTI igazságot méri: (a) minden adatmezőnek van-e célja, retentionje és jogalapja, (b) a consent visszavonása AZONNAL leállítja-e az adott adatáramlást. Új képernyőt tehát NEM hoz létre — a `test/ui/ui_inventory_test.dart` egzakt képernyőszáma nem mozdulhat.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "docs/privacy/data-inventory.yaml",
  "docs/privacy/consent-enforcement.md",
  "tool/check_data_inventory.dart",
  "test/privacy/consent_enforcement_test.dart",
  "test/tooling/data_inventory_test.dart",
  "docs/rounds/e12-r17-privacy-data-inventory-and-consent-enforcement.md",
]
gate_tests = [
  "test/privacy/consent_enforcement_test.dart",
  "test/tooling/data_inventory_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör tárgya közvetlenül adatvédelmi határ (consent, retention, hálózatra kerülő adat) — egy hibás cella hamis biztonságérzetet adna arról, hogy egy visszavont hozzájárulás tényleg leállította az adatküldést. A `security-reviewer` futtatása a review-ban KÖTELEZŐ.

## 0.0.A Pre-flight revízió — MÉRT javítások (2026-08-29, `main @ 34aff7fd`)

A brief 2026-08-27-én készült; az alábbi állításait a pre-flight ÚJRAMÉRTE, és
ahol a fa mást mond, a fa nyer. **A mérvadó szöveg ez a szakasz.**

### 0.0.A.1 ADR-szám: `0457` → **`0479`**

A `tools/round-slots.py reserve-adr --round E12-R17` foglaló **`0479`**-et adta
(§1.0.1: a foglalótól kérünk számot, nem `ls`-sel). A `0457` a 2026-08-27-i
batch-előosztás maradéka; a Chapter 12 sáv azóta `0477`-ig fogyott. Az ADR a
`docs/adr/0479-privacy-data-inventory-and-consent-enforcement.md`.
(Megjegyzés: egy második, ellenőrző foglaló-hívás `0480`-at is lefoglalt — az
**nem használt**, a számozásban keletkező rés ártalmatlan.)

### 0.0.A.2 A kibocsátási felület — MÉRVE négy út, ebből kettő élő

| # | Út | Kapu | Élő ma? |
|---|---|---|---|
| 1 | `DioFactory.createAccountClient` — Account API | `accountEnabled` + auth session-generáció | **igen** |
| 2 | `DioFactory.createDiagnosticsClient` — Diagnostics upload | `diagnosticsEnabled` **és** `diagnosticsConsentProvider` | **igen** |
| 3 | `HttpTutorStreamTransport` — `POST /tutor/stream` (SSE) | `TutorConsent.modelUseGranted` a turn-úton | **nem** — nincs konstrukciós hely a `lib/**`-ban |
| 4 | `CommunityMediaUploader` — presigned PUT | — | **nem** — „a HTTP wiring Kör 19+ feladat" |

A 3. és 4. út **injektált** `Dio`-t fogad, tehát NEM a `DioFactory`-n megy át. A
meglévő `test/tooling/dio_factory_guard_test.dart` csak a `Dio(`
konstruktor-hívást tiltja — egy injektált klienst fogadó transportot nem lát.
Ez pontosan az [L140](../LESSONS.md#l140) vakfoltja, és ez a kör MÉRCÉJE: a
checker fa-bejárásának mindhárom mintaosztályt fel kell ismernie (ADR 0479 D1).

### 0.0.A.3 A visszavonási kapcsolók — és **A5 ÁTÍRVA**

MÉRT kapcsolók a fán:

| Csatorna | Kapcsoló | Kikényszerítés (mért hely) |
|---|---|---|
| Tutor | `TutorConsent.modelUseGranted` | `tutor_orchestrator.dart:47`, `local_tutor_fallback.dart:120` |
| Diagnostics | `diagnosticsConsentProvider` (default `false`) | `diagnostics_providers.dart` + `diagnostics_uploader.dart:52` |
| Account-hátterű írás-utak (settings sync **és a Community repók**) | auth session-generáció | `_AuthSessionGeneration.advance()` + `_AuthSessionCredentials.clear()`; olvasva: `auth_interceptor.dart:50,73` |

**MÉRT tény:** `grep -rn "consent\|Consent" lib/features/community/` → **0
találat**. Community-specifikus, kliensoldali consent-kapcsoló NEM létezik. A
brief által hivatkozott `e09_r04_0004_community_privacy_fields.py` **backend**
profil-láthatósági mező, és a `backend/**` ennek a körnek tiltott zónája.

Az eredeti **A5** („Community-consent visszavonása után a közösségi írás-út nem
küld") tehát **kimérhetetlen**: teljesítéséhez vagy `lib/**`-módosítás (tiltott
zóna, H3), vagy ÚJ consent-fogalom bevezetése (a §3 kifejezetten tiltja)
kellene. A §1 mérési szabálya szerint ezt **brief-revízióval** oldjuk fel, nem
lista-tágítással. Az A5 új szövege (§6-ban is átvezetve):

> **A5' —** Az account-session visszavonása (logout / `invalidateSession`) után
> a **Community írás-út** (`challenge`/`profile`/`relationship` repók) és a
> settings-sync **NEM küld**. A cella a MÉRT kapcsolón mér — a session-generáció
> léptetésén —, mert a fán MA ez a Community írás-útra ténylegesen ható
> visszavonás.

A kör intenciója változatlan (három FÜGGETLEN csatorna, azonnali hatályú
visszavonás); csak a harmadik csatorna kapcsolója lett a valóban létezőre kötve.

### 0.0.A.4 Elavult §2-állítások javítása

| §2 állítás | MÉRT valóság |
|---|---|
| `ui_inventory_test.dart` … `hasLength(94)` | **`hasLength(96)`** (`test/ui/ui_inventory_test.dart:26`) — a szám nem mozdulhat (A7) |
| „a `tool/ci/` fa védett — `protect_factory_files.py` `PROTECTED_GLOBS`" | `tools/protect_factory_files.py` **nem létezik**, és az `ADR 0321` nem erről szól (`0321-gateguard-round-hold-not-chain-halt.md`). A `tool/` gyökér mint cél ettől függetlenül ÁLL: a `tool/check_architecture.dart` / `tool/check_screen_reachability.dart` a bevett minta. |
| `docs/privacy/` egy dokumentum | ÁLL (`practice-planning-data.md`) |
| `AppConfig.usesNetwork => accountEnabled \|\| diagnosticsEnabled` | ÁLL (`lib/app/config/feature_flags.dart:302`) |

### 0.0.A.5 Visszakeresés (ADR 0312)

`--corpus lessons,halts,adr`: **[L140](../LESSONS.md#l140)** (a döntő lecke — az
egress-próba VAK a feature saját transportjára), **[ADR 0132](../adr/0132-ai-tutor-privacy-and-consent.md)**
(consent-boundary, azonnali hatály), **[ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)**
(export/delete szerződés). Teljes korpusz: `tool/ci/check_assets.dart` mint
YAML-olvasó minta.

### 0.0.A.6 A tooling-teszt MÉRT mintája

`test/tooling/screen_reachability_test.dart:5` a checkert **könyvtárként
importálja** (`import '../../tool/check_screen_reachability.dart';`), nem
shellel ki `dart run`-nal. A `data_inventory_test.dart` ugyanezt kövesse — a
checker tehát tesztelhető belépési pontot exportáljon, ne csak `main()`-t.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy cella MÉRT szivárgást talál (visszavont consent mellett is megy adat), a kimenet a `stopped` jelzés és jelentés — a `lib/**` javítása ebben a körben TILOS, mert a javítás önálló, review-zott kört érdemel.

## 1. Cél

Géppel olvasható adat-leltár minden feature-höz, és MÉRT bizonyíték arra, hogy a hozzájárulás visszavonása azonnal érvényre jut.

## 2. Jelenlegi állapot — mért tények

- `docs/privacy/` MA **egy** dokumentumot tartalmaz (`practice-planning-data.md`) — teljes leltár nincs.
- Consent-hordozók a fán: `tutor_consent.dart` (AI Tutor), `tutor_privacy_providers.dart`, `vision_privacy_screen.dart` (Vision), `diagnostics_uploader.dart` (Lab-diagnosztika), és a Community privacy-mezői (`e09_r04_0004_community_privacy_fields.py` migráció).
- `test/privacy/` **nem létezik**; `tool/check_data_inventory.dart` **nem létezik** (a `tool/ci/` fa a MÉRCE védett zónája — ADR 0321/0372, `protect_factory_files.py` `PROTECTED_GLOBS` —, ezért az ÚJ ellenőrző a `tool/` gyökérbe kerül, a `tool/check_architecture.dart` mintájára).
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel (`hasLength(94)` a megíráskor) — ez a kör NEM mozdíthatja el.
- `AppConfig.usesNetwork => accountEnabled || diagnosticsEnabled` — a hálózat-használat MA két flagből következik; a leltárnak ezt is le kell írnia.

## 3. Scope

**Benne van:** `docs/privacy/data-inventory.yaml` — feature-enként MINDEN tárolt/továbbított adatmező: cél, jogalap, retention, tárolási hely (eszköz/backend), consent-kapcsoló, „elhagyja-e az eszközt" · `tool/check_data_inventory.dart` (hiányzó mező vagy a fán MÉRT, leltárban nem szereplő adatküldő út → nem-nulla kilépés) · `test/privacy/consent_enforcement_test.dart` (a consent visszavonása után az adott út NEM küld: tutor, diagnostics, community — mindegyik a MAGA MÉRT kapcsolójával) · `docs/privacy/consent-enforcement.md`.

**NINCS benne (tilos):**

- ÚJ képernyő vagy bármely `lib/**` módosítás.
- Új consent-fogalom vagy -kapcsoló bevezetése.
- Backend séma-változás.
- `docs/adr/**` — az ADR 0457-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/privacy/data-inventory.yaml` | ÚJ — a leltár |
| `docs/privacy/consent-enforcement.md` | ÚJ — a kényszerítési szabályok |
| `tool/check_data_inventory.dart` | ÚJ — a leltár teljesség-ellenőrzése |
| `test/privacy/consent_enforcement_test.dart` | a §6 kényszerítési cellái |
| `test/tooling/data_inventory_test.dart` | a leltár séma-cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `test/ui/goldens/**` · `docs/adr/**` · `.github/**` · `tools/**`

## 5. Kötött architekturális döntések (ADR 0457)

### 5.1 A leltár teljességét a KÓD méri, nem a szerző

A checker a fán megkeresi az adatküldő utakat (HTTP-kliens hívóhelyek, uploader-ek), és mindegyikhez leltár-bejegyzést követel. **NEM elfogadható gyengítés:** kézzel írt lista gépi teljesség-ellenőrzés nélkül — az első új végpont után hazudna.

### 5.2 A visszavonás AZONNAL hat, nem a következő indításkor

**NEM elfogadható gyengítés:** „a következő app-indításkor lép életbe" viselkedés elfogadása — a mért felhasználói elvárás és az ADR 0132 is azonnali hatályt ír.

### 5.3 Nincs csendes cloud-fallback

Ha egy helyi út nem elérhető, a rendszer NEM esik vissza felhő-hívásra hozzájárulás nélkül. **NEM elfogadható gyengítés:** „degradált mód" néven bevezetett hálózati ág.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A leltár MINDEN mezője hordoz célt, jogalapot, retentiont és tárolási helyet | `data_inventory_test.dart` |
| A2 | A fán MÉRT **mind a négy** kibocsátási úthoz (§0.0.A.2) tartozik leltár-bejegyzés, a bekötetlenek `wired: false`-szal | `data_inventory_test.dart` (fa-bejárás, ADR 0479 D1) |
| A3 | `TutorConsent.modelUseGranted` visszavonása után a tutor-turn NEM ér el gateway-t/transportot — a cella a TURN-ÚTON mér, gateway-kémmel, nem képernyő-renderrel ([L140](../LESSONS.md#l140)) | `consent_enforcement_test.dart` |
| A4 | `diagnosticsConsentProvider` visszavonása után az uploader NEM küld | `consent_enforcement_test.dart` |
| A5' | **(ÁTÍRVA — §0.0.A.3)** Az account-session visszavonása (logout / `invalidateSession`) után a Community írás-út (`challenge`/`profile`/`relationship` repók) és a settings-sync NEM küld | `consent_enforcement_test.dart` |
| A6 | A visszavonás AZONNAL hat (ugyanabban a session-ben, újraindítás nélkül) — mind a három csatornán | `consent_enforcement_test.dart` |
| A7 | A képernyő-leltár száma VÁLTOZATLAN — `hasLength(96)`, a kör nem hoz új képernyőt | `test/ui/ui_inventory_test.dart` a §7 gate-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker a leltárból indul, nem a fából (új végpont láthatatlan) | A2 |
| A checker csak a `DioFactory`-t nézi, az injektált `Dio`-t fogadó transportokat nem ([L140](../LESSONS.md#l140)) | A2 — a 3./4. út leltár nélkül maradna |
| A teszt a visszavonást app-újraindítás után méri | A6 |
| A teszt csak EGY csatornát tilt, a többi nyitva marad ([L453](../LESSONS.md#l453)) | A3–A5' valamelyike |
| A tutor-cella a képernyőt rendereli, nem a turnt futtatja (a provider nélküli screen semmit nem indít) | A3 |
| A kör „mellékesen" új privacy-képernyőt hoz létre | A7 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** a teszt-fake-ben állítsd a diagnostics-consentet úgy, hogy a visszavonás csak a következő indításkor érvényesüljön, futtasd a §7 gate-et → az **A4** és **A6** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/privacy/consent_enforcement_test.dart test/tooling/data_inventory_test.dart test/ui/ui_inventory_test.dart
```

A leltár-ellenőrző közvetlen futtatása (kimenet a §10-be):

```bash
dart run tool/check_data_inventory.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: adatküldő utak kigyűjtése a `lib/**` fából.
2. `docs/privacy/data-inventory.yaml`.
3. `tool/check_data_inventory.dart` (fa ↔ leltár összevetés).
4. `test/privacy/consent_enforcement_test.dart` — az A3–A6 cellák.
5. `test/tooling/data_inventory_test.dart`.
6. `docs/privacy/consent-enforcement.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Hamis biztonság.** Egy csatorna-specifikus mock zöldre viszi a cellát, miközben másik úton megy adat ([L453](../LESSONS.md#l453)).
- **A leltár elavulása.** Kézi lista mellett az első új végpont után hamis (A2).
- **Termékhiba felfedezése.** Ha egy út visszavonás után is küld, az `stopped` jelzés — a javítás önálló kör.

## 10. Implementation handoff — az implementer tölti ki

**Motor:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`). **Ág:**
`sonnet-impl/e12-r17-privacy-data-inventory-and-consent-enforcement`.

### Mit építettem

Az engedélyezett fájllista mind az öt tétele elkészült, a §8 sorrendjében
(1. mérés a fán → 2. leltár → 3. checker → 4. consent-enforcement tesztek →
5. tooling-teszt → 6. doksi + valódi-sértés próba):

1. **`docs/privacy/data-inventory.yaml`** — a §0.0.A.2 mind a négy mért
   egress-útjához (`DioFactory.createAccountClient`,
   `DioFactory.createDiagnosticsClient`, `HttpTutorStreamTransport`,
   `CommunityMediaUploader`) van bejegyzés, mezőnkénti
   purpose/legal_basis/retention/storage/leaves_device-szel; a bekötetlen
   kettő (`tutor_stream`, `community_media`) `wired: false`.
2. **`tool/check_data_inventory.dart`** — a fa-bejárás a D1 mindhárom
   mintaosztályát felismeri: (a) `DioFactory.create*Client` metódusok,
   (b) bármely `lib/**`-beli, injektált HTTP-klienst fogadó ÉS kérés-igét
   hívó osztály (regex a deklaráció-alakra kötve, nem puszta `Dio` szótöved
   — egy „Dio implementations" jellegű kommentre nem fut rá), kivéve a
   `dio_factory.dart`/`api_client.dart` két, írásban indokolt infra-fájlt;
   (c) közvetlen `HttpClient(`/`package:http` használat (ma nulla találat).
   A checker a FÁBÓL indul (`discoverEgressRoutes`), nem a leltárból — egy
   leltárban nem szereplő, mért út nem-nulla kilépést ad. Tesztelhető
   belépési pontokat exportál (`DataInventory.parse`, `discoverEgressRoutes`,
   `checkDataInventory`), a `main()` csak vékony CLI-wrapper.
3. **`test/tooling/data_inventory_test.dart`** — A1 (séma-teljesség, két
   valódi-sértés próbával: hiányzó `purpose`, hiányzó `leaves_device` sor) és
   A2 (fa↔leltár keresztellenőrzés a VALÓDI fán, három valódi-sértés
   próbával: egy mért, huzalozott út kiejtése a leltárból, egy leltárban nem
   szereplő új osztály felbukkanása, egy `wired: true` bejegyzés, amit a fa
   már nem termel). 9/9 zöld.
4. **`test/privacy/consent_enforcement_test.dart`** — A3, A6(tutor), A4,
   A6(diagnostics), A5'(community), A5'(settings-sync). Mindegyik a
   TURN-/WIRE-úton mér (gateway-spy a tutorhoz, `HttpClientAdapter`-próba a
   diagnosztikához és az account-kliens forgalmához), soha nem képernyő-
   renderrel. 6/6 zöld.
5. **`docs/privacy/consent-enforcement.md`** — a három kikényszerítési pont
   (Tutor/Diagnostics/Account-session) mért forrás+sor hivatkozásokkal, és a
   §10 valódi-sértés próba.

### A gate — csonkítatlan kimenet

```
tools/round-gate.sh test/privacy/consent_enforcement_test.dart test/tooling/data_inventory_test.dart test/ui/ui_inventory_test.dart
```

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/privacy/consent_enforcement_test.dart            zöld
    test test/tooling/data_inventory_test.dart                 zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

(analyze: „No issues found! (ran in 26.6s)"; a `test/ui/ui_inventory_test.dart`
`hasLength(96)` pinje NEM mozdult — A7 teljesül; `architecture`: 12 meglévő,
változatlan allowlist-tétel, egyik sem ebből a körből.)

### A leltár-ellenőrző közvetlen futtatása

```
$ dart run tool/check_data_inventory.dart
Data inventory check OK (4 measured egress route(s), 4 inventory route(s)).
```

### Valódi-sértés próba (§10 kötelező bizonyíték)

A `test/privacy/consent_enforcement_test.dart` A6 (diagnostics) cellájában a
reaktív `diagnosticsConsentProvider.overrideWith((ref) => ref.watch(consent))`
sort ideiglenesen egy befagyasztott pillanatképre (`overrideWithValue(true)`)
cseréltem — pontosan azt szimulálva, amit a D2 tilt: a visszavonás csak a
következő indításkor lépne életbe. `flutter test
test/privacy/consent_enforcement_test.dart` PIROSRA váltott:

```
00:00 +3 -1: A6 (diagnostics) — revoking upload consent stops the NEXT upload in the SAME
container, no restart upload 1 (consent true) reaches the wire; upload 2 (consent flipped
false, same container) does not [E]
  Expected: an object with length of <1>
    Actual: [Instance of 'RequestOptions', Instance of 'RequestOptions']
     Which: has length of <2>
  the second, post-revocation upload must not reach the wire — the consent check re-reads the
  live provider value, not a snapshot taken at boot
```

**Mért, pontos állítás:** az A6(diagnostics) cella váltott pirosra — ez az a
cella, aminek KIFEJEZETT feladata a session-közbeni azonnaliság mérése, és
pontosan ezt a hibaosztályt fogta meg. Az A4 cella (ami a „kezdettől
`false`" forgatókönyvet méri, `overrideWithValue(false)`) a próba alatt is
zöld maradt — helyesen, mert a befagyasztott-pillanatkép hiba egy MÁSIK
forgatókönyvet érint, nem azt, amit A4 mér. A `docs/privacy/consent-
enforcement.md` §10 ugyanezt a nüánszot dokumentálja — mindkét cellát
pirosnak állítani hazugság lett volna.

Visszaállítás után (`diff` a próba előtti másolattal nulla eltérést mutatott)
a teljes gate-et újra lefuttattam — fent a zöld kimenet a visszaállítás
UTÁNI állapotot mutatja.

### STOP-eset nem történt

Egyik cella sem talált mért szivárgást (visszavont hozzájárulás mellett is
menő adatot) — a `lib/**` mind a három élő kikényszerítési pontja
(`tutor_orchestrator.dart:47`, `diagnostics_providers.dart:66` +
`diagnostics_uploader.dart:52`, `auth_interceptor.dart:50,73` +
`settings_sync.dart`'s `!_signedIn` guard) a turn-/wire-úton ellenőrizve
helyesen állítja meg az adatáramlást. A tiltott zóna (`lib/**` stb.)
érintetlen maradt.

### Ismert, dokumentált korlátok (nem ennek a körnek a hibája)

- A Tutor SSE (`HttpTutorStreamTransport`) és a Community media
  (`CommunityMediaUploader`) útnak nincs `lib/**` konstrukciós helye — A3/A6
  a tutor esetében ezért a gateway-létrehozás előtti rövidzárlatot méri (a
  valódi HTTP-hívás nem létezik még), nem magát a hálózati hívást. Ez a mért
  valóság, nem gyengítés — a leltár `wired: false`-szal jelzi.
- Community-specifikus, kliensoldali consent nincs (mért, 0 találat) — az
  A5' cella ezért az account-session kapcsolón mér, az ADR 0479 §"Döntés" D4
  pontja szerint.

## 11. Review — a Claude tölti ki
