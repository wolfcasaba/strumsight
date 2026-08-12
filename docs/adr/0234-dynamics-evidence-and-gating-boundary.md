# ADR 0234 — Dynamics evidence és kapuzási határ

- **Státusz:** Elfogadva (E06-R16 pre-flight, 2026-08-12)
- **Kör:** E06-R16 — Dynamics és stroke balance
- **Implementer motor:** `sonnet-impl`
- **Kapcsolódó szerződések:** [ADR 0203](0203-analysis-metric-catalog-contract.md),
  [ADR 0206](0206-preprocessed-audio-dual-buffer-provenance.md),
  [ADR 0224](0224-signal-quality-stage-measurement-boundary.md)

## Kontextus

Az R08 az eredeti és a feature-extraction PCM-et külön választotta. Az R10
eredeti PCM-ből kiszámított attack peaket és local RMS-t ad a `StrumEvent`
evidence-hez, de nem ad per-event clipping flaget. Az R07 jelminőségi reportja
pedig explicit megkülönbözteti a mért és a legacy/fabrikált számokat a
`measured` mezővel. Az R16-nak ehhez kell sessionön belüli dynamics-metrikát
publikálnia, anélkül, hogy a V2 esemény-, pipeline- vagy jelminőség-szerződést
előre bővítené.

## Döntés

1. A dynamics-számítás kizárólag `PreprocessedAudio.originalSamples`-ből
   olvas. A canonical/normalizált puffer sem közvetlenül, sem visszaszámított
   jelforrásként nem használható.
2. A per-event `clipped` állapot az R16 saját belső inputjában képződik: a
   `StrumEvent.sampleIndex`-től induló, az R10 által is használt 20 ms-os
   attack-ablakban bármely véges mintára `abs(sample) >= 0.999`. A jelző nem
   kerül a már elfogadott `StrumEvent` domain szerződésbe. Hiányzó
   `sampleIndex` vagy nem értelmezhető ablak esetén a metrika nem publikálható
   értékként.
3. A `SignalQualityReport.measured == false`, nem véges jelminőségi adat vagy
   hiányzó required quality evidence fail-closed dynamics availabilityt eredményez;
   nem helyettesíthető semleges számokkal. A noise-floor sávok csak valóban
   mért reportból használhatók. Ez felvételi minőség-proxy, nem backing-track
   vagy forrásazonosítási állítás.
4. A már elfogadott `MetricGate` marad a minimum-eseményszám egyetlen
   igazságforrása. A target nélküli eredmények leírók; accent-pontosság csak
   explicit targettel lehet elérhető.

## Következmények

- A clipping-kizárás és a clipping-arány ugyanabból az eredeti, lokális
  evidence-ből vezethető le, miközben a statisztikai suite nem torzul a
  clippingtől.
- A normálás bekapcsolása mellett is mérhető marad az original-samples
  invariáns; a teszt ezt `canonicalSamples` szándékos eltérítésével védi.
- A későbbi pipeline-bekötő körnek explicit módon kell átadnia a nyers
  dynamics inputot és a mért quality reportot; ez az R16 nem módosítja.

## Elutasított alternatívák

- **`StrumEvent.clipped` felvétele:** az R10 domain/codec szerződésének
  bővítése, amely nem szükséges a még bekötetlen R16 számításhoz.
- **`canonicalSamples` használata:** sérti az ADR 0206 amplitude-provenance
  határát, és a normalizáció hamis dinamikai egyenletességet teremthet.
- **Nem mért quality report elfogadása:** legacy placeholderből gyártana
  jelbizonyítékot, ami ellentétes az R07 fail-closed határával.
