# ADR 0192 — Practice Engine vision integration contract

- **Státusz:** Elfogadva (E05-R25 pre-flight, 2026-08-08)
- **Kör:** E05-R25 — Practice Engine vision integráció
- **Implementer motor:** Terra (Codex CLI, `~/.codex-terra`, `gpt-5.6-terra`,
  `tools/codex-round.sh`) — az ADR-t az orchesztrátor (Claude Sonnet 5) írta a
  pre-flightban (ADR 0055, pipeline-prompt §0 — nincs előre kiosztott ADR).
- **Epic:** [Chapter 6 — Epic 5: Computer Vision](../sdd/06-epic-05-computer-vision.md) Kör 25; §25
- **Kontext-ADR-ek:** [0176](0176-cross-feature-public-barrel-recognition.md)
  (nested/feature `public.dart` barrel a cross-feature belépési pont — ez a
  kör az ELSŐ `practice → vision` élt nyitja meg ugyanezen a mintán),
  [0178](0178-vision-privacy-by-default.md) (raw-media-mentes vision
  eredmény — ezt örökli a `VisionSessionResult` referencia),
  [0179](0179-vision-capability-aware-feedback.md) (capability-alapú
  feedback gyökérelve — ennek Practice-oldali tükre a pilot-gyakorlat
  capability-gate), [0070](0070-builtin-practice-catalog-contract.md)
  (a builtin katalógus szerződése — ez a kör NEM bővíti).

## Kontextus

