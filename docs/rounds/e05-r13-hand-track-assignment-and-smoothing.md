# E05-R13 — Hand track assignment és temporal smoothing

- **Státusz:** PLANNING (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`;
  pre-flight mérve 2026-08-07: main @ `7c9ee09`, E05-R12 merge után)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 13; §15.3–15.4
- **Branch:** `codex/e05-r13-hand-track-assignment-and-smoothing`
- **Előfeltétel:** **E05-R12 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/landmarks/hand_track.dart",
  "lib/features/vision/domain/landmarks/hand_track_assigner.dart",
  "lib/features/vision/domain/landmarks/landmark_smoothing.dart",
  "lib/features/vision/domain/landmarks/track_continuity.dart",
  "lib/features/vision/public.dart",
  "test/features/vision/domain/hand_track_assigner_test.dart",
  "test/features/vision/domain/landmark_smoothing_test.dart",
  "test/property/hand_track_property_test.dart",
  "test/fixtures/vision/tracks",
  "docs/rounds/e05-r13-hand-track-assignment-and-smoothing.md",
]
gate_tests = [
  "test/features/vision",
  "test/property/hand_track_property_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R12 merge; olvasd újra a
> `HandLandmarks` mezőit (handedness confidence van-e), az R07 mirror-szabályát
> (a model input **nem** tükrözött) és a `StorageKeys.leftHanded` beállítást.
> Nincs ÚJ ADR. PREPARED→PLANNING, brief commit az implementer indítása ELŐTT.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PLANNING.** Nincs előre kiosztott ADR, és ez a kör nem is hoz létre újat
(megerősítve, nem hiba). Hét mért megerősítés (a §1 két mérési szabálya
lefutott — nincs a kódból hiányzó hivatkozás, tehát nincs tartalmi
brief-revízió, csak státuszváltás):

1. **Handedness confidence NEM létezik önálló mezőként.** `HandObservation`
   (`lib/features/vision/domain/landmarks/hand_landmarks.dart:94-125`)
   kizárólag egy összesített `confidence` mezőt hordoz ("Overall
   hand-detection confidence in `[0, 1]`") — a handedness-osztályozásnak
   nincs saját bizalmi értéke. Ezt a §9 kockázat előre jelezte: a
   track-hozzárendelés tehát **pozíció + előző állapot** alapján megy (az
   összesített `confidence`-et csak általános minőségi jelzésként
   felhasználva), és ezt a §10-nek explicit rögzítenie kell.
2. **R07 mirror-szabály megerősítve.** A `HandLandmarkPoint` dokumentáltan
   "the model's non-mirrored, resolution-independent normalized frame
   space"-ben él; a front-kamera preview-mirror (`mirrorPreview = camera ==
   front`, R08/R11 minta) kizárólag megjelenítési réteg — a landmark-
   koordináták és a `Handedness` osztályozás nem függ a kamera facing-től
   (R07 saját property tesztje: "front preview mirroring cannot alter the
   model input space"). A §6 4-cellás `leftHanded × front/back kamera`
   mátrix tehát egy **invariancia-próba**: helyes implementáció mellett a
   front/back tengely NEM változtatja a gitáros szerepet. Az assigner NE
   vegyen fel kamera-facing paramétert bemenetként; ha egy teszt ezt mégis
   megkövetelné a helyes eredményhez, az implementációs hiba jele.
3. **`StorageKeys.leftHanded`** (`ss.settings.left_handed`,
   `lib/core/storage/storage_keys.dart:19`) megerősítve, meglévő
   `leftHandedProvider`-rel (`lib/features/settings/providers/
   left_handed_provider.dart`) olvasható.
4. **`lib/features/vision/public.dart`** megerősítve additív export
   mintaként — a meglévő `hand_landmarks.dart` export mellé kerülnek az ÚJ
   track/assigner/smoothing exportok, a meglévő sorok változatlanok.
5. **SDD §15.3–15.4 + Kör 13** (`docs/sdd/06-epic-05-computer-vision.md:1123-1151,
   2652-2687`) megerősítve — a brief hatóköre pontosan lefedi. A §15.3 által
   említett "gitár orientationtől" és "setup profiltól" függőségi tényezőt a
   brief tudatosan kizárja ebből a körből (gitár-geometria R15 tárgya; a
   setup profil kamera-framing ajánlás, nem szerep-hozzárendelési bemenet) —
   ez NEM hiányzó lefedettség, hanem szándékos hatókör-szűkítés.
6. **Erőforrás-tulajdonlás:** nincs `.acquire(`/lease/lock hívás ennek a
   körnek a scope-jában (pure Dart domain, nincs kamera/mikrofon-erőforrás
   érintve) — a §1 2. mérési szabálya erre a körre nem alkalmazható.
7. **Elérhetetlen cél-státusz:** a brief acceptance-cellái (`trackLost`,
   track-ID stabilitás) ÚJ, ebben a körben bevezetett enumokra vonatkoznak,
   nem egy meglévő reducer/állapotgép előírt cél-állapotára — a §1 1. mérési
   szabálya erre a körre szintén nem alkalmazható (nincs mit a kódban
   ellenőrizni, mert a kód még nem létezik).

**Egyéb pre-flight ellenőrzés:** brief-lint nulla lelet
(`.pipeline/brief-lint-E05-R13.md`); nincs inflight párhuzamos kör
(`.pipeline/inflight/` csak ezt a kört tartalmazza); `gh pr list` üres;
motor `minimax` (nyilvántartás: harness=`claude` → `tools/mm-round.sh`).
`risk = "high"` → dedikált **security-reviewer** review kötelező, és ezúttal
**a merge ELŐTT** ütemezve (L162 — R12-ben ezt elmulasztottuk, utólag
pótoltuk; ez a kör előre tervezi, hogy ne ismétlődjön).

## 1. Cél

Stabil **fretting** és **picking** hand track jitter és rövid takarás mellett:
track-hozzárendelés, szerep-elválasztás, profilfüggő simítás, jump-rejection és
gap-recovery — **pure Dart**, fixture-ekkel bizonyítva.

## 2. Jelenlegi állapot (mért, megelőző körök)

- Az R12 ad nyers, timestampelt `HandLandmarks`-ot 0/1/2 kézre, StrumSight
  landmark ID-kkel; tracking és simítás **nincs**.
- Az R07 rögzíti: a model input **nem tükrözött** — a bal/jobb szerep tehát
  nem következtethető a preview-tükrözésből.
- `StorageKeys.leftHanded` (`ss.settings.left_handed`) létező beállítás — a
  **fizikai kéz** és a **gitáros szerep** leképezésének bemenete.

## 3. Scope

**Benne:** `HandTrack` (stabil ID + életciklus), `HandTrackAssigner`
(pozíció + handedness confidence + előző állapot), a **fizikai kéz** (left/right)
és a **gitáros szerep** (fretting/picking) szétválasztása, profilfüggő simítás
(gyors picking vs lassú fretting), jump-rejection, rövid gap-recovery, hosszú
gap után **új** track ID, `TrackContinuity` metrika.

**Kívül — TILOS:** pose (R14), gitárkoordináta (R15), metrikák (R18/R19),
UI, provider-adapter módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/landmarks/hand_track.dart` | ÚJ | track modell + ID |
| `.../domain/landmarks/hand_track_assigner.dart` | ÚJ | hozzárendelés |
| `.../domain/landmarks/landmark_smoothing.dart` | ÚJ | profilfüggő szűrő |
| `.../domain/landmarks/track_continuity.dart` | ÚJ | folytonossági metrika |
| `lib/features/vision/public.dart` | meglévő | additív export |
| `test/features/vision/domain/*`, `test/property/*`, `test/fixtures/vision/tracks` | ÚJ | tesztek |
| `docs/rounds/e05-r13-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **Fizikai kéz ≠ gitáros szerep.** A modell mindkettőt tárolja, és a
   leképezés a `leftHanded` beállításból + a gitárgeometriából származik.
   **NEM elfogadható:** a „bal kéz = fretting" hardcode.
2. **A simítás nem tompíthatja el a gyors stroke-ot.** A picking profil
   szűrőjének **mért** amplitúdó-megtartása gyors fixture-en ≥ **90 %** a
   nyers amplitúdóhoz képest; a fretting profil erősebben simíthat.
   **NEM elfogadható:** egyetlen közös szűrő „az egyszerűség kedvéért", és
   **nem elfogadható** a 90 %-os korlát lejjebb vitele kódkommenttel indokolva.
3. **Rövid gap (≤ `shortGapFrames`) → ugyanaz a track ID**, hosszú gap →
   **explicit `trackLost` + új ID**. A határ konfigurált konstans, és a
   teszt az **alatta / rajta / fölötte** hármast méri.
4. **A jump-rejection nem törölhet valós, gyors mozgást**: a küszöb sebességre
   (nem elmozdulásra) vonatkozik, és a fixture-mátrix tartalmaz egy **valódi
   gyors strum** esetet, ami NEM eshet ki.
5. **A simítás késleltetése mérve** és a `TrackContinuity`/performance
   összegzés része — nem rejtett költség.
6. **Pure Dart, framework-mentes domain**; determinisztikus (injektált óra,
   nincs `DateTime.now()` a szűrőben).

## 6. Acceptance criteria

- [ ] **Track-ID property teszt (`PROPERTY_SEED`):** zajos, de folytonos
      pályán a track ID **nem változik**; a küszöbök %-alapúak.
- [ ] **Occlusion-mátrix:** gap hossza a `shortGapFrames` **alatt / rajta /
      fölött** — az első kettő ugyanaz az ID, a harmadik `trackLost` + új ID.
      A cellák értékét `python3 -c` számolja (a §10-ben idézve).
- [ ] **Cross-hand fixture:** a két kéz keresztezi egymást → a szerepek
      **nem cserélődnek fel** (ID-stabilitás), és a teszt ezt cellánként méri.
- [ ] **Smoothing-mátrix:** gyors strum fixture-en a picking profil amplitúdó-
      megtartása ≥ 90 %, a fretting profil zajcsökkentése ≥ a dokumentált érték;
      mindkettő **számmal** az assertben.
- [ ] **Mirror/left-handed paritás:** `leftHanded` be/ki × front/back kamera =
      4 cella; a gitáros szerep helyes mind a négyben.
- [ ] **Valódi-sértés próba (§10):** a picking profil szűrőjének felcserélése a
      frettingére → a smoothing-mátrix PIROS → visszaállítás.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/property/hand_track_property_test.dart
```

Külön processzek, nincs `&&`/pipe/`tail`. CI-dispatch/PR/merge = orchestrátor.

## 8. Implementációs sorrend

1. Fixture-generátor (folytonos, zajos, occlusion, cross-hand, gyors strum).
2. RED: ID-stabilitás, occlusion-, smoothing-, paritás-mátrix.
3. Track modell + assigner.
4. Simítás + jump-rejection + continuity; property teszt; gate.

## 9. Kockázatok

- **A szűrő „megeszi" a gyors pengetést**, és emiatt az R19 stroke-metrikái
  hamisan konzisztensek lesznek — a 90 %-os amplitúdó-korlát ezt fogja meg.
- **A handedness confidence hiányozhat** a provider kimenetéből (R12 mérése
  dönti el); ha nincs, a hozzárendelés pozíció + előző állapot alapján megy, és
  ezt a §10-nek rögzítenie kell.

**STOP:** közös szűrő, hardcode-olt kéz-szerep vagy az amplitúdó-korlát
lazítása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r13-hand-track-assignment-and-smoothing-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
