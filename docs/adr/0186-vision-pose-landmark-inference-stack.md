# ADR 0186 — Vision pose landmark inference stack

- **Státusz:** Elfogadva feltételesen (E05-R14 pre-flight, 2026-08-07); az
  asset-beszerzés és a natív bekötés **PENDING**, jövőbeli aktiváló kör dolga
  (ugyanaz a posztúra, mint [ADR 0185](0185-vision-hand-landmark-inference-stack.md))
- **Kör:** E05-R14 — Pose landmark provider és posture baseline
- **Implementer motor:** MiniMax M3 — az ADR-t az orchestrátor (Claude Sonnet 5)
  írta a pre-flightban (ADR 0055, pipeline-prompt §2)
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md)
  §16 (Pose landmark pipeline), §30 (Modellkezelés és manifest)
- **Kontext-ADR-ek:** [0178](0178-vision-privacy-by-default.md) (adatminimalizálás —
  a döntés 1 ennek a pose-specifikus alkalmazása), [0185](0185-vision-hand-landmark-inference-stack.md)
  (a provider/manifest minta, amit ez a kör másodszor alkalmaz), [0180](0180-vision-android-first-camera-strategy.md)
  (domain platform-függetlenség)

## Kontextus

Az SDD Ch6 §16.1 egy **szűkített** felsőtest-pose kontraktust ír elő: váll,
könyök, csukló, csípő-referencia ha látható, és legfeljebb egy semleges
fej/nyak-referenciapont opcionális neck-posture proxyként — kifejezetten
**arcelemzés nélkül** (§16.2: "Ha a pose provider arcpontokat ad, azok ne
kerüljenek persistence-be, insightba vagy logba"). Ez az [ADR 0178](0178-vision-privacy-by-default.md)
adatminimalizálási elvének pose-specifikus alkalmazása.

Az [ADR 0185](0185-vision-hand-landmark-inference-stack.md) Kontextus-szakaszában
mért három korlát (az `allowed_paths` nem tartalmaz bináris/natív útvonalat,
`native_gate = false`, AGENTS.md §9 asset-provenance szabálya) erre a körre is
**azonosan** érvényes — ez a kör is strukturálisan képtelen valódi natív
pose-inference-t szállítani, függetlenül attól, melyik stacket választanánk.

**Négy, ma mérhető tény alakítja ezt az ADR-t** (a kör-brief §0.0 R1–R4-ben
részletesen dokumentálva):

1. A `vision_models` manifest-kulcs (ADR 0185 által bevezetve) validátora
   (`lib/core/ml/vision_model_manifest.dart:205-211`) **egyetlen, hardkódolt**
   `output_schema` értéket fogadott el (`handLandmarksOutputSchema`), mert az
   E05-R12 pre-flightjában csak EGY modellcsalád létezett. A hozzá tartozó
   teszt (`test/tooling/ml_asset_manifest_test.dart:108`) explicit
   `hasLength(1)`-et várt, `"one deferred vision model expected"` indokkal. Egy
   második, additív `vision_models` bejegyzés (ez a kör `pose_landmarker`-je)
   emiatt **nem tud átmenni** a validátoron a jelenlegi kód mellett — mérve, nem
   feltételezve.
2. A generátor (`ml/make_manifest.py` `_VISION_MODEL_SPECS`, sor 202-217) a
   `vision_models` array **egyetlen forrása** — a shipped JSON-t kézzel
   szerkeszteni a generátor megkerülése lenne (a fájl saját kommentje: "a
   jövőbeli aktiváló kör bővítheti újabb modellekkel" — ez a kör pontosan ez a
   bővítés).
3. A `deferred` ágon **sem fájlrendszer-, sem pubspec-érintés nem történik**
   (`lib/core/ml/vision_model_manifest.dart:232` — a checksum/asset-ellenőrzés
   `status == active` mögé zárva, az E05-R12 F1 javítókör óta); mérve: ma nincs
   `assets/ml/hand_landmarker_deferred.tflite` a lemezen, és a `pubspec.yaml`
   nem deklarál vision-asset-et. A pose `deferred` bejegyzés ugyanígy
   asset-mentes maradhat.
4. A `PoseLandmarkProvider.infer()` bemenete ugyanaz a kameraframe, mint a
   `HandLandmarkProvider.infer()`-é — a `VisionImage` (és a hozzá tartozó
   `HandLandmarkTimestamp`, `VisionDeviceTier`) típus **már létezik**
   (`lib/features/vision/data/landmarks/hand_landmark_provider.dart:37-125`),
   és R14 `allowed_paths`-a nem tartalmazza azt a fájlt — tehát a pose oldal
   ezt importálja, nem másolja.

## Döntés

1. **Stabil, provider-független landmark ID topológia — 9 pont**, a SDD §16.1
   kategóriái szerint, mindkét oldalra kifejtve (a póz EGY hívásban a teljes
   felsőtestet adja, nem hívásonként egy oldalt, szemben a kéz-modellel):

   `leftShoulder`, `rightShoulder`; `leftElbow`, `rightElbow`; `leftWrist`,
   `rightWrist`; `leftHip`, `rightHip`; `neckReference` (a **legfeljebb egy**
   semleges fej/nyak-referenciapont — SDD §16.1 "fej/fül csak opcionális neck
   posture proxyhoz", tehát ha a provider nem ad megbízható nyak/fej pontot,
   ez az egyetlen ID marad hiányzó, sosem null-lal/0-val töltött álérték).

   A `left`/`right` előtag a **személy fizikai, anatómiai oldalát** jelöli (a
   `Handedness.left/right` és az R07 nem-tükrözött bemenet-garancia
   konvencióját követve — brief §5 pont 1 "adatminimalizálás", nem
   kamera-relatív oldal). **Szem, orr, száj, fül landmark ID NEM létezik ebben
   az enumban** — ha a provider ilyet ad, a mapping eldobja, mielőtt a domain
   típus létrejönne (ADR 0178 Döntés 1 pose-alkalmazása; a privacy-audit teszt
   ezt a kulcshalmazt pinneli).

2. **A manifest-validátor általánosítása additív, modell-id-kulcsolt
   sémakészletre.** `lib/core/ml/vision_model_manifest.dart`
   `outputSchema != handLandmarksOutputSchema` egysoros ellenőrzése egy kis,
   ismert `(model_id → elvárt output_schema)` regisztrációra bővül (vagy
   ezzel ekvivalens halmaz-tagsági ellenőrzésre) — a `hand_landmarker` bejegyzés
   validációja **bitre azonos** marad, a `pose_landmarker` egy ÚJ, saját
   `strumsight.pose_landmarks.v1` sémával válik elfogadhatóvá. `ml/make_manifest.py`
   `_VISION_MODEL_SPECS` egy második tuple-t kap (a `hand_landmarker` bejegyzés
   alakját tükrözve: `status = "deferred"`, dokumentált placeholder sha256,
   `docs/eval/vision/pose_landmarker.md` evaluation-report útvonal — a fájl
   maga nem kötelező eleme ennek a körnek, csak az útvonal-mező). A
   `test/tooling/ml_asset_manifest_test.dart` `hasLength(1)` várakozása
   `hasLength(2)`-re módosul. **Mind a három fájl additívan bővül** — az
   `allowed_paths` a kör-brief §0.0 R3 revíziójában ennek megfelelően bővült
   (nem a mérce lazítása, hanem a ténylegesen szükséges célfájlok pótlása,
   mérve, nem feltételezve — ugyanaz a három fájl, amit az ADR 0185 saját köre,
   az E05-R12 is `allowed_paths`-on tartott, ugyanezért az okért).
3. **Ugyanaz az aktiválás-halasztási testtartás, mint az ADR 0185-nél.** Ez a
   kör NEM szerzi be, NEM tölti le és NEM pinneli a pose-modell binárist; a
   `pubspec.yaml` nem kap új asset-deklarációt (a `deferred` ág sosem ér
   fájlrendszerhez vagy pubspec-hez — 1–3. kontextus-pont). A
   `NativePoseLandmarkProvider` ebben a körben fail-closed `unavailable`,
   pontosan a `NativeHandLandmarkProvider` alakját követve (manifest
   init-kori validáció, `deferred` status → `AppResult.failure`).
4. **A `VisionImage`/`HandLandmarkTimestamp`/`VisionDeviceTier` bemenet-típusok
   ÚJRAFELHASZNÁLTAK, nem újradefiniáltak.** A `PoseLandmarkProvider.infer()`
   ugyanazt a `VisionImage`-et fogadja, amit a `HandLandmarkProvider.infer()`
   (import a `hand_landmark_provider.dart`-ból) — egy kameraframe mindkét
   pipeline-t táplálhatja. A cadence-korlátozás mechanizmusa a kör saját
   döntése (a `MonotonicHandLandmarkProvider` wrapper-minta ajánlott
   precedens, nem kötelező forma) — a device-tier-alapú finomhangolás **kívül
   esik** ezen a körön (E05-R29).
5. **Posture-baseline scope-határ.** Ez a kör a baseline collectort (quality +
   duration-kapuzott) és a nyers posture-quality/drift **megfigyelés-modelleket**
   építi (SDD Kör 14 feladatlista) — pl. pontonkénti, baseline-hoz viszonyított
   delta. **NEM** épít posture safety policy-t, coaching-küszöböt vagy
   "jó/rossz testtartás" ítéletet — az az interpretációs réteg E05-R20 dolga
   (a kör-brief §3 explicit kizárása).

## Következmények

- A `PoseLandmarkProvider` interfész és a `PoseLandmarks` domain-modell ebben a
  körben készül el és **stabil marad**, függetlenül attól, hogy melyik stack
  aktiválódik később (ADR 0185 Döntés 1 mintáját követve, amikor a jövőbeli
  aktiváló kör kiválasztja a konkrét inference-stacket).
- A `RecordedPoseLandmarkProvider` a valódi CI-út, amíg a production adapter
  deferred — ugyanaz a végleges CI-stratégia, mint a kéz-oldalon (ADR 0185
  Következmények).
- A `vision_models` manifest-kulcs a gyakorlatban is bizonyítottan bővíthető
  marad (nem csak egy kódkomment szándéka) — egy jövőbeli harmadik
  modellcsalád ugyanezt a regisztrált-séma mintát követheti további
  validátor-sebészet nélkül.
- A device-mátrix (`docs/manual-testing/vision-device-matrix.md`) pose-sorai a
  jövőbeli aktiváló kör dolga; ez a kör nem módosítja a fájlt.

## Elutasított alternatívák

- **Önálló `pose_models` testvér-manifest-kulcs.** Elvetve: duplikálná a
  validációs logikát, és ellentmond a kör-brief §4 saját „additív bejegyzés"
  szövegének, valamint a validátor-fájl saját kommentjének, amely a MEGLÉVŐ
  `vision_models` kulcs többmodelles bővítését irányozta elő.
- **A `handLandmarksOutputSchema` újrahasználata a pose bejegyzéshez.** Elvetve:
  hamis manifest-metaadat (egy checksum+licenc+séma-regisztráció, amely
  hazudik arról, mit ad ki a modell, rosszabb, mint egy nyíltan hiányos —
  AGENTS.md §9).
- **A manifest-bejegyzés elhagyása ebben a körben.** Elvetve: ellentmond a
  kör-brief saját §4/§5.6 követelményének és az SDD Kör 14 feladatlistájának
  ("Adj model manifestet ... teszteket").
- **Google ML Kit Pose Detection.** Elvetve ugyanazon az alapon, mint az ADR
  0185-ben az ML Kit kéz-landmark hiánya: bár az ML Kit KATALÓGUSA tartalmaz
  Pose Detection API-t, a döntés az ADR 0185 §Elutasított alternatívák
  keretrendszerét követi (natív platform-channel igény, licenc/redisztribúciós
  kérdés) — a jövőbeli aktiváló kör dolga a tényleges stack-választás, ahogy
  az ADR 0185 Döntés 5 falszifikálható újradöntési feltétele is leírja.
