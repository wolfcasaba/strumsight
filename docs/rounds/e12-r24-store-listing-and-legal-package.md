# E12-R24 — Store listing, privacy és legal package

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 24
- **Kör-azonosító:** `E12-R24`
- **Branch:** `<motor>/e12-r24-store-listing-and-legal-package`
- **Előfeltétel:** `E12-R17` merge-elve (a data safety nyilatkozat FORRÁSA a data-inventory)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a kör dokumentum-csomagot állít elő; a hivatkozott szerződéseket korábbi ADR-ek rögzítik.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "store listing privacy policy data safety permission rationale deletion"` → **[ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)** (export/share/delete szerződés — a törlési út MÉRT szerződése) és **[ADR 0378](../adr/0378-achievement-presentation-and-privacy-safe-evidence.md)**. A store-nyilatkozat ezekre hivatkozik, nem újat ígér.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd ki az `android/app/src/main/AndroidManifest.xml` TÉNYLEGESEN kért engedélyeit és a `docs/privacy/data-inventory.yaml` (Kör 17) mezőit. A store-csomag minden állítása EBBŐL a két forrásból következzen — nem a marketing-szándékból.

## 0.0 A kör felelősségi határa

A store-fiók, a tényleges feltöltés és a jogi felülvizsgálat EMBERI (user-) lépés. A kör terméke a döntéshez szükséges, ellentmondás-mentes DOKUMENTUM-csomag és annak gépi ellenőrzése (minden engedélyhez indoklás, minden data-safety kategóriához leltár-fedezet, minden hivatkozott URL/route létezik).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/store/listing.md",
  "docs/store/permissions-rationale.md",
  "docs/store/data-safety.yaml",
  "docs/legal/privacy-policy-draft.md",
  "docs/legal/community-guidelines-draft.md",
  "test/tooling/store_package_test.dart",
  "docs/rounds/e12-r24-store-listing-and-legal-package.md",
]
gate_tests = [
  "test/tooling/store_package_test.dart",
  "test/tooling/data_inventory_test.dart",
]
native_gate = false
```

## 0.0.1 §0.0 BRIEF-REVÍZIÓ — pre-flight mérés (orchestrátor, 2026-09-02, `main @ 62c88b35`)

A brief előre megírt (2026-08-27) állításait a pre-flight kimérte. Négy állítás
avult vagy volt pontatlan; a revízió **szűkít és forrást köt**, nem tágít. A
`brief-lint (strict)` 0 leletet adott, a hagyaték-szonda `ÁLLAPOT: NINCS`.

