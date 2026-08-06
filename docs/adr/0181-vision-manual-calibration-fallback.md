# ADR 0181 — Vision manual calibration fallback

- **Státusz:** Elfogadva (E05-R01 pre-flight, 2026-08-06)
- **Kör:** E05-R01 — Vision baseline, alapozó ADR-ek
- **Implementer motor:** DeepSeek v4 Pro (`deepseek/deepseek-v4-pro`, Kilo-profil,
  örökölt kézi override, `codex-round.sh`) — az ADR-eket az orchestrátor (Claude)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) §5.8, §9.4
- **Kontext-ADR-ek:** [0179](0179-vision-capability-aware-feedback.md),
  [0180](0180-vision-android-first-camera-strategy.md)

## Kontextus

A vision-coaching a gitár geometriájára (nyak, húrok, bundok, kéz) támaszkodik.
A geometria automatikus detektálása eszköz- és fényfüggő, és megbízhatatlan
lehet. Az SDD Ch6 §5.8 szerint a perspektíva-, tükör-, crop- és
orientation-transzformációk pure Dart függvények, fixture- és property teszttel
védve; a §9.4 `GuitarGeometry` a mérés alapja. A rendszernek akkor is
használhatónak kell lennie, ha az automatikus detektor gyenge — összhangban a
capability-aware feedback ([ADR 0179](0179-vision-capability-aware-feedback.md))
elvvel.

## Döntés

1. **A gitárgeometria production útja a kézi kalibráció.** A felhasználó által
   megadott/megerősített kalibráció a mérhető, determinisztikus alap, amelyre a
   production coaching épül.
2. **Automatikus geometria-detektor csak experimental flag mögött**, és csakis a
   manual fallback megtartása mellett létezhet; a detektor sosem váltja ki a
   kézi utat, csak felajánlja.
3. **A koordinátageometria tesztelhető.** A transzformációk pure Dart függvények,
   fixture + property teszttel (SDD §5.8); a geometria a domainben él,
   platform-független.

**NEM elfogadható:** az automatikus detektor kimenetét production coaching
kizárólagos geometriaforrásaként használni, vagy a kézi kalibrációs utat
eltávolítani/elrejteni azért, mert egy detektor „elég jónak tűnik" — a manual
fallback minden esetben elérhető marad.

## Következmények

- A kézi kalibrációs UX és a `GuitarGeometry` domainmodell külön kör; ez az ADR a
  boundaryt és a fallback-elsőbbséget rögzíti.
- Az automatikus detektor bevezetése experimental flaggel, a capability-státusza
  `experimental`, és a manual eredményhez képest mérendő.
- A geometria-transzformációk property gate-je (randomizált seed) a detektortól
  függetlenül védi a pure Dart magot.

## Elutasított alternatívák

- **Auto-detektor mint alapértelmezett geometriaforrás.** Elvetve: eszközfüggő,
  megbízhatatlan, és false feedbackhez vezetne (SDD §5.5); a manual út mérhető és
  stabil.
- **Csak manual, detektor nélkül.** Elvetve: az experimental detektor később
  csökkentheti a beállítási súrlódást — de csak a manual fallback megtartásával.
- **A geometria a platform-adapterben.** Elvetve: sérti a tesztelhető,
  platform-független koordinátageometria elvét (SDD §5.8).
