# E05-R20 — Review

Brief: `docs/rounds/e05-r20-posture-metrics-and-safety-policy.md`
Diff: `git diff origin/main...minimax/e05-r20-posture-metrics-and-safety-policy`
(exact SHA reviewed: `4a53832`)
Reviewer: Claude Sonnet 5 (orchestrator) + dedicated `security-reviewer` agent
(brief §11 mandatory, `risk = "high"`) · Dátum: 2026-08-08
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 2 · NOTE: 2

Mindkét MAJOR **latens** — a mai szállított katalógus (10 kód) korrekt, nincs
élő fogyasztó (R23/R27 jövőbeli), és **nincs bizonyított egészségügyi
claim-szivárgás vagy hibás observable/notObservable besorolás a mai kódon**.
A gate genuinely zöld (saját, független futtatással megerősítve), a scope
tiszta. A két MAJOR oka: (1) a fő biztonsági mechanizmus gyengébb, mint amit a
brief állít — a guard az OSZTÁLYT ellenőrzi, nem a kód SZEMANTIKÁJÁT; (2) egy
explicit §6 acceptance-kritérium (visibility-mátrix) valójában nincs
implementálva/tesztelve, és ezt a handoff nem jelezte eltérésként.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Claim-guard teszt (mind a tiltott minta elutasítva + nem katalogizált kód elutasítva) | ✅ | `safety_claim_guard_test.dart` 17/17 (saját gate-futtatással megerősítve, 331/331 a teljes vision-fában) |
| 2 | Valódi-sértés próba (tiltott osztályba eső kód → PIROS → visszaáll) | ⚠️ Gyengébb, mint a brief állítja | Az implementer próbája (§10) valódi, de csak azt igazolja, hogy egy kód **saját, forbidden osztályba deklarálva** elutasításra kerül — ez a guard TERVEZETT viselkedése, nem egy meglepő rés lezárása. A security-reviewer **erősebb** próbája (kód **allowed** osztályba deklarálva, de orvosi tartalmú szöveg) **ÁTMENT** a guardon és a teljes 39-tesztes suite-on — ld. **F1**. |
| 3 | Baseline-mátrix (hiányzik/részleges/teljes) | ✅ | `posture_metric_engine_test.dart` „baseline matrix" group, 3 teszt; saját olvasással megerősítve |
| 4 | Metrikánkénti unit teszt (4×tipikus/határ/degenerált) | ✅ | 4 group, mind lefedve, R8-degenerate önálló teszt |
| 4b | **Visibility-mátrix (alatt/rajta/fölött)** | ❌ | **Nincs implementálva.** `grep -n visibility` a teszt fájlban **egyetlen** találat: a fejléc-komment SAJÁT állítása, hogy ez le van fedve. A fixture-ök (`posture_fixtures.dart`) kizárólag `0.9` (alapérték) vagy `0.0` (hiányzó) visibility-t használnak — nincs határérték (0.54/0.55/0.56) eset. Ld. **F2**. |
| 5 | Kameraperspektíva-fixture (≥3 nézőpont, előjel/nagyságrend konzisztens) | ✅ | `posture_metric_engine_test.dart` „perspective-fixture matrix" group, 3 szög, sign-agnostic magnitude-egyenlőség tesztelve |
| 6 | NaN/Infinity guard | ✅ | `posture_metric_engine.dart:79` (`!drift.isFinite` a required-landmark loopban); dedikált teszt |
| 7 | §5 pont 7 / §0.0 R8 — `observation.state` nem gate | ✅ | `posture_metric_engine.dart:71-80` — a state-check csak a `notObservable` esetet zárja ki explicit, a tényleges gate a per-metrika `requiredPoseLandmarkIds` + `driftFor(id) != null`. Saját, a fixture-től független `PostureBaselineCollector`-építéssel is megerősítve (ld. security-review §10 pont 10) |

## Scope-audit

`git diff --stat origin/main...HEAD` (saját futtatás, `/tmp/review-e05-r20`
friss klón): **10 fájl**, pontosan a brief `allowed_paths` 8 bejegyzése +
`docs/adr/0188-*.md` (orchestrátor pre-flight, nem implementer-scope) +
`docs/rounds/e05-r20-*.md` (brief maga, listán van). **Listán kívüli fájl:
nincs.** A wrapper saját `scope_audit=ok` jelzését (base `c7ae30a`, 9 changed)
függetlenül megerősítve.

## Megállapítások

