# E14-R23 — Strum shadow mód az alkalmazásban (ADR 0548)

- **Kör:** E14-R23 · **Csomag:** PKG-E · **ADR:** 0548
- **Ág:** `claude/laptop-apk-debug-prompt-kys4oa`
- **Környezet:** nincs Dart/Flutter SDK ezen a boxon → **lokális gate nem
  futtatható**; a mérce a session végi `full-gate.yml` + `build-apk.yml`, a
  végső elfogadási predikátum pedig a felhasználó valós gitáros APK-tesztje.

## 1. Cél

A `recognitionShadowModeEnabled` zászlónak **valódi fogyasztót** adni: a
PKG-A által leszállított kimeneti seam-re egy korlátos, determinisztikus,
Lab-látható összehasonlító réteget kötni, amely soha nem érinti a produkciós
kimenetet, és amelynek a memóriaigénye nem nő a menet hosszával.

## 2. Mért állapot (a kör előtt)

- `recognitionShadowModeEnabled` **fogyasztó nélkül** állt a `lib/**`-ben.
- `recognition_shadow_observer.dart` (PKG-A, ADR 0545 D6): egy hívási pont
  `LivePipeline.addChunk`-ban, `void` visszatérés, no-op alapértelmezés.
  **Kimenetet ad át, jellemzőt nem.**
- `RecognitionRolloutStage` + a két zászlópár (PKG-D, ADR 0542 D2):
  aszimmetrikus ÉS, fail-closed, `shadow.isUserVisible == false`.
- `RealStrumEngine` izolátum-protokollja csak `LiveFrame`-et hoz vissza; a
  megfigyelő-gyár 0 argumentumú top-level függvény → nincs visszaút a UI-ig.
- `LiveLabState` a kör előtt csak `phase` / `result` / `runtimeInfo` mezőt vitt.

## 3. Scope

**Benne:** `lib/features/live/data/shadow/**` (gyűrű, taxonómiák,
aggregátumok, felvevő, két megfigyelő + fan-out, kapu, session-futtató);
`RecognitionRuntimeInfo` bővítése (mód + shadow-fokozat); a Lab panel
shadow-szekciója; a Lab provider bekötése `compute()`-tal.

**Kívül:** `live_pipeline.dart` és `recognition_shadow_observer.dart`
(PKG-A); `feature_flags.dart` (PKG-D); `evaluation/**` (PKG-B); ARB
(orchestrátor); DSP-küszöb bármelyike (ez a kör egyet sem hangol).

## 4. Érintett fájlok

**Új (lib):** `data/shadow/{shadow_metrics,recognition_shadow_recorder,
recognition_shadow_observers,chord_shadow_candidate,recognition_shadow_gate,
recognition_shadow_session}.dart`
**Módosított (lib):** `model/recognition_runtime_info.dart`,
`providers/live_lab_provider.dart`, `widgets/live_lab_panel.dart`
**Új (test):** `test/features/live/shadow/{shadow_metrics,
recognition_shadow_gate,strum_shadow_observer,recognition_shadow_session,
shadow_allocation_bound}_test.dart`,
`test/features/live/lab/live_lab_shadow_panel_test.dart`
**Módosított (test):** `test/features/live/recognition_runtime_info_test.dart`
**Docs:** `docs/adr/0548-*.md`, ez a brief, `docs/rag/chunks/015-*.md`
**l10n:** 14 új kulcs a scratch protokoll szerint (`liveLabShadow*`).

## 5. Kapuk

Változatlan ADR 0052 zöld kapu. A kör nem ad új CI-workflow-t és nem bővít
CLI belépési pontot (a terv §0/1 tiltja).

## 6. Acceptance

| # | Kritérium | Státusz |
|---|---|---|
| 1 | Zászló OFF → nulla extra inferencia (nem „lefut és eldobjuk") | **PINNED-BY-TEST** — `a closed gate does not even PARSE the weights it was handed` |
| 2 | A shadow kimenet SOHA nem ér el `LiveFrame`-et/score-t | **PINNED-BY-TEST** — `installing BOTH observers leaves the frames bit-identical` |
| 3 | A disagreement-riport determinisztikus ugyanarra a PCM-re | **PINNED-BY-TEST** — `the same PCM produces the same snapshot JSON` |
| 4 | A buffer korlátos (nem nő hosszú folyamon) | **PINNED-BY-TEST** — `shadow_allocation_bound_test.dart` (objektumszám, nem wall-clock) |
| 5 | A kapu a PKG-D zászlópárt olvassa, aszimmetrikus ÉS-sel | **PINNED-BY-TEST** — `recognition_shadow_gate_test.dart` |
| 6 | Üres ablakon NINCS egyezési arány (null, nem 0/1) | **PINNED-BY-TEST** |
| 7 | A mód és a shadow-fokozat megjelenik a `RecognitionRuntimeInfo`-ban, JSON-körbefordulással | **PINNED-BY-TEST** |
| 8 | 10 perces valós A/B memória-mérés eszközön | **NEEDS-MEASUREMENT** |
| 9 | Egy MÁSIK jelölt-háló futtatása ugyanazokon a jellemzőkön | **NOT DELIVERED** — jellemző-csap kell `live_pipeline.dart`-ba (patch a jelentésben); ADR 0548 D3 kimondja |

## 7. Verifikáció

Lokálisan nem futtatható (nincs SDK). A cellák felsorolása és az, hogy mit
bizonyítanak, a §6-ban van; sikeres verifikáció **nincs állítva** (Ch14 §9/9).

## 8. Kockázatok

1. A kör a **kimeneti** csapot méri; aki „árnyékmodellt" olvas bele, többet
   képzel, mint amennyi van. Ezt az ADR 0548 D3 és ez a §6/9. sor kimondja.
2. A Lab-vezérelt futtatás egy második pipeline a felvett PCM felett: nem
   mutatja meg a két pipeline hosszú menet alatti elsodródását.
3. Semmi nem fordult le ezen a boxon.

## 9. Rollback

A kapu bármelyik felének kikapcsolása (PKG-D zászlók) az egész utat
kikapcsolja; a szállított fán mindkettő `off`/`false` minden környezetben.

## 10. Handoff

- PKG-A: a jellemző-csap és az izolátum-visszaút patchei a PKG-E jelentés §5-ben.
- PKG-B: `RecognitionShadowSnapshot.toJson()` kész riport-forrás az
  `evaluation/**` oldali összehasonlításhoz.
- Orchestrátor: ARB-merge (`scratchpad/l10n/PKG-E.json`, `base`, 14 kulcs).
