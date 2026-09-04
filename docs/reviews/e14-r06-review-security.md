# Biztonsági review — E14-R06 (Accuracy Lab + consented capture)

- Branch: `sonnet-impl/e14-r06-accuracy-lab-and-consented-capture` @ `bb860903`
- Munkapéldány: `/home/ubuntu/ss-sonnet-impl-e14-r06` (READ-ONLY nézve)
- Próbák: `/tmp/sec-e14-r06` (a klón másolata), `dart run probe.dart`
- ADR: `docs/adr/0358-consented-on-device-lab-capture-package.md` D1–D8
- Hatókör: 5 új production fájl a `lib/features/accuracy_lab/` alatt, 3 teszt.
  A `LabPackageWriter` jelenleg **UNWIRED** — nincs production hívó (mérve:
  `grep -rn "LabPackageWriter\|\.write(\|\.delete(" lib/` csak a definíciót és
  a doc-kommenteket adja).

## Osztályozott leletek

### MAJOR-1 — Path traversal a `locate()`/`delete()`-ben: root-on kívüli rekurzív törlés
`lib/features/accuracy_lab/data/lab_package_writer.dart:52`
(`Directory('${root.path}/$packageId')`), kihat: `write` (72–73, 79),
`delete` (116–121, `deleteSync(recursive: true)`), `status` (105).

**Failure scenario (MÉRVE, Probe 2):** `packageId = "../OUTSIDE_VICTIM"` esetén
a cél a root testvérkönyvtára lesz. A próba kimenete:
```
locate(root=.../lab-root, id="../OUTSIDE_VICTIM")
  -> directory.path = .../lab-root/../OUTSIDE_VICTIM
  write() SUCCEEDED, manifest at .../lab-root/../OUTSIDE_VICTIM/manifest.json
  delete(recursive) done. victim precious.txt still exists? false
  victim dir still exists? false
```
A `delete(recursive: true)` **a root-on kívüli, nem a Lab által létrehozott
`OUTSIDE_VICTIM/` könyvtárat is törölte** (a benne lévő `precious.txt`-tel
együtt). Nincs `packageId`-validáció (nincs `..`/szeparátor/üres tiltás,
nincs canonicalize + `isWithin(root)` ellenőrzés).

Két további degenerált eset ugyanabból a gyökérből (MÉRVE):
- **Üres id:** `locate(root, '')` → `directory.path == "<root>/"`, azaz maga a
  root. `delete(root, packageId: '')` a **teljes root könyvtárat** (az összes
  csomagot) rekurzívan törölné.
- **Abszolút id:** `${root.path}/<abs>` konkatenáció miatt kettős perjel
  (`.../lab-root//tmp/...ABS_VICTIM`) — ez a root alatt marad, tehát abszolút
  id-vel a FS-gyökérig nem szökik ki, de `..`-vel korlátlanul igen.

**Sértett szabály:** ADR 0358 D4 (a törlés a fájlrendszert érinti — igaz, de
korlátlanul); a review-mandátum „path traversal / RCE" kategóriája.

**Miért MAJOR és nem CRITICAL/BLOCKER most:** a defektus bizonyítottan
kihasználható, de **nincs production hívó**, amely nem generált, path-szerű
`packageId`-t adna át. A `packageId` a `fromJson`-ből is jöhet
(`lab_capture_package.dart:131`), így egy visszaolvasott/importált manifest
path-szerű id-je is ide folyna — de ilyen olvasó-hívó sincs a diffben.

**Escalation:** ez a lelet **CRITICAL-lé válik abban a pillanatban, amikor
bármely hívó** nem-generált, felhasználói/perzisztált/importált eredetű
`packageId`-t ad a `write`/`locate`/`delete`/`status` bármelyikének. A
bekötő kör előtt javítandó.

**Javítás iránya:** `packageId` validálása belépéskor (allowlist-regex, pl.
`^[A-Za-z0-9_-]+$`, üres tiltva), VAGY canonicalize után
`p.isWithin(root.path, resolved)` fail-closed ellenőrzés a `locate`-ben, hogy
a feloldott útvonal a root-on belül maradjon; ismeretlen/kilógó id → típusos
hiba, nem néma művelet.

### MAJOR-2 — A `write()` a `consent` paramot SOHA nem olvassa; a manifest a hívó által adott `consentVersion`-t rögzíti
`lib/features/accuracy_lab/data/lab_package_writer.dart:66–96`
(a `consent` paraméter csak típuskapu; a manifest a 89–92 sorban
`package.toJson()`-ből veszi a `consentVersion`-t, ami a
`lab_capture_package.dart:110` szerinti, HÍVÓ által megadott mező).

