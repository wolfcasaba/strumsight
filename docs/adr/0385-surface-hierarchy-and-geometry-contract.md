# ADR 0385 — Surface hierarchy and geometry contract

**Státusz:** elfogadva (E13-R05 pre-flight, 2026-08-21).

Kapcsolódó források: [ADR 0273](0273-design-system-token-source-of-truth.md),
[ADR 0381](0381-semantic-theme-and-accessibility-contract.md),
[`Chapter 13 §8.2, §9.5–§9.6 és Kör 5`](../sdd/13-chapter-13-ui-ux-design-system.md),
valamint [`E13-R05`](../rounds/e13-r05-spacing-and-surfaces.md).

## Kontextus

Az E13-R02 már letette a 4 dp spacing- és a radius-skálát, az E13-R03 pedig a
három téma szemantikai színcontractját. A Chapter 13 következő lépése nem új
geometriai igazságforrás, hanem olyan surface-primitívek létrehozása, amelyek
a szintet, a hátteret, a bordert és a rövid árnyékot együtt oldják fel. A
legacy palettában a `surfaceRaised` jelenleg azonos lehet a `surface`
értékével, ezért a puszta tokenválasztás sötét témában nem minden esetben adna
látható hierarchiát.

## Döntés

1. Az egyetlen spacing- és radius-forrás továbbra is az `SsSpacing` és az
   `SsRadius`. A compact, medium és expanded képernyőpadding rendre
   `space4` (16 dp), `space6` (24 dp) és `space8` (32 dp). Az új primitivek
   nyers `EdgeInsets`- vagy radius-számot nem vezethetnek be.
2. Az `SsElevation` zárt `base`, `raised`, `overlay`, `modal` hierarchiát ad.
   Minden szint egyetlen resolveren keresztül köti össze a szemantikai
   háttérszínt, bordert és legfeljebb rövid, központosított shadowt; a hívó
   külön háttérszínt nem adhat a szint mellé.
3. Dark Studio alatt a szintek elsődleges jele a surface-lightness és a border;
   erős, nagy shadow tilos. Warm Light kaphat rövid kiegészítő shadowt. High
   Contrast minden emelt szintet `borderStrong` használatával is
   megkülönböztet, dekoratív glow nélkül. Új hex szín vagy legacy theme-módosítás
   nem készül.
4. Az `SsSurface` opcionális, névvel ellátott safe-area módot ad, amely a
   `MediaQuery` rendszer-inseteit maga alkalmazza; a hívónak nem kell külön
   `SafeArea` widgetet beágyaznia. A default mód nem ad kétszeres insetet a
   beágyazott card/section használathoz.
5. Az `SsCard` normál `SsRadius.md`, az `SsHeroCard` `SsRadius.lg` geometriát
   használ. Az `SsHeroCard` kizárólag caller-fed prezentációs gyermekeket kap;
   feature-, provider- vagy felismerési state importja tilos. Az `SsSection`
   cím + tartalom kompozíció, és önmagában nem hoz létre felesleges újabb
   kártyaréteget.
6. A Chapter 13 háromtémás golden követelménye ebben a körben determinisztikus
   visual-contract mátrix: dark/light/high-contrast ×
   base/raised/overlay/modal esetén a feloldott háttér-, border- és
   shadow-tulajdonságokat widgetteszt méri. Bináris PNG corpus nem készül,
   mert a jóváhagyott exact scope nem tartalmaz golden asset útvonalat; az
   eltérést a kör briefje nyíltan rögzíti.
7. A kör saját source-contract tesztje elutasítja az új surface-fájlokban a
   nyers geometriai konstruktorokat, és valódi rontással falszifikálandó. A
   védett globális architecture-gate ettől a körtől nem változik.

## Következmények

- A későbbi képernyők szintet választanak, nem egymástól független színt,
  bordert és árnyékot.
- A dark és High Contrast hierarchia árnyék nélkül is gépileg
  megkülönböztethető.
- A safe-area viselkedés közös primitive contract, de a beágyazott surface-ek
  nem kapnak automatikusan duplikált rendszermargót.
- A két célzott tesztfájl együtt méri a tokenforrást, a vizuális mátrixot, a
  2.0 text-scale/nested esetet és a nyers geometria tiltását.

## Elvetett alternatívák

- **A hívó adja meg a surface-színt:** szétválasztaná a szintet és annak
  szemantikai jelentését, képernyőnként eltérő hierarchiát hozva létre.
- **Minden szint nagy `BoxShadow`:** sötét témában halót adna, és sértené a
  Chapter 13 depth-szabályát.
- **Új spacing/radius skála:** második tokenforrás lenne az E13-R02 mellett.
- **Minden surface automatikusan safe-area:** nested komponenseknél kétszeres
  insetet okozna.
- **Globális gate-módosítás ebben a körben:** a mércét módosítaná a mért kör;
  a célzott source-contract teszt ugyanazt a scope-ot biztonságosan őrzi.
