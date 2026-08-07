# E05-R13 — Review

Brief: `docs/rounds/e05-r13-hand-track-assignment-and-smoothing.md`
Diff (1. kör, review előtt): `git diff origin/main...cd4d49e`
Diff (javító kör 1 után): `git diff origin/main...2ff9338`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-07
Verdikt: **APPROVED** (javító kör 1 után)

## Javító kör 1 — újra-ellenőrzés (2026-08-07, commit `2ff9338`)

MiniMax egy javító körben mindhárom nyitott leletet (F1 BLOCKER, F2 MAJOR,
F3 MINOR) javította. **Függetlenül újra-ellenőrizve, friss `/tmp` klónban**
(`/tmp/review-e05-r13-fix1`, nem az implementer önjelentésére hagyatkozva):

- **A gate-eket saját kézzel újrafuttattam**: mind a 7 lépés zöld
  (`test/features/vision` + `test/property/hand_track_property_test.dart`).
- **A saját, EREDETI három próbatesztemet (nem az implementerét) újra
  lefuttattam a javított kódon** — mindhárom PIROS→ZÖLD:
  - F1a (occlusion + reappear 0.40 távolabb): a régi kódon 27 frame után is
    `0.30`-on ragadt; a javított kódon **pontosan `0.70`**-re konvergál.
  - F1b (occlusion NÉLKÜL, tartós áthelyeződés): a régi kódon 50 frame után
    is `0.30`-on ragadt; a javított kódon **pontosan `0.70`**-re konvergál.
  - F2 (TrackContinuity zajos bemeneten): a régi kódon `maxJitterNormalized=
    0.0`/`totalProcessingDuration=0:00:00.000000` FIXEN; a javított kódon
    **`maxJitterNormalized=0.265`, `totalProcessingDuration=1.562ms`**
    (valós, nem-nulla mérés).
  - F3 (tartós alacsony visibility): a régi kódon a simított visibility a
    történelmi max (`0.95`) maradt 5 gyenge frame után is; a javított kódon
    **`0.10`**-re esik, követi a raw-t.
- **Regresszió-ellenőrzés (saját próbateszttel):** az EREDETI egy-frame-es
  teleport-majd-visszatérés eset (a meglévő `landmark_smoothing_test.dart`
  cellája) VÁLTOZATLANUL helyesen elutasításra kerül a javítás után is — a
  bypass-logika (`gapSinceLastMatch`/`consecutiveRejections`) NEM engedi át
  az egy-frame-es tüskét, csak a ≥2 egymást követő elutasítást vagy a
  rövid-gap utáni első visszatérést. Nincs regresszió.
- **A javítás mechanizmusa** (`hand_track_assigner.dart`): a jump-rejection
  bypass akkor lép életbe, ha (a) a track épp egy `≤ shortGapFrames` hosszú
  megfigyelhetőségi rés után tér vissza, VAGY (b) már 2 egymást követő
  frame-en elutasításra került — mindkét esetben a `previousSmoothed`
  horgony frissül, ahelyett hogy örökre befagyna. Ez pontosan a review F1
  tételében javasolt (a) irány egy variánsa, plusz egy (c)-szerű
  catch-up-küszöb az occlusion NÉLKÜLI esetre — mindkét eredeti próbám
  lefedve.
- **F2 mechanizmusa:** valódi `Stopwatch` a `process()` törzse körül
  (`HandTrackFrameState.processingDuration`, additív mező), valódi
  raw-vs-smoothed wrist-delta a `HandTrack.rawSmoothedDeltaNormalized`
  (additív mező) — a `TrackContinuity.aggregate` ezekből számol MAX
  jittert és összeg-időt a korábbi élettelen `0.0`/`Duration.zero` helyett.
  A doc-comment is javítva, nem állít többé nem létező mechanizmust.
- **F3 mechanizmusa:** a simított visibility most a raw-t követi (nem
  `max(raw, previous)`), a legkisebb, legvilágosabb javítás.
- **Scope-audit tiszta:** 7 fájl, mind a brief `allowed_paths`-án (a wrapper
  gépi auditja is `scope_audit=ok`-t adott, bázis `e49dcae`, 7 fájl).
