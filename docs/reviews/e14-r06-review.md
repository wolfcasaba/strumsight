# Review — E14-R06 (Accuracy Lab és engedélyezett adatgyűjtés)

- **Kör:** `E14-R06`, branch `sonnet-impl/e14-r06-accuracy-lab-and-consented-capture`
- **Reviewelt HEAD:** `bb860903` (implementer commitok: `38820c3c`, `c593e105`, `bb860903`)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5) — orchestrátor-szék, READ-ONLY, production kód nem módosult
- **ADR:** [`0358`](../adr/0358-consented-on-device-lab-capture-package.md) D1–D8
- **Kockázat:** `high` → kötelező biztonsági review, külön jelentés:
  [`e14-r06-review-security.md`](e14-r06-review-security.md)
- **VERDIKT: CHANGES REQUESTED** — 2 MAJOR, 2 MINOR nyitva.

## 1. Formai ellenőrzések (MÉRVE, nem bemondásra)

| Mérés | Parancs | Eredmény |
|---|---|---|
| Kör-jelzés | `cat .codex-round-status` | `status=done`, `head=bb860903`, `gate_shape=ok`, `scope_audit=ok`, `scope_audit_changed=9` |
| Munkafa | `git status --short` | üres (a `dirty_files=1` a jelzésfájl maga volt) |
| Scope-audit | `python3 tools/scope-audit.py --repo … --base cf688a08` | `Legacy scope audit OK (cf688a082c6c..bb8609032adf, 9 changed path(s), 0 generated/ignored)` |
| Gate — SAJÁT futtatás izolált klónban (`/tmp/review-e14-r06`) | `tools/round-gate.sh test/features/accuracy_lab/lab_capture_package_test.dart test/features/accuracy_lab/lab_package_writer_test.dart test/features/accuracy_lab/lab_consent_test.dart test/features/accuracy_lab` | **9/9 ZÖLD**, `GATE_EXIT=0` (format, analyze, 4× teszt, architecture, secrets, l10n); 19 teszt zöld |

A brief §10 handoffja nem bemondás: a determinizmus- és az allowlist-cella
falszifikációja tényleges piros kimenettel dokumentált, és a visszaállítást a
saját, független gate-futásom igazolja.

## 2. Acceptance criteria tételesen

