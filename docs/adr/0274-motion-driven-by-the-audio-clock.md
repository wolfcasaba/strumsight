# ADR 0274 — A ritmus-animációt az audio óra hajtja, nem független időzítő

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R06` (Chapter 13, Kör 6 — motion rendszer és reduced motion)
- **Kapcsolódó:** [`0273`](0273-design-system-token-source-of-truth.md) (token-forrás),
  AGENTS.md §9 (DSP- és időzítés-tilalom)

## Kontextus

A StrumSight felülete ritmust jelenít meg: beat-pulzus, metronóm-visszajelzés,
strum-idővonal. Két forrásból lehet hajtani:

1. **Független időzítő** — a BPM-ből számolt periódussal futó `Timer.periodic`
   vagy `AnimationController.repeat`.
2. **Az audio óra** — a lejátszási/analízis idővonal, amit a hang maga ad.

A független időzítő olcsóbb: nincs szükség idő-forrás injekcióra, és a
teszteléshez sem kell fake óra. Cserébe **elcsúszik**. Az eltérés forrásai
mérhetőek és elkerülhetetlenek: a `Timer` kerekített ezredmásodperc-periódust
kap, a keretidő ingadozik, a hang oldalán pufferelés és eszközlatencia van, és
a felhasználó tekerhet, szüneteltethet vagy váltogathat forrást — amiről a
független időzítő nem tud.

Egy ritmusjátékos számára a vizuális és a hallott ütés különbsége nem
kozmetikai kérdés: az egész visszajelzés hitelét viszi. A projekt máshol már
kimondta ugyanezt más alakban — a néma, magabiztosan hazudó kimenet
veszélyesebb, mint a látható hiba (ADR 0251 §2, 0253 §3, 0261 §2, 0268).

## Döntés

**Minden ritmushoz kötött animáció az audio idővonalat kérdezi.** A design
system motion-rétege idő-**forrást** kap (injektálható), nem BPM-ből számolt
saját periódust.

1. A `SsBeatPulse` és minden ritmus-vezérelt komponens az idővonal aktuális
   pozíciójából származtatja a fázist. Ha nincs élő idővonal, a komponens
   **nem animál**, nem pedig „szabadon fut".
2. Az idővonal ugrása (seek), megállása és újraindulása után a fázis
   **azonnal** követi az órát — nincs felhalmozott drift.
3. A megengedett vizuális eltérés **≤ 100 ms** (a határ inkluzív). Ez a
   `E13-R06` brief §6.1 mérce-mátrixának küszöbe.
4. A design system az időzítés-forrást **csak olvassa**. A DSP és az időzítés
   módosítása az AGENTS.md §9 szerint tiltott zóna — a motion-réteg nem nyúl
   `lib/features/audio_analysis/**`-hoz.

## Következmények

**Pozitív.** A vizuális ritmus a hanghoz kötött marad tetszőleges hosszú
sessionben is. A seek és a szünet ingyen helyes. A viselkedés **tesztelhető**:
fake idő-forrással a drift, a seek és a megállás mind determinisztikus cella.

**Negatív / ár.** Minden ritmus-komponensnek kell idő-forrás — ez több
huzalozás, mint egy `Timer`. A design system függ egy absztrakt óra-interfésztől
(nem a konkrét analízis-rétegtől), amit a hívó ad meg.

**Amit ez a döntés TILT.** `Timer.periodic(Duration(milliseconds: 60000 ~/ bpm))`
vagy ezzel egyenértékű, önállóan futó animáció bármely ritmust ábrázoló
komponensben. A tiltás akkor is él, ha a kód kommentben megindokolja, hogy „a
tesztekben úgyis stabil" — a mérce a `E13-R06` §6.1 óra-szinkron cellája.

## Alternatívák, amiket elvetettünk

- **Független időzítő periodikus újraszinkronizálással.** Egyszerűbbnek látszik,
  de a resync pillanatában ugrik a vizuális ritmus, ami zavaróbb, mint a lassú
  csúszás — és a seek-et továbbra sem kezeli.
- **A BPM-ből számolt periódus finomhangolása eszközönként.** Kalibrációs
  adósságot termel, és nem old meg semmit szünet/seek esetén.