- **Egy apró tesztminőségi észrevétel (nem blokkoló):** a
  "relocation after a short occlusion" cella második fele ugyanazt a
  trajektóriát MÉG EGYSZER lefuttatja UGYANAZON a (már állapotos) assigneren
  — ez a második kör `frameIndex`-e 0-ról indul újra egy már 39-nél járó
  belső állapotú track mellett (negatív "gap"), ami nem crashel (a
  `frameIndex` monotonitása nincs validálva — lásd a security-review
  NOTE-2-jét), de a második ciklus lényegében redundáns, nem ad hozzá valódi
  bizonyítékot az elsőhöz képest. Nem befolyásolja a fix helyességét (amit
  a saját, tiszta próbáim függetlenül igazoltak) — stílusjegyzet egy
  jövőbeli takarításhoz, NEM follow-up tétel.

**Minden korábbi (F1/F2/F3) lelet STÁTUSZA: FIXED (`2ff9338`).** N1
(kozmetikai commit-hash), N2 (handedness-flip robusztusság) és N3
(kéz-szám korlát) változatlanul follow-up, nem blokkoló — egyik sem
igényel brief-revíziót vagy újabb javító kört.

## Összegzés

**Javító kör 1 UTÁN: BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 3** (mind a
három nyitott lelet FIXED, függetlenül újra-ellenőrizve — lásd a jelentés
elején). Eredeti (javítás előtti) állapot referenciaként: BLOCKER: 1 ·
MAJOR: 1 · MINOR: 1 · NOTE: 3.

**Dedikált security-review** (`docs/reviews/e05-r13-hand-track-assignment-and-smoothing-security.md`,
brief `risk = "high"`): **PASS**, 0 CRITICAL/BLOCKER/MAJOR, 3 MINOR + 2 NOTE
— futott a merge ELŐTT (L162 helyesen alkalmazva ezúttal). Figyelemre méltó:
a security-review **egymástól függetlenül, más módszerrel** ugyanarra a
gyökérokra jutott, mint ennek a jelentésnek az F1 BLOCKERje (az ő MINOR-2-je
== ez az F1) — a security-lencse MINOR-nak minősíti (nincs mai fogyasztó →
nincs mai kár), a funkcionális/architektúra-lencse BLOCKER-nek (sérti a
brief §5 pont 4 kötött döntését, függetlenül a fogyasztótól). A
security-review két ÚJ tétele (visibility-kezelés, kéz-szám korlát)
lentebb F3/N3 néven be van építve ebbe a jelentésbe is, hogy a javító kör
egyetlen menetben lássa mindkét review teljes leletlistáját.

