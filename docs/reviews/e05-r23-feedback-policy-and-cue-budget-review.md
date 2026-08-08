# E05-R23 — Review

Brief: `docs/rounds/e05-r23-feedback-policy-and-cue-budget.md`
ADR-ek: [0191](../adr/0191-feedback-policy-and-cue-budget.md) (ez a kör),
[0188](../adr/0188-vision-safety-claim-guard.md) (safety guard, R20),
[0190](../adr/0190-vision-observation-fusion-and-evidence.md) (evidence, R22)
Diff: `git diff origin/main...codex/e05-r23-feedback-policy-and-cue-budget` (base `6afcede`, tip `307246e`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-08
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 1 · MAJOR: 2 · MINOR: 5 · NOTE: 4

A dedikált security-review (`docs/reviews/e05-r23-feedback-policy-and-cue-budget-security.md`,
`risk = "high"` miatt kötelező, AGENTS.md §15.1) minden lelet mögé **futtatott**
próbát tett (nem csak kódolvasást) — az alábbi B1/M1/M2/MI1-MI5/N1-N4 azonosítók
onnan származnak, ezt a jelentést a security-review-val EGYÜTT kell olvasni. Ez
a jelentés a funkcionális/acceptance-criteria oldalt zárja le, és B1/M1/M2-t
saját kézzel, a shippelt forráson (nem a security-agent állítására hagyatkozva)
független logikai bejárással megerősítette — lásd az egyes leletek "Saját
megerősítés" sorát.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Katalógus-teszt: minden `InsightCode` → policy + en/hu ARB + safety guard | ✅ | `feedback_policy_test.dart:19-39` `InsightCode.values` felett iterál, mind a 3 dimenzióra; security-próba `[probe2]`: mind a 11 kód `allowed=true` a production ágon |
| 2 | Cooldown-teszt injektált órával (alatt/rajta/fölött) | ✅ | `feedback_policy_test.dart:53-65`, három cella, `>` szigorú határ önmagában helyes |
| 3 | Prioritás-teszt: setup+technikai → csak setup; azonos prioritásnál determinisztikus | ❌ **NEM** (lásd B1) | `feedback_policy_engine_test.dart:35-51` csak az ELSŐ hívásra igaz; a `111-133`-as teszt saját `reason`-je dokumentálja, hogy a MÁSODIK kiértékelésen a technikai kód nyer, amíg a setup cooldownja tart. A tie-break maga determinisztikus (✅ az al-kritérium), de az irány véletlenszerűen a negatívnak kedvez (MI5). |
| 4 | Confidence-mátrix: 6 cella, negatív szigorúbb (assert) | ✅ *a tesztelt alakra*, ⚠ lásd M2 | `feedback_policy_engine_test.dart:13-33` 6 cella zöld; a `FeedbackPolicy` konstruktor kikényszeríti `negative > positive`-t. **De** a 6-cellás teszt nem csatol `comparisonEvidence`-t — az a kombináció, ahol M2 szerint a kapun átment insight kimenő confidence-e a küszöb ALÁ esik, kívül esik ezen a tesztmátrixon. |
| 5 | Session-summary korlát: ≥5 jelölt → ≤2, determinisztikus | ✅ | `feedback_policy_test.dart:67-89`, forward+reversed input azonos eredmény |
| 6 | Golden summary fixture: bit-stabil két futás közt | ✅ *mechanikusan*, ⚠ lásd B1 | `feedback_policy_engine_test.dart:111-133` — a két futás egymással konzisztens (ismételhető), de a PINNELT viselkedés maga a B1 hiba; a fixture-t a javító kör kell átírja a helyes viselkedésre |
| 7 | Lokalizációs paritás zöld | ✅ | gate `[7] l10n`: „L10n parity OK (en → hu, 975 message(s))"; `test/core/l10n_parity_test.dart` 3/3 |
| 8 | Valódi-sértés próba: negatív küszöb → pozitívéra → PIROS → visszaállítás | ✅ | Implementer §10: a `FeedbackPolicy` konstruktor `ArgumentError`-t dob egyenlő küszöbre (`negativeConfidenceThreshold <= positiveConfidenceThreshold` invariáns, `feedback_policy.dart:19-25` — magam is elolvastam, a throw feltétele helyes és teszteletlen ág nélküli) |

**5/8 teljes, 2/8 részleges (a tesztelt alakra igen, a teljes kontraktra nem), 1/8 bukott.**

## Scope-audit

Nincs eltérés. `git diff --stat 6afcede 307246e` = 12 fájl, mind a brief
`allowed_paths` 12 bejegyzésének egyike; a `vision_safety_policy.dart` meglévő
9 bejegyzése kulcs/érték szinten változatlan (a `dart format` újratördelte a
`Map`-deklarációt — lásd security NOTE-1 pontosítás), a `VisionSafetyClaimClass`
enum és a `safety_claim_guard.dart` teljes egészében érintetlen.

## Megállapítások

### F1 — BLOCKER — a setup-elsőbbség nem tart a setup cue saját cooldownja alatt

- **Fájl:** `lib/features/vision/domain/feedback/cue_budget.dart:11-23` (a
  cooldown-szűrés a `selectRealtime`-ban a rendezés ELŐTT fut, minden
  jelöltre egyformán, iránytól függetlenül).
- **Probléma:** a brief §5/2 és az ADR 0191 Döntés 4 szerint a setup/
  observability cue **abszolút** elsőbbséget kap a technikai kritika előtt —
  "sosem technikai kritikát ugyanarra az ablakra". A kód ehelyett a setup-jelöltet
  is a KÖZÖS cooldown-szűrőn futtatja: mihelyt egyszer megjelent, 2 másodpercre
  "elhallgat", és ez idő alatt bármely eligible technikai jelölt (akár egy
  0.5-ös prioritású, negatív irányú kritika) átveszi a cue-slotot.
- **Hatás:** a felhasználó pontosan azt a párhuzamos/felcserélt megjelenítést
  kapja, amit a brief explicit "NEM elfogadható"-nak jelöl — egy setup-hibás
  (kamera/geometria nem megfigyelhető) állapotban a rendszer 500 ms–2 s
  ablakokban technikai kritikát mutat, miközben a mérése bizonyítottan
  hiányos.
- **Saját megerősítés:** kézzel bejártam a `feedback_policy_engine_test.dart:111-133`
  tesztet: az `_engine()` egy FIX (nem előrehaladó) órát ad a `CueBudget`-nek;
  az `engine.evaluate(candidates)` két egymást követő hívása pontosan az
  imént leírt mechanizmust futtatja — a második hívásnál
  `timestamp.difference(previous) == Duration.zero`, ami nem `>` a 2000 ms
  cooldownnál, tehát a setup-jelölt kiesik, és `frettingFocus` nyer. A teszt
  SAJÁT `reason` szövege ("the setup code is cooling down, so the next ranked
  code wins") ezt a viselkedést dokumentálja elvárásként, nem hibaként — a
  gate emiatt erre a kritériumra **hamisan zöld** (`docs/execution/09-review-report.md`
  BLOCKER-definíció: "hamis »zöld« állítás").
- **Kötelező javítás:** a setup-irányú jelölt vagy (a) mindig megelőzi a
  technikai jelölteket a cooldown-szűrés ELŐTT (a `selectRealtime` először a
  setup-alkategóriában választ, csak setup-jelölt hiányában esik a technikai
  listára), vagy (b) ha a setup-jelölt cooldown miatt kiesik, a realtime slot
  `null` marad ugyanarra az ablakra (no feedback > false priority). A
  `feedback_policy_engine_test.dart:111-133` tesztet és `reason`-jét a
  javításnak a helyes viselkedésre kell átírnia — a jelenlegi szöveg a rést
  írja le, nem a kontraktot.
- **Ellenőrzés:** új/módosított teszt, amely egy setup-jelöltet a SAJÁT
  cooldownja alatt, egy egyidejű technikai jelölttel együtt kiértékel, és
  `realtimeCue` `null`-t vagy a setup kódot várja, `frettingFocus`-t sosem.
- **Státusz:** OPEN

### F2 — MAJOR — a `comparisonEvidence` egyetlen kapun sem megy át

- **Fájl:** `lib/features/vision/application/feedback_policy_engine.dart:43-67`,
  `lib/features/vision/domain/feedback/insight_code.dart:125-129`.
- **Probléma:** `_accepts` kizárólag a primer `candidate.evidence`-t kapuzza
  (guard, capability, minimumDuration, observability, confidence); a
  `hasComparableImprovement` csak practiceId/capabilityLevel/metric.key
  egyezést néz, a comparison-evidence saját megfigyelhetőségét/confidence-ét
  soha. Egy `notObservable` (érték nélküli) vagy near-zero-confidence
  comparisonEvidence-szel is kiadható egy "javultál" insight.
- **Saját megerősítés:** elolvastam `_accepts` mind a hat elágazását — a
  `candidate.comparisonEvidence` szó egyszer sem szerepel a metódusban;
  `hasComparableImprovement` (`insight_code.dart:125-129`) négy egyenlőség-
  vizsgálatot futtat (`!= null`, practiceId, capabilityLevel, metric.key),
  observability/confidence-mezőt nem érint. A security-report `[B]`/`[B2]`
  próbája ugyanezt futtatva reprodukálta.
- **Kötelező javítás:** a `comparisonEvidence`-re ugyanazok a kapuk, mint a
  primerre (`observationState ∈ {observed, inferred}`,
  `confidence >= policy.confidenceThreshold`), plusz azonosság-/idősorrend-
  ellenőrzés (`comparisonEvidence.id != evidence.id`, korábbi
  `provenance.window`).
- **Ellenőrzés:** teszt egy `notObservable` és egy near-zero-confidence
  comparisonEvidence-re — mindkettő `_accepts=false`-t kell adjon
  improvement-kódra.
- **Státusz:** OPEN

### F3 — MAJOR — az emittált confidence a beengedő küszöb alá eshet

- **Fájl:** `lib/features/vision/application/feedback_policy_engine.dart:69-86`
  (`_toInsight`: az emittált `confidence` a primer és a comparison evidence
  MINIMUMA), a beengedés (`_accepts:61-65`) viszont csak a primert méri.
- **Probléma:** egy alacsony confidence-ű `comparisonEvidence` csatolásával
  BÁRMELY kód (nem csak `*Improved`) kimenő confidence-e a policy küszöbe alá
  vihető, miközben a candidate átment a gate-en a primer evidence alapján.
- **Saját megerősítés:** `_toInsight` négy sorát elolvasva a `confidence`
  változó tényleg `evidence.map(...).reduce(min)` — a primer ÉS a comparison
  minimuma —, és ez FÜGGETLEN attól, hogy a kód `isImprovement` vagy nem
  (a `comparisonEvidence` paraméter bármelyik kódnál átadható a
  `FeedbackCandidate` konstruktorán). A security-report `[C]`-próbája egy
  `frettingFocus` (negatív, effektív küszöb 0.85) esetet futtatott 0.95
  primer + 0.02 comparison confidence-szel → emittált `confidence=0.02`.
- **Kötelező javítás:** a küszöb-ellenőrzés az AGGREGÁLT (kimenő) confidence-en
  fusson, ne csak a primer evidence-en — vagy dobja el a comparisonEvidence-et
  nem-improvement kódoknál.
- **Ellenőrzés:** invariáns-teszt minden emittált `VisionInsight`-ra:
  `insight.confidence >= FeedbackPolicies.catalog[insight.code]!.confidenceThreshold`.
- **Státusz:** OPEN

### F4 — MINOR — a `*Focus` kódok `baselineRelative`-nak deklaráltak, de nincs baseline

- **Fájl:** `lib/features/vision/domain/safety/vision_safety_policy.dart:130,133,136`.
- Lásd security-report MI1 — a `*Focus` ág sem az engine-ben, sem az
  evidence-ben nem hasonlít baseline-hoz; `neutralObservation` (mint a
  `*Stable` kódoknál) a pontos osztály, vagy a `*Focus` ág kapja meg a
  `hasComparable…` szerkezetet.
- **Státusz:** OPEN (javítás a fix-körben, ugyanaz a fájl már scope-ban)

### F5 — MINOR — a publikus `VisionInsight`/`CueBudget` felület megkerülheti a guardot

- **Fájl:** `lib/features/vision/domain/feedback/insight_code.dart:44-60`,
  `cue_budget.dart:11`, `public.dart:11-14`.
- Lásd security-report MI2 — a fail-closed tulajdonságot ma csak TESZT tartja
  (`InsightCode.values` iteráció), nem a típusrendszer; a `priority`/`direction`
  szabad paraméter a konstruktoron. Mérve: ma nincs production hívó (R24
  pending), tehát nem felhasználóig érő ma, de a `public.dart` már kiadja a
  megkerülő utat.
- **Státusz:** OPEN (javítás javasolt ugyanebben a körben, mert a réteg
  tulajdonosa épp most dolgozik a fájlokon)

### F6 — MINOR — azonos prioritású döntetlen a negatív irányt részesíti előnyben

- **Fájl:** `cue_budget.dart:41-45`, `feedback_policy_engine.dart:88-94`.
- Lásd security-report MI5 — a `safetyCode` lexikai tie-break szisztematikusan
  a `*Focus` (negatív) kódoknak kedvez a `*Stable`/`*Improved` (pozitív) felett
  ábécé-sorrend miatt. Determinisztikus (a §6 betű szerint teljesül), de az
  irány véletlen melléktermék, szemben az aszimmetrikus-küszöb szándékával.
- **Státusz:** OPEN (javítás javasolt: explicit, dokumentált tie-break — pl.
  magasabb confidence előbb, majd stabil kód-sorrend)

### F7 — MINOR — 11 új ARB-kulcs `@description` nélkül

- **Fájl:** `lib/l10n/app_en.arb:1313-1323`.
- Lásd security-report MI4. Olcsó, additív javítás (a fájl már scope-ban).
- **Státusz:** OPEN

### F8 — MINOR (follow-up, NEM ebben a körben) — a lexikai deny-list nem fedi az ergonómiai szókincset

- Lásd security-report MI3. A `safety_claim_guard.dart` (R20, ma nincs az
  `allowed_paths`-on) bővítését igényelné — a security-report is külön
  körnek jelöli. **Nem blokkolja ezt a mergét**; dokumentált follow-up.
- **Státusz:** DEFERRED (follow-up issue: a deny-list bővítése ergonómiai
  szókinccsel, VAGY az `InsightCode` szuffix zárt szótárra kötése — külön
  brief, mert `safety_claim_guard.dart` scope-bővítést igényel)

## Egyéb, tisztán funkcionális ellenőrzés (a security-review dimenzióján túl)

- **Architektúra (AGENTS.md §6):** a négy új fájl framework-mentes, nem
  importál Riverpod/Flutter-t; `public.dart` additív export; nincs
  core→feature import. `tool/check_architecture.dart` zöld (12 allowlisted
  deviation — meglévő, nem ehhez a körhöz tartozó).
- **`FeedbackCandidate` mint boundary, nem nyers `VisionEvidence`:** a brief
  §1 szövege "VisionEvidence → VisionInsight"-ot ír, a tényleges belépő pont
  `FeedbackCandidate` (evidence + explicit kód + practice/capability
  context). Ez NEM lelet — a brief scope-ja (§3) sosem kért metrika-érték→kód
  leképezési logikát (az 17 metrikára kalibrált küszöb ma sehol nem létezik),
  és minden §6 acceptance-teszt is ezen a boundary-n dolgozik. Dokumentálva
  NOTE-ként a jövőbeli olvasónak: a "melyik evidence melyik kódot indokolja"
  döntés egy KÉSŐBBI kör (valószínűleg R24 vagy egy dedikált metrika-threshold
  kör) dolga marad.
- **Gate-bizonyíték saját kézzel, izolált klónban, a HELYES (307246e) commiton
  újrafuttatva** (az első próbám a pre-flight-commitra futott véletlenül,
  0 új teszttel — felismerve és korrigálva, lásd alább):

| Gate | Állított eredmény (implementer) | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (1163 fájl, 0 changed) |
| analyze | zöld | ✅ (No issues found) |
| test test/features/vision | zöld, 378 teszt | ✅ 378/378, "All tests passed!" |
| test test/core/l10n_parity_test.dart | zöld, 3 teszt | ✅ 3/3 |
| architecture | zöld | ✅ |
| secrets | zöld | ✅ (2010 fájl, 0 finding) |
| l10n | zöld | ✅ (975 kulcs, en→hu teljes) |
| CI (teljes suite + property + APK) | — | nincs dispatch-elve — a B1/M1/M2 miatt a javító kör UTÁN jön |

A zöld gate — ahogy B1 is mutatja — **nem bizonyítja** a §5/2 setup-elsőbbség
kontraktot, mert a shippelt teszt maga pinnelte a hibás viselkedést. A többi
hét gate-lépés (format/analyze/architecture/secrets/l10n/a másik hat
acceptance-kritérium) valódi, független bizonyíték.

## Merge-döntés

**Merge TILOS.** 1 BLOCKER (F1/B1) + 2 MAJOR (F2/M1, F3/M2) nyitva
(`09-review-report.md` tábla: BLOCKER/MAJOR → "Merge tilos, amíg nyitva van").
Javító kör szükséges, UGYANAZZAL a motorral (Terra), a §2 önjavítási szabály
szerint (user-döntés 2026-07-31: a javító kör a lánc normál útja). A javító
körnek a `feedback_policy_engine_test.dart:111-133` téves `reason`-jét is
korrigálnia kell, különben a következő review ugyanezt a hamis-zöld mintát
találja.

Javasolt a fix-körben egyszerre zárni: F1 (BLOCKER), F2, F3 (MAJOR), és — mivel
ugyanazok a fájlok már módosulnak — F4, F5, F6, F7 (MINOR). F8 (MI3, a
lexikai deny-list) **kimarad**: `safety_claim_guard.dart` nincs az
`allowed_paths`-on, és a security-review is önálló körnek jelöli.
