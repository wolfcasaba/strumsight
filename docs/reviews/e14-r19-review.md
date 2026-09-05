# E14-R19 — Független kör-review (ADR 0055)

- **Kör:** `E14-R19` — Adataugmentáció és kiegyensúlyozott training recept
- **Branch:** `sonnet-impl/e14-r19-augmentation-and-balanced-recipe`
- **Review-elt HEAD:** `ff3ae59c538df80be073ea1dcfb36d781487b003`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), orchesztrátor · read-only, izolált klónban
- **Dátum:** 2026-09-05
- **ADR:** [`0525`](../adr/0525-seeded-manifested-augmentation-and-honest-ablation.md)

## VÉGSŐ DÖNTÉS: **CHANGES REQUESTED** — 2 MAJOR, 2 MINOR, 1 NOTE

A kör minősége magas: az additív bővítés fegyelmezett, a validátor fail-closed,
az ablation-riport becsületes, és a `docs/eval/augmentation-ablation.md` a kör
kellemetlen mért tényét (a szállított recept ROMLIK) nem szépíti. **A két
MAJOR mégis a kör saját célját üti ki:** a szállított manifestet a CI-ban
semmi nem védi, és a manifest tartalma nem egy ténylegesen futott halmazt ír
le. Mindkettő az `allowed_paths`-on belül javítható → **javító kör, nem halt.**

---

## 1. Jelzés és handoff

`.codex-round-status`: `status=done`, `gate_shape=ok`, **`scope_audit=ok`**,
`scope_audit_base=aeebf6076…`, `scope_audit_changed=7`. A munkafa a jelzés
után tiszta (`git status --short` üres).

## 2. Scope-audit

A burkoló gépi auditja (ADR 0138) `ok`-ot adott 7 változott fájlra. Saját
kereszt-ellenőrzés a review-klónban:

```
$ git diff --name-only aeebf60760603a0227bd527ad9ae26d8b4d6342c..HEAD
docs/eval/augmentation-ablation.md
docs/rounds/e14-r19-augmentation-and-balanced-recipe.md
evaluation/recognition/fixtures/augmentation_manifest_sample.json
ml/augment.py
ml/augmentation_manifest.json
ml/test_augmentation_labels.py
test/tooling/augmentation_manifest_test.dart
```

Pontosan a brief `allowed_paths` hét eleme. Az `ml/chords/**` **egyetlen
fájlja sem** változott, tehát az R11 read-only-függőség szerződése tartja
magát. Listán kívüli fájl: nincs.

## 3. Kapuk — saját kézzel, izolált klónban újrafuttatva

Izolált klón: `/tmp/review-e14-r19` (`git clone --branch … `, HEAD `ff3ae59c`).

```
$ tools/round-gate.sh test/tooling/augmentation_manifest_test.dart
  [1] format: ZÖLD
  [2] analyze: ZÖLD
  [3] test test/tooling/augmentation_manifest_test.dart: ZÖLD   (27/27)
  [4] architecture: ZÖLD   (Architecture dependencies OK, 12 allowlisted deviation)
  [5] secrets: ZÖLD
  [6] l10n: ZÖLD
  MINDEN GATE ZÖLD   (exit 0)
```

```
$ python3 -m pytest ml -q
157 passed in 21.25s
```

Mindkettő külön processzben, csővezeték nélkül. A 157 = 115 meglévő + 42 új;
egyetlen meglévő `ml/test_pipeline.py` cella sem módosult és egyik sem bukott
(8. acceptance-pont, regresszió) — ezt a `git diff --name-only` is igazolja
(`ml/test_pipeline.py` nincs a listán).

## 4. Acceptance criteria tételesen