### F1 — MAJOR — A safety guard a claim-kód DEKLARÁLT OSZTÁLYÁT ellenőrzi, nem a kód SZEMANTIKÁJÁT — egy rosszul osztályozott, orvosi tartalmú kód átjut

- **Fájl:** `lib/features/vision/domain/safety/safety_claim_guard.dart:59-80` (az `evaluate` tisztán map-lookup + forbidden-Set check, sosem vizsgálja a `code` string tartalmát); `vision_safety_policy.dart:78-83` (`isForbidden` egy denylist, nincs pozitív `allowed` halmaz).
- **Probléma:** a kör-brief §5 pont 1 szerint „a guard **kód-szinten** tiltja, nem prózában" és „NEM elfogadható ezek enyhébb megfogalmazása sem" — ez azt sugallja, hogy a guard a TARTALOM ellen véd. A ténylegesen szállított mechanizmus ezzel szemben **kizárólag azt ellenőrzi, hogy a katalógusban deklarált osztály nincs a tiltott halmazban** — ha egy jövőbeli katalógus-bővítés (R23/R27, a fájl saját kommentje szerint pontosan ezek a jövőbeli bővítők) egy orvosi tartalmú kódot **rosszul, egy engedélyezett osztályba** classify-el, a guard és a teljes acceptance-suite is zöld marad.
- **Hatás:** a kör kulcs-ígérete (§9: „a fail-closed allowlist az EGYETLEN gépi őr") gyengébb, mint amit a brief és az ADR 0188 sugall — a valódi védelem ma a HELYES OSZTÁLYOZÁS emberi/implementer fegyelmén múlik, nem egy gépi tartalmi ellenőrzésen.
- **Mérve (security-reviewer, független próba, `/tmp/security-review-e05-r20`):** a production katalógusba ideiglenesen felvéve
  ```dart
  'postureShoulderAsymmetryMayCauseLongTermPain': VisionSafetyClaimClass.baselineRelative,
  ```
  (allowed osztály, de a §5 pont 1 saját tiltott-példamondatával szemantikailag megegyező tartalom) → a teljes szállított suite (`safety_claim_guard_test.dart` + `posture_metric_engine_test.dart`, 39 teszt) **zöld maradt**. Visszaállítva, fa tiszta.
- **Miért MAJOR és nem BLOCKER:** a MA szállított 10 katalógus-kód mind helyesen, nem-orvosi osztályba tartozik (a security-reviewer ellenőrizte); nincs élő fogyasztó/sink (R23/R27 még nem épült) — orvosi tartalom MA nem hagyhatja el a rendszert. A kockázat egy jövőbeli, e körön kívüli hibára vonatkozik, nem egy jelenlegi határsértésre.
- **Javasolt irány (nem patch):** a kód STRINGJÉN is fusson egy lexikai/kulcsszó-alapú védelem (pain/injury/diagnos/harm/recovery-jellegű minták), FÜGGETLENÜL a deklarált osztálytól — plusz egy teszt, ami egy orvosi-jellegű kód-stringet `baselineRelative` osztályba deklarálva is elutasít. Másodlagosan érdemes az ADR 0188 / brief §5 pont 1 szövegét pontosítani, hogy a garancia ma „osztály-alapú", ne keltsen erősebb benyomást.
- **Státusz:** OPEN

### F2 — MAJOR — `confidenceFormula` dokumentált állítása ("mean landmark visibility") nem egyezik a tényleges számítással; a `minimumVisibility` mező sosem kerül kiértékelésre; a §6 "visibility-mátrix" acceptance-kritérium valójában nincs tesztelve

- **Fájl:** `lib/features/vision/domain/metrics/posture_metric_engine.dart:168-185` (`_confidence` ≡ `1 − min(1, |mean drift|)`, tehát a drift NAGYSÁGÁNAK inverze) vs. `posture_metrics.dart:154` (és a másik 3 definíció) `confidenceFormula: 'mean(minimum landmark visibility)'`. A `minimumVisibility: 0.55` mező egyetlen helyen sincs kiolvasva/összehasonlítva a `compute()`-ban.
- **Probléma:** a fretting/picking mintát ("kövesd a `picking_metrics.dart` MINTÁJA szerint") az implementer STRUKTURÁLISAN helyesen követte, de a mezők SZEMANTIKÁJÁT nem adaptálta ahhoz, hogy a `PostureObservation` (R14 kimenete) — a fretting/picking nyers per-frame landmark-modelljével ellentétben — **nem** exportál per-landmark visibility-t, csak már R14-ben egy fix 0,5-ös küszöbbel előszűrt drift-értékeket (`driftById`). Emiatt a `minimumVisibility`/`confidenceFormula` mezők a fretting/picking mintából szó szerint átmásolt, de ebben a rétegben **kiértékelhetetlen** metaadatok maradtak.
- **Mérve (saját, eldobható próba, azonos visibility mellett):** két megfigyelés, MINDKETTŐ 0,95 landmark-visibility (tehát egyformán megbízható mérés), csak a drift nagysága különbözik:
  ```
  PROBE A (visibility=0.95, nagy valódi drift):  value=0.25   confidence=0.75
  PROBE B (visibility=0.95, apró drift):          value=0.0035 confidence=0.9964
  ```
  A confidence tehát KIZÁRÓLAG a drift nagyságától függ, a visibility-től nem — pontosan az ellenkezője annak, amit a `confidenceFormula` mező állít, és annak, amit az ADR 0179 „confidence = a mérés megbízhatósága" elve előír. Ugyanezt függetlenül megerősítette a security-reviewer saját próbája (`confidence=0.80` vs `confidence=0.10` azonos visibility mellett, eltérő drifttel).
- **Kapcsolódó, ugyanabból a gyökérokból fakadó hézag:** a brief §6 „**visibility-mátrix (alatt / rajta / fölött)**" acceptance-kritériuma **nincs implementálva** — a teszt fájl fejléc-kommentje ÁLLÍTJA a lefedést, de a fájlban SEHOL nincs `visibility`/`minimumVisibility` teszt (`grep` nulla találat a fejléc-kommenten kívül), és a fixture-ök csak bináris (0.9 / 0.0) visibility-t generálnak, sosem határértéket. Ez a hézag a **§10 „Eltérések és okuk"** szakaszban NINCS jelezve — az implementer nem tudott róla, vagy nem jelezte, egyik esetben sem helyes.
- **Hatás:** ha egy jövőbeli kör (R23 feedback policy) a `confidence`-t priorizáláshoz/elnyomáshoz használná, ez PONT FORDÍTVA viselkedne: a legnagyobb, legmegbízhatóbban mért testtartás-eltéréseket „alacsony bizalmú"-ként, a jelentéktelen eltéréseket „magas bizalmú"-ként jelentené.
- **Miért MAJOR:** ellentétben egy tisztán biztonsági-kockázati besorolással (ahol a fogyasztó hiánya miatt ez latensnek/MINORnak számítana — ld. a security-review saját, szűkebb „m-2 MINOR" besorolását ugyanerre a jelenségre), ez a kör SAJÁT, explicit §6 checklist-pontjának **csendes, dokumentálatlan** elmulasztása — a `done` jelzés és a §10 handoff „minden acceptance-cella teljesült" narratívát állít, ami erre a pontra nézve NEM igaz.
- **Javasolt irány (nem patch):** mivel a `PostureObservation` ma nem exportál per-landmark visibility-t (R14 kontraktja, nincs az `allowed_paths`-on, nem módosítható ebben a körben), a reális javítás VAGY (a) a `confidence`/`confidenceFormula` szemantikájának ŐSZINTE átfogalmazása egy ténylegesen elérhető, megbízhatóság-jellegű jelre (pl. konstans, vagy `comparedLandmarkCount`/`requiredPoseLandmarkIds.length` fedettségi arány — NEM drift-alapú), VAGY (b) a brief §6 "visibility-mátrix" kritériumának dokumentált, mért indoklású újraskálázása arra, amit a mai `PostureObservation`-kontraktus ténylegesen mérhetővé tesz (a jelenlét/hiány R8-kapu, ami MÁR helyesen implementált és tesztelt). A választás és a §0.0 dokumentálása az orchestrátor/implementer közös döntése a javító körben.
- **Státusz:** OPEN

### F3 — MINOR — `SafetyClaimGuard.evaluate(code, declaredClass:)` megkerüli a katalógus-tagság ellenőrzést azon az ágon

- **Fájl:** `safety_claim_guard.dart:68` — `declaredClass` megadásakor a katalógus-lookup (és vele a „nem katalogizált kód elutasítva" fail-closed fél) teljesen kimarad, csak a forbidden-class check fut.
- **Miért MINOR, nem MAJOR:** az EGYETLEN production hívó (`posture_metric_engine.dart:98`) `declaredClass` NÉLKÜL hívja (`evaluate(definition.claimCode)`), tehát a mai adatfolyamban mindkét fail-closed irány érvényesül. A rés egy jövőbeli hívó (R23/R27) számára látens API-csapda.
- **Javasolt irány:** `declaredClass` megadásakor is követeljük meg `catalog.containsKey(code)`-ot (vagy `@visibleForTesting` jelöléssel zárjuk production-hívásból).
- **Státusz:** OPEN (follow-up-ként is elfogadható, ha a diffet nem hizlalja érdemben)

### F4 — MINOR — a gate mind a négy önellenőrző futtatása `| tail` mögé volt írva, a brief és a bundled preambulum kifejezett tiltása ellenére

- **Fájl:** implementer-log (`/tmp/mm-e05-r20.log`), 4 `Bash` tool_use: `tools/round-gate.sh test/features/vision 2>&1 | tail -100/120/100/100`.
- **Probléma:** a prompt §6 és a bundled implementer-preambulum is explicit, névre szóló (E02-R07) precedenssel tiltja ezt — a `| tail` elrejti a valódi kilépési kódot és csonkolja a kimenetet. A wrapper gépi ellenőrzése (`gate_shape=VIOLATION`) ezt helyesen jelezte.
- **Hatás:** a mai esetben NEM okozott hamis „zöld" állítást — a saját, csővezeték nélküli, friss klónban futtatott gate ugyanazt a MINDEN GATE ZÖLD / 331 tesztet adta vissza —, de a fegyelmezetlenség önmagában ismétlődő, névre szóló hibaminta.
- **Javasolt irány:** nincs kód-javítás; a javító kör promptjában ismételten, explicit módon meg kell erősíteni a szabályt.
- **Státusz:** OPEN (megjegyzésként a javító körben, nem önálló ok a javításra)

### F5 — NOTE — a `VisionSafetyClaimClass` osztálytaxonómia deny-by-exception

`vision_safety_policy.dart:78-83`: `isForbidden` egy explicit tiltott-halmazt néz; nincs pozitív `allowed` felsorolás. Egy jövőbeli, `forbidden`-be felvenni elfelejtett enum-érték alapértelmezetten ENGEDÉLYEZETT lenne. Javasolt irány: pozitív `allowed` halmaz + `assert(forbidden.length + allowed.length == VisionSafetyClaimClass.values.length)`-jellegű zárt-fedés ellenőrzés.

### F6 — NOTE — az engine nem adja vissza a ténylegesen alkalmazott claim-kódot; R23-nak kell majd helyesen irányt választania

A `compute()` csak `MetricObservation`-t ad (érték/confidence/observability), a claim-kódot csak belül, önmaga-kapuzására használja. A katalógusban léteznek irány-specifikus párok (`...IncreasedVsBaseline` / `...ReducedVsBaseline`), de az engine ma csak a fix „increased/shifted" változatot birtokolja — egy jövőbeli R23-implementációnak helyesen kell majd az érték előjeléből a megfelelő kódot választania, különben hamis irányú állítás születne. Nem e kör hibája, csak explicit follow-up jegyzet R23-nak.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (saját, `/tmp/review-e05-r20`, friss GitHub-klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/features/vision | zöld, 331/331 | ✅ zöld, 331/331 (saját futtatás, csővezeték nélkül, `--result-json`) |
| architecture | zöld (12 allowlisted deviation, egyik sem e körhöz tartozik) | ✅ zöld — a 12 deviation egyike sem hivatkozik posture/safety fájlra |
| secrets | zöld | ✅ zöld |
| l10n | zöld | ✅ zöld |
| CI (teljes suite + property + APK) | — | Még nem dispatch-elve (a review lezárása előtt nem esedékes) |

A gate-et az implementer NÉGYSZER `| tail` mögé futtatta önellenőrzésre (F4) —
a fenti „ellenőrizve" oszlop a reviewer SAJÁT, csővezeték nélküli, friss klónon
futtatott, csonkítatlan artefaktuma, nem az implementer önjelentése.

## Merge-döntés

**CHANGES REQUIRED.** Az ADR 0052 zöld kapuja (gate) teljesül, de a kör saját
§11 mércéje („nulla OPEN BLOCKER/MAJOR") **nem** — F1 és F2 nyitva. Egy javító
kört a MiniMax kap (router-first eszkalációs szabály, első javító kör), a
fenti F1–F4 leletlistával; F5/F6 opcionális, ha a diffet nem hizlalja.
