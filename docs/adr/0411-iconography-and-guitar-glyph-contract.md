# ADR 0411 — Iconography and guitar-glyph contract

**Státusz:** elfogadva (E13-R07 pre-flight, 2026-08-23).

Kapcsolódó források: [ADR 0273](0273-design-system-token-source-of-truth.md),
[ADR 0381](0381-semantic-theme-and-accessibility-contract.md),
[ADR 0383](0383-typography-and-text-scale-contract.md),
[`Chapter 13 §9.8`](../sdd/13-chapter-13-ui-ux-design-system.md) és
[`E13-R07`](../rounds/e13-r07-iconography-and-guitar-glyphs.md).

## Kontextus

A Chapter 13 §9.8 (a fájl 703–726. sora) egységes stroke-ot, 24 dp alapot,
32–48 dp Stage-méretet, Material Symbols alapot saját gitárglyph-készlettel,
kötelező semantics labelt interaktív ikonra, és production felületen emoji
helyett ikont ír elő. A készlet tizennégy nevesített glyph-je ugyanott van
felsorolva (`downstrum` … `loopAB`).

A pre-flight három mért tényt talált, amelyek a megvalósítás útját megkötik:

1. **Nincs SVG-renderer a fában.** A `flutter_svg` nem szerepel a
   `pubspec.yaml`-ben, és a Flutter beépítetten nem rendereli az SVG-t. Új
   ikon-csomag felvétele viszont a CLAUDE.md ONE-win32-major szabálya miatt
   külön kör tárgya, ezért a „vektoros asset" út ebben a körben nem járható.
2. **A `CustomPainter` a fa mért, függőségmentes vektor-útja.** Tíz production
   fájl használja, közte a `lib/features/live/widgets/strum_arrow.dart`, amely
   már ma is festett — nem karakteres — strum-jelet ad, semantics labellel.
3. **A `lucide_icons_flutter` NINCS a projektben.** A pruning után csak egy
   doc-comment említi (`reaction_bar.dart:99`). A fordítás-idejű ikonnév-hiba
   kockázata ettől nem szűnik meg: a Material `Icons.*` konstansok ugyanígy
   csak fordításkor bukhatnak, ezért a névkatalógus indoka változatlanul él.

## Döntés

1. **A saját gitárglyph-ek festettek, nem asset-alapúak.** A tizennégy glyph a
   `SsGuitarGlyphs` `CustomPainter`-készleteként valósul meg, pure-Dart
   vektorként. Nem kerül `assets/icons/` könyvtár a fába, és a `pubspec.yaml`
   érintetlen marad — sem asset-bejegyzés, sem új `dependencies:` sor.
2. **Egy stroke-forrás.** Minden saját glyph ugyanabból a névvel ellátott
   stroke-arányból számolja a vonalvastagságát, az optikai méretet pedig a
   kért dp-méretből. Painter nem találhat ki saját vonalvastagságot — ez a
   §9.8 „egységes stroke" előírásának gépi alakja.
3. **A strum-irány saját glyph, nem nyílkarakter.** A `downstrum`/`upstrum`
   festett jel; `Text('↓')`, `Text('↑')` vagy bármely `←`–`⇿`
   tartományba eső karakter a design system ikon-rétegében tiltott. Indok: kis
   méretben összetéveszthető, és a képernyőolvasó „lefelé mutató nyíl"-at
   olvas a zenei jelentés helyett.
4. **Az interaktív és a dekoratív ikon két külön, kikényszerített szerep.** Az
   interaktív ikon semantics labelt ÉS tooltipet követel, mindkettő
   hívó-oldali, nem üres szöveg; a dekoratív ikon ki van zárva a semantics
   fából, hogy ne zajosítsa a felolvasást. A design system a labelt nem
   lokalizálja: a szöveget a hívó adja, a réteg `AppLocalizations`-mentes
   marad (ahogy a többi `lib/core/design_system/**` fájl).
5. **A méretszerződés kétszintű.** `SsIconSize.base = 24`,
   `stageMin = 32`, `stageMax = 48`; a Stage-tartomány MINDKÉT vége inkluzív.
   A `stage` kontextusban a tartományon kívüli kérés **elutasított**: a
   predikátum hamis, és a tényleges widget-úton a renderelt méret a
   legközelebbi érvényes Stage-értékre áll be — a kért 24 dp NEM juthat át
   Stage-re. Az `assert` önmagában nem elég, mert release buildben nem fut.
6. **A hiányzó glyph LÁTHATÓAN esik vissza.** A feloldatlan névre festett,
   nem nulla kiterjedésű fallback-jel kerül, a feloldás eredménye pedig
   gépileg lekérdezhető (`isFallback`). `SizedBox.shrink()`, üres `Container`
   vagy bármely nulla méretű ág tilos: az néma információvesztés.
7. **A funkcionális emoji FELMÉRVE, nem javítva.** A production
   `lib/features/**` felmérése leletként rögzül a kör §10-ében; a tényleges
   csere a képernyő-migrációs körök (Ch13 Kör 16–35) hatásköre.

## Következmények

- Az ikon-réteg nulla új plugin- és asset-kockázattal áll be, tehát a
  win32-major szabály nem sérül, és a `pubspec.yaml` diffje üres marad — ez
  önmagában a scope-audit gépi bizonyítéka.
- A stroke-egységesség, a méretküszöb és a fallback-láthatóság mind unit
  cellával falszifikálható, nem csak szemrevételezéssel.
- A strum-irány jelzésének két, egymástól független megvalósítása él
  átmenetileg: a `features/live` meglévő `StrumArrow` és a design system új
  glyph-je. Az összevonás a képernyő-migrációs körök dolga; ez a kör a
  `lib/features/**`-hez nem nyúl.
- A semantics szerződés a hívóra hárítja a szöveget, így a későbbi migrációs
  körök ARB-kulcsokat adhatnak anélkül, hogy a design system l10n-függővé
  válna.

## Elvetett alternatívák

- **SVG asset + `flutter_svg`:** új függőség, amit a §9.8 megvalósítása nem
  indokol, és a ONE-win32-major szabály miatt külön mérést kívánna.
- **Ikon-font (.ttf) asset:** bináris artefaktum, amit ez a lánc nem tud
  reprodukálhatóan előállítani vagy review-zni; a `CustomPainter` ugyanazt a
  skálázhatóságot adja olvasható forrással.
- **PNG-készlet:** nem vektor, Stage-méreten életlen, és témánként külön
  változatot kívánna.
- **Nyílkarakter a strum-irányra:** nulla munkával kész, és pont a termék
  megkülönböztető jelzését teszi olvashatatlanná kis méretben és
  képernyőolvasóval.
- **Néma (`SizedBox.shrink()`) fallback:** a hiányzó glyph észrevétlen marad,
  ezért sokáig életben tud maradni.
