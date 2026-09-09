# Ch14 Kör 39 — adaptív, akadálymentességi és kültéri audit

- **Kör:** E14-R39 · **Csomag:** PKG-C · **ADR:** [0547](../adr/0547-narrow-viewport-colour-vision-and-outdoor-contrast.md)
- **Készült:** 2026-09-09, `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK ezen a boxon → **egyetlen cella sem
  futott le itt**. A számok statikusan, a repó saját, kipinnelt WCAG
  transzformjával (`tool/ui_contrast_check.dart`) készültek; a futtatás
  mércéje a CI (`full-gate.yml`).

Két oszlop van, és a különbség kötelező (Ch14 §9, ADR 0271):

- **MÉRVE (teszt-pinnelt)** — van olyan cella, ami az állítást elbukná, ha
  nem lenne igaz. A cella neve itt szerepel.
- **NEM MÉRVE** — nincs rá cella. Ide semmilyen szám nem kerül becslésként.

---

## 1. Adaptív / méret-profil

| Állítás | Státusz | Bizonyíték |
|---|---|---|
| compact 412 / landscape / medium / expanded × textScale 1,0–2,0 golden-mátrix | MÉRVE (korábbi kör) | `test/ui/goldens/e13_r36_variant_matrix_test.dart`, `e15_r13_full_variant_matrix_test.dart` |
| **360 px portré profil, overflow/kivétel nélkül** — Today hub, Tuner, Metronome, `en`+`hu`, textScale 1,0 / 1,3 / 2,0 | **MÉRVE (új)** | `test/ui/e14_r39_narrow_viewport_matrix_test.dart` → „the 360 px profile renders every PKG-C screen cleanly" (30 cella) |
| a 360 px profil új E14-R36 felületei (lánc-recap a Today-n, lánc-átadás a hangolón) | **MÉRVE (új)** | ugyanott, „…chain on its recap" / „…chain hand-off visible" cellák |
| a túlcsordulás-detektor tényleg lát túlcsordulást | **MÉRVE (új)** | ugyanott, „the detector itself → a row that really does not fit 360 px IS reported" |
| nincs orientation lock | MÉRVE (korábbi kör) | E12-R20 audit, `docs/accessibility/release-audit.md` |
| 360 px profil a NEM PKG-C képernyőkre (Live stage, Practice session, Songs, Coach, Profile) | **NEM MÉRVE** | tulajdonos: PKG-F (Live/Practice) és a megfelelő csomagok; ez a kör csak a saját képernyőit fedi |

---

## 2. Színlátás / szürkeárnyalat

| Állítás | Státusz | Bizonyíték |
|---|---|---|
| „nincs csak-színnel közölt állapot" | MÉRVE (korábbi kör) | E13-R14 akadálymentességi toolkit cellái |
| **a konfidencia-tokenek szürkeárnyalatos szétválása egyik témában sem éri el a 3:1 padlót** | **MÉRVE (új, LELET)** | `test/accessibility/e14_r39_colour_vision_test.dart` → „no pair of confidence tokens reaches even the 3:1 non-text floor" |
| a legrosszabb pár: dark `confidenceHigh` ↔ `confidenceMedium` = **1,01:1** | **MÉRVE (új, LELET)** | ugyanott, „the worst pair is a total collapse" |
| a szétválás-metrika hamisítható (fekete/fehér = 21:1, önmaga = 1:1) | **MÉRVE (új)** | ugyanott, „the metric itself is falsifiable" |
| minden `SsStatusMarkerKind` saját ikont kap | **MÉRVE (új)** | ugyanott, „every status-marker kind has its OWN icon" |
| a konfidencia-badge a szinteket CÍMKÉVEL különbözteti meg, és `textPrimary`-vel fest (nem státusz-hue-val) | **MÉRVE (új)** | ugyanott, „the confidence badge distinguishes high/medium/low by LABEL…" |
| a hangoló in-tune / out-of-tune állapota ikonnal is elkülönül, teljes hue-vesztés alatt | **MÉRVE (új)** | ugyanott, „the tuner keeps its state under total hue loss" |
| valódi színtévesztő felhasználó általi olvashatóság (protan/deutan/tritan szimuláció perceptuális validálása) | **NEM MÉRVE** | a `ColorFiltered` szűrő csak azt bizonyítja, hogy a fa renderelődik hue nélkül; a *érzékelési* validálás ember |

### Mért szürkeárnyalatos szétválás (WCAG-arány, hue nélkül ez az egyetlen csatorna)

| pár | dark | light |
|---|---|---|
| confidenceHigh ↔ confidenceMedium | **1,01** | 1,18 |
| confidenceHigh ↔ confidenceLow | 2,50 | 1,57 |
| confidenceMedium ↔ confidenceLow | 2,52 | 1,33 |

**Következmény (nem javítva ebben a körben):** a konfidencia-szint SOHA nem
közölhető csak színnel — a paletta ezt nem tudja kiszolgálni. A tokenek
tulajdonosa `lib/core/theme/**` + `lib/core/design_system/foundations/**`,
egyik sem PKG-C.

---

## 3. Reduced motion

| Állítás | Státusz | Bizonyíték |
|---|---|---|
| `SsMotionScope` háromcellás feloldás (app override true/false/null) | MÉRVE (korábbi kör) | `test/core/design_system/motion/ss_motion_scope_test.dart` |
| `SsBeatPulse` (design system) reduced motion alatt nem skáláz, de a szín lépked | MÉRVE (korábbi kör) | `test/core/design_system/motion/ss_beat_pulse_test.dart` |
| **a SZÁLLÍTOTT metronóm-pulzus (`BeatPulseDot`) reduced motion alatt nem skáláz, de a szín lépked** | **MÉRVE (új, JAVÍTVA)** | `test/accessibility/e14_r39_reduced_motion_test.dart` → „reduced motion: no scale, but the pulse still steps with the beat" |
| ugyanez CSAK a platform-kapcsolóból, app-szintű override nélkül | **MÉRVE (új)** | ugyanott, „the PLATFORM setting alone is enough" |
| full motion alatt a pont tényleg skáláz (hamisítási cella) | **MÉRVE (új)** | ugyanott, „full motion: the dot really does scale…" |
| a Live hero per-beat pulzusa reduced motion alatt nem skáláz | **NEM MÉRVE — NYITOTT LELET** | `lib/features/live/widgets/chord_timeline.dart:204` (`.animate(key: ValueKey('beat-$beat')).scaleXY(begin: 1.022 …)`) nem néz `SsMotionScope`-ot. Tulajdonos: **PKG-F**. Javasolt patch: `e14-r39-adaptive-accessibility-outdoor-audit.md` §10 |
| a Live feedback-animáció (belépő flash / shimmer) reduced motion alatt visszafogott | **NEM MÉRVE — NYITOTT LELET** | ugyanaz a fájl, ugyanaz a tulajdonos |
| reduced motion alatt a Live akkord-információ nem vész el és a fa lenyugszik | **MÉRVE (új)** | `test/accessibility/e14_r39_reduced_motion_test.dart` → „the recognised chord stays fully readable…" |

---

## 4. Kültéri olvashatóság / kontraszt

| Állítás | Státusz | Bizonyíték |
|---|---|---|
| a dark (szállított) téma minden szöveg- és státusz-tokenje ≥ 4,5:1 a canvason | **MÉRVE (új)** | `test/accessibility/e14_r39_outdoor_contrast_test.dart` → „every text and status token clears the 4.5:1 text floor" |
| dark `confidenceLow` = 4,04:1 → indikátornak jó, szövegnek NEM | **MÉRVE (új, LELET)** | ugyanott, „MEASURED GAP — confidenceLow…" |
| **light téma `brand` = 2,40:1 → a 3:1 indikátor-padló ALATT** | **MÉRVE (új, LELET)** | ugyanott, „the brand accent falls below even the 3:1 indicator floor" |
| **light téma `info` (secondary amber) = 1,93:1 → a paletta legrosszabb tokenje** | **MÉRVE (új, LELET)** | ugyanott, „the info/secondary amber is the worst token" |
| light `danger` (3,27) és `success` (3,84) indikátornak jó, szövegnek nem | **MÉRVE (új, LELET)** | ugyanott, „danger and success are indicator-legal but NOT text-legal" |
| light `textPrimary` / `textSecondary` / `warning` / `confidenceLow` ≥ 4,5:1 | **MÉRVE (új)** | ugyanott, „what still holds…" |
| **a High Contrast téma NEM emel kontrasztot** — csak a keretvastagságot (1→2) és a fókuszgyűrűt (2→4) növeli, a dekoratív effekteket kikapcsolja, és **csak dark-ban létezik** | **MÉRVE (új, LELET)** | ugyanott, „MEASURED: it thickens borders and drops decorative effects" |
| a stage-képernyők (Today hub, Tuner) kivétel nélkül renderelődnek High Contrast témán | **MÉRVE (új)** | ugyanott, „the stage screens render under the High Contrast theme" |
| **valódi kinti fényben, 1–2 m-ről, legalább 3 telefonon olvasható-e a Live/Today/Tuner** | **NEM MÉRVE — EMBERI MÉRÉS** | protokoll: E14-R40 field study (PKG-D). Ehhez napfény, készülékek és ember kell; teszttel kipipálni hazugság lenne |
| a Live stage saját tokenjeinek kontrasztja | **NEM MÉRVE** | tulajdonos: PKG-F |

### Mért kontraszt-arányok (canvas ellenében)

| token | dark | light |
|---|---|---|
| textPrimary | 15,11 | 15,26 |
| textSecondary | 5,77 | 5,14 |
| brand | 6,93 | **2,40** |
| info | 8,65 | **1,93** |
| success | 10,09 | **3,84** |
| warning | 10,20 | 4,53 |
| danger | 5,09 | **3,27** |
| confidenceLow | **4,04** | 6,01 |

Vastag = a saját szintjének padlója alatt (szöveg 4,5:1; a 2,40 és az 1,93 a
3:1 nem-szöveg padló alatt is).

---

## 5. Nyitott tételek, felelőssel

| # | Lelet | Tulajdonos | Miért nem itt |
|---|---|---|---|
| R39-1 | A light téma `brand` (2,40) és `info` (1,93) tokenje a 3:1 padló alatt van, `success`/`danger` a 4,5 alatt — a light téma a KÜLTÉRI mód | `lib/core/theme/app_colors.dart`, `app_palette.dart` | nem PKG-C tulajdon; paletta-változtatás mérés nélkül tilos, itt viszont a mérés MEGVAN, tehát a következő paletta-kör bemenete |
| R39-2 | A konfidencia-tokenek szürkeárnyalatban egybeesnek (legrosszabb 1,01:1) | ugyanaz | ugyanaz; a mitigáció (ikon + címke) mérve van |
| R39-3 | A High Contrast téma nem emel kontrasztot és nincs light változata | `lib/core/design_system/themes/**` | nem PKG-C tulajdon |
| R39-4 | A Live hero per-beat skála-pulzusa és a feedback-animáció figyelmen kívül hagyja a reduced motion beállítást | **PKG-F** (`lib/features/live/widgets/chord_timeline.dart`) | csomag-tulajdon; a javasolt patch a kör-brief §10-ben |
| R39-5 | Kültéri olvashatósági checklist (napfény, 1–2 m, ≥3 telefon) | E14-R40 field study, PKG-D | ember + eszköz kell |
| R39-6 | 360 px profil a nem-PKG-C képernyőkre | a megfelelő csomagok | csomag-tulajdon |

`docs/accessibility/known-exceptions.yaml` **nem bővült** ebben a körben: a
registry *tűréseket* tart nyilván, ez a kör pedig nem vezetett be tűrést — a
fenti leletek pontos értékű, magától elavuló állításként vannak kipinnelve
(ADR 0547 D5). Emiatt az A6 mirror-őr
(`release_flow_semantics_test.dart`) sem változott.
