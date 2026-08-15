# ADR 0279 — A megerősítés a következményt mondja ki

- **Státusz:** elfogadva
- **Dátum:** 2026-08-15
- **Kör:** `E13-R13` (Chapter 13, Kör 13)
- **Kapcsolódó:** [`0278`](0278-ai-provenance-is-visible.md),
  [`0277`](0277-failure-presentation-model.md)

## Kontextus

Az alkalmazásban több visszafordíthatatlan művelet van: session törlése, poszt
közzététele, modell letöltése mobilhálózaton, gyakorlási terv módosítása
AI-tool által, mentetlen session elhagyása.

Az általános „Biztos vagy benne? Igen / Nem" párbeszéd ezekre nézve
információmentes. Sietve olvasva nem mond semmit; felolvasóval a gombfelirat
(„Igen") önmagában értelmezhetetlen; és nem különbözteti meg a
visszafordítható műveletet a véglegestől.

Az AI-tool-akciók külön esetet jelentenek: ott a felhasználó nemcsak azt nem
tudja, mi történik, hanem azt sem, **mihez nyúl hozzá** az eszköz, és elhagyja-e
adat a készüléket (vö. ADR 0278).

## Döntés

1. A megerősítő gomb **a műveletet nevezi meg** („Session törlése"), és a szöveg
   kimondja, mi vész el és mi visszafordíthatatlan. Homályos „Igen/Nem" tilos.
2. Az **AI-tool megerősítés megmutatja**: mit olvas, mit ír, elhagyja-e az adat
   a készüléket, indul-e rögzítés.
3. A **Mégse minden kockázatos műveletnél elérhető** — nincs csak-előre felület.
4. Modális alatt a **háttér semanticsa elrejtett**, a fókusz csapdázott, és
   bezáráskor a fókusz oda tér vissza, ahonnan indult.
5. A destruktív visszahívás **pontosan egyszer** fut — dupla koppintás,
   Android vissza és Escape kombinációjából sem kétszer. Törlésnél a második
   lefutás adatvesztés.
6. A felület-méret a képernyőhöz igazodik: compacton alsó lap, nagy képernyőn
   indokolt esetben oldalsó lap.

## Következmények

**Pozitív.** A felhasználó a döntés pillanatában látja a következményt. A
felolvasóval használt felület ugyanazt az információt adja. A dupla lefutásból
eredő adatvesztés kizárt.

**Negatív / ár.** Minden destruktív műveletnek **saját** microcopy kell (en +
hu); egyetlen általános párbeszéd nem elég.

**Amit ez a döntés TILT.** Az általános „Biztos vagy benne? Igen/Nem"-et; a
mégse nélküli megerősítést; a részletek nélküli AI-tool-jóváhagyást.
