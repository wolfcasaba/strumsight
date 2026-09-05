# E14-R10 — Review (ADR 0055, független, read-only)

- **Kör:** `E14-R10` — Az irány-abstention BEKÖTÉSE a Live úton
- **Branch:** `sonnet-impl/e14-r10-direction-abstention-hotfix`, head `f39f4bd1`
- **Implementer:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude (Opus 5), a kör orchestrátora — read-only, production
  fájlt nem módosítottam
- **ADR:** [0512](../adr/0512-live-direction-abstention-wiring.md) (a pre-flightban írva)
- **Review-klón:** `/tmp/claude-1001/rev-e14-r10` (izolált `git clone` a
  munkapéldányból, `f39f4bd1`)

## 1. VÉGSŐ DÖNTÉS: **APPROVED**

0 BLOCKER, 0 MAJOR. 2 MINOR + 1 NOTE — egyik sem blokkol merge-öt (ADR 0052:
a merge-kapu a zöld gate + zöld CI a merge SHA-n).

## 2. Scope-audit

`scope_audit=ok` a wrapper gépi auditjából
(`scope_audit_base=b542c1b3`, `scope_audit_changed=8`). Saját mérés,
`git diff --name-only b542c1b3..f39f4bd1`:

| Fájl | `allowed_paths`-on? |
|---|---|
| `lib/features/live/engine/dsp/live_pipeline.dart` | ✅ |
| `lib/features/live/engine/dsp/strum_analyzer.dart` | ✅ |
| `lib/features/live/engine/dsp/strum_direction_classifier.dart` | ✅ |
| `lib/features/live/engine/ml/live_crnn_classifier.dart` | ✅ |
| `test/features/live/strum_direction_abstention_test.dart` (ÚJ) | ✅ |
| `test/features/live/dsp/live_pipeline_test.dart` | ✅ |
| `docs/eval/recognition-direction-abstention.md` (ÚJ) | ✅ |
| `docs/rounds/e14-r10-direction-abstention-hotfix.md` (§10) | ✅ |

A `lib/features/live/domain/recognition/` **egyetlen fájlja sem** szerepel — a
6. acceptance-pont (szerződés-érintetlenség) mérve teljesül. A
`public.dart`-ot nem kellett bővíteni (a `StrumPrediction` export már élt:
`public.dart:30`). A munkafa a `done` jelzés után **tiszta**
(`git status --short` üres) — a jelzésbeli `dirty_files=1` a §10-handoff
commit előtti pillanatfelvétel volt, nem maradék.

## 3. Acceptance-pontok — leletenként mérve

| # | Pont | Verdikt | Mérés |
|---|---|---|---|
| 1 | Kivezetés, `direction`/`confidence` bájtra ugyanaz | ✅ | a `classifyProbs` `direction`/`confidence` sorai a diffben érintetlenek; a `live_crnn_classifier_test.dart` **módosítás nélkül** zöld a saját gate-futásomban |
| 2 | Döntés-hármas (alatta/rajta/fölötte) | ✅ | mind a 3 cella zöld; a „rajta" cella a `(2·T, T)` egzakt párral, `expect(pDown - pUp, 0.05)` asserttel |
| 3 | `uncertain` → nincs nyíl, az idő sem lép | ✅ | `_latestStrumTime` az őrzött blokkon BELÜL marad; a cella `latestStrumTime == -1`-et állít minden frame-re |
| 4 | `confirmed` → változatlan mai viselkedés | ✅ | új regressziós cella a `live_pipeline_test.dart`-ban; a fájl 4 meglévő cellája változatlanul zöld |
| 5 | Heurisztikus ág: nincs kitalált valószínűség | ✅ | `_isDirectionConfirmed` `null` prob-nál `true`; a `HeuristicStrumClassifier` egyetlen sora sem változott |
| 6 | A szerződés érintetlen | ✅ | lásd §2 |

## 4. Falszifikáció — SAJÁT, független próbák (nem bemondásra)

Négy valódi-sértés próbát futtattam az izolált klónban, mindegyiket
visszaállítva. **Baseline: `00:00 +4: All tests passed!`**

