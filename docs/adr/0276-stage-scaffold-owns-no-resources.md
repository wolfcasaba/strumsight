# ADR 0276 — A Stage layout nem birtokol erőforrást

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R09` (Chapter 13, Kör 9)
- **Kapcsolódó:** AGENTS.md §9 (DSP- és időzítés-tilalom),
  [`0274`](0274-motion-driven-by-the-audio-clock.md)

## Kontextus

Hat aktív mód (Live, Practice, Song, Tuner, Metronome, Vision) osztozik ugyanazon
a vizuális szerkezeten: állapot-fejléc, hero, visszajelzés, idővonal, alsó
akciósor. Kézenfekvő lenne a közös Stage layoutba tenni az erőforrás-kezelést is
— mikrofon, kamera, felvétel, képernyő-ébrentartás —, hiszen minden mód
ugyanazt csinálja.

Ez azonban azt jelentené, hogy egy **prezentációs widget** elhelyezése bárhol a
fában engedélykérést és rögzítést indítana. Egy előnézet, egy katalógus-oldal
vagy egy teszt is mikrofont nyitna. Az ilyen mellékhatás a kódot olvasva nem
látszik: a hívó egy layoutot lát.

## Döntés

1. Az `SsStageScaffold` **nem indít** mikrofont, kamerát vagy felvételt, és nem
   birtokol erőforrás-életciklust. Az a feature rétegé marad.
2. A képernyő-ébrentartás **kérés**, ami az elhagyáskor visszavonódik — nem
   birtoklás.
3. A mentetlen adat miatti vissza-megerősítés **hook**: a scaffold jelzi az
   eseményt, a feature dönt a szövegről és a mentésről. Az adatvesztés tényét
   csak a feature ismeri.
4. A Pause és a Finish **minden aktív állapotban látható** — nem rejthető
   overflow menübe, görgetés alá vagy „elegánsabb elrendezés" mögé. Aki játszik,
   egyetlen mozdulattal meg tud állni; landscape-ben is.

## Következmények

**Pozitív.** A layout bárhol elhelyezhető mellékhatás nélkül — katalógusban,
tesztben, előnézetben. Az erőforrás-hibák ott maradnak, ahol az életciklus van.

**Negatív / ár.** Minden feature-nek magának kell huzaloznia az erőforrásait; a
közös kód kevesebb, mint amennyi elméletileg megosztható lenne.

**Amit ez a döntés TILT.** Bármilyen `autoStart`-szerű paraméter a Stage
layouton, ami erőforrást nyitna; a Finish elrejtése helyhiány miatt.