| # | Kritérium | Bizonyíték | Verdikt |
|---|---|---|---|
| 1 | `LabTask` hat család, 15–20, 14/15/21 cellahármas | `lab_capture_package_test.dart:8-37`; `LabTaskCatalog.validated` tetszőleges listára fut (`lab_task.dart:57`), a standard katalógus 16 elem, `family` halmaz == `LabTaskFamily.values` | ✅ |
| 2 | Round-trip veszteségmentes + bájtra azonos | `:43-88` — a kulcssorrend-független cella a valódi determinizmus-mérce (a puszta „kétszer ugyanaz" önmagában gyenge lenne) | ✅ |
| 3 | Consent nélkül nem fordul; `granted`/`revoked`/`unknown` mátrix | `lab_consent_test.dart:27-55` — kimerítő `switch` a TÉNYLEGES hívási láncon (L161), a `write` csak a `LabConsentGranted`-re szűkített ágból érhető el | ✅ |
| 4 | A csomag nem hordoz azonosítót | `:113-131` — kulcshalmaz-**egyenlőség** az allowlisttel (L260 szerint ez a mutáció-ölő cella) + érték-oldali kanári | ✅ (de lásd MINOR-1) |
| 5 | Törlés után a könyvtár nem létezik, `missing` státusz | `lab_package_writer_test.dart:85-112` — `existsSync()` mind a három fájlra ÉS a könyvtárra | ✅ |
| 6 | Ismeretlen `schemaVersion` → típusos hiba | `:90-106` + `lab_capture_package.dart:124-128` (hiányzó verzió is dob) | ✅ |

A §6.1 mérce-mátrix minden sorához tartozik cella; a két legkockázatosabb sort
(D3 determinizmus, D2 allowlist) az implementer ideiglenes rontással pirosra is
vitte (§10.3).

## 3. Leletek

### MAJOR-1 — Path traversal: a `packageId` validálatlanul útvonalba fűződik, a rekurzív törlés kiszökik a rootból

`lib/features/accuracy_lab/data/lab_package_writer.dart:52`
(`Directory('${root.path}/$packageId')`), kihat: `write` (72–79), `status`
(105), `delete` (116–121, `deleteSync(recursive: true)`).

**MÉRVE** (biztonsági review, Probe 2, eldobható próba `/tmp/sec-e14-r06`-ban):
`packageId = "../OUTSIDE_VICTIM"` mellett a `write` a root **testvér**könyvtárába
írt, a `delete(recursive: true)` pedig letörölte azt a könyvtárat a benne lévő,
nem a Lab által létrehozott `precious.txt`-tel együtt:

```
locate(root=.../lab-root, id="../OUTSIDE_VICTIM")
  -> directory.path = .../lab-root/../OUTSIDE_VICTIM
  write() SUCCEEDED, manifest at .../lab-root/../OUTSIDE_VICTIM/manifest.json
  delete(recursive) done. victim precious.txt still exists? false
  victim dir still exists? false
```

Két degenerált eset ugyanabból a gyökérből, szintén mérve: **üres id** →
`locate` a rootot adja vissza, tehát `delete(root, packageId: '')` a TELJES
gyökeret (minden csomagot) törölné; **abszolút id** → a kettős perjel miatt a
root alatt marad, tehát az nem szökik ki.

**Miért MAJOR (és nem BLOCKER) ma:** nincs production hívó — a
`LabPackageWriter` a diffben unwired. **De a `packageId` a `fromJson`-ből is
jöhet** (`lab_capture_package.dart:131`), tehát egy visszaolvasott manifest
path-szerű id-je ugyanide folyna. A lelet a bekötő körben (E14-R06b) azonnal
CRITICAL, ezért itt kell zárni: a szerződés most kap gépi őrt, nem a UI-kör
alatt.

**Javasolt irány (nem kész patch):** a `packageId` belépéskori validálása
(allowlist-regex, üres tiltva) VAGY feloldott útvonal + „a rooton belül van"
fail-closed ellenőrzés a `locate`-ben; sértés esetén **típusos hiba**, nem néma
művelet. Kell hozzá cella, ami a mai kódot PIROSRA viszi (a fenti `..`-eset).

### MAJOR-2 — A `write()` a `consent` paramétert soha nem olvassa: a manifest consent-verziója nem az engedélyből származik

`lib/features/accuracy_lab/data/lab_package_writer.dart:66-96` — a `consent`
paraméter kizárólag típuskapu; a manifest `consentVersion` mezője a hívó által
összerakott `package.toJson()`-ből jön (`lab_capture_package.dart:110, 119`).

**MÉRVE** (biztonsági review, Probe 1):

```
actual granted consent.consentVersion = consent-v2-2026
manifest records: {... "consentVersion":"v1-stale" ...}
=> manifest consentVersion matches ACTUAL grant? false
```

A D1 **kapuja** teljesül (a `write` továbbra sem hívható `revoked`/`unknown`
consenttel), de a csomagba írt **audit-nyom** független a tényleges
engedélytől: a manifest azt állíthatja, hogy a felhasználó olyan
consent-verzióhoz járult hozzá, amelyhez nem. Egy consent-verziót rögzítő mező
értéke pontosan attól ér valamit, hogy az engedélyből származik.

Ezt a kör saját tesztje nem foghatta meg: a `lab_consent_test.dart:31` a
`granted.consentVersion`-t adja tovább a package-be, azaz épp a konzisztens
esetet méri.

**Javasolt irány:** a writer a `consent.consentVersion`-t írja a manifestbe (a
grant az EGYETLEN forrás), vagy eltérés esetén típusos hibát dob. Kell hozzá
cella, ami a mai viselkedést pirosra viszi (eltérő package/consent verzió).

### MINOR-1 — Path-szerű `packageId` bekerül a szerializált kimenetbe

`lab_package_writer.dart:84` (annotation), `lab_capture_package.dart:117`
(manifest). MÉRVE: `packageId = "../OUTSIDE_VICTIM"` mellett a manifest
`"packageId":"../OUTSIDE_VICTIM"` útvonal-töredéket hordoz; normál id-nél a
kimenet tiszta (sem `/tmp`, sem `/home`, sem a root útja nem jelenik meg). A
MAJOR-1 validációja ezt is orvosolja — külön munkát nem igényel, de a lelet
zárását a D2 oldaláról is ellenőrizni kell.

### MINOR-2 — Teszttel nem bizonyított doc-comment állítás (`LabTask.id` egyedisége)

`lib/features/accuracy_lab/domain/lab_task.dart:19` — „Stable identifier,
**unique within its catalog**". A `LabTaskCatalog.validated`
(`:57-62`) kizárólag a hosszt méri; az egyediséget sem kód, sem teszt nem
kényszeríti ki. A brief §6 doc-comment fegyelme szerint doc-commentbe csak
teszttel bizonyított állítás kerülhet. **Zárás:** vagy a `validated` utasítsa
el a duplikált id-t (+ cella), vagy a doc-comment mondjon le az állításról.

### NOTE-1 — `capturedAt` UTC-normalizálás

`lab_capture_package.dart:118` `toUtc()`-t ír, a `fromJson` `DateTime.parse`-ot
olvas: egy lokális idejű bemenet ugyanazt a PILLANATOT adja vissza, de `isUtc`
flaggel. A determinizmus szempontjából ez helyes (ez teszi bájtazonossá), a
round-trip „veszteségmentes" a pillanatra nézve. Nem blokkol; ha a §10 vagy a
doc-comment ezt kimondja, később egyértelműbb.

### NOTE-2 — Ami MÉRVE rendben van

- **D7 — nulla kimenő csatorna:** a feature import-halmaza `dart:io`,
  `dart:typed_data`, `package:crypto/crypto.dart` + relatív importok. Nincs
  `share_plus`/`Dio`/`ApiClient`/`HttpClient`/`package:http`/`path_provider`.
  A `tool/check_data_inventory.dart` egress-felderítése tehát nem aktiválódik,
  a kör nem igényel `docs/privacy/data-inventory.yaml` bejegyzést.
- **D8 / architektúra:** saját WAV-kódoló (`_encodeWav`, `:126-163`), idegen
  feature barrelje nincs bővítve; az `architecture` gate zöld (12 allowlistelt
  deviáció, változatlan).
- **R6 (barrel):** nincs `lib/features/accuracy_lab/public/` fragment-könyvtár,
  a `public.dart` kézzel írott — a generált-barrel frissesség-őr nem aktiválódik.
- Nincs `print`/log a production fájlokban → nyers PCM nem kerülhet logba.
- Nincs új függőség; a `pubspec.yaml` érintetlen.

## 4. Merge-döntés

**CHANGES REQUESTED.** A két MAJOR merge előtt zárandó (ADR 0052: nyitott
MAJOR mellett nincs merge). A javító kört ugyanaz a motor (`sonnet-impl`)
viszi, a fenti leletlistával; a javításhoz **cellának kell tartoznia, ami a
MAI kódot pirosra viszi** — enélkül a zárás nem bizonyított (L160).

## 5. Javító kör után — a zárás ellenőrzése

| Lelet | Zárás feltétele |
|---|---|
| MAJOR-1 | validáció + cella, ami `packageId="../x"`-re és üres id-re a MAI kódon PIROS; a `delete` nem léphet ki a rootból |
| MAJOR-2 | a manifest `consentVersion`-je a `consent` paraméterből jön (vagy eltérésre típusos hiba) + cella az ELTÉRŐ esetre |
| MINOR-1 | a MAJOR-1 validációjának következménye, D2-oldali ellenőrzéssel |
| MINOR-2 | egyediség-kényszer + cella, VAGY a doc-comment állítás visszavonása |