| Próba | Sértés | Mért eredmény |
|---|---|---|
| **P1** | a döntés-lekérdezés megkerülése (`&& _isDirectionConfirmed(event)` törölve) | **PIROS** — a „below" és a „rajta" cella bukik (`+2 -2`) |
| **P2** | ELFOGADÁS-oldalon inkluzív határ (`directionMargin >= threshold`) a szerződés-getter helyett | **PIROS** — **kizárólag** a „rajta" cella bukik (`+3 -1`) |
| **P3** | a heurisztikus ág is kapuzva (`null` prob → `false`) | **PIROS** — kizárólag a heurisztikus cella bukik (`+3 -1`) |
| **P4** | `_latestStrumTime` az őrzött blokkon KÍVÜLRE emelve | **PIROS** — a „below" és a „rajta" cella bukik (`+2 -2`) |

**A P2 a kör legfontosabb bizonyítéka.** A brief §6.1 mérce-mátrixa azt ígéri,
hogy „a margó-határ elfogadás-oldalon inkluzív (`<`)" hibát a „rajta" cella
fogja pirosra — és pontosan azt, egyedül azt fogja meg. Ez egyben a pre-flight
§0.0b/9 javításának igazolása: a naiv `(0.525, 0.475)` párral ez a cella a
HELYES implementáción lett volna piros (IEEE-754-ben `0.050000000000000044`),
tehát semmit nem mért volna.

## 5. Kötelező gate — SAJÁT futtatás, izolált klónban

```
tools/round-gate.sh test/features/live/strum_direction_abstention_test.dart \
  test/features/live/dsp/live_pipeline_test.dart \
  test/features/live/live_frame_adapter_test.dart \
  test/features/live test/features/audio_analysis
```

```
format      zöld     analyze     zöld     architecture  zöld
test strum_direction_abstention_test.dart  zöld
test live_pipeline_test.dart               zöld
test live_frame_adapter_test.dart          zöld
test test/features/live                    zöld
test test/features/audio_analysis          zöld
secrets     zöld     l10n        zöld
MINDEN GATE ZÖLD
```

A `test/features/audio_analysis` sáv a D1 additivitást méri: a `StrumEvent`
TILOS zónában lévő hívói (`clip_analyzer.dart`, `strum_crnn.dart`,
`test/property/dsp_property_test.dart`,
`test/features/live/dsp/strum_analyzer_suppression_test.dart`) módosítás
nélkül fordulnak és zöldek.

## 6. Leletek

### MINOR-1 — a `docs/eval/…` egy provenienciát tévesen hivatkoz

`docs/eval/recognition-direction-abstention.md:31-36` azt írja: *„The only
direction-accuracy number in the repo — **80.7 %** — is a DIFFERENT
measurement … (`docs/rag/chunks/018-strum-ml-pipeline.md`, `noStrumThreshold`
doc comment in `live_crnn_classifier.dart`)"*. Mérve
(`grep -rn "80\.7" docs/ lib/`):

- a **80,7 %** literál `docs/eval/recognition-release-guard.md:15`-ben él, NEM
  a két hivatkozott helyen (a `noStrumThreshold` doc-commentben nem szerepel);
- „az egyetlen irány-pontossági szám a repóban" **nem igaz**: a
  `docs/rag/chunks/018-strum-ml-pipeline.md:232` `79.8 % / 79.9 %` eval-fold
  irány-pontosságot közöl, a `:177` pedig egy irány-pontossági táblázatot.

**Miért csak MINOR:** a szakasz **érdemi** következtetése helyes és általam
függetlenül igazolt — a `baseline_manifest.json` `direction.status` és
`calibration.status` egyaránt `not-measured`, per-margó-bin coverage-tábla a
fában sehol nincs, tehát a coverage/accuracy pár valóban nem vezethető le.
Kód-viselkedést nem érint. **Nem indítottam rá javító kört:** egy mondat
kedvéért egy teljes implementer-futás + CI-újradispatch aránytalan, a
merge-kapu pedig nem lazul tőle. **A javítás pontos szövege** a következő,
`docs/eval/**`-t érintő körnek: a forrás `docs/eval/recognition-release-guard.md:15`,
és az „only … number in the repo" állítást el kell hagyni.