| # | Állítás | Verdikt | Bizonyíték |
|---|---|---|---|
| 1 | egész-félhangos címke-transzponálás ±1/±3/±6, N.C. invariáns, törtérték típusos hiba | ✅ | `_validate_whole_semitone` + `transpose_pcm_and_chord_labels`; a merge-elt `chords.labels.transpose_class` importálva (`ml/augment.py:176`), NEM újraírva |
| 2 | ±6 **inkluzív**, ±7 hiba | ✅ | `abs(value) > max_range → ValueError` (`ml/augment.py:236`) — a határ ide tartozik |
| 3 | seed-determinizmus a SZÁLLÍTOTT belépési ponton (L631) | ✅ | a cellák `augment_pcm_configurable` / `augment_pcm_with_chord_labels` / `random_label_transposing_shift`-et hívják, nem kézzel épített dictet |
| 4 | minden kapcsoló hamis → bitazonos | ✅ | `_apply_secondary_transforms` KÖZÖS mindkét komponáló útra, így a garancia nem tud szétcsúszni |
| 5 | manifest kötelező mezők, típusos hiba mindkét oldalon | ⚠️ **részben** | a szabályrendszer megvan és erős; a **tartalom** nem felel meg a D5-nek → MAJOR-2 |
| 6 | „nem mért" ≠ 0, „nem mért" soha `accepted` | ⚠️ **részben** | a szabály Python+Dart oldalon is kódolva; **de CI-ban a szállított manifestre nem érvényesül** → MAJOR-1 |
| 7 | a szállított recept `rejected`, idézett LOGO-delták | ✅ | `composite_recipe_r173.status = "rejected"`, split-delták `-0.0081` / `-0.0772` bitre egyeznek az `ml/honest_results.json` mért értékeivel; a konfund kimondva |
| 8 | `augment_pcm` bitre változatlan | ✅ | `test_existing_augment_pcm_is_byte_identical_for_a_pinned_seed`; `git diff` szerint a fájl első 151 sora érintetlen |

---

## 5. Leletek

### MAJOR-1 — A szállított manifestet a CI-ban SEMMI nem védi (mérve)

**Fájl:** `test/tooling/augmentation_manifest_test.dart`,
`evaluation/recognition/fixtures/augmentation_manifest_sample.json:1`,
`ml/augmentation_manifest.json:1`

A fixture a szállított manifest **bájtazonos másolata**
(`sha256 = ae3300ed…` mindkettőre), de **semmi nem pinneli őket egymáshoz**.
A brief **R7** kimondja: a Python-cellát egyetlen CI-workflow sem futtatja, a
**CI-oldali mérce a Dart-őr** — az viszont a MÁSOLATOT olvassa.

**Mért próba** (`/tmp/probe-e14-r19`, csak `ml/augmentation_manifest.json`
mutálva, a fixture érintetlen — a `composite_recipe_r173` mért, ROMLÓ sora
`accepted` státuszra állítva, azaz pontosan az a jogsértés, amiért az
ADR 0525 D6 létezik):

```
$ python3 -m pytest ml/test_augmentation_labels.py -k shipped_ml_augmentation_manifest
FAILED …::test_the_shipped_ml_augmentation_manifest_json_validates_cleanly
  ml/augment.py:643: ValueError                      # a Python-cella FOGJA — de CI-ban nem fut

$ flutter test test/tooling/augmentation_manifest_test.dart
00:00 +27: All tests passed!                          # a CI-oldali EGYETLEN mérce ZÖLD marad
```

Kontroll-próba (a fixture mutálva, a manifest érintetlen) → a Dart-őr
**PIROS** (3 cella bukik), tehát az őr él és erős; a rés kizárólag a két fájl
összekötésének hiánya.

**Miért MAJOR:** a kör célja az anti-reward-hacking szerződés. Ma egy jövőbeli
kör (pl. az E14-R20, amelyik épp `candidate` → `accepted` átírásokat fog
végezni) a szállított manifestet a szerződés ellenében módosíthatja, és a
teljes CI zöld marad. A kör legfontosabb őre a rossz fájlon áll.

**Javasolt irány (a listán belül):** egy cella a Dart-őrben, ami a valós
fából mindkét fájlt beolvassa és a normalizált JSON-jaikat egyenlőnek
követeli meg (a `_findProjectRoot()` mindkettőt eléri; a fixture-olvasás már
most is így működik). A Python oldalon a `test_the_shipped_…` cella mellé
ugyanez a párosítás.

---

### MAJOR-2 — A szállított manifest nem egy TÉNYLEGESEN futott halmazt ír le (ADR 0525 D5)

**Fájl:** `ml/augmentation_manifest.json` (és a bájtazonos fixture)