Az SDD Ch6 §25 opcionális vision-bizonyítékot ír elő kiválasztott Practice
gyakorlatokhoz, az audio-pontozás bitre-változatlanságával. A kör-brief
2026-08-05-i batch-írásakor nem kapott ADR-számot (`nincs`); a pipeline-prompt
§0 táblája explicit „te írod meg a pre-flightban" — `tools/round-slots.py
reserve-adr --round E05-R25` → **0192**.

**Mért rések a pre-flightban** (pipeline-prompt §1 mérési szabályai — minden
brief-hivatkozott típust/útvonalat/enumot ki kell grep-elni, nem a
rétegdiagramból feltételezni):

1. **`PracticeSessionResult`-nak nincs saját JSON-kódja.**
   `grep -n "toJson\|fromJson\|Json" lib/features/practice/domain/model/practice_session_result.dart`
   nulla találat. A ténylegesen perzisztált wire-alak
   `PracticeHistoryEntry` (`data/practice_session_result_history_mapper.dart`
   `toHistoryEntry()` projekció), amely a kör `allowed_paths`-án **kívül**
   esik és a brief §3 explicit „persistence (R28)" kizárásának tárgya. A
   brief §6 negyedik acceptance-cellája („korábban mentett result olvasható
   — deszerializációs teszt") ezért nem fordítható le tényleges kódra ebben
   a körben — nincs mit deszerializálni, mert e kör nem hoz létre új
   szerializációt. Lásd Döntés 2.
2. **A cross-feature import mechanikusan legális.** `tool/check_architecture.dart`
   `_isFeaturePublicBarrel` bármely `lib/features/<f>/.../public.dart`
   célt elfogad (ADR 0176 mintája), és `test/features/practice/domain/domain_purity_test.dart`
   kizárólag az adott fájl SAJÁT, közvetlen `import`-sorát reguláris
   kifejezéssel vizsgálja (nem oldja fel tranzitívan a célfájl exportjait).
   Mindkettőt lefuttatva/elolvasva mérve: a `practice_session_result.dart`
   → `vision/public.dart` import egyik gépi őrt sem sérti. Lásd Döntés 3.
3. **A három pilot gyakorlat NEM létező katalógus-bejegyzés.**
   `grep -rln BuiltinPracticeCatalog lib/features/practice/` →
   `data/builtin_practice_catalog.dart`, amely NINCS az `allowed_paths`-on.
   Az E02-R04-ben (ADR 0070) szállított tíz beépített gyakorlat egyike sem
   „Small Strum Motion" / „Down/Up Symmetry" / „Chord Change Economy" nevű
   vagy tartalmú. Lásd Döntés 4.
4. **A `requiredCapabilities` mezőnek van élő precedense.** A vision
   metrika-domain már három, egymástól független, feature-lokális capability
   enumot szállított: `FrettingCapability{handTracking,guitarRelativeTracking}`
   (`domain/metrics/metric_definition.dart`), `PickingCapability{guitarRelativeTracking}`
   (`domain/metrics/picking_metrics.dart`), `PostureCapability{poseTracking}`
   (`domain/metrics/posture_metrics.dart`) — mindhárom ADR 0179 elvét követi.
   Lásd Döntés 4.
5. **A vision-állapot hármas (`unavailable`/`degraded`/`good`, brief §6 2.
   cella) szó szerint nem létező enum**, de a legközelebbi élő jel
   (`VisionQualitySummary.overall: VisionMetricState{good,needsImprovement,notObservable}`,
   `domain/quality/vision_quality_summary.dart`) szerkezetileg 1:1
   megfeleltethető. Lásd Döntés 5.
6. **`VisionSessionResult`-nak nincs érték-egyenlősége** (`lib/features/vision/domain/vision_session_result.dart`
   — nincs `operator==`/`hashCode` felülírás, tehát identitás-egyenlőség).
   Ez a kör nem adhat hozzá érték-egyenlőséget ehhez a típushoz (a fájl
   nincs az `allowed_paths`-on), és nem is szükséges — a típus szándéka
   szerint egy session végén PONTOSAN EGY aggregátum jön létre (HANDOFF
   E05-R24). Lásd Döntés 6.
7. **A session-summary képernyő nincs scope-ban.** `lib/features/practice/presentation/screens/practice_result_screen.dart`
   NINCS az `allowed_paths`-on — csak az önálló `practice_vision_dimension.dart`
   widget + saját widget-tesztje. Lásd Döntés 7.

## Döntés

1. **ADR-szám: 0192.** A brief minden `nincs`/pre-flight ADR-hivatkozása ide
   mutat.
2. **A §6 negyedik acceptance-cella (`Visszafelé kompatibilitás… deszerializációs
   teszt`) a mért valósághoz igazítva, brief-revízióval (§0.0):** mivel
   `PracticeSessionResult`-nak nincs kódolása, a cellát három, ténylegesen
   futtatható próba váltja:
   - **(a) konstrukciós kompatibilitás** — mind a 12 meglévő
     `PracticeSessionResult(…)` hívóhely (1 production —
     `application/practice_session_controller.dart:483` — + 11 teszt,
     grep-számolva) változatlanul fordul, mert `vision` **opcionális,
     implicit-null** paraméter;
   - **(b) egyenlőség-regresszió** — egy `vision: null`-lal épített
     pre-round-ekvivalens és egy explicit `vision: null` post-round példány
     `==` és azonos `hashCode`, tehát a kibővített `operator==` nem tér el a
     mai szemantikától null vision mellett;
   - **(c) mapper-érintetlenség** — a §6 első cellájának (audio-parity
     fixture) RÉSZE: `PracticeSessionResultHistoryMapper.toHistoryEntry()`
     kimenete bitre azonos `vision: null` és `vision: <kitöltött>` mellett,
     ami bizonyítja, hogy a jövőbeli (R28) perzisztencia-út ma semmit nem
     lát a vision mezőből. Ez erősebb bizonyíték, mint egy önmagában álló
     deszerializációs teszt lenne, és nem igényel új kódolást.
3. **A `practice_session_result.dart → vision/public.dart` import
   szándékos és a mai két gépi őrrel (architektúra + domain-purity)
   összhangban áll — nincs allowlist-bővítés.** Mindkét őr kizárólag az
   adott fájl saját, közvetlen import-sorát nézi (nem tranzitív); a
   `vision/public.dart` maga UI-képernyőket is exportál (pl.
   `vision_setup_screen.dart`), ami azt jelenti, hogy a practice domain
   fordítási gráfja tranzitívan függővé válik a Flutter-től. Ez a mai
   scanner-kontraktus ismert határa (nem ezen kör vezeti be, és nem
   szűkíthető e kör keretein belül — a scannerek módosítása a
   `tools/`/`test/core/` felett kívül esik az `allowed_paths`-on), ezért
   **tudatosan elfogadott, dokumentált korlát**, nem hiba. A gyakorlatban a
   `PracticeSessionResult` egyetlen új mezőt kap (`VisionSessionResult?`),
   a `vision/public.dart`-ból importált konkrét screen-osztályokat sosem
   használja.
4. **A három pilot gyakorlat (Small Strum Motion, Down/Up Symmetry, Chord
   Change Economy) a kör SAJÁT, új fájljain belüli adat, nem
   `BuiltinPracticeCatalog`-bejegyzés.** Stabil, a meglévő
   `builtin.<slug>.v1` mintától megkülönböztethető azonosító-névtér alatt
   (pl. `vision.pilot.<slug>`) él a `vision_practice_contract.dart` /
   `practice_vision_adapter.dart` párban. A `VisionPracticeContract.requiredCapabilities`
   a három meglévő, feature-lokális capability-enum (`FrettingCapability`,
   `PickingCapability`, `PostureCapability`) uniójára épül — vagy ezek
   közvetlen újrafelhasználásával, vagy egy azokra 1:1 leképezhető, a
   `vision/domain/integration/` alatt élő kontraktus-szintű enummal; a
   pontos forma implementer-döntés, amíg a leképezés a három meglévő
   enumra teljes és tesztelt.
5. **A kontraktus-szintű vision-állapot hármas (`unavailable`/`degraded`/`good`)
   determinisztikusan a `VisionQualitySummary.overall`-ból származik**
   (`good → good`, `needsImprovement → degraded`, `notObservable` vagy
   hiányzó session → `unavailable`), nem három, egymástól független,
   kézzel felvett teszt-fixture. Ez teszi a §6 vision-állapot mátrixot
   falszifikálhatóvá egy valós termelő jelen keresztül (pipeline-prompt §1
   1. mérési szabálya), nem csak a kontraktus saját, önreferens
   definícióján.
6. **`PracticeSessionResult` kibővített `operator==`/`hashCode`-ja a
   `vision` mezőn sima `==`/`hashCode` delegálást használ (identitás a
   `VisionSessionResult` szintjén), NEM kap egyedi érték-egyenlőséget.**
   Összhangban a típus egyetlen-aggregátum tervezési szándékával (E05-R24);
   a `vision_session_result.dart` fájl amúgy sincs az `allowed_paths`-on.
7. **A „session-summary vision-dimenzió UI" ebben a körben az izolált
   `practice_vision_dimension.dart` widget + saját widget-teszt — a
   `practice_result_screen.dart`-ba drótozás KÖVETKEZŐ kör dolga.** A minta
   megegyezik az Epic 3 Song Trainer sorozat minden eddigi round-jával
   („Hívó UI/repository még nincs — production viselkedés változatlan").
   Nulla regressziós kockázat, mert semmi nem hívja az új widgetet ebben a
   diffben.

**NEM elfogadható:** audio-score bármely számításának módosítása;
`lib/features/vision/` belső (nem-`public.dart`) fájl importja a
practice-ből; új `BuiltinPracticeCatalog`-bejegyzés vagy meglévő bejegyzés
módosítása; a `practice_result_screen.dart` szerkesztése; `VisionSessionResult`
saját érték-egyenlőségének utólagos hozzáadása; a `check_architecture.dart`
allowlistjének bővítése.

## Következmények

- `lib/features/vision/domain/integration/vision_practice_contract.dart` —
  új, a vision oldal szűk exportja Practice felé.
- `lib/features/practice/data/vision/practice_vision_adapter.dart` — új,
  fogyasztó-oldali adapter a három pilot gyakorlat capability-gate-jével.
- `lib/features/practice/domain/model/practice_session_result.dart` —
  additív `final VisionSessionResult? vision;` mező, bővített
  `operator==`/`hashCode` (Döntés 6).
- `lib/features/practice/public.dart` / `lib/features/vision/public.dart` —
  additív exportok.
- `lib/features/practice/presentation/widgets/practice_vision_dimension.dart` —
  új, önálló (nem bekötött) summary-widget.
- `lib/l10n/app_en.arb` / `app_hu.arb` — additív kulcsok a vision-dimenzióhoz.
- A `PracticeHistoryEntry`/`practice_session_result_history_mapper.dart`
  JSON-perzisztencia változatlan marad — a vision mező e körben sosem éri el
  a storage-t (R28 dolga).
- A `practice_result_screen.dart` élő drótozása, a Speed Builder
  vision-gate aktiválása és a Song Trainer/Tutor integráció (R26/R27) kívül
  esik ezen a körön és az `allowed_paths`-on.

## Elutasított alternatívák

- **`PracticeSessionResult`-nak saját `toJson`/`fromJson` hozzáadása, hogy a
  brief szó szerinti „deszerializációs teszt" cellája fordítható legyen.**
  Elvetve: ez a `data/`-réteg (perzisztencia) feladata lenne egy domain
  típuson, ellentmondana a §3 explicit „persistence (R28)" kizárásnak, és a
  fájl (`practice_history_serializer.dart`) nincs az `allowed_paths`-on — új
  kódolás bevezetése éppen azt a réteghatárt sértené, amit a brief védeni
  akar. A mapper-parity teszt (Döntés 2c) ugyanazt a garanciát adja kódolás
  nélkül.
- **A `vision/public.dart` UI-exportjainak eltávolítása vagy szűkítése,
  hogy a practice-domain tranzitív Flutter-függése megszűnjön.** Elvetve:
  a `vision/public.dart` szerkesztése additív-only e körben is megengedett,
  de a meglévő UI-exportok törlése más, éles hívók (a vision feature saját
  screenjei) számára regresszió lenne, és a két gépi őr (mérve) amúgy sem
  tranzitív — a „probléma" ma nem mérhető build- vagy teszt-hibaként, csak
  elvi rétegtisztaság kérdéseként, amit egy jövőbeli, önálló ADR dönthet el
  a teljes vision `public.dart` szétválasztásáról (domain-only vs. UI-barrel).
- **A három pilot gyakorlatot mégis a `BuiltinPracticeCatalog`-ba felvenni,
  az `allowed_paths` bővítésével.** Elvetve: a katalógus-fájl szerkesztése
  H3 (tilos zóna) kockázat; a brief §3 „Kívül — TILOS" listája nem
  tartalmazza a katalógust explicit módon, de az `allowed_paths` tételes
  felsorolása normatív, és a pilot-adat a kör saját új fájljain belül
  teljes egészében reprezentálható.
- **A vision-állapot hármast a kontraktus saját, a `VisionQualitySummary`-tól
  független definíciójaként hagyni (nincs előírt leképezés).** Elvetve: egy
  ilyen kontraktus tesztelhető lenne, de csak önmagával szemben — a
  pipeline-prompt §1 1. mérési szabálya pontosan az ilyen, „elérhetetlen
  vagy tetszőlegesen választott státusz" mintát célozza. A `VisionQualitySummary.overall`
  leképezés fixálja, hogy a mátrix egy MÉRT jelet falszifikál.