> Megjegyzés: ez ugyanannak a hibaosztálynak az ismétlődése, amit a
> `docs/reviews/e14-r01-security.md:53-56` már megfogott (a 80,7 % ott a
> baseline-doknak volt tulajdonítva). A szám vándorol; a hivatkozása nem.

### MINOR-2 — `pNoStrum: event.pNoStrum ?? 0.0` kitalált érték, a kódban nincs kimondva

`live_pipeline.dart:293` egy 2-osztályos modellnél `0.0`-t ír a
`StrumPrediction.pNoStrum`-ba, holott ott „nincs harmadik osztály" ≠ „a
no-strum valószínűsége nulla". **Ma ártalmatlan:** a példány lokális, sosem
hagyja el a `_isDirectionConfirmed`-et, és a `decision`/`directionMargin`
getter kizárólag `pDown`/`pUp`-ot olvas — ezt ellenőriztem. A kockázat a
JÖVŐ: ha egy későbbi kör ezt a `StrumPrediction`-t a `RecognitionFrame`-be
emeli (az **szerializálódik**), a `0.0` publikált hamis állítássá válik, ami
pontosan az ADR 0505 D2 tiltása. Az indoklás ma csak a brief §10-ében él, a
kódban nem. **Ajánlás:** a `pNoStrum` sor mellé kódkomment a lokalitás
kikötésével.

### NOTE-1 — a `_placeInBar` kihagyása `uncertain` eseményre nincs dokumentálva

Az őr a `_placeInBar(event)` hívást is kizárja bizonytalan eseményre. Ez
**helyes** — a `_placeInBar` a `_bar[slot].strum`-ba az AKTUÁLIS
`_latestStrum`-ot írja, tehát meghívva egy korábbi, magabiztos nyilat
másolna egy új ütem-slotba egy bizonytalan pengetés hatására (csendes
`CONFIDENTLY WRONG`). Regressziót nem okoz: a döntésnek e kör előtt nulla
termelője volt, `uncertain` állapot a futásidőben nem létezett. Csak annyi a
lelet, hogy sem a §10, sem cella nem rögzíti ezt a szándékot.

## 7. Amit külön ellenőriztem és rendben találtam

- **ADR 0505 D2 (nyers valószínűség ≠ confidence):** a `confidence` mező
  sehol nem kap valószínűséget, és a `pDown`/`pUp` sehol nem kerül
  confidence-alakú mezőbe. A `StrumClassification.pDown` doc-commentje ezt ki
  is mondja.
- **AGENTS.md §9 (DSP-tilalom):** egyetlen DSP/ML konstans sem változott —
  `noStrumThreshold`, a `calibrate()` knot-lista, a heurisztikus létra és az
  `uncertainMarginThreshold` mind érintetlen (`git diff` mérve).
- **A 3-osztályos suppressed ág:** `probs[2] > noStrumThreshold` továbbra is
  valószínűség NÉLKÜLI, `suppressed: true` klasszifikációt ad — az analyzer
  nem is bocsát ki eseményt, tehát a döntési réteg helyesen nem fut rá.
- **A `sum == 0` degenerált eset:** `pDown = pUp = 0.5` → margó `0` →
  `uncertain`. Őszinte viselkedés, nem néma `confirmed`.
- **A `debugWithClassifier` teszt-varrat:** `@visibleForTesting`, a meglévő
  `debugStrumClassifier`/`debugTonalness` mintát követi, production hívója
  nincs (`grep` mérve).
- **A `docs/eval/…` (b)/(d) mért állításai:** a manifest két `not-measured`
  státusza és a `ConfidenceThresholdNotifier.defaultValue = 0.45` mind
  igazolva; a `calibrate()` legalsó knotja valóban `(0.50, 0.55)`.

## 8. CI és merge-kapu

A Full Gate (`full-gate.yml`) és a Router CI a merge SHA-n zölden kell
lezáruljon — a CI-tervező (`tools/round-ci-plan.py`) `full-gate.yml`-t írt elő
(`apk_required: false`, `router_ci_expected: true`). A run `headSha`-ja
`f39f4bd1`, egyezik a lokális HEAD-del. A merge csak mindkettő
`conclusion=success` esetén történhet meg.
