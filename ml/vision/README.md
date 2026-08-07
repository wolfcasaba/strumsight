# StrumSight — vision guitar/neck detector experimental path

A **manual kalibráció** (`lib/features/vision/calibration/`) marad a
**production** út (ADR 0181). Ez a mappa a KÖVETKEZŐ lépcsőhöz tartozik:
egy **automatikus gitárnyak-detektor** kísérleti kiértékelése, amely a
manual utat **soha nem írhatja felül**, csak **felajánlhatja**
(`visionExperimentalFineFretEnabled` flag mögött, [ADR 0187](../../docs/adr/0187-vision-automatic-guitar-geometry-detection.md)
Döntés 1).

A kör (E05-R17) jelenlegi állapota: **nincs consentelt adat**, **nincs
modell**, **nincs bináris asset** — csak a döntési keret és a mérce. A
kísérleti út indítása egy későbbi aktiváló kör feladata, amihez ez a
mappa adja a reprodukálható vázat.

## Ami itt van

- **`evaluate_geometry_baseline.py`** — tiszta-stdlib Python harness
  (numpy/scipy kizárva, box-kompatibilis). Az
  [ADR 0187](../../docs/adr/0187-vision-automatic-guitar-geometry-detection.md)
  Döntés 2 számait (mean anchor error ≤ 0.030 / p95 ≤ 0.050 /
  failure rate ≤ 0.05, normalizált `[0,1]×[0,1]` kamera-tér) és a
  minimum eval-korpuszt (≥ 200 frame, ≥ 3 gitár, ≥ 2 fény, mindkét
  kezesség) kódolja. JSONL-bemenet, kilépési kódjai: `0` OK,
  `2` NO_DATA, `3` BAD_INPUT, `4` SELF_TEST_FAIL.
  `--self-test` kilenc belső mintán bizonyítja a metrika-számítást ÉS
  a brief §6.2 küszöb-kezelést. Bemenet nélkül `NO_DATA` státusszal
  áll meg — sosem null-értékű metrikával.
- **`dataset_manifest.md`** — a jövőbeli dataset kötelező
  kategória-szerkezete és consent-szabályai (SDD §31.1 + §31.2), a
  tiltott források explicit listájával. Jelenleg minden kategória
  `PENDING_COLLECTION` (kivéve a synthetic fixture — `READY`, de NEM
  használható production küszöb mérésére).

## Lehetséges detektor-kimenetek — összevetés

A detektor kimenetének formátuma határozza meg, hogyan mérhető a
`mean anchor error` (a harness ezt várja). Három reális opció:

