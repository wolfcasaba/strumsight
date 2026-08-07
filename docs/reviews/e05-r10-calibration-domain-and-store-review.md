# E05-R10 — Review

Brief: docs/rounds/e05-r10-calibration-domain-and-store.md
Diff: `git diff 539d346...codex/e05-r10-calibration-domain-and-store` (post-rebase tip `c0701db`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-07
Verdikt: **CHANGES REQUESTED** (F1 nyitva — javító kör szükséges)

## Összegzés

BLOCKER: 0 · MAJOR: 1 (F1, OPEN) · MINOR: 1 (F2, OPEN) · NOTE: 1

Örökség-eset (ADR 0087 §0.2): a pre-flight és a MiniMax M3 implementer-futás
egy korábbi, jelzés nélkül megszakadt session alatt már lezajlott (`done`
jelzés, `9449733`, 2026-08-07T04:10 UTC). Ez a session a review-t végezte —
a pre-flight/implementáció nem ismételve, csak a branch `origin/main`-re
rebase-elve (`main` időközben 8, a diffhez nem kapcsolódó pipeline-infra
commit-tal mozdult; dry-run `git merge-tree` konfliktusmentes volt, a valódi
rebase is az; új tip `c0701db`).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Round-trip: modell → JSON → modell bit-stabil, determinisztikus kulcssorrend | ✅ | `vision_calibration_repository_test.dart` `round-trip` csoport, 3 teszt (109–156. sor): érték-egyenlőség + kétszeri encode bájt-azonosság + kézzel rögzített kulcssorrend mindhárom szinten |
| 2 | Migrációs mátrix: v0/vN-1/vN/vN+1, mind a négy cella külön teszt, a jövőbeli verzió kontrollált setup-kérés | ⚠️ | 4 teszt jelen (159–252. sor), DE a vN+1 cella csak a **meglévő** `JsonDocumentStore` envelope-őrt méri, a kör saját, új codec-szintű őrét nem — lásd **F1**, javítva |
| 3 | Idempotencia: kétszeri migráció azonos eredmény | ✅ | `idempotence` csoport, 2 teszt (254–295. sor): friss write kétszer azonos bájt; migrált legacy dokumentum két olvasása azonos érték |
| 4 | Korrupció-teszt: csonka JSON / hibás típus / degenerált polygon → érintett rekord karanténba, a többi olvasható marad | ✅ | `corruption tolerance` csoport, 3 teszt (297–371. sor). A „többi rekord" ez esetben vacuously igaz: a bundle **egy** `JsonObjectStore`-mintájú rekord (nem lista, mint a songs/practice-log) — dokumentálva a repository doc-commentjében (10–13. sor) és a §10 handoffban; a kar­antén a **teljes app egyéb dokumentumait** (songs, streak, …) nem érinti, ezt a meglévő `user_content_documents_test.dart` kereszt-ellenőrzi (a gate ugyanabban a futásban zöld) |
| 5 | Validity-mátrix: kamera/orientation/zoom/timestamp/geometria → öt önálló invalidation reason, priority-sorrend | ✅ | `calibration_validity_test.dart`, 5 cella (68–142. sor) + happy-path + tolerancia-határ cella + priority-teszt (158–171.) + enum-pin teszt (175–190.) a hatodik érték ellen |
| 6 | Privacy-snapshot: rögzített kulcskészlet minden szinten, raw-kép mező nem csúszhat be észrevétlenül | ✅ | `privacy snapshot` csoport (374–453. sor): 3 szintű hand-pinned kulcshalmaz + substring-scan (`image`/`jpeg`/`png`/`base64`/`thumbnail`) a teljes szerializált bájtfolyamon |
| 7 | Valódi-sértés próba (§10): pixelkoordináta → normalizált-tér teszt PIROS → visszaállítás | ✅ | `real-violation probe` csoport (455–536. sor): pixelkoordináta (x=1920) és string-a-numerikus-mezőben mindkettő elutasítva a codec `requireDouble`-jén keresztül, release-módban is (nem csak a constructor assert-jén, ami debug-only) |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff 539d346...HEAD --name-only`
pontosan a brief 10 `allowed_paths` bejegyzését adja vissza, 1:1 megfeleltetve
(kézzel ellenőrizve — a wrapper `scope_audit=skipped`-et jelzett, mert a
korábbi session nem adta át `ROUND_BRIEF`-et, így ez a session pótolta az
ellenőrzést a brief szerinti diff-listával).

## Megállapítások

### F1 — MAJOR — a migrációs mátrix „vN+1" cellája nem a kör saját új kódját méri

- **Fájl:** `test/features/vision/data/vision_calibration_repository_test.dart:219-251`
  (a mért kódág: `lib/features/vision/data/persistence/vision_calibration_codec.dart:121-131`)
- **Probléma:** a `VisionCalibrationCodec` **két, egymástól független**
  verziószámot kezel: a `JsonDocumentStore` megosztott, minden dokumentumra
  érvényes **envelope** `schemaVersion`-jét (pre-existing infra, `documentSchemaVersion`,
  `json_document_store.dart:19`), és a kalibráció **saját, e körben új**
  belső alak-verzióját (`calibrationShapeSchemaVersion`,
  `vision_calibration_codec.dart:48`, `_migrateToCurrent` 121–131. sor). A
  shippelt „cell vN+1" teszt az envelope-verziót állítja 99-re — ez a
  `JsonDocumentStore._decodeEnvelope` MEGLÉVŐ (nem e körben írt) őrén akad el,
  a kódot a codec-ig **el sem éri**. A codec saját `_migrateToCurrent`
  `throw JsonRecordException(unknownEnum, …)` ága — a kör tényleges, új
  védelme a „jövőbeli belső alak-verzió" ellen — **egyetlen tesztben sincs
  lefedve**.
- **Hatás:** ha ezt az ágat egy jövőbeli refaktor véletlenül elrontja (pl.
  fallback-ol „legyen current" helyett elutasítás helyett), a shippelt 17
  teszt közül **egy sem** venné észre — pontosan az az eset, amit az
  acceptance criteria #2 kifejezetten tilt („a jövőbeli verzió nem olvasódik
  félre").
- **Mérve (mutáció-kill próba, `/tmp/review-e05-r10` izolált klónban):**
  eldobható teszt (`_review_probe_shape_version_test.dart`) egy body-t ír,
  ahol az envelope `schemaVersion=1` (érvényes) DE a `data.schemaVersion=2`
  (a codec `currentSchemaVersion=1` fölött) → a MEGLÉVŐ kódon a próba ZÖLD
  (`read()` → `null`, `storage.document.record_skipped` logolva — a kód
  helyesen viselkedik). Ezután a `_migrateToCurrent` throw-ágát ideiglenesen
  egy `return json;` fallback-ra cserélve: a próba PIROSRA vált (a bundle
  hibásan dekódolódik current-ként), DE a teljes shippelt
  `vision_calibration_repository_test.dart` mind a 17 tesztje **változatlanul
  zöld marad** — bizonyítva, hogy a jelenlegi teszt-készlet nem védi ezt az
  ágat. A mutáció visszaállítva (`git diff` üres a codec fájlon).
- **Kötelező javítás:** a próba-teszt (a jelentéssel együtt mellékelve, lásd
  lent) beemelése a permanens suite-ba — a body legyen: envelope
  `schemaVersion == documentSchemaVersion`, de a `data.schemaVersion` a
  codec `currentSchemaVersion`-nél eggyel nagyobb; elvárás: `read() == null`
  és `storage.document.record_skipped` a loggon.
- **Ellenőrzés:** az új teszt PIROS a fent leírt fallback-mutáción, ZÖLD a
  jelenlegi kódon.
- **Státusz:** **OPEN** — javító kör szükséges (a próba-teszt e jelentéssel
  együtt átadva az implementernek, beemelendő a permanens suite-ba).

### F2 — MINOR — `GuitarCalibration.neckPolygon` doc-comment „Immutable"-t
  állít, de a lista nincs védve külső mutációtól

- **Fájl:** `lib/features/vision/domain/calibration/guitar_calibration.dart:28-45`
- **Probléma:** a konstruktor a kapott `neckPolygon` listát közvetlenül
  tárolja (`required this.neckPolygon`), `List.unmodifiable`/`UnmodifiableListView`
  nélkül — a `final` csak a mezőre mutató referenciát rögzíti, a mögötte álló
  listát a hívó a konstrukció UTÁN is mutálhatja, ha a saját (nem const)
  listájára tartott referenciát megtartja. A repó-ban van pontosan erre a
  mintára precedens: `lib/features/practice/domain/model/speed_builder_state.dart:68`
  (`attempts = List.unmodifiable(attempts)` az initializer-listában), és
  `practice_attempt_result.dart:32` doc-commentje explicit figyelmezteti a
  hívót, ha a védelem hiányzik.
- **Hatás:** ma minden hívó `const` listával konstruál (a tesztek és a
  §10 handoff is), tehát élesben nem exploitable — de a domain-osztály saját
  „Immutable" ígérete (2. sor doc-comment) csak konvenció, nem kikényszerített
  invariáns, ha egy jövőbeli hívó (pl. az R11 kalibrációs UI) egy mutálható
  listát ad át.
- **Kötelező javítás:** `neckPolygon: List<NormalizedPoint>.unmodifiable(neckPolygon)`
  az initializer-listában, a `speed_builder_state.dart` mintáját követve.
- **Ellenőrzés:** meglévő equality-tesztek változatlanul zöldek maradnak
  (az `UnmodifiableListView`/`List.unmodifiable` elem-egyenlőségre transzparens).
- **Státusz:** **OPEN** — javító kör szükséges (ugyanabban a javító körben,
  mint F1, egysoros változás).

### N1 — NOTE — a „hiányzó schemaVersion mező" ág (nem „hiányzó dokumentum") szintén tesztelt-len

- **Fájl:** `lib/features/vision/data/persistence/vision_calibration_codec.dart:109-119`
  (`_readShapeVersion`, `raw == null → legacySchemaVersion`)
- **Megfigyelés:** a shippelt „cell v0" teszt egy **teljesen üres tárat**
  mér (`document.readBody() == null`), ami korábban tér vissza, mint hogy a
  codec `_readShapeVersion`-je lefutna. Az az ág, ahol a body LÉTEZIK, de a
  `schemaVersion` kulcs hiányzik belőle (nem `0`, hanem nincs jelen),
  szintén nincs közvetlenül lefedve — bár ugyanazt az útvonalat futtatja,
  mint a vN-1 cella (mindkettő `legacySchemaVersion`-re fut), így a
  kockázat lényegesen kisebb, mint F1-nél (nincs KÜLÖN ág, csak egy
  be nem járt feltétel-ág ugyanahhoz a már tesztelt eredményhez). Nem
  blokkoló — follow-up, ha egy jövőbeli kör a legacy-migrációt bővíti.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (izolált `/tmp/review-e05-r10` klón, saját futás) |
| analyze | zöld | ✅ (ua., a klón-csapda — hiányzó `flutter pub get`/`gen-l10n` — először PIROS-t adott; `tools/prepare-flutter-generated.sh` után zöld, dokumentált klón-artefaktum, nem kód-hiba) |
| test test/features/vision | zöld | ✅ (ua., saját futás, 2× — pre- és post-rebase is) |
| test test/core/storage | zöld | ✅ (ua.) |
| architecture | zöld (12 allowlisted deviation — változatlan, a kör egyik allowed_path-ja sem architektúra-konfig) | ✅ |
| secrets / l10n | zöld | ✅ |
| CI — Full Gate (no APK), pre-rebase tip `9449733` | success | ✅ [31149519825](https://github.com/wolfcasaba/strumsight/actions/runs/31149519825) — **a rebase után újra-dispatch szükséges** az új `c0701db` (majd a javító kör utáni) tipre, ADR 0086 §2 szerint; ezt az orchestrátor a review lezárása után indítja |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
F1 nyitva → **merge tilos**, amíg zárva nincs. Javító kör indul (ugyanaz a
motor — MiniMax M3 — az első javító kör, a motor-eszkaláció táblája szerint),
a findings-lista (F1 + F2) a promptban. Javítás után: gate-ek újrafuttatása
izolált klónban, a review frissítése APPROVED-ra a javító commit SHA-jával,
friss CI-dispatch az új tipre, majd squash-merge.
