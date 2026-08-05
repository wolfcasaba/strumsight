# E05-R12 — Hand landmark provider adapter és model manifest

- **Státusz:** PREPARED (előre megírva 2026-08-05, kód olvasva: main @ `5d082dc`)
- **SDD-kör:** [`docs/sdd/06-epic-05-computer-vision.md`](../sdd/06-epic-05-computer-vision.md) Kör 12; §15.1–15.2, §30
- **Branch:** `codex/e05-r12-hand-landmark-provider-and-model-manifest`
- **Előfeltétel:** **E05-R06, E05-R07 merge**
- **Brief szerzője:** Claude (batch) · **Implementáció:** Codex (Terra)

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/vision/domain/landmarks/hand_landmarks.dart",
  "lib/features/vision/data/landmarks/hand_landmark_provider.dart",
  "lib/features/vision/data/landmarks/native_hand_landmark_provider.dart",
  "lib/features/vision/data/landmarks/recorded_hand_landmark_provider.dart",
  "lib/core/ml/vision_model_manifest.dart",
  "lib/features/vision/public.dart",
  "assets/ml/model_manifest.json",
  "ml/make_manifest.py",
  "pubspec.yaml",
  "test/features/vision/data/hand_landmark_provider_test.dart",
  "test/features/vision/domain/hand_landmarks_test.dart",
  "test/tooling/ml_asset_manifest_test.dart",
  "docs/adr/0168-vision-hand-landmark-inference-stack.md",
  "docs/rounds/e05-r12-hand-landmark-provider-and-model-manifest.md",
]
gate_tests = [
  "test/features/vision",
  "test/tooling",
]
native_gate = false
```

> ⚠ **Pre-flight (KÖTELEZŐ):** `origin/main` + E05-R06/R07 merge; olvasd újra
> `assets/ml/model_manifest.json` **mai sémáját**, `ml/make_manifest.py`-t és
> `test/tooling/ml_asset_manifest_test.dart`-ot (ADR 0063) — a vision-manifest
> ezt **bővíti**, nem újat épít. **ADR 0168** előre kiosztva; ütközéskor a
> 0161–0170 blokk tolása. PREPARED→PLANNING, brief commit előbb.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>" ; tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>" ; tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 0.0 Tervezési baseline és pre-flight revízió

**PREPARED.** Előre kiosztott ADR: **0168** (a választott on-device inference
stack, a model-asset licenc- és integritás-politikája).

## 1. Cél

**Providerfüggetlen** kéz-landmark contract + production adapter + rögzített
kimeneten futó CI-adapter, és a model-asset **checksum + licenc + output-schema**
nyilvántartása a meglévő manifest-rendszerben.

## 2. Jelenlegi állapot (mért, `5d082dc`)

- `assets/ml/model_manifest.json` (3 114 bájt) írja le a mai audio-modelleket
  (`chord_crnn.bin`, `strum_crnn*.bin`); a generátor `ml/make_manifest.py`, az
  őr `test/tooling/ml_asset_manifest_test.dart` (ADR 0063).
- **Nincs `lib/core/ml/`**, nincs vision model-asset, nincs inference plugin.
- Az R06 adapter szolgáltatja a `CameraFrame`-et; az R07 a nem tükrözött
  normalized teret — a modell bemenete **ez**.

## 3. Scope

**Benne:** `HandLandmarks` domain-modell **stabil StrumSight landmark ID-kkel**,
`HandLandmarkProvider` interfész (timestampelt, stream-alapú), production
adapter az ADR 0168 szerinti stackkel, `RecordedHandLandmarkProvider`
(rögzített kimenet fixture-ből, CI-ben ez fut), `VisionModelManifest`
(checksum + input/output schema + licenc + evaluation-hivatkozás),
manifest-generátor és -őr bővítése, initialization-kori asset- és
output-shape-validáció.

**Kívül — TILOS:** tracking/smoothing (R13), pose (R14), metrikák (R18+),
DSP-paraméter, audio-modellek érintése, **training**.

## 4. Engedélyezett fájlok

| Útvonal | Állapot | Miért |
|---|---|---|
| `.../domain/landmarks/hand_landmarks.dart` | ÚJ | landmark ID-k + modell |
| `.../data/landmarks/hand_landmark_provider.dart` | ÚJ | interfész |
| `.../data/landmarks/native_hand_landmark_provider.dart` | ÚJ | production adapter |
| `.../data/landmarks/recorded_hand_landmark_provider.dart` | ÚJ | fixture-adapter |
| `lib/core/ml/vision_model_manifest.dart` | ÚJ | manifest olvasó/validátor |
| `assets/ml/model_manifest.json` | meglévő | **additív** vision bejegyzés |
| `ml/make_manifest.py` | meglévő | generátor bővítés |
| `pubspec.yaml` | meglévő | inference függőség (ha az ADR 0168 kér) |
| `test/features/vision/*`, `test/tooling/*` | ÚJ/meglévő | tesztek |
| `docs/adr/0168-*.md` | ÚJ | inference stack döntés |
| `docs/rounds/e05-r12-*.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más; `assets/ml/*.bin` (audio modellek); `docs/rag`;
DSP-konstans; bármely training-script futtatása. Listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. **A domain nem függ provider-API-tól** (ADR 0163): a `HandLandmarks` a
   StrumSight saját ID-jeit használja, a provider mapping a `data/` rétegben van.
   **NEM elfogadható:** provider-index (`landmark[8]`) szivárgása a domainbe.
2. **Nincs kimenet ≠ hiba.** Zero-hand output **`notObservable`**, nem failure —
   a hívó nem kap „valamit" kényszerből. **NEM elfogadható:** üres landmark-lista
   helyett nullákkal kitöltött modell.
3. **Timestamp-monotonitás védett:** régebbi timestampű eredmény **eldobódik**
   (a stream nem keveredhet). Ezt teszt méri.
4. **Model-asset szabály (AGENTS.md §9 + ADR 0063):** minden asset mellé
   **checksum + licenc + verzió + output-schema** a manifestben, és az
   initialization **ellenőrzi a checksumot és az output shape-et**; eltérés →
   fail-closed, capability `unavailable`. **NEM elfogadható:** manifest nélküli
   asset, vagy checksum-ellenőrzés kihagyása „mert lassú".
5. **Ha a kör környezetében a model-asset nem szerezhető meg jogtisztán**
   (letöltés/licenc nem teljesíthető): a kör a **contractot, a manifest-sémát,
   a validátort és a `RecordedHandLandmarkProvider`-t szállítja**, az assetet
   a manifestben `status = "deferred"` bejegyzés jelöli, és a device-mátrix kap
   egy PENDING sort. Ez **nem halt** és **nem mércegyengítés** — a production
   adapter ilyenkor fail-closed `unavailable`-t ad, tesztelve.
6. **A CI-ben a rögzített kimenetű adapter fut** — natív inference a CI-ben nem
   követelmény. A valós eszközös latency a device-mátrix PENDING sora.

## 6. Acceptance criteria

- [ ] **Mapping-teszt rögzített kimeneten:** a fixture provider-kimenet →
      StrumSight landmark ID-k, **mind a 21 pont** ellenőrzött indexszel.
- [ ] **Kéz-szám mátrix:** 0 / 1 / 2 kéz — a 0 `notObservable`, az 1 és 2
      külön track-jelölt, a >2 kimenet kontrolláltan levágott (nem crash).
- [ ] **Timestamp-mátrix:** növekvő / azonos / **csökkenő** timestamp — a
      csökkenő eldobódik, és ezt számláló méri.
- [ ] **Manifest-őr:** hiányzó checksum / rossz checksum / hiányzó licenc /
      eltérő output-schema → mind a négy esetben **init-hiba**, capability
      `unavailable`; és a `test/tooling/ml_asset_manifest_test.dart` a vision
      bejegyzésre is fut.
- [ ] **Valódi-sértés próba (§10):** a manifest checksum egy karakterének
      átírása → a manifest-őr PIROS → visszaállítás.
- [ ] Az ADR 0168 megnevezi: a választott stacket, a licencet, az asset méretét,
      az elutasított alternatívákat és a **visszavonás** feltételét.
- [ ] Az audio modellfájlok (`chord_crnn.bin`, `strum_crnn*.bin`) **bájtra
      változatlanok** (`git diff --stat` nem tartalmazza őket).

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/vision test/tooling
```

Külön processzek, nincs `&&`/pipe/`tail`. A natív inference fordítási
bizonyítéka a CI `build-apk`; a valós latency PENDING a device-mátrixban.

## 8. Implementációs sorrend

1. ADR 0168 (stack + licenc + asset-politika).
2. RED: mapping-, kéz-szám-, timestamp- és manifest-mátrix.
3. Domain modell + interfész + rögzített adapter.
4. Manifest-séma + generátor + validátor.
5. Production adapter (vagy fail-closed `unavailable`, §5.5); gate.

## 9. Kockázatok

- **Az asset licence/beszerzése blokkol** — a §5.5 deferred útja erre van.
- **A manifest-séma töri az audio-oldali őrt** — a bővítés **additív**, a mai
  mezők nem nevezhetők át; ha a meglévő teszt elbukik, az **megállás és jelentés**.
- **Az APK mérete ugrik** a model-assettel — a méretet a §10-ben számmal kell
  rögzíteni.

**STOP:** training indítása, audio-modell érintése, checksum-ellenőrzés
kihagyása vagy provider-típus szivárgása helyett dokumentált brief-revízió.

## 10. Implementation handoff — az implementer tölti ki

_(üres)_

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e05-r12-hand-landmark-provider-and-model-manifest-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
