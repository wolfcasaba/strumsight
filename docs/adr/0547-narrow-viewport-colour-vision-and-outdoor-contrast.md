# ADR 0547 — 360 px profil, szürkeárnyalatos színlátás-cella és a kültéri kontraszt mért határa

**Státusz:** elfogadva (2026-09-09) · **Kör:** E14-R39 · **Csomag:** PKG-C ·
**Épít rá:** ADR 0274 (mozgás/reduced motion), ADR 0381 (szemantikus téma és
akadálymentességi szerződés), E12-R20 (known-exceptions registry) ·
**Nem érint** semmilyen DSP-küszöböt

## Kontextus (mért)

A Ch14 Kör 39 audit négy hézagot nevezett meg. Mindegyiket megmértük:

1. **360 px profil.** A szállított variant-mátrix (`e13_r36`, `e15_r13`) a
   legkisebb esetben **compact 412**-t használ. A 360 dp az Android-alapvonal
   (kis 5"-os készülék, illetve osztott képernyő) — nincs róla cella.
2. **Szürkeárnyalat / színlátás.** Volt „nincs csak-színnel közölt állapot"
   cella, de nem volt olyan, ami MEGMÉRI, mely szemantikus színek esnek
   egybe hue nélkül.
3. **Reduced motion.** A `SsBeatPulse` (design system) ADR 0274 óta betartja.
   A **szállított** pulzusok nem: a `BeatPulseDot`
   (`lib/features/metronome/beat_pulse_dot.dart:115`) feltétel nélkül skálázott
   (`scale = 1 + (1 - _phase) * 0.3`), a Live hero per-beat
   `flutter_animate` skálája (`chord_timeline.dart:204`) szintén.
4. **Kültéri / high-contrast.** A `SsHighContrastTheme` a fán
   `SsDarkTheme.build(highContrast: true)`.

### A mért kontraszt-számok

Az alábbiak a repó saját, kipinnelt sRGB relatív-luminancia transzformjával
készültek (`tool/ui_contrast_check.dart::ContrastCheck.relativeLuminance`;
a `0xff948d82 → 0.2695735834450039` érték egyezik).

| token (canvas ellenében) | dark | light |
|---|---|---|
| textPrimary | 15,11 | 15,26 |
| textSecondary | 5,77 | 5,14 |
| brand | 6,93 | **2,40** |
| info (secondary amber) | 8,65 | **1,93** |
| success | 10,09 | **3,84** |
| warning | 10,20 | 4,53 |
| danger | 5,09 | **3,27** |
| confidenceLow | **4,04** | 6,01 |

Szürkeárnyalatos szétválás a konfidencia-tokenek között (a 3:1 „nem-szöveg"
padló ellenében):

| pár | dark | light |
|---|---|---|
| high↔medium | **1,01** | 1,18 |
| high↔low | 2,50 | 1,57 |
| medium↔low | 2,52 | 1,33 |

## Döntés

### D1 — A 360 px profil OVERFLOW-mátrix, nem golden

Egy új méret goldenje csak PNG-forgalmat adna; az audit kérdése az, hogy
**eltörik-e** valamelyik elrendezés. A cella `FlutterError.onError`-t fog
(soha nem szöveg-heurisztikát a renderelt kimeneten, L558), 360×640
portré-viewporton, `en`/`hu` × textScale 1,0 / 1,3 / 2,0 bontásban, a PKG-C
képernyőire (Today hub, Tuner, Metronome) — beleértve az E14-R36 lánc két új
állapotát, mert azok ezen a méreten új felület. A mátrixot egy hamisítási
próba kíséri (egy 360-ba tényleg bele nem férő `Row`), különben minden
„tiszta" cella semmit sem bizonyítana.

### D2 — A színlátás-cella a szétválást MÉRI, nem a szándékot deklarálja

A tokenek szürkeárnyalatos szétválását a WCAG-arány adja meg (hue nélkül a
luminancia az egyetlen csatorna). A mérés eredménye: **a konfidencia-tokenek
EGYETLEN párja sem éri el a 3:1 nem-szöveg padlót egyik témában sem**, a
legrosszabb (dark high↔medium) 1,01:1 — vizuálisan egyetlen szürke.

Ez nem hibaként, hanem **kipinnelt mérésként** kerül a tesztbe: a cella azt
állítja, ami igaz. Ha egy jövőbeli paletta-kör megjavítja, ez a cella az,
ami pirosra vált — így az audit soha nem hivatkozhat egy már megszűnt hibára.
A mitigáció szintén mérve van: az `SsStatusBadge` a `textPrimary` tokennel
festi az ikont és a címkét (nem a státusz-hue-val), és a három konfidencia-szint
három KÜLÖNBÖZŐ címkét kap.

### D3 — A reduced motion ott landol kódban, ahol a csomag tulajdonos

A `BeatPulseDot` megkapja ugyanazt a szabályt, amit az `SsBeatPulse` már
alkalmaz (ADR 0274 §5.1): **nincs skálázás, de a szín továbbra is lépked a
ütemmel** — a pulzus funkcionális visszajelzés, ezért de-animálni kell, nem
eltüntetni. Az off-beat szín tompított brand, nem a `mutedColor`: különben a
futó metronóm minden ütem második felében pontosan úgy nézne ki, mint a
megállított.

A Live hero pulzusa (`chord_timeline.dart`) **PKG-F tulajdona**, ezért itt
nem változik. A tesztben az kerül rögzítésre, ami ma igaz: reduced motion
alatt a felismert akkord INFORMÁCIÓJA nem vész el és a fa lenyugszik. A
skálázás-elnyomás állítása a javasolt patch-csel EGYÜTT szállítható, előtte
nem — egy szándékosan piros cella nem audit, hanem törött kapu.

### D4 — A kültéri állítás kettéválik: mért kontraszt vs. emberi mérés

Ami gépi: a fenti luminancia-arányok. Ezek cellaként landolnak, a **bukó**
értékekkel együtt kipinnelve (light brand 2,40, light info 1,93).

Ami NEM gépi és nem is állítjuk: valódi napfény, 1–2 m olvashatóság, 3
telefon. Ez a `docs/accessibility/ch14-r39-audit.md` „nem mérve itt" sora
marad, felelőssel — nem pipáljuk ki teszttel.

### D5 — A `known-exceptions.yaml` NEM bővül ebben a körben

A registry **tűréseket** tart nyilván (a teszt elnézi a mért hibát). Ez a kör
nem vezet be tűrést: a light-téma kontraszt-hiányokat **pontos értékű
állítás** rögzíti a saját fájljában, ami szigorúbb, mint egy tűrés, és
magától pirosra vált, ha a paletta változik. Mivel nincs új tűrés, nincs mit
tükrözni az A6 mirror-őrben sem — a `release_flow_semantics_test.dart`
érintetlen marad. (A hibák tulajdonosa `lib/core/theme/**`, ami nem PKG-C.)

## Ami MÉRVE van és ami NINCS

**Mérve (cellával rögzítve):** a fenti két táblázat minden száma; a
`BeatPulseDot` reduced-motion viselkedése app-szintű override-dal ÉS csak a
platform-kapcsolóval; a full-motion hamisítási cella; a státusz-marker
ikonok egyedisége; a konfidencia-badge címke-egyedisége és `textPrimary`
festése; a hangoló in-tune/out-of-tune ikon-elkülönülése teljes hue-vesztés
alatt; a 360×640 mátrix 30 cellája + a detektor hamisítási próbája.

**NINCS mérve:** egyetlen futtatás sem (nincs Dart SDK a boxon); a valódi
kültéri olvashatóság; a színtévesztés-szimuláció *érzékelési* oldala (a
`ColorFiltered` szűrő azt bizonyítja, hogy a fa renderelődik hue nélkül — az
ikon/címke állítások bizonyítják, hogy az ÁLLAPOT is megmarad); és az, hogy
a 360 px cellák CI-ben zöldek-e — ha valamelyik pirosra vált, az **valódi
lelet**, amit regisztrálni kell, nem elnyomni.