Az ADR 0525 D5 és a brief §5.2 szerint „a manifest a **ténylegesen futott**
halmazt írja le". A szállított tartalom három ponton mond ellent ennek:

1. **Nincs provenance.** A felső szint kulcsai: `schemaVersion`, `seed`,
   `transforms`, `classRatios`, `pitchShiftLimits`, `balancing`. Nincs mező,
   ami megmondaná, MELYIK futást / konfigurációt / adatkészletet írja le, és
   nincs `illustrative`/`example` jelölés sem. Sem a JSON, sem a
   `docs/eval/augmentation-ablation.md` nem mondja ki, hogy sablonról van szó.

2. **Az `enabled` mezők ellentmondanak a szállított alapkonfigurációnak.**
   Mind a 11 sor `enabled: true`, miközben a `DEFAULT_TRANSFORM_CONFIG`
   (`ml/augment.py:365`) négy transzformációt **kikapcsolva** szállít:
   `device_response`, `compression`, `traffic_noise`, `transient_burst`
   (`"enabled": False`). A manifest tehát olyan receptet állít, amit a
   szállított konfiguráció egyike sem állítana elő.

3. **A `composite_recipe_r173` egyszerre `enabled: true` és `status:
   "rejected"`.** A brief §5.3 és az ADR 0525 D6 szerint egy transzformáció
   csak MÉRT javulással marad a receptben; egy mérten romló sor „futott
   halmaz" tagjaként való feltüntetése önellentmondás, és a validátor ma ezt
   nem is tiltja.

4. **A `classRatios` kézzel választott kerek számok** (`down 0.42 / up 0.40 /
   noStrum 0.18`, `N.C. 0.35 / major 0.44 / minor 0.21`) forrás-megjelölés
   nélkül, miközben a kör szállít egy `class_ratios()` függvényt, ami valós
   arányt számol. A `docs/eval/augmentation-ablation.md` „Osztály-kiegyensúlyozás"
   szakasza úgy hivatkozik rájuk, mintha mértek volnának.

A handoff §10 azt állítja, a manifest „a `build_manifest`-tel **TÉNYLEGESEN
generált** (nem kézzel írt JSON-dict)". Generátor-script vagy regeneráló cella
nincs a diffben — az egyetlen cella **betölti és validálja** a fájlt. Az
állítás így nem ellenőrizhető, és a 4. pont fényében félrevezető. (Ez nem
gate-hiba: minden cella zöld — pontosan az a hibaosztály, amiért a review MÉR
és nem olvas.)

**Javasolt irány (a listán belül):**
- provenance-blokk a manifestben (pl. `generatedFrom`: a leíró konfiguráció
  neve, `datasetSource`, és ha a számok illusztratívak, egy **kimondott**
  `classRatiosSource: "illustrative — not measured"`), a validátorban
  kötelező mezőként;
- az `enabled` mezők igazítása ahhoz a konfigurációhoz, amit a manifest
  állítása szerint leír;
- új validátor- **és** Dart-guard-szabály: `status == "rejected"` mellett
  `enabled` nem lehet `true`;
- a `docs/eval/augmentation-ablation.md` mondja ki ugyanezt.

---

### MINOR-1 — A `measuredCostSeconds` minden „nem mért" soron ugyanaz a szám

**Fájl:** `ml/augmentation_manifest.json` (mind a 11 sor), `ml/augment.py:559`

Mind a 11 sor `measuredCostSeconds: 10769.7`. A prózában (ablation-riport)
korrektül szerepel, hogy ez **egyetlen** mért adatpont reprezentatív alapként
idézve — a JSON-ban viszont a mezőnév azt sugallja, hogy ez az adott
transzformáció saját mért költsége. Gépi olvasó számára ez ugyanaz a
„hiányzó mérés számnak látszik" hibaosztály, ami ellen a D6 született.
Javaslat: külön mezőnév (`costBasisSeconds` + `costBasisSource`), vagy a
`measuredCostSeconds` csak a ténylegesen mért soron.

### MINOR-2 — Csendes csonkítás a konfigurált félhang-TARTOMÁNYON

**Fájl:** `ml/augment.py:454` (`augment_pcm_with_chord_labels`)

```python
semitone_range = int(cfg["pitch_shift"]["semitone_range"])
```