**Visszakeresés (ADR 0312, szűkítve → teljes korpusz):**
`--corpus lessons,halts,adr` → [ADR 0479](../adr/0479-privacy-data-inventory-and-consent-enforcement.md)
(a leltár gépi szerződése; „ez a döntés nem lazítható azért, hogy egy teszt zöld
legyen"), [ADR 0247](../adr/0247-analysis-export-share-and-delete-contract.md)
(export/share/delete). `--corpus lessons,halts` → [L420](../LESSONS.md#l420)
(a célzott gate NEM fedi a kereszt-fájlrendszeres `test/tooling/*_guard_test.dart`
őröket — a teljes CI a mérce), [L102](../LESSONS.md#l102) (a `dart format` lépés
csak a `round-gate.sh`-ban fut le). Teljes korpuszon nem jött új, releváns
előzmény a briefen kívülről.

### R1 — A GA-scope EGYETLEN igazsága a device-mátrix, nem a brief prózája

[ADR 0477](../adr/0477-ai-release-evidence-aggregation-and-ga-scope-truth.md) **D1**
kimondja: a GA-scope egyetlen forrása a `docs/testing/device-matrix.yaml`
`capabilities[].ga_scope` mezője — **új GA-lista TILOS**. A brief A3 cellája ezt
nem nevezte meg. MÉRVE (`docs/testing/device-matrix.yaml:90–133`):

| `ga_scope: true` (11) | `ga_scope: false` (3) |
|---|---|
| `onboarding`, `live_and_tuner`, `practice_engine`, `song_trainer_local`, `audio_analysis_core`, `progress_goals_streak`, `storage_migration`, `offline_operation`, `localization_en_hu`, `accessibility_minimum`, `session_lifecycle_stability` | `computer_vision`, `offline_ai`, `ai_tutor` |

**Kötelező:** az **A3** cella a `device-matrix.yaml`-t OLVASSA (szűkített,
`package:yaml` NÉLKÜLI olvasóval — a `yaml` csomag ezen a fán csak tranzitív
függőség, lásd `docs/testing/device-lab.md` §3), és a `listing.md` capability-
hivatkozásait ehhez méri. A három `ga_scope: false` capability (Computer Vision /
Vision coach, Offline AI, AI Tutor) a store-leírásban **nem ígérhető**, sem
„hamarosan" alakban (§5.3). Beégetett capability-lista a tesztben TILOS.

### R2 — A §2 „fiók-törlés a `backend/app/routers/auth.py` felelőssége" állítás MÉRVE HAMIS

`grep -n "@router\." backend/app/routers/auth.py` → **csak** `POST /register`,
`POST /login`, `GET /me`. **A fán MA nincs kliens által indítható
fiók-törlési végpont** — ezt a `docs/privacy/data-inventory.yaml` maga is
kimondja (`account_api`/`email` retention: *„backend/** has no measured
client-triggered account-deletion endpoint as of this round"*).

A MÉRT, létező törlési/exportálási felületek:

| Felület | Mérés | Hatóköre |
|---|---|---|
| `PrivacyCenterScreen` — „delete all" + export | `lib/features/settings/screens/privacy_center_screen.dart:92,118` (`deleteAllVisionData`), belépés `lib/features/settings/screens/settings_screen.dart:86`-ról `MaterialPageRoute`-tal — **nincs hozzá nevesített `AppRoute` konstans** | on-device vision-adat |
| `AppRoute.tutorData` = `/tutor/data` | `lib/app/routing/app_route.dart:38` | on-device tutor-memória |
| `AppRoute.tutorPrivacy` = `/tutor/privacy` | `lib/app/routing/app_route.dart:37` | tutor consent visszavonás |
| `AppRoute.settings` = `/settings` | `lib/app/routing/app_route.dart:11` | a Privacy Center szülő-képernyője |

**Kötelező:** a store-csomag a fiók-törlést **NEM** írhatja le meglévő in-app
útként vagy backend-végpontként. A dokumentumnak ki kell mondania, hogy a
**backend-oldali fiók-törlés ma nem létező képesség**, és a kezelése támogatási
(e-mail) csatorna. Az **A4** cella két irányban mér: (a) minden, a
dokumentumokban `/…` alakban hivatkozott alkalmazás-útvonalnak léteznie kell az
`app_route.dart`-ban; (b) a `PrivacyCenterScreen`-re hivatkozás a
fájl:osztály párra mutasson, ne kitalált route-ra. Nem létező végpont
dokumentálása az A4-et PIROSRA viszi.

### R3 — A manifest MÉRT engedélylistája (az A1 bemenete)

`android/app/src/main/AndroidManifest.xml`: **`RECORD_AUDIO`** (3), **`CAMERA`**
(5), **`INTERNET`** (9), **`POST_NOTIFICATIONS`** (12),
**`RECEIVE_BOOT_COMPLETED`** (13); továbbá `uses-feature
android.hardware.camera` `required="false"` (6). A `debug`/`profile` variáns
**kizárólag** `INTERNET`-et kér, a Flutter tooling hot-reloadjához — ezek nem
kerülnek a release-artefaktumba, tehát a rationale-dokumentum a `main` variánst
sorolja, és a két dev-variánst **kimondva** zárja ki.

**Mért feszültség, amit a rationale-nak kezelnie kell (NEM STOP):** a `CAMERA`
engedélyhez van a fán mérhető funkció (`lib/features/vision/**`), tehát a §0
STOP-protokoll **nem** áll fenn — de az általa kiszolgált `computer_vision`
capability `ga_scope: false` (R1). A `permissions-rationale.md`-ben a `CAMERA`
sor ezért **opcionális, nem-GA** minősítést kap, és a `listing.md` nem
reklámozhatja. A `RECEIVE_BOOT_COMPLETED` indoklása a
`ScheduledNotificationBootReceiver` (manifest 60–66. sor,
`flutter_local_notifications`) — a §5.2 szerint a FUNKCIÓT (napi gyakorlás-
emlékeztető újraregisztrálása újraindítás után) és az adatot kell megnevezni,
nem a plugint.

**Az A1 cella a manifestet OLVASSA** (`uses-permission android:name="…"`
regex), és minden megtalált engedélyhez követel egy sort a
`permissions-rationale.md`-ből. Beégetett engedélylista a tesztben TILOS — a
falszifikáció (§6.1) az indoklás kivételére épül.

### R4 — Az A2 forrása a MÉRT leltár, a szűkített olvasó KÉSZ

A `docs/privacy/data-inventory.yaml` **11 route**-ot deklarál: `account_api`,
`diagnostics_upload`, `tutor_stream`, `community_media`, `share_export`, és 6
`rides:` alakú, saját mező nélküli bejegyzés
(`account_api_auth_repository`, `…_settings_repository`,
`…_community_profile_repository`, `…_social_graph_repository`,
`…_community_challenge_repository`, `diagnostics_upload_uploader`).

A leltár olvasásához **ne írj új parsert**: a `tool/check_data_inventory.dart`
már szállít egy `package:yaml`-mentes `DataInventory.parseFile` olvasót, amit a
`test/tooling/data_inventory_test.dart` ugyanígy importál
(`import '../../tool/check_data_inventory.dart';`). A `tool/**` a tilos zónában
van: **importálni szabad, módosítani TILOS**.

**Az A2 kétirányú:** minden `data-safety.yaml` kategória egy LÉTEZŐ
`route.id`/`field.name` párra hivatkozzon, és minden `leaves_device: true`
leltár-mezőnek legyen data-safety fedezete. A `rides:` route-ok mezők nélküliek
— ezeket a fedezet-számítás a `rides` célján keresztül vegye, ne követeljen
rájuk külön kategóriát (különben a cella szükségszerűen piros).

### R5 — A gate és a teljes suite viszonya (L420)

A §7 célzott gate **nem** fedi a kereszt-fájlrendszeres őröket
(`test/tooling/sdd_index_guard_test.dart`, `check_secrets_test.dart`,
`check_assets_test.dart`, `test/ui/ui_inventory_test.dart`). Öt ÚJ dokumentum-
fájl keletkezik: a merge-kapu az **exact-SHA CI teljes suite-ja**, nem a célzott
gate. A `dart format` a `round-gate.sh` ELSŐ lépése (L102) — a záró sort
csővezeték nélkül, szó szerint kell futtatni.

### R6 — ADR: nincs, és ez SZÁNDÉKOS

A kör dokumentum-csomagot állít elő; minden normatív állítása MÁR merge-elt
döntésre vezet vissza (ADR 0477 D1 a GA-scope-ra, ADR 0479 a leltárra, ADR 0247
a törlés/export szerződésre). Új ADR-szám kiosztása merge-elt döntés fölé nem
történik; a precedens az E12-R13 (RTM: „**új ADR nincs**"). A `docs/adr/**`
ezért marad a tilos zónában.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a manifest olyan engedélyt kér, amire nincs a fán MÉRHETŐ funkció, a kimenet a `stopped` jelzés — az engedély eltávolítása vagy indoklása külön döntés.

## 1. Cél

A store-metaadat, az adatbiztonsági nyilatkozat és a jogi dokumentumok legyenek a TÉNYLEGES adatkezeléssel konzisztensek, túlzó AI- vagy tanulási ígéret nélkül.

## 2. Jelenlegi állapot — mért tények

- `docs/store/` és `docs/legal/` **nem létezik**.
- A `docs/privacy/data-inventory.yaml` a Kör 17 után létezik — ez a data-safety nyilatkozat egyetlen forrása.
- A törlési/exportálási út szerződése ADR 0247-ben rögzített. ~~a fiók-törlés backend-oldali útja a `backend/app/routers/auth.py` felelőssége.~~ **§0.0 revízió R2 (MÉRVE 2026-09-02): a `backend/app/routers/auth.py` HÁROM végpontot ad (`POST /register`, `POST /login`, `GET /me`) — kliens által indítható fiók-törlés a fán NEM létezik.** A MÉRT törlési felületek a revízió R2 táblázatában.
- A publikus store-jelenlét MA nincs (Kör 1 release-history audit).

## 3. Scope

**Benne van:** `docs/store/listing.md` (leírás, képernyőkép-terv, kategória, korhatár-megfontolás) · `docs/store/permissions-rationale.md` (MINDEN, a manifestben kért engedélyhez: melyik funkció, milyen adat, opcionális-e) · `docs/store/data-safety.yaml` (a data-inventory kategóriáira leképezve, gépileg összevethető alakban) · `docs/legal/privacy-policy-draft.md` és `community-guidelines-draft.md` (TERVEZET jelöléssel — a jogi felülvizsgálat emberi lépés) · `test/tooling/store_package_test.dart` (a fenti konzisztencia gépi ellenőrzése).

**NINCS benne (tilos):**

- `android/**` engedély-módosítás.
- Store-feltöltés vagy fiók-művelet.
- Olyan képesség-ígéret, amit a fán MÉRT állapot nem támogat (pl. „valós idejű AI-tanár", ha az Offline AI sáv `hold`-on áll).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/store/listing.md` | ÚJ — store-metaadat |
| `docs/store/permissions-rationale.md` | ÚJ — engedély-indoklások |
| `docs/store/data-safety.yaml` | ÚJ — gépileg ellenőrizhető nyilatkozat |
| `docs/legal/privacy-policy-draft.md` | ÚJ — adatkezelési tájékoztató tervezet |
| `docs/legal/community-guidelines-draft.md` | ÚJ — közösségi irányelvek tervezet |
| `test/tooling/store_package_test.dart` | a §6 cellái |

**Tilos zóna:** `android/**` · `lib/**` · `backend/**` · `docs/privacy/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A data-safety nyilatkozat SZÁRMAZTATOTT

Minden kategóriája a `data-inventory.yaml` egy vagy több mezőjére hivatkozik. **NEM elfogadható gyengítés:** önállóan megfogalmazott kategória-lista, ami „nagyjából" fedi a valóságot.

### 5.2 Minden kért engedélyhez indoklás tartozik

**NEM elfogadható gyengítés:** „a Flutter plugin kéri" típusú indoklás önmagában — meg kell nevezni a FUNKCIÓT és az adatot.

### 5.3 Nincs túlzó képesség-ígéret

A listing csak a GA-scope-ban lévő capabilitykre hivatkozik. **NEM elfogadható gyengítés:** „hamarosan" megfogalmazású funkció-ígéret a store-leírásban.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A manifest MINDEN kért engedélyéhez van indoklás — a listát a teszt az `AndroidManifest.xml`-ből OLVASSA (§0.0 R3), beégetett engedélylista tilos | `store_package_test.dart` |
| A2 | A data-safety minden kategóriája LÉTEZŐ leltár-`route.id`/`field.name` párra hivatkozik, és fordítva: nincs `leaves_device: true` leltár-mező nyilatkozat nélkül; a `rides:` route-ok a céljukon át fedettek (§0.0 R4) | `store_package_test.dart` |
| A3 | A listing nem hivatkozik GA-scope-on kívüli capabilityre — a GA-lista a `docs/testing/device-matrix.yaml` `capabilities[].ga_scope`-jából OLVASVA (ADR 0477 D1, §0.0 R1), beégetett lista tilos | `store_package_test.dart` |
| A4 | Minden, a csomagban `/…` alakban hivatkozott alkalmazás-útvonal LÉTEZIK az `app_route.dart`-ban, ÉS a csomag nem állít nem létező fiók-törlési végpontot/route-ot (§0.0 R2) | `store_package_test.dart` |
| A5 | A jogi dokumentumok TERVEZET jelöléssel és felülvizsgálati felelőssel készülnek | a dokumentumok fejléce |
| A6 | A Kör 17 `data_inventory_test.dart` VÁLTOZATLANUL zöld | a §7 gate |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Egy manifest-engedély indoklás nélkül marad | A1 |
| A data-safety kategória kézzel íródik, leltár-hivatkozás nélkül | A2 |
| A listing „AI gitártanár"-t ígér, miközben az `ai_tutor`/`offline_ai` `ga_scope: false` | A3 |
| A teszt beégetett GA-listát használ a `device-matrix.yaml` olvasása helyett | A3 önvédő cella: a mátrix egy `ga_scope` értékét `true`↔`false`-ra billentve a cellának meg kell FORDULNIA |
| A törlési útvonal nem létező route-ra (pl. `/privacy-center`) vagy nem létező backend-végpontra (pl. `DELETE /auth/me`) mutat | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az egyik engedély indoklását, futtasd a §7 gate-et → az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/store_package_test.dart test/tooling/data_inventory_test.dart
```

## 8. Implementációs sorrend

1. Az `AndroidManifest.xml` engedélyeinek és a data-inventory mezőinek MÉRÉSE.
2. `docs/store/permissions-rationale.md` és `data-safety.yaml`.
3. `test/tooling/store_package_test.dart`.
4. `docs/store/listing.md` (a GA-scope korlátjával).
5. A két jogi tervezet + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Ellentmondás a valósággal.** A store-nyilatkozat és a tényleges adatkezelés eltérése a legnagyobb jogi kockázat (A2).
- **Túlzó ígéret.** A `hold`-on álló Offline AI sáv reklámozása (A3).
- **Emberi lépés összemosása.** A jogi felülvizsgálat és a store-feltöltés a useré — a dokumentum ezt mondja ki (§0.0).

## 10. Implementation handoff — az implementer tölti ki

**Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort medium`), 2026-09-02.

### Létrehozott fájlok

- `docs/store/listing.md` — store-szöveg, kategória, screenshot-terv, engedély/
  data-safety-mutató, és a gépileg olvasott `<!-- capabilities-marketed: … -->`
  jelölés (9 GA-scope capability id, a `computer_vision`/`offline_ai`/
  `ai_tutor` egyike sincs se a jelölésben, se a prózában).
- `docs/store/permissions-rationale.md` — a `main` variant mind az 5 mért
  engedélyéhez (`RECORD_AUDIO`, `CAMERA`, `INTERNET`, `POST_NOTIFICATIONS`,
  `RECEIVE_BOOT_COMPLETED`) funkció+adat indoklás; a `CAMERA` sor kimondottan
  opcionális/nem-GA; külön szakasz a debug/profile variant (csak `INTERNET`)
  kizárásáról.
- `docs/store/data-safety.yaml` — 11 kategória, mindegyik egy létező
  `docs/privacy/data-inventory.yaml` route.id/field.name párra hivatkozva; a
  12 `leaves_device: true` mező mindegyike lefedett (email+password egy
  kategóriában, a többi 1:1).
- `docs/legal/privacy-policy-draft.md` — TERVEZET, nevesített felülvizsgáló
  (Ralph, `kcsabi176@gmail.com`), a §0.0 R2 szerinti ŐSZINTE fiók-törlési
  állapot (`does not have a client-triggered account-deletion endpoint`,
  szó szerint, a `test/tooling/store_package_test.dart` A4 cellája ellenőrzi),
  támogatási e-mail PLACEHOLDER (`privacy-support@strumsight.app`).
- `docs/legal/community-guidelines-draft.md` — TERVEZET, ugyanaz a
  felülvizsgáló, őszinte "nincs önálló moderátor-felület" állapot.
- `test/tooling/store_package_test.dart` — 29 cella, A1–A5 mindegyikéhez
  valós-fa mérés + legalább egy self-defense/regresszió cella, amely egy
  MÁSOLATON (nem a valódi fájlon) fordítja meg az eredményt.

### Valódi-sértés próbák (§6.1/§7, ténylegesen lefuttatva)

**A1 (kötelező, brief §6.1 utolsó bekezdése):** a
`docs/store/permissions-rationale.md` `## android.permission.RECORD_AUDIO`
fejlécét ideiglenesen átneveztem (`## VIOLATION-PROBE-TEMPORARILY-REMOVED-RECORD_AUDIO`),
lefuttattam `tools/round-gate.sh test/tooling/store_package_test.dart
test/tooling/data_inventory_test.dart`-ot — kilépési kód **10**, az A1
real-tree cella `[E]`-vel bukott, szó szerinti üzenet:

```
Expected: empty
  Actual: [
            'android.permission.RECORD_AUDIO has no rationale entry in docs/store/permissions-rationale.md'
          ]
```

Ezután a fejlécet visszaállítottam (`## android.permission.RECORD_AUDIO`),
`git status --porcelain -- docs/store/permissions-rationale.md` az eredeti
tartalmat mutatja (a fájl untracked, nincs commit-alapú diff, de az öt
`## android.permission.*` fejléc száma és neve a próba előtti állapottal
egyezik — ellenőrizve `grep -n "^## android"`-dal), és a teljes gate utána
újra zöld (lásd alább).

**A3 (brief §5 második fele — device-matrix.yaml ideiglenes billentése):**
**NEM végrehajtható a jelenlegi engedélyezett-fájllistával.** A brief §5
szó szerint azt kéri, hogy a `docs/testing/device-matrix.yaml` egy
`ga_scope` értékét ideiglenesen állítsam át, majd `git checkout`-tal
állítsam vissza — de ez a fájl NINCS a §0.0 `ai-router` blokk
`allowed_paths` listáján, és a `tools/hooks/implementer_guard.py`
kilépő-kóddal megtagadta magát az Edit hívást is (nem csak egy commitot):

```
IMPLEMENTER-ŐR: `docs/testing/device-matrix.yaml` NINCS a(z) E12-R24
engedélyezett fájllistáján (a brief ai-router blokkja). A lista tágítása
TILOS (STOP-protokoll).
```

Ez a §0.0 (allowed_paths) és a §5 (a próba szövege) közötti ELLENTMONDÁS —
a fájl SOSEM módosult (`git status --porcelain -- docs/testing/device-matrix.yaml`
üres az egész kör alatt), tehát a §0.0 STOP-protokollja nem sérült. A §5
mögötti tényleges acceptance-igényt ("a teszt NEM egy beégetett GA-listát
használ") a `store_package_test.dart` A3 csoportjának két self-defense
cellája automatizáltan, a VALÓS `device-matrix.yaml`-t beolvasva, majd egy
IN-MEMORY másolaton flip-elve bizonyítja (mindkét irányban: GA-true→false
és GA-false→true; lásd "flipping a marketed capability's ga_scope..." és
"prose scan: flipping audio_analysis_core..." cellák) — ez ekvivalens
bizonyíték a fájlt ténylegesen nem érintve. Ha az orchestrátor mégis a
fájlt ténylegesen billentő, kézi próbát kéri, az `allowed_paths` bővítése
külön döntés (brief-revízió), nem ennek a körnek a hatásköre.

### A záró gate

```
tools/round-gate.sh test/tooling/store_package_test.dart test/tooling/data_inventory_test.dart
```

**Eredmény: MINDEN GATE ZÖLD** — `format`, `analyze`, mindkét célzott teszt
(29, illetve 27 cella, mindkettő 100%-ban zöld), `architecture`, `secrets`,
`l10n`. Az A6 (a Kör 17 `data_inventory_test.dart` változatlanul zöld) ezzel
bizonyított — a `docs/privacy/**` fát ez a kör nem érintette.

### Kétértelmű forrás-döntések

- **A `capabilities-marketed` jelölés formátuma listing.md-ben nem volt
  előírva a briefben** — egy HTML-kommentben elhelyezett, géppel olvasott,
  vesszővel tagolt id-lista mellett döntöttem (a szerző SAJÁT deklarált
  listája, amit a teszt a device-matrix.yaml-hoz mér), MERT egy tisztán
  kulcsszó-alapú prózakeresés nem tudta volna megbízhatóan levezetni,
  mely capability id-khez tartozik a szöveg — ez viszont önmagában nem
  fedte volna le azt az esetet, amikor a próza ígér valamit anélkül, hogy
  a jelölésben szerepelne. Ezért A3 KÉT réteget kapott: a jelölés-alapú
  ellenőrzés (elsődleges) ÉS egy kulcsszó-alapú próza-scan (másodlagos, a
  három tiltott capability ismert megfogalmazásaira) — mindkettő a
  device-matrix.yaml-t olvassa élőben, nincs beégetett GA-lista egyikben
  sem.
- **A `privacy-support@strumsight.app` támogatási cím kitalált placeholder**
  — nincs mért, valós támogatási postafiók a fán; mindkét jogi tervezetben
  és a store_package_test.dart-ban is kimondottan "placeholder"-ként van
  jelölve, a valódi cím megerősítése a §0.0 szerinti emberi jogi
  felülvizsgálat feladata.
- **A `data-safety.yaml` kategorizálása (Play "data safety" kategóriák,
  pl. "Personal info", "App activity") nem hivatalos Play-taxonómia szerint
  ellenőrzött** — csak a route/field-fedezet géppel bizonyított (A2); a
  `play_category` mezők tartalmi helyessége a store-feltöltéskor, a Play
  Console saját űrlapjával szemben, emberi lépés.

## 11. Review — a Claude tölti ki
