# ADR 0232 — Timing metric identity and publication boundary

- **Státusz:** Elfogadva (E06-R14 pre-flight, 2026-08-12)
- **Kör:** E06-R14 — Timing és rush/drag metrikák
- **Kapcsolódó szerződések:** SDD Ch7 §15.2–15.5; [ADR 0218](0218-analysis-metric-id-and-version-governance.md), [ADR 0219](0219-analysis-capability-aware-publication.md), [ADR 0231](0231-target-alignment-engine-boundary.md)

## Kontextus

Az R13 immutable `AlignmentResult`-ja a párosított `timingError`, a
`missedExpected` és az `extraObserved` evidenciát már elkülönítve adja. A
meglévő zárt katalógusban ugyanakkor már szerepel az általános
`timing.mean_absolute_error.v1`, miközben az R14 brief a target és free-play
mérések diszjunkt, mode-ot kódoló `timing.target_*` és `timing.freeplay_*`
azonosítóit írja elő. A régi ID átnevezése sértené az ADR 0218 additív,
stabil-azonosító szabályát.

## Döntés

1. R14 minden új timing publikációja additív, mode-kódolt ID-t használ:
   `timing.target_*` csak `AlignmentResult`-ból, `timing.freeplay_*` csak
   explicit beat-grid alapú becslésből készülhet. A két névhalmaz diszjunkt.
2. A régi `timing.mean_absolute_error.v1` változatlan marad és nem lesz
   átnevezve vagy új jelentéssel feltöltve ebben a körben.
3. Target metrikánál `error = observed - expected`; a `TolerancePolicy`
   ugyanazon inkluzív ablaka dönti el az on-time állapotot és az alignment
   párosíthatóságát. A kapun kívüli eseményből nem lesz target timing score.
4. Nyolcnál kevesebb matched pár esetén (stable streaknél háromnál kevesebb)
   az eredmény `unavailable`, `insufficientEvents` okkal és érték nélkül;
   szintetikus nulla vagy NaN nem publikálható.
5. Minden hotspot a contributing observed eventek valódi ID-jait és a
   katalógusbeli metric ID-kat hordozza. A kör nem köt be UI-t, V1 Analyze-t
   vagy Practice-pontozást.

## Következmények

- A későbbi session-összehasonlítás az ID-ből is látja, hogy target vagy
  free-play mérésről van szó; az eredmények nem keverhetők össze.
- A free-play confidence legfeljebb az azt alátámasztó beat-grid confidence,
  de a kalibrációs jelentését az R19 kezeli.
- Képlet-, egység- vagy bemeneti szemantika-változás új metrika-verziót
  igényel ADR 0218 szerint.

## Elutasított alternatívák

- A régi általános ID átnevezése vagy újrahasználata — inkompatibilis,
  mert a stabil katalogizált azonosító jelentése csendben változna.
- Reference nélküli target-ID kiadása — hamis pontosság-állítás lenne.
- Küszöb alatti eredmény 0-val történő publikálása — elfedné az
  `insufficientEvents` állapotot.
