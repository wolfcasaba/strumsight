# ADR 0246 — Analysis session comparison és trend szerződés

- **Státusz:** Elfogadva (E06-R25 pre-flight, 2026-08-13)
- **Kör:** E06-R25 — Session comparison és fejlődési trend
- **Kapcsolódó szerződések:** [ADR 0218](0218-analysis-metric-id-and-version-governance.md)
  (metric ID és verzió), [ADR 0219](0219-analysis-capability-aware-publication.md)
  (availability), [ADR 0220](0220-audio-analysis-v2-parallel-rollout-boundary.md)
  (V2 flag boundary), valamint SDD Ch7 §26.

## Kontextus

Az `AnalysisDocument` már verziózott metrikákat, provenance-ot és mért
jelminőséget hordoz. Ezekből két session értékeit csak akkor szabad automatikusan
összevetni, ha a számértékek ugyanazt jelentik és a bemenet minősége nem teszi
félrevezetővé a különbséget. A trend nem jövőre vonatkozó előrejelzés, hanem
helyben számolt, bizonytalanságtudatos múltbeli összegzés.

## Döntés

1. A comparison minden metric-párra fail-closed eredményt ad. Eltérő ID,
   inkompatibilis metric-version, target, quality grade, clipping-állapot vagy
   10 dB-nél nagyobb noise-floor eltérés `inconclusive` indokkal; az értékeket
   ilyenkor nem állítjuk egymás mellé következtetésként.
2. A változás irányát kizárólag teljes katalogusú `MetricMetadata` határozza
   meg. `descriptive` metrika nem lehet improved/regressed; a
   `minimumMeaningfulDelta` alatt a változás unchanged, a küszöbön már érdemi.
3. A dinamikai metrikákhoz a normalizációs policy és a releváns provenance is
   kompatibilitási feltétel. Hiányzó vagy eltérő bizonyíték mellett az eredmény
   `inconclusive`, nem optimista összehasonlítás.
4. Trend legalább három kompatibilis sessionből, metric-version szerint
   csoportosítva készül. A 3×MAD-on kívüli pont a trendvonalból kiesik, de a
   lokális pontlistában `excluded` jelöléssel látható marad. Nincs forecast,
   extrapolation vagy hálózati hívás.
5. A Comparison UI és route csak az új `analysisComparisonEnabled` flag mögött
   regisztrálható. A flag alapértéke minden környezetben false; ez a V2 rollout
   határt nem nyitja meg.

## Következmények

- A feature csak helyi, származtatott adatokat olvas; nyers audio nem hagyja el
  az eszközt.
- A catalog bővítése vagy egy metrika jelentésének változtatása nem e kör
  hatásköre; azt ADR 0218 szerinti új metric-version kezeli.
- A mércék a kompatibilitási- és küszöb-mátrixot, metadata-teljességet,
  outlier-megjelölést, route-flaget és hálózat/extrapoláció hiányát tesztelik.

## Elutasított alternatívák

- Inkompatibilis értékek megjelenítése „figyelmeztetéssel”: a figyelmeztetés
  nem teszi összehasonlíthatóvá a különböző méréseket.
- Minden növekedés javulásként kezelése: leíró és alacsonyabb-érték-a-jobb
  metrikáknál hamis állítást okozna.
- Felhőben számolt vagy jövőbe vetített trend: sértené az offline-first és
  evidence-before-claims határokat.