| Kimenet | Anchor-ek származtatása | Előny | Hátrány | Passzol-e a brief §6.2 küszöbre? |
|---|---|---|---|---|
| **Bounding box** (pl. YOLO/SSD a teljes gitárra vagy a nyakra) | a bbox két sarokpontja proxy az anchor-párokra (nut + bridge) | egyszerű, sok pretrained backbone létezik | a bbox sarokpontjai nem konzisztensek a valós anchor-pontokkal; a neck-hez képest „túl tág" vagy „túl szűk" lehet; a kapott anchor-ok nem invertálhatóak biztonságosan a manual anchor-rendszerre | a mért hiba jellemzően magas, mert a bbox-sarok nem a nut/bridge; **valószínűtlen**, hogy 0.030 mean alá menjen |
| **Line** (a nyak-tengely egyenes + nut/bridge végpontok) | közvetlenül a két anchor-pont | a harness által mért érték **megegyezik** a manual anchorokkal (1-1 leképezés); a legkisebb módosítás a meglévő R10 `GuitarCalibration` interfészre | a nyak-tengely detekció nehéz edge-case-ben (capo, ferde nyak, occlusion); landmark-osztályozó kell (nem sima bbox); a `degraded`/`lost` határok érzékenyebbek | **a legígéretesebb** út a 0.030 mean küszöbre, mert nincs proxy; de csak akkor, ha a nyak-tengely detektor robust |
| **Segmentation** (a nyak polygon maszkja) | a polygon két végpontja (nut + bridge) vagy a polygon két legtávolabbi csúcsa | sűrű, vizuálisan interpretálható; a polygon kontúrjából a nyak-tengely is származtatható (másodlagos lépésben) | nehéz lightweight on-device modell; a maszk-pontosság nem javítja a nut/bridge anchor pontosságát (az csak a polygon csúcsaitól függ); a legkisebb hamis-bizalom kockázat (a polygon „jól néz ki", de a nut/bridge rossz) | **kétes**: a polygon-csúcsokból származtatott anchor-ok tipikusan rosszabbak, mint a direkt line-detekció; a küszöb eléréséhez a polygon-detektornak is igen pontosnak kell lennie |

**Javaslat (a mérce alapján):** a **line**-alapú kimenet a
legígéretesebb, mert közvetlenül a manual anchorok formátumára képződik
le — így a harness által mért `mean anchor error` **magával a
geometriai pontatlansággal** mér, nem egy proxy-szal. A bounding box-ot
és a segmentationet a jövőbeli aktiváló körök csak akkor vegyék
számításba, ha a line-detekció a saját minimum-korpuszon (≥ 200 frame,
≥ 3 gitár, ≥ 2 fény, mindkét kezesség) nem teljesíti a 0.030 mean
küszöböt — ebben az esetben viszont **nem** a kimeneti formátumot kell
cserélni, hanem **magát a detekciót** kellene javítani (vagy a
kísérletet lezárni).

## Miért NEM itt a modell

- **Nincs consentelt adat** ([`dataset_manifest.md`](dataset_manifest.md)
  minden kategóriája `PENDING_COLLECTION`).
- **`AGENTS.md` §9**: training normál fejlesztési körben nem fut —
  csak külön előírással (ami a Kör 17 SDD-feladatlistájában a
  consent-feloldáshoz van kötve).
- A production geometria-út (manual + R16 tracker, ADR 0181) **stabil
  és mért** — a detektor nem egy hiányzó funkciót pótol, hanem egy
  MÁR MŰKÖDŐ út MELLÉ kerül. A mérce ezért szigorúbb, mint egy
  „jobb, mint a semmi" összevetés.

## Aktiváló kör — mit kellene szállítania

Ha egy jövőbeli kör a fenti korlátok mindegyikét feloldja:

1. **Consent-politika** — legalább 3 contributor, aláírt contributor
   agreement, a [`dataset_manifest.md`](dataset_manifest.md) §2
   consent-rekord 8 mezős sémája szerint.
2. **Dataset** — a §1 kategóriák közül legalább a kötelező minimum
   (≥ 200 frame, ≥ 3 gitár, ≥ 2 fényhelyzet, mindkét kezesség,
   különböző bőrtónusok és nyakszín-kontraszt).
3. **Detektor** — line-alapú kimenet, on-device inference (ADR 0178),
   a `visionExperimentalFineFretEnabled` flag mögé regisztrálva.
4. **Mérés** — ugyanezzel a harness-szel, valós adaton. A
   `decision()` kimenet `PRODUCTION_CANDIDATE` kell legyen a §6.2
   küszöb-sweephez hasonlóan; ha `EXPERIMENTAL` marad vagy a
   `failure_rate` küszöb (5%) fölé megy, a detektor **nem** lép
   `production-candidate`-be, és a manual út változatlan marad.
5. **Dokumentáció** — a `docs/baseline/epic-05-guitar-detector-evaluation.md`
   `PENDING` sorainak kitöltése a mért számokkal, és a
   `docs/manual-testing/vision-device-matrix.md` §2.7 PENDING sorok
   átállítása mért értékre.

A `PRODUCTION_CANDIDATE` minősítés **mindig** a javaslat minőségéről
szól (mennyire jó az automatikus felajánlás), **soha** nem a
megerősítés kihagyásáról — a manual kalibrációs UI előtöltése
**explicit felhasználói megerősítéssel** történik, ADR 0181 §Döntés 2
szerint (az ADR 0187 §Döntés 5 ezt megerősíti, nem lazítja).

## Hivatkozások

- [ADR 0187](../../docs/adr/0187-vision-automatic-guitar-geometry-detection.md)
  — kísérleti státusz, számszerű átfordítási küszöbök, hamis-geometria
  kockázat;
- [ADR 0181](../../docs/adr/0181-vision-manual-calibration-fallback.md)
  — a manual kalibráció a production út;
- [ADR 0179](../../docs/adr/0179-vision-capability-aware-feedback.md)
  — `notObservable` > hamis ítélet;
- [ADR 0178](../../docs/adr/0178-vision-privacy-by-default.md) —
  kizárólag on-device feldolgozás;
- [`docs/baseline/epic-05-guitar-detector-evaluation.md`](../../docs/baseline/epic-05-guitar-detector-evaluation.md)
  — manuális kalibráció idő-/hibaköltség-becslés + a detektorral való
  összevetés;
- [`docs/manual-testing/vision-device-matrix.md`](../../docs/manual-testing/vision-device-matrix.md)
  §2.7 — a jövőbeli aktiváló kör mérési helye.