Mind a hat §6 acceptance-cella a saját, szűken vett próbáján zöld — beleértve
a §10.5 valódi-sértés próbát, amit **függetlenül, saját kézzel megismételve**
pontosan ugyanazt a 60.3%-os számot adta vissza. A BLOCKER és a MAJOR nem az
acceptance-listán, hanem a brief §5 **kötött architekturális döntésein**
bukik el — olyan bemeneteken, amiket a szállított fixture-mátrix nem próbált
ki (a review protokoll pontosan ezért követel próbatesztet az ÉLEKEN, nem
csak a brief saját fixture-jein).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Track-ID property teszt (`PROPERTY_SEED`) | ✅ | Függetlenül újrafuttatva izolált `/tmp` klónban: `PROPERTY_SEED=42`, 80/80 trial stabil, `hand_track_property_test.dart` zöld. |
| 2 | Occlusion-mátrix (alatta/rajta/fölötte `shortGapFrames`) | ✅ | Kód+fixture olvasással ellenőrizve: `occludedTrack(gapAt:10, gapLength:{2,3,5})` + `hand_track_assigner.dart:158-186` gap-logikája pontosan az inkluzív `≤` határt implementálja. Lásd F1 — az ID-stabilitás igaz, de a mögötte lévő POZÍCIÓ hibás lehet occlusion után. |
| 3 | Cross-hand fixture (szerep nem cserélődik) | ✅ | `hand_track_assigner_test.dart:190-223` + a hard handedness-constraint (`hand_track_assigner.dart:117`) olvasással ellenőrizve — a szerep a track létrehozásakor rögzül, a crossing csak pozíciót cserél, handedness-t nem. |
| 4 | Smoothing-mátrix (picking ≥90%, fretting ≥60%, számmal) | ✅ | Gate-újrafuttatás zöld; `landmark_smoothing_test.dart` mindkét assert konkrét %-ot számol és azt hasonlítja a küszöbhöz. |
| 5 | Mirror/leftHanded paritás (4 cella) | ✅ | `hand_track_assigner_test.dart:226-286` — a formula pontosan a brief §0.0 R8 levezetését implementálja (`hand_track_assigner.dart:193-202`), a facing NEM paraméter, tehát a 4 cella szerkezetileg triviális invariancia — ez SZÁNDÉKOS (lásd a brief R2), nem hiányosság. |
| 6 | Valódi-sértés próba (§10.5) | ✅ | **Függetlenül megismételve**: `pickingAlpha` átmenetileg `0.30`-ra állítva → `landmark_smoothing_test.dart` amplitúdó-cella PIROS, mért arány **60.3%** (bitre egyezik az implementer §10.5 állításával) → visszaállítva `0.85`-re, újra zöld. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --stat origin/main...HEAD` = 10 fájl, mind a brief `allowed_paths`-án (a 10. a brief maga, `§10` handoff + `§0.0` pre-flight — ez is listán van). A wrapper saját gépi scope-auditja (`scope_audit=ok`, `scope_audit_changed=10`, bázis `82e4602`) egyezik.

## Architektúra + termékhatárok (AGENTS.md §6, brief §5)

- **Domain-tisztaság:** a négy új fájl importja kizárólag `dart:math` + testvér domain fájlok (`hand_landmarks.dart`, `hand_track.dart`, `landmark_smoothing.dart`) — nincs Flutter/material import, nincs core↔feature visszahurkolás.
- **Determinizmus (§5 pont 6):** `grep -n "DateTime.now\|Random("` a négy production fájlon nulla találat (a `DateTime.now()` egyetlen előfordulása egy doc-comment, ami kifejezetten az ELKERÜLÉSÉT dokumentálja). Az egyetlen "óra" az injektált `frameIndex`.
- **`public.dart` (§4):** a diff pontosan 4 új `export` sor, egyetlen meglévő sor sem változott — additív, a claim igaz.
- **Fizikai kéz ≠ szerep (§5 pont 1):** a `_roleFor` formula (`hand_track_assigner.dart:193-202`) pontosan a brief §0.0 R8 levezetését implementálja, `leftHanded`-től függ, nem konstans — a tiltott hardcode NEM történt meg.

## Megállapítások

### F1 — BLOCKER — A jump-rejection nem tud felépülni egy valódi, tartós pozícióváltásból — a track némán, örökre befagy

- **Fájl:** `lib/features/vision/domain/landmarks/hand_track_assigner.dart:245-268` (`_InternalTrack.observe`), a mögöttes ok `landmark_smoothing.dart:82-89` (`shouldReject`) tervezési hibája.
- **Probléma:** a jump-rejection mindig a `previousSmoothed`-hez (az UTOLSÓ ELFOGADOTT simított értékhez) hasonlítja az új nyers pontot. Elutasításkor `previousSmoothed` NEM változik. Ha a kéz ténylegesen és tartósan egy `jumpVelocityThreshold`-nál (0.30/frame) távolabbi pozícióba kerül — akár egy rövid occlusion UTÁN (amit a §6 #2 kritérium sikeres felépülésnek minősít, hiszen az ID nem vált), akár occlusion NÉLKÜL, egyetlen folyamatosan látható kéz esetén is —, MINDEN további frame ugyanúgy elutasításra kerül, mert az összehasonlítási alap sosem mozdul. A track a régi pozícióban fagy be **örökre**, `status=active` mellett — semmilyen jelzés nem jut a fogyasztóhoz, hogy az adat elavult.
- **Hatás:** ez pontosan az, amit a brief §5 pont 4 tilt ("a jump-rejection nem törölhet valós, gyors mozgást"), csak nem az egyetlen tesztelt fixture-ön (oszcilláló fast-strum, aminek frame-enkénti deltája sosem lépi át a küszöböt), hanem bármilyen valós, tartós áthelyeződésen, ami MEGHALADJA a küszöböt — ez gitáros gyakorlat közben rutinszerű (akkordváltás, kapodaszter-igazítás, fogásváltás közbeni kézmozdítás rövid occlusionnal vagy anélkül). A "rövid gap → sikeres felépülés" acceptance kritérium (§6 #2) az ID-azonosságot igazolja, de a mögötte szállított POZÍCIÓ hibás maradhat — ez rosszabb eredmény, mint egy hosszú gap utáni új track (ott legalább `trackLost` jelzi a szakadást).
- **Bizonyíték (két eldobható próbateszt, mindkettő futtatva és törölve a review után):**
  1. **Occlusion + reappearance távolabb:** 10 frame 0.30-nál, 3 frame occlusion (`shortGapFrames` határon belül), majd 27 frame 0.70-nél (valós, tartós áthelyeződés). Mért kimenet: `frame10=0.3 frame59... last=0.3` — 27 frame (~0.9s) elteltével is a régi pozíción ragad.
  2. **Occlusion NÉLKÜL, folyamatosan látható kéz:** 10 frame 0.30-nál, majd 50 frame FOLYAMATOSAN látható 0.70-en. Mért kimenet: `frame10=0.3 frame59=0.3` — a hiba occlusiontól FÜGGETLENÜL, önmagában a jump-rejection tervezési hibája.
- **Kötelező javítás (irány, nem kész patch):** a jump-rejection alapját frissíteni kell, amikor a track state átmenetileg elveszett/recovering volt, vagy amikor több egymást követő frame kerül elutasításra — pl. (a) az első observáció `recovering`→`active` visszaváltáskor bypassolja az ellenőrzést (ugyanaz a minta, mint a meglévő "első frame, nincs previous" bypass a `filter()`-ben), vagy (b) a küszöböt a ténylegesen eltelt gap-hosszal skálázza, vagy (c) egy "N egymást követő elutasítás után catch-up" mechanizmus. Bármelyik irányhoz ÚJ fixture kell (tartós áthelyeződés occlusionnal és anélkül is), mert a meglévő `teleportingTrack` csak egy "blip-vissza-a-régi-pozícióra" mintát fed le, ami pont nem meríti ki ezt az esetet.
- **Ellenőrzés:** egy új smoothing/assigner teszt, ami egy tartós (nem visszatérő) áthelyeződést szimulál occlusionnal és anélkül is, és megköveteli, hogy N frame-en belül a simított kimenet konvergáljon az új pozícióhoz.
- **Státusz:** FIXED (`2ff9338`) — függetlenül újra-ellenőrizve, lásd a jelentés elején.

### F2 — MAJOR — `TrackContinuity` a két legfontosabb mezőjében (jitter, latency) funkcionálisan üres, ellentmond egy kötött döntésnek, és nulla tesztlefedettsége van

- **Fájl:** `lib/features/vision/domain/landmarks/track_continuity.dart:39-45,59,76-78,91-96`.
- **Probléma:** `maxJitterNormalized` egy sosem frissülő lokális `0.0` konstans — a forráskód saját kommentje elismeri ("jitter is therefore 0 unless the caller provides a comparison source... Hook left for R17/R18 metrics"), de a §10 handoff ezt nem jelöli meg eltérésként, a §10.6 kifejezetten "None"-t állít. `totalProcessingDuration` egy külső `processingDurations` paraméterre szorul, amit a kódbázisban SEMMI nem tölt ki — a `hand_track_assigner.dart`-ban nincs `Stopwatch`, miközben a `track_continuity.dart:44` doc-comment kifejezetten azt állítja, hogy "the assigner reports a `Stopwatch.elapsed` per call" — ez **tényszerűen hamis állítás a saját forráskódjában**.
- **Hatás:** a brief §5 pont 5 kötött döntése ("A simítás késleltetése MÉRVE és a TrackContinuity/performance összegzés RÉSZE — nem rejtett költség") NINCS teljesítve — a latency ma sehol nincs mérve. A `test/` fában `grep -rn "TrackContinuity"` NULLA találatot ad a saját tesztfájljain kívül — a négy domain fájl közül ez az egyetlen, aminek egyáltalán nincs semmilyen unit tesztje (a brief `allowed_paths`-a nem is jelöl ki külön teszt-útvonalat rá, de a két engedélyezett tesztfájl bármelyike bővíthető lett volna egy `TrackContinuity`-csoporttal új fájl nélkül).
- **Bizonyíték (eldobható próbateszt, futtatva és törölve):** `noiseAmplitude=0.30` (szándékosan extrém) `continuousNoisyTrack`-on át `TrackContinuity.aggregate(frames)` → `maxJitterNormalized=0.0`, `totalProcessingDuration=0:00:00.000000`.
- **Kötelező javítás (irány, nem kész patch):** vagy (a) valódi mérés bekötése — `Stopwatch` a `HandTrackAssigner.process()` törzse köré, az eltelt idő felszínre hozása (pl. `HandTrackFrameState` egy opcionális mezőjén vagy egy injektálható sink-en át), a jitter pedig a `_InternalTrack.observe()`-ban már elérhető nyers-vs-simított delta felhasználásával — PLUSZ egy dedikált tesztcsoport a meglévő két engedélyezett tesztfájl egyikében; vagy (b) ha a halasztás R17/R18-ra tényleg szándékos, ezt egy dokumentált brief-jegyzettel (nem csendes kódkommenttel) kell rögzíteni, és a `totalProcessingDuration`/`maxJitterNormalized` doc-commentjéből törölni a nem létező "assigner reports Stopwatch" állítást.
- **Ellenőrzés:** a fenti próbateszt (vagy annak végleges változata) NEM adhat vissza `0.0`-t egy ismerten zajos bemeneten, ha a mérés valóban be van kötve.
- **Státusz:** FIXED (`2ff9338`) — függetlenül újra-ellenőrizve, lásd a jelentés elején.

### F3 — MINOR — A simított `visibility` monoton MAX, nem konfidencia-tudatos (dedikált security-review MINOR-1)

- **Fájl:** `lib/features/vision/domain/landmarks/landmark_smoothing.dart:114-119`.
- **Probléma:** a security-review önállóan mérte: ha egy kéz eleinte tisztán látszik (`visibility=0.95`), majd tartósan gyengén (`visibility=0.10` sok frame-en át), a simított `visibility` a `max(raw, previous)` szabály miatt SOSEM csökken a történelmi max alá — 5 frame gyenge jel után is `0.95`-öt jelent.
- **Hatás:** ellentmond az SDD §15.4 kifejezetten kötelezőnek jelölt "confidence-aware exponential smoothing" elvárásának és az ADR 0179 capability-aware feedback szellemének — a mező elavult-optimista bizalmi jelzést hordoz. R13-ban nincs fogyasztó (látens), de OLCSÓN javítható most, amíg a fájl úgyis nyitva van az F1 miatt.
- **Kötelező javítás:** a `visibility` aggregálása NE `max(raw, previous)` legyen — kövesse a raw értéket (vagy kapjon saját, konzervatív EMA-t), hogy egy tartósan gyenge jel a kimeneten is gyengének látsszon.
- **Ellenőrzés:** egy teszt, ami tartósan alacsony raw visibility-t ad be N frame-en át, és megköveteli, hogy a simított visibility N frame után közel legyen a raw-hoz, ne a korábbi maximumhoz.
- **Státusz:** FIXED (`2ff9338`) — függetlenül újra-ellenőrizve, lásd a jelentés elején.

### N1 — NOTE — A §10.1 handoff-tábla elavult commit-hash-t idéz

- **Fájl:** `docs/rounds/e05-r13-hand-track-assignment-and-smoothing.md:227`.
- **Megfigyelés:** "Commit: `344dbf8`" — ez a `git add docs/... && git commit --amend --no-edit` ELŐTTI hash; a tényleges végső commit `cd4d49e`. Önreferenciális paradoxon (a commit nem idézheti a saját, még nem létező hash-ét), ártalmatlan, de érdemes a javító körben egy mondattal pontosítani.
- **Státusz:** OPEN (kozmetikai, nem blokkoló).

### N2 — NOTE — A handedness hard-constraint nem véd egy jövőbeli, valós providerből jövő átmeneti handedness-flip ellen

- **Fájl:** `lib/features/vision/domain/landmarks/hand_track_assigner.dart:117` (`if (candidate.handedness != obs.handedness) continue;`).
- **Megfigyelés:** a matching kizárólag a modell handedness-címkéjére hard-constraint-el. Ha egy éles (nem fixture-alapú) provider egy crossing/occlusion közben átmenetileg téves handedness-t jelentene ugyanarra a fizikai kézre, ez az assigner szintjén track-csere (ID-churn) formájában jelentkezne, NEM simulna el a rövid-gap logikával — mert a hard constraint miatt az observáció "unmatched" lesz, és új tracket kap. A brief §0.0 R1 szerint a handedness-t ez a kör bemenetként, adottként kezeli, tehát ez explicit módon NEM ennek a körnek a hatásköre — pusztán egy mérési megfigyelés a jövőbeli, éles providerrel futó köröknek (R14+), amikor a `RecordedHandLandmarkProvider` fixture-alapú, mindig konzisztens handedness-e helyett valódi ML-kimenet kerül a láncba.
- **Státusz:** follow-up, nem blokkoló.

### N3 — NOTE — Nincs kéz-szám korlát frame-enként (dedikált security-review MINOR-3, itt NOTE-ra süllyesztve)

- **Fájl:** `hand_track_assigner.dart:98,108-134,137-153`.
- **Megfigyelés:** a security-review mérte: 4000 "kéz" egy frame-ben ~118s-ot vesz igénybe (köbös skálázódás a greedy `matched.contains(...)` List-alapú tagságvizsgálat miatt). R13-ban a bemenet valós on-device ML-ből jön (≤2 kéz), és a hosszkorlát bevezetése a felelős fájl (`hand_landmarks.dart`, `HandLandmarkResult`) NINCS ezen a kör `allowed_paths`-án — a teljes javítás (input-oldali korlát) kívül esik a jelenlegi kör hatáskörén. A `matched` `Set`-re cserélése (O(1) tagság a `List.contains` helyett) VISZONT a jelenlegi fájlokon belül maradna, és olcsó védelem lenne — de mivel nincs untrusted feed ma, ez NEM feltétele a mostani merge-nek.
- **Státusz:** follow-up (R14+ pipeline-drótozás előtt érdemes megoldani), nem blokkoló ebben a körben.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer §10.2) | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ — függetlenül újrafuttatva izolált `/tmp` klónban |
| analyze | zöld | ✅ — 0 hiba/figyelmeztetés a diffen (a klón első futása l10n-generálás hiánya miatt piros volt — `tools/prepare-flutter-generated.sh` után zöld, ez a klón hibája, nem a köré) |
| test test/features/vision | zöld | ✅ — 109 teszt, mind zöld |
| test test/property/hand_track_property_test.dart | zöld | ✅ — `PROPERTY_SEED=42`, 1/1 zöld |
| architecture | zöld | ✅ — 12 allowlistelt eltérés, nincs új |
| secrets | zöld | ✅ — 0 lelet, 1919 fájl |
| l10n | zöld | ✅ — en↔hu 964 üzenet, nincs új string |
| CI (teljes suite + property + APK) | — | ⏳ orchestrátor dispatch-eli a javító kör után |

## Merge-döntés

**APPROVED — mehet a CI-dispatch és a merge.** Mind a három nyitott lelet
(F1 BLOCKER, F2 MAJOR, F3 MINOR) FIXED a javító kör 1-ben (`2ff9338`),
függetlenül újra-ellenőrizve friss `/tmp` klónban — saját (nem az
implementer) próbatesztekkel, a gate teljes újrafuttatásával, és a meglévő
teleport-rejection viselkedés regressziómentességének igazolásával. A
dedikált security-review (`risk=high`) PASS, futott a merge ELŐTT. N1
(kozmetikai), N2 (handedness-flip robusztusság) és N3 (kéz-szám korlát)
follow-up, nem feltétele ennek a merge-nek. Hátravan: CI-dispatch a javító
kör fejére (`2ff9338`) exact-SHA-n, majd a squash-merge (ADR 0052).