Egy törtértékű konfigurált tartomány (pl. `6.5`) **csendben 6-ra csonkolódik**,
miközben a kör másutt kifejezetten tiltja a félhang-értékek néma kerekítését
(D2). Kicsi a hatás (az alapérték `6.0`), de a szerződés következetessége
kedvéért ugyanaz a fail-closed bánásmód járna neki.

### NOTE-1 — A `scope-audit.py` kézi újrafuttatását a factory-védő hook blokkolta

A review-protokoll (skill §3) saját kezű `tools/scope-audit.py` futtatást ír
elő. A `.claude/hooks/protect_factory_files.py` a parancssorban BÁRHOL
előforduló `tools/scope-audit.py` mintára tüzel, tehát egy **read-only**
futtatást is megtagad („a mércét nem javíthatja az, akit mér"). A jelen review
ezért a burkoló gépi auditját (`scope_audit=ok`, base + 7 fájl) és egy
független `git diff --name-only` kereszt-ellenőrzést használt — a következtetés
nem gyengült. A hook szűkítése (olvasó invokáció engedése) egy jövőbeli ADR
0112 önjavító kör tárgya; a kör-diffhez nincs köze.

---

## 6. Amit külön ellenőriztem, és RENDBEN van

- **R11 (a merge-elt osztály-matematika újrahasználása):** `ml/augment.py:176`
  `from chords.labels import NO_CHORD, transpose_class`; nincs második
  `transpose_class`-implementáció a fában, és `ml/chords/**` nem változott.
  A `test_label_transpose_uses_the_merged_transpose_class_not_a_reimplementation`
  cella a merge-elt függvénnyel SZEMBE mér (A-moll −1 → G#-moll).
- **A két félhang-korlát nem mosódik össze:** `PITCH_SHIFT_LIMITS` mindkettőt
  domén-címkével rögzíti, és mindkét oldali validátor LITERÁLISAN követeli a
  `6` / `5` értéket, illetve elutasítja az összemosást (Dart A7 csoport).
- **A Dart-őr valóban független szabálykészlet**, nem a Python-validátor
  hívása (R8/ADR 0517 D8 mintája) — és él: a fixture mutációjára 3 cella
  PIROSRA vált (saját próba).
- **`balance_indices` nem dob el valós sort:** minden osztály teljes
  index-tömbje bekerül, a hiányt ismétléses húzás pótolja (D8).
- **Az ablation-riport becsületes:** kimondja, hogy nem teljes ablation, hogy
  az `ml/honest_results.json` gitignore-olt és doboz-lokális (D11), és hogy a
  `logo_aug` szám regularizációval konfundált (D7). A mért delták bitre
  egyeznek az általam a pre-flightban mért értékekkel.
- **A §7.1 falszifikációs cellák:** a handoff mind a négyet dokumentálja
  PIROS → ZÖLD átmenettel; a 4b (Dart) állítást a saját fixture-mutációs
  próbám függetlenül megerősítette.

## 7. Eldobható próbatesztek

Minden próba a `/tmp/probe-e14-r19` eldobható másolatban futott, a kör-ág
munkafáját nem érintette; a másolat a review után törölve. Production kódot a
review nem módosított.

| # | Próba | Eredmény |
|---|---|---|
| P1a | csak `ml/augmentation_manifest.json` mutálva (`composite_recipe_r173` → `accepted`) | Python-cella PIROS (`ValueError`, `ml/augment.py:643`) |
| P1b | ugyanaz a mutáció, Dart-őr | **ZÖLD 27/27** → MAJOR-1 |
| P2 | csak a fixture mutálva | Dart-őr PIROS (3 cella) → az őr él |

## 8. Merge-feltételek

1. MAJOR-1 és MAJOR-2 zárva, mindkettőhöz olyan cellával, ami a hibát
   PIROSRA fogta volna (L563).
2. MINOR-1 és MINOR-2 javítva vagy kimondottan follow-upra utalva.
3. `tools/round-gate.sh test/tooling/augmentation_manifest_test.dart` és
   `python3 -m pytest ml -q` újra zöld (reviewer-oldalon is).
4. Full Gate **és** Router CI `success` a merge SHA-n (exact-SHA, ADR 0086 §2).
