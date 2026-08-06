# E05-R07 — Review

Brief: `docs/rounds/e05-r07-frame-transform-and-overlay-coordinates.md`
Diff: `git diff origin/main...codex/e05-r07-frame-transform-and-overlay-coordinates`
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-06
Implementer: Terra (Codex CLI, `gpt-5.6-terra`) — 1 fő forduló (`089953e`) + 1
gate-only folytatás (üres diff, `scope_audit_changed=0`), a köztes `blocked`
jelzés oka klón-artefaktum (hiányzó generált `lib/l10n/`), nem kódhiba —
részletek a Megjegyzések alatt.
Verdikt: **CHANGES REQUESTED**
Dedikált security review (kötelező, brief `risk = "high"`):
[`e05-r07-frame-transform-and-overlay-coordinates-security.md`](e05-r07-frame-transform-and-overlay-coordinates-security.md)
— **PASS** (0 CRITICAL/BLOCKER; 1 MAJOR + 1 MINOR/NOTE carried forward, nem
blokkolja EZT a kört — indoklás a security jelentésben; kötelező előfeltétel
R13/R15/R24 előtt, amikor ez a réteg valós kamera-metaadathoz kötődik).

## Összegzés

Ez a (funkcionális) review: BLOCKER: 0 · MAJOR: 1 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Numerikus fixture-mátrix (16 cella × 3 pont, kézzel számolt) | ✅ | `test/core/camera/camera_transform_test.dart:25-71`; a brief §10 `python3 -c` levezetése és a teszt `_f(...)` hívásai 5/16 cellán kézzel keresztellenőrizve (r0/r90/r180/r270 mix, fit+fill), mind egyezik |
| 2 | Property teszt: (a) round-trip ≤1e-6, (b) kettős mirror = identitás, (c) 4×90° = identitás, (d) fit/fill bennmarad a preview téglalapban | ✅ | `test/property/camera_transform_property_test.dart` — mind a négy property jelen van, saját `/tmp` klónban újrafuttatva `PROPERTY_SEED=42`-vel, 4/4 zöld |
| 3 | Letterbox-teszt: fit-offset, fill-crop, határon (egyező arány) offset=0 | ✅ | `test/core/camera/preview_fit_test.dart:8-48` — mindhárom cella jelen van |
| 4 | Valódi-sértés próba: mirror áthelyezése normalized térbe → PIROS → visszaállítás | ✅ | **Függetlenül reprodukálva** (nem csak a §10 bemondása alapján): `PreviewFit.toModelInput()` ideiglenes mutációja (`a:-1, tx:1`) → `front preview mirroring cannot alter the model input space` teszt ténylegesen PIROSRA vált (lásd a jelentés végi próbateszt-napló); a mutáció visszaállítva, a review-klón tiszta |
| 5 | §6.1 küszöb-mátrix (alatta/rajta/fölötte, ULP-pontos) | ✅ | `test/core/camera/camera_transform_test.dart:73-89` — bit-szintű `_nextUp`/`_nextDown` ULP-manipulációval, a „rajta" cella explicit inkluzív |
| 6 | `lib/core/` szabály: nincs `dynamic`, nincs `dart:ui`, nincs feature-import | ✅ | Import-sweep mind a 6 fájlon: kizárólag `dart:math` + a két testvér core-fájl; `architecture` gate zöld (`tool/check_architecture.dart`, saját klónban is újrafuttatva) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat origin/main...HEAD` (saját `/tmp/review-e05r07` klónban, Terra push-a után) pontosan a brief §4 hét fájlját mutatja:
`lib/core/camera/camera_transform.dart`, `lib/core/camera/camera_coordinate_space.dart`,
`lib/core/camera/preview_fit.dart`, `test/core/camera/camera_transform_test.dart`,
`test/core/camera/preview_fit_test.dart`, `test/property/camera_transform_property_test.dart`,
`docs/rounds/e05-r07-frame-transform-and-overlay-coordinates.md`. `scope_audit=ok` mindkét
jelzésben (`scope_audit_changed=7`, majd a gate-only fordulón `=0`).

## Megállapítások

### F1 — MAJOR — Az „overlay" tér deklarálva van, de egyetlen transzformáció sem éri el

- **Fájl:** `lib/core/camera/camera_coordinate_space.dart:109-124` (`OverlayPoint`),
  `camera_coordinate_space.dart:11` (`CameraCoordinateSpace.overlay`)
- **Probléma:** a brief §1 Célja szó szerint öt teret nevez meg: „sensor → upright
  → normalized → preview → **overlay**", és a §5.1 kötött döntés kimondja, hogy „a
  presentation **kizárólag** ezt a mappinget használhatja **overlayhez**" — azaz ez a
  kör ígéri az overlay-mapping egyetlen igazságforrását. A ténylegesen leszállított
  lánc (`sensorToUpright` → `uprightToNormalized` → `PreviewFit.toPreview/
  toNormalized`) viszont **megáll a `PreviewPoint`-nál**: `OverlayPoint` és
  `CameraCoordinateSpace.overlay` deklarálva van (egyenlőség/hashCode is jár hozzá),
  de a diffben SEHOL nem szerepel `CameraTransform<…, OverlayPoint>` vagy
  `…toOverlay()` — grep-elve mind a 3 lib-fájlban és mind a 3 teszt-fájlban, egy
  találat sincs a saját deklaráción kívül.
- **Hatás:** a leendő R24 (overlay-widget) körnek NINCS szentesített mappingje az
  overlay térbe — pontosan azt a helyzetet állítja elő, amit az §5.1 explicit ki
  akar zárni („NEM elfogadható widgetbe írt gyors korrekció"). A checkbox-szintű §6
  acceptance criteria (fixture/property/letterbox/sértés-próba) egyike sem nevezi meg
  külön az overlay-mappinget, ezért ez zöld gate mellett csúszott át — a brief saját
  mérce-mátrixának hiányossága, nem a teszteké.
- **Kötelező javítás:** vagy (a) egészítsd ki a láncot egy tényleges
  `PreviewPoint`/`NormalizedPoint` → `OverlayPoint` transzformmal (ha az overlay tér
  szándékosan eltér a preview tértől, pl. device-pixel-ratio miatt), vagy (b) ha az
  overlay tér SZÁNDÉKOSAN azonos a preview térrel, dokumentáld ezt explicit
  doc-commentben ÉS adj hozzá egy identitás-transzformot/tesztet, ami ezt bizonyítja
  — ne maradjon néma, fel nem használt típus. A döntés architekturális, ezért vagy a
  javító kör dokumentált §0.0-jában, vagy egy explicit brief-revízióban rögzítendő.
- **Ellenőrzés:** új teszt, ami `OverlayPoint`-ot ténylegesen egy
  `CameraTransform`-on keresztül állít elő (nem csak konstruktorral), plusz a
  fixture-mátrix vagy egy külön overlay-cella ugyanazzal a kézi-levezetési
  fegyelemmel (§10 mintájára).
- **Státusz:** OPEN

### F2 — MINOR — `isRoundTripErrorWithinTolerance` és a property teszt függetlenül mérnek

- **Fájl:** `lib/core/camera/camera_transform.dart:82-84`,
  `test/property/camera_transform_property_test.dart:53-61`
- **Probléma:** a küszöb-mátrix unit tesztje (`camera_transform_test.dart:73-89`) a
  `CameraTransform.isRoundTripErrorWithinTolerance` segédfüggvényt méri ULP-pontosan,
  de a property teszt a round-trip hibát KÖZVETLENÜL számolja
  (`(roundTrip.x - point.x).abs() / sensorSize.width` és `lessThanOrEqualTo`), a
  segédfüggvényt nem hívja. A két bizonyíték nem egy code-path-on megy — ha valaki a
  segédfüggvény szemantikáját eltolja, a property teszt ezt nem venné észre.
- **Hatás:** kis kockázat, mert mindkét teszt önmagában helyesen fedi a saját
  állítását; csupán a „single source of truth" elve sérül a segédfüggvény szintjén.
- **Kötelező javítás:** nem blokkoló — follow-up: a property teszt cserélje a nyers
  hányados-számítást `CameraTransform.isRoundTripErrorWithinTolerance(...)` hívásra.
- **Ellenőrzés:** a property teszt továbbra is zöld marad a csere után.
- **Státusz:** OPEN (follow-up, nem blokkolja ezt a kört)

### F3 — NOTE — `BufferPoint` / `CameraCoordinateSpace.buffer` szintén felhasználatlan

- **Fájl:** `lib/core/camera/camera_coordinate_space.dart:38-53`
- **Megfigyelés:** a `buffer` tér NINCS megnevezve a brief §1 öt-tér láncában
  („sensor → upright → normalized → preview → overlay") — ezért ez, az F1-től
  eltérően, nem ígért-és-hiányzó funkció, csak egy előre felvett, egyelőre
  felhasználatlan bővítési pont (pl. platform-raw-buffer vs. advertised-sensor-size
  eltérésekhez). Nem blokkol; érdemes megemlíteni egy jövőbeli körnek, ha ez a típus
  hosszabb távon is holt kód marad.
- **Státusz:** nem blokkol

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (Terra jelzése) | Ellenőrizve (saját `/tmp/review-e05r07` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/core/camera | zöld (66, majd 62 teszt — l. megjegyzés) | ✅ zöld, 66 teszt |
| test test/property/camera_transform_property_test.dart | zöld (4 property) | ✅ zöld, 4 property, `PROPERTY_SEED=42` |
| architecture | zöld | ✅ zöld („12 allowlisted deviation(s)", a körhöz nem kapcsolódó, meglévő allowlist) |
| secrets | (a kör-gate 2. fordulós futtatásában zöld) | ✅ zöld (1825 fájl, 0 találat) |
| l10n | (ua.) | ✅ zöld (en→hu, 913 üzenet) |
| CI (teljes suite + property + APK) | — | orchestrátor dispatch-eli a fix kör után |

**Megjegyzés a köztes `blocked` jelzésről:** Terra első fordulója (`089953e`) helyesen
implementálta a teljes kört és a célzott `flutter analyze`/`flutter test` hívásokat
zölden futtatta, de a KÖTELEZŐ `tools/round-gate.sh` az `analyze` fázisban 882,
**scope-on kívüli** hibával blokkolt — egy friss klón hiányzó, gitignore-olt
`lib/l10n/app_localizations*.dart` generált fájlja miatt (dokumentált, ismételten mért
klón-artefaktum, ld. `HANDOFF.md` E04-R16 pre-flight tanulság: „nem H6"). Az
orchestrátor `tools/prepare-flutter-generated.sh`-t futtatta az implementer
munkapéldányán (`flutter pub get && flutter gen-l10n`), majd egy szűken skótozott
gate-only folytató fordulót indított — az nulla kód-diffel (`scope_audit_changed=0`)
zöld gate-et jelzett. A `test test/core/camera` tesztszám-eltérés (66→62 az
első/megjegyzésben, majd a valós újrafuttatásban 66) elírás volt Terra saját log-
összegzésében, nem valódi regresszió — a review saját futása 66-ot mért mindkét
körben.

## Merge-döntés

**CHANGES REQUESTED — F1 (MAJOR) nyitva.** Az ADR 0052 szerint minden gate zöld ÉS
nincs nyitott BLOCKER/MAJOR szükséges a merge-hez; F1 nyitva van, ezért a merge
jelenleg TILOS. Javító kör indul UGYANAZZAL a motorral (Terra) az F1 (és opcionálisan
F2) leletlistával. F3 nem blokkol, follow-up.