**Failure scenario (MÉRVE, Probe 1):**
```
actual granted consent.consentVersion = consent-v2-2026
manifest records: {... "consentVersion":"v1-stale" ...}
=> manifest consentVersion matches ACTUAL grant? false
```
A ténylegesen átadott `LabConsentGranted(consentVersion: 'consent-v2-2026')`
ellenére a manifest a `package.consentVersion = 'v1-stale'` értéket rögzíti.
A consent-audit-nyom (melyik consent-verzióhoz egyezett bele a felhasználó)
**el van választva a tényleges engedélytől** — egy stale/hibás `package`
mező azt írhatja, hogy a felhasználó olyan verzióhoz járult hozzá, amelyhez
nem.

**Sértett szabály:** ADR 0358 D1 szelleme (a consent a típusban él — a
*kapu* teljesül, de a *rögzített érték* nem az engedélyből származik).
Nem §5 határsértés (nincs consent-megkerülés: `write` továbbra is csak
`LabConsentGranted`-tel hívható), ezért MAJOR, nem BLOCKER.

**Javítás iránya:** a manifest `consentVersion`-jét a `consent`
paraméterből (`consent.consentVersion`) írja a writer, felülírva/validálva a
`package.consentVersion`-t; eltérés esetén típusos hiba, vagy egyszerűen a
grant az egyetlen forrás.

### MINOR-1 — Path-szerű `packageId` a szerializált kimenetbe kerül (D2 kereszthatás)
`lib/features/accuracy_lab/data/lab_package_writer.dart:84` (annotation),
`lib/features/accuracy_lab/domain/lab_capture_package.dart:117` (manifest).

**Failure scenario (MÉRVE, Probe 2 manifest):** `packageId = "../OUTSIDE_VICTIM"`
esetén a manifest tartalma `... "packageId":"../OUTSIDE_VICTIM" ...`, azaz egy
útvonal-töredék a szerializált kimenetben. Normál (nem path-szerű) id-nél a
kimenet tiszta (MÉRVE, Probe 3: sem `/tmp`, sem `/home`, sem a root útja nem
jelenik meg). Ugyanaz a validáció orvosolja, mint a MAJOR-1-et; önmagában
alacsony súly, mert normál id-vel nem szivárog.

### NOTE — Ami rendben van (bizonyítékkal)
- **D7 (nulla kimenő csatorna):** MÉRVE — a feature fájljainak import-halmaza
  csak `dart:io`, `dart:typed_data`, `package:crypto/crypto.dart` és lokális
  relatív importok. Nincs `share_plus`/`dio`/`ApiClient`/`HttpClient`/
  `package:http`/`path_provider` (grep: nincs találat). ✓
- **D2 (zárt kulcskészlet):** `LabDeviceMetadata.toJson`
  (`lab_capture_package.dart:41–47`) pontosan `modelName/osVersion/sampleRate/
  channelCount/appVersion`; a csomag `toJson` (115–122) `schemaVersion/
  packageId/capturedAt/consentVersion/device/events`; a manifest ehhez
  `audioSha256`-ot ad. Nincs e-mail/token/pontos hely/IMEI/hirdetési
  azonosító/felhasználónév/abszolút út a metaadatokban (MÉRVE, Probe 3). Az
  egyetlen szabad-szöveg vektor a `packageId` → MINOR-1. ✓
- **D3 (determinizmus):** nincs `DateTime.now()`/`Random(` a csomag-úton
  (grep: nincs); `capturedAt` a hívótól jön; kanonikus, rekurzív kulcsrendezés
  (`canonicalJsonEncode`, 154–181). ✓
- **D4 (törlés a FS-t érinti):** `status` `existsSync()`-re,
  `delete` `deleteSync(recursive:true)`-ra épül, nem flag. ✓
  (a korlátlanságát lásd MAJOR-1)
- **D5 (ismeretlen schemaVersion → típusos hiba):** `fromJson` 125–128 sor
  `schemaVersion != 1` (hiányzó/null is) → `LabCapturePackageSchemaVersionException`,
  fail-closed. ✓
- **Logolás:** nincs `print`/log a production fájlokban → nyers PCM/audio nem
  kerül logba. ✓
- **Függőség:** nincs új dependency; `crypto` már a fában van.

## Verdikt
Nincs bizonyított §5 határsértés és nincs jelenleg elérhető titok-szivárgás.
Két MAJOR javítandó merge előtt: (1) a `packageId` traversal/validáció —
escalál CRITICAL-lé bekötéskor —, (2) a consent-verzió provenance
(`consent` param olvasatlan). A csomag-szerződés D2/D3/D5/D7 része strukturálisan
teljesül.
