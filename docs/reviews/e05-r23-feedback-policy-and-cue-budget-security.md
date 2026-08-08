# E05-R23 — Dedikált biztonsági review (risk = "high")

> ✅ **ORCHESTRÁTOR-ZÁRÁS (Claude Sonnet 5, 2026-08-08, `211d7a8`).** B1, M1,
> M2 és MI1/MI2/MI4/MI5 mind **FIXED** — lásd
> [`e05-r23-feedback-policy-and-cue-budget-review.md`](e05-r23-feedback-policy-and-cue-budget-review.md)
> „Javító kör #1 zárás" szakaszát a soronkénti bizonyítékért (fájl:sor a
> javított kódban, az érintett dedikált regressziós teszt neve). A zárás
> módja: saját kézzel elolvastam a `307246e`→`211d7a8` diffet minden egyes
> lelet ellen (nem az implementer önjelentésére hagyatkozva), és a
> `tools/round-gate.sh`-t egy friss `/tmp` klónban újrafuttattam (387/387
> teszt, minden lépés zöld). MI3 (a lexikai deny-list) szándékosan
> **DEFERRED** marad — a `safety_claim_guard.dart` nincs ennek a körnek az
> `allowed_paths`-án, önálló, jövőbeli kör dolga. Az alábbi, eredeti jelentés
> **változatlanul** a lelet-felfedezés időpontjának (`307246e`) állapotát
> rögzíti — ne a "Verdikt" sort olvasd a végállapotnak, azt a fenti
> hivatkozott review-fájl adja.

Brief: `docs/rounds/e05-r23-feedback-policy-and-cue-budget.md`
ADR-ek: `docs/adr/0188-vision-safety-claim-guard.md`, `docs/adr/0191-feedback-policy-and-cue-budget.md`
Diff: `git diff origin/main HEAD` — branch `codex/e05-r23-feedback-policy-and-cue-budget`,
HEAD `307246e` (`feat(vision): add feedback policy cue budget`), base `origin/main` `6afcede`
Reviewer: `security-reviewer` ágens · Dátum: 2026-08-08
Verdikt (a `307246e` időpontjában — lásd a fenti zárás a végállapotért):
**FAIL / CHANGES REQUIRED** — **1 BLOCKER**, 2 MAJOR, 5 MINOR, 4 NOTE.
0 CRITICAL.

> Az `AGENTS.md` §15.1 szerint kötelező dedikált biztonsági pass (a brief
> `ai-router` blokkja `risk = "high"`). A kimenet READ-ONLY: jelentés, nem
> javítás — production/teszt kód ebben a passban nem módosult. A merge-et a
> funkcionális review + az ADR 0052 zöld kapu együtt szabályozza; ez a
> jelentés a security/privacy/claim-boundary/injection dimenziót fedi.

## Súlyossági séma

`docs/execution/09-review-report.md` táblája (BLOCKER/MAJOR/MINOR/NOTE),
kiegészítve CRITICAL szinttel (bizonyított titok-szivárgás / consent-megkerülés
/ RCE / path traversal → merge tilos). Ebben a körben **CRITICAL = 0**.

## Módszer — minden lelet FUTTATOTT bizonyítékkal

A jelentésben szereplő `[A]`–`[F]` hivatkozások egy **izolált, read-only
próba KIMENETEI**, nem kézi kódolvasás:

- A próba a scratchpadben él
  (`…/scratchpad/probe/{probe.dart,probe2.dart}`), és a **ténylegesen
  szállított** forrásokat importálja abszolút `file:` URI-val a kör-worktree-ből;
  semmit nem ír vissza a repóba. Package-feloldás: kézzel írt
  `package_config.json` (`meta` a pub-cache-ből, `strumsight` a worktree
  `lib/`-jére) — így a `FeedbackPolicyEngine`, `CueBudget`, `FeedbackPolicies`,
  `SafetyClaimGuard`, `VisionSafetyPolicy` **valódi** példányai futottak.
- A katalógus additivitását külön, forrásból kiolvasó összehasonlítás mérte
  (`git show origin/main:… ` vs. `git show HEAD:…` → kulcs–érték párok
  halmaz-diffje), nem a commit-üzenet állítása.
- Az ARB-szövegek `json.load`-dal, mindkét nyelven, teljes egészében ki lettek
  írva és tételesen átolvasva.

## Összegzés

CRITICAL: 0 · **BLOCKER: 1** · MAJOR: 2 · MINOR: 5 · NOTE: 4

| # | Súly | Lelet | Fájl |
|---|---|---|---|
| B1 | **BLOCKER** | A setup-elsőbbség nem abszolút: a setup cue cooldownja alatt negatív technikai kritika jelenik meg UGYANARRA az ablakra | `cue_budget.dart:11-23,34-39` |
| M1 | MAJOR | A `comparisonEvidence` egyetlen kapun sem megy át → „javultál" állítás nem megfigyelhető (érték nélküli) vagy önmagával összevetett ablakból | `feedback_policy_engine.dart:43-67`, `insight_code.dart:125-129` |
| M2 | MAJOR | Az emittált `VisionInsight.confidence` a beengedő küszöb ALÁ eshet — negatív cue is (0.85-ös kapu, 0.02-es kimenet) | `feedback_policy_engine.dart:75-77` |
| MI1 | MINOR | A három `*Focus` kód `baselineRelative`-nak deklarált, miközben sem a réteg, sem az ARB-mondat nem baseline-relatív | `vision_safety_policy.dart:130,133,136` |
| MI2 | MINOR | A guard csak az engine-ben fut: az exportált `VisionInsight` konstruktor + `CueBudget` guard nélküli, prioritás-hamisítható utat ad | `insight_code.dart:44-60`, `cue_budget.dart:11`, `public.dart:11-14` |
| MI3 | MINOR | A lexikai deny-list nem fedi azt az ergonómiai/orvosi szókincset, amerre ez a névminta a legvalószínűbben bővül | `safety_claim_guard.dart:43-54` |
| MI4 | MINOR | A 11 új ARB-kulcs `@description` nélkül (89 másik kulcsnak van) — a fordítónak nincs jelzés, hogy ezek nem csúszhatnak diagnosztikusba | `app_en.arb:1313-1323` |
| MI5 | MINOR | Azonos prioritásnál a döntetlent lexikai sorrend dönti → rendszeresen a NEGATÍV cue nyer | `cue_budget.dart:41-45` |
| N1 | NOTE | A katalógus-bővítés mérten additív; a meglévő 9-en csak `dart format` újratördelés történt | `vision_safety_policy.dart:98-140` |
| N2 | NOTE | A `setupNotObservable` ágon nincs semmilyen confidence-kapu (0.0-nál is emittál) | `feedback_policy_engine.dart:52-55` |
| N3 | NOTE | A `minimumDuration` evidence-ablak kapu, NEM az SDD §23.3 „cue minimum megjelenési idő"-je — az utóbbi implementálatlan | `feedback_policy_engine.dart:48-49` |
| N4 | NOTE | Az egyetlen `lib/`-beli `declaredClass`-hívó a `validateCatalog()`, R20-as, változatlan, nem claim-emissziós út | `safety_claim_guard.dart:103-114` |

## Scope-audit

A brief `ai-router.allowed_paths` **pontosan** egyezik a diff-fel; listán kívüli
változás **nincs** (`git diff --name-status origin/main HEAD` = 12 fájl,
`allowed_paths` = 12 bejegyzés). Mérve: `pubspec.yaml`, `pubspec.lock`,
`android/`, `ios/`, `.github/`, `tool/` **érintetlen** — nincs új dependency,
nincs új platform-permission, nincs CI/gate-módosítás.

---

## B1 — BLOCKER: a setup-elsőbbség cooldown alatt megfordul

**Fájl:** `lib/features/vision/domain/feedback/cue_budget.dart:11-23` és `:34-39`
(a szűrés a rendezés ELŐTT fut), a shippelt teszt pedig
`test/features/vision/application/feedback_policy_engine_test.dart:127-131`.

**Sértett szabály:**

- SDD Ch6 §23.3: „**setup cue elsőbbséget élvez a technikai cue előtt**";
- brief §5 pont 2: „Ha a keret rossz vagy a geometria elveszett, a felhasználó
  azt kapja, **nem technikai kritikát**. **NEM elfogadható:** párhuzamos
  megjelenítés";
- ADR 0191 Döntés 4: „…**sosem** technikai kritikát ugyanarra az ablakra";
- brief §6 acceptance: „Prioritás-teszt: egyszerre setup + technikai insight
  jelölt → **csak a setup** jelenik meg".

**Failure scenario (futtatva, valódi előrehaladó órával — `[A]`):** a kamera
NEM megfigyelhető (setup jelölt) ÉS egy negatív technikai jelölt
(`frettingFocus`, evidence-confidence 0.95) folyamatosan él ugyanabban a
batchben, 2,5 másodpercen át. A `setupNotObservable` cooldownja 2000 ms, a
technikaié 5000 ms:

```
t=+0ms     setupCandidateAccepted=true  realtimeCue=setupNotObservable dir=setup    prio=100
t=+500ms   setupCandidateAccepted=true  realtimeCue=frettingFocus      dir=negative prio=50   ← SÉRTÉS
t=+1000ms  setupCandidateAccepted=true  realtimeCue=null
t=+1500ms  setupCandidateAccepted=true  realtimeCue=null
t=+2000ms  setupCandidateAccepted=true  realtimeCue=null
t=+2500ms  setupCandidateAccepted=true  realtimeCue=setupNotObservable dir=setup    prio=100
```

`t=+500ms`-nál a `setupNotObservable` jelölt **el van fogadva** (benne van a
`decision.insights`-ban, tehát a réteg tudja, hogy nem lát), de a cooldown
kiszűri a cue-slotból, és helyette a felhasználó a **„Keep the fretting pattern
consistent." / „Tartsd egyenletesen a fogásmintát."** kritikát kapja — pontosan
azt a kimenetet, amit a brief „NEM elfogadható"-nak, az ADR „sosem"-nek mond.

Ez **nem** szintetikus szélsőség: 500 ms-os újraértékelés realtime vision
kadenciában normális, és a setup-cooldown 2 s — vagyis minden setup-cue utáni
első 2 másodpercben a technikai kritika átveszi a helyét, amíg a setup-feltétel
fennáll.

**Súlyosbító körülmény — a zöld gate ezt a viselkedést rögzíti:** a shippelt
teszt `feedback_policy_engine_test.dart:111-133` a **sértő** kimenetet
állítja be elvárásként:

```dart
expect(
  second.realtimeCue!.code,
  InsightCode.frettingFocus,
  reason: 'the setup code is cooling down, so the next ranked code wins',
);
```

Ezzel a §6 „Prioritás-teszt" acceptance-cellája **hamisan zöld**: a teszt-készlet
nem a kötött invariánst méri, hanem az attól eltérő tényleges viselkedést.
(`09-review-report.md` táblája: „hamis »zöld« állítás" → BLOCKER.)

**Javítás iránya (nem írom meg — a réteg tulajdonosa dönt):** a setup/
observability ágnak a cooldown-szűrés **fölött** kell állnia. Két járható forma:
(a) a `selectRealtime` először a setup-irányú jelöltek közül választ, és csak
akkor esik technikai jelöltre, ha setup-jelölt egyáltalán nincs (nem: „van, de
hűl"); vagy (b) ha egy setup-jelölt cooldown miatt kiesik, a technikai jelöltek
is el vannak nyomva ugyanarra az ablakra (`null` cue), mert „no feedback is
better than false feedback". A `[A]` próba mindkét változatnál `t=+500ms`-on
`setupNotObservable`-t vagy `null`-t kell adjon, `frettingFocus`-t soha.
A javításnak a `feedback_policy_engine_test.dart:111-133` `reason`-jét is át
kell írnia — jelenleg ez dokumentálja a rést.

---

## M1 — MAJOR: a `comparisonEvidence` egyetlen kapun sem megy át

**Fájl:** `lib/features/vision/application/feedback_policy_engine.dart:43-67`
(`_accepts` **kizárólag** a `candidate.evidence`-t kapuzza) +
`lib/features/vision/domain/feedback/insight_code.dart:125-129`
(`hasComparableImprovement` csak practiceId / capabilityLevel / `metric.key`
egyezést néz).

**Sértett szabály:** SDD Ch6 §23.3 utolsó pontja — „**pozitív megerősítés csak
valódi javulás vagy stabil teljesítés esetén**"; `AGENTS.md` §5 — „Kamera és AI
nem találgathat … mérési bizonyíték nélkül". (ADR 0191 Döntés 7 három feltételt
sorol — a kód **azt a hármat teljesíti**; a rés az, hogy ez a három nem elég az
SDD-követelményhez.)

**Failure scenario 1 (futtatva — `[B]`):** az összehasonlító ablak
`ObservationState.notObservable`, tehát `VisionEvidence` invariánsa szerint
`value == null` — nincs benne EGYETLEN mért érték sem —, de a confidence-e
0.95, a practice/capability/metrika egyezik:

```
emitted: [frettingImproved dir=positive conf=0.95 prio=50 ids=[now, prev]]
```

A felhasználó ARB-szövege ehhez: **„Fretting pattern improved in comparable
practice." / „A fogásmintád összehasonlítható gyakorlásban javult."** — magabiztos
(0.95) javulás-állítás egy olyan ablakhoz képest, amelyben a rendszer saját
bevallása szerint semmit nem tudott megfigyelni.

**Failure scenario 2 (futtatva — `[B2]`):** ugyanaz a `VisionEvidence` példány
adva `evidence`-nek ÉS `comparisonEvidence`-nek:

```
emitted: [frettingImproved dir=positive conf=0.95 prio=50 ids=[same-window, same-window]]
```

Az ablak önmagához képest „javult"; az `evidenceIds` duplikált. Nincs
`id`-különbözőségi, sem időbeli sorrend-ellenőrzés
(`provenance.window.startUs` egyik ágon sincs összehasonlítva).

**Teszt-fedettség:** `feedback_policy_engine_test.dart:70-92` az egyetlen
improvement-teszt, és **csak** a `comparisonPracticeId`-t variálja; az
összehasonlító evidence ott mindig a `_evidence(id:'previous')` default
(observed, 0.9). A fenti két bemenet egyik tesztben sem szerepel.

**Javítás iránya:** a `comparisonEvidence`-re ugyanazok a kapuk, mint a
primerre (`observationState` ∈ {observed, inferred}, `confidence >=
policy.confidenceThreshold`), plusz `comparisonEvidence.id != evidence.id` és
szigorúan korábbi `provenance.window`.

---

## M2 — MAJOR: az emittált confidence a beengedő küszöb alá eshet

**Fájl:** `lib/features/vision/application/feedback_policy_engine.dart:75-77`
— az emittált confidence a két evidence **minimuma**, miközben a beengedésnél
(`:63`) csak a primer confidence-e volt mérve.

**Sértett szabály:** `AGENTS.md` §5 — „Gyenge confidence nem jelenhet meg biztos
állításként"; ADR 0191 Döntés 6 (aszimmetrikus küszöb) gépi garanciája.

**Failure scenario (futtatva — `[C]`):** `frettingFocus` (NEGATÍV irány,
effektív kapu **0.85**), primer evidence 0.95 → beengedve; mellette egy
`comparisonEvidence` 0.02 confidence-szel (a jelölt-konstruktor bármely kódnál
engedi, nem csak `*Improved`-nél):

```
frettingFocus gates: positive=0.7 negative=0.85 effective=0.85
emitted: [frettingFocus dir=negative conf=0.02 prio=50 ids=[aux, primary]]
```

Egy negatív technikai kritika hagyja el a réteget **0.02** saját
confidence-értékkel, jóllehet a policy szerint 0.85 alatt nem lett volna szabad
megjelennie. A downstream (R24 rendering) így két rossz opció közé kerül: vagy
`insight.confidence`-re szűr — akkor a kapu inkonzisztens és a cue eltűnik —,
vagy megjeleníti, és akkor a §5 határ sérül. A kör egész értelme (a negatív
irány szigorúbb kapuja) így nem terjed ki a kimenetre.

**Javítás iránya:** a kapuzás az **aggregált** (kimenetre kerülő) confidence-en
fusson, ne csak a primer evidence-en — azaz `_toInsight` számítása előbb, és
`insight.confidence >= policy.confidenceThreshold` invariánsként tesztelve
minden emittált insightra.

---

## MI1 — MINOR: a `*Focus` kódok `baselineRelative`-nak deklaráltak, de nincs baseline

**Fájl:** `lib/features/vision/domain/safety/vision_safety_policy.dart:130`
(`'visionInsightFrettingFocus'`), `:133` (`picking`), `:136` (`posture`) —
mindhárom `VisionSafetyClaimClass.baselineRelative`.

Az enum saját doc-commentje (`vision_safety_policy.dart:58-61`) szerint a
`baselineRelative` jelentése: „**Baseline-relative quantitative observation** …
measured against the user's **own baseline**". A kör kódjában viszont a `*Focus`
ág sehol nem hivatkozik baseline-ra: az `_accepts` (`:61-65`) csak
`observationState`-et és confidence-t néz, a `VisionEvidence`-ben nincs baseline
mező, és az ARB-mondat sem összehasonlító: **„Keep the fretting pattern
consistent."** / „Tartsd egyenletesen a fogásmintát." — imperatívusz, nulla
baseline-hivatkozás. (A `*Improved` kódoknál a `baselineRelative` **helytálló**:
ott van összehasonlító ablak. A `*Stable` kódok `neutralObservation`-je szintén
helytálló.)

**Miért lelet és nem kozmetika:** a guard futásidőben nem lát különbséget
(mindkét osztály engedélyezett), tehát a hibás deklaráció **hangtalan** — de az
ADR 0188 Döntés 4 („Abszolút ítélet csak baseline mellett") jövőbeli
ellenőrzése, illetve az R27 tutor-integráció ezt a mezőt fogja provenance-ként
olvasni. Egy nem baseline-alapú ítélet baseline-relatívnak címkézve pontosan az
a fajta osztály/tartalom elcsúszás, amit a katalógus meg akar előzni.

**Javítás iránya:** vagy `neutralObservation` a három `*Focus` kódra, vagy — ha
a szándék tényleg a baseline-hoz kötés — a `*Focus` ág kapja meg ugyanazt a
`hasComparable…` szerkezetet, mint az `*Improved`.

---

## MI2 — MINOR: a guard csak az engine-ben fut, a publikus felület megkerülhető

**Fájl:** `lib/features/vision/domain/feedback/insight_code.dart:44-60`
(publikus `VisionInsight` konstruktor, `priority` és `direction` **szabad
paraméter**, nem a policy-katalógusból származtatott),
`lib/features/vision/domain/feedback/cue_budget.dart:11` (a `selectRealtime`
tetszőleges `VisionInsight`-ot fogad), `lib/features/vision/public.dart:11-14`
(mindkettő exportált).

**Failure scenario (futtatva — `[F]`):** kézzel épített insight, guard nélkül,
egyenesen a `CueBudget`-nek adva:

```
selectRealtime([spoof, realSetup]) -> postureFocus dir=setup conf=0.01 prio=9999 ids=[hand-built]
sessionSummary(...)                -> []   // a hamis direction=setup kiszűrte a summaryból
```

A `priority: 9999` **kiüti** a valódi setup cue-t (prio 100), a hazug
`direction: setup` pedig kiszökteti a session-summary szűrője alól
(`cue_budget.dart:28`) — miközben a kód valójában egy negatív posture-kritika,
0.01 confidence-szel.

**Mérték-tartás:** ma ez **nem** felhasználóig érő rés — `InsightCode` zárt
enum, mind a 11 érték katalogizált (`[probe2]`: `all InsightCode values
guard-allowed on the production path: true`), és a rétegnek még nincs production
hívója (R24). A rés az, hogy a fail-closed tulajdonságot **teszt** tartja
(`feedback_policy_test.dart:19-39` iterálja az `InsightCode.values`-t), nem a
típusrendszer, és a `public.dart` már most kiadja a megkerülő utat annak az
R24-nek, amelyik a következő körben ír rá hívót.

**Javítás iránya:** a `VisionInsight` `priority`/`direction` mezője a
`FeedbackPolicies.catalog[code]`-ból származzon (konstruktor-szinten), és a
`CueBudget` publikus belépője csak engine-től származó insightot fogadjon
(factory/`@internal`), vagy maga is futtassa a guardot.

---

## MI3 — MINOR: a lexikai deny-list nem fedi ezt a névmintát

**Fájl:** `lib/features/vision/domain/safety/safety_claim_guard.dart:43-54`
(R20-as kód, ebben a körben **változatlan** — a lelet a bővíthetőségről szól,
mert ez a kör az első katalógus-bővítés, és ez a kör vezeti be a
`visionInsight<Család><Ítélet>` szuffix-konvenciót szabad ítélet-szóval).

A 11 új kód **mind tiszta** a `pain / diagnos / injur / harm / recover / treat /
symptom / disease / disorder / syndrome` listára (mechanikusan ellenőrizve,
mind a 11 „clean"). Ugyanez a lista viszont **egyet sem** fog meg az alábbi,
ugyanezzel a mintával képzett, ergonómiai-orvosi irányba csúszó kódokból:

```
PASSES lexical check  visionInsightFrettingStrain
PASSES lexical check  visionInsightWristOveruse
PASSES lexical check  visionInsightPostureFatigue
PASSES lexical check  visionInsightFrettingTension
PASSES lexical check  visionInsightPostureUnhealthy
PASSES lexical check  visionInsightWristRiskRising
PASSES lexical check  visionInsightShoulderSoreness
PASSES lexical check  visionInsightNerveCompressionProxy
PASSES lexical check  visionInsightPostureRestNeeded
PASSES lexical check  visionInsightFrettingDamageLikely
PASSES lexical check  visionInsightPostureCorrectVsPopulation
```

Vagyis a második védelmi vonal ezekre nulla, és marad az egyetlen emberi
lépés: valaki nem-tiltott osztályt deklarál. (A `visionInsightFrettingDamageLikely`
egy `injuryPrediction`, a `visionInsightPostureRestNeeded` egy `recoveryAdvice`,
a `visionInsightPostureCorrectVsPopulation` pedig ADR 0188 Döntés 4 sértése —
a guard mindhármat átengedné `neutralObservation` deklarációval.)

**Javítás iránya (follow-up, külön kör is lehet):** a deny-list bővítése az
ergonómiai szókinccsel (`strain`, `ache`, `sore`, `fatigue`, `tension`, `numb`,
`nerve`, `tendon`, `carpal`, `overuse`, `damage`, `chronic`, `risk`, `unhealthy`,
`population`), **vagy** — erősebb és e körhöz illőbb — az `InsightCode` szuffix
zárt szótárra kötése (`Stable | Focus | Improved | NotObservable |
Observation`), teszttel kikényszerítve. Ezt a jelentés **nem** blokkolónak,
hanem a katalógus-bővítés első alkalmához kötött hardening-javaslatnak jelöli.

---

## MI4 — MINOR: a 11 új ARB-kulcs `@description` nélkül

**Fájl:** `lib/l10n/app_en.arb:1313-1323`, `lib/l10n/app_hu.arb:1247-1257`.

Az `app_en.arb`-ban ma **89** `@`-metaadat kulcs van, tehát a konvenció létezik;
a 11 új `visionInsight*` kulcs egyikéhez sem tartozik leírás.

**Miért biztonsági lelet:** a gépi guard **sosem** látja az ARB-mondatot — csak
a kódot (`safety_claim_guard.dart:61-100` a `code` stringen dolgozik). A
kód→mondat párosítás helyessége ezért kizárólag emberi fegyelem kérdése, és a
fordítónak/jövőbeli szerkesztőnek jelenleg semmilyen in-file jelzése nincs
arról, hogy `visionInsightPostureFocus` mondata nem sodródhat orvosi/diagnosztikai
irányba (a mai szövegek — lásd a PASS-szakasz — tiszták). Egy `@`-leírás
(„must remain a non-diagnostic, non-predictive observation; see ADR 0188") a
legolcsóbb elérhető kontroll ezen a felületen.

---

## MI5 — MINOR: az azonos prioritású döntetlent lexikai sorrend dönti, a negatív javára

**Fájl:** `lib/features/vision/domain/feedback/cue_budget.dart:41-45`
(és ugyanez a mintázat `feedback_policy_engine.dart:88-94`): döntetlennél
`first.code.safetyCode.compareTo(second.code.safetyCode)`.

**Failure scenario (futtatva — `[E]`):** egy pozitív (`frettingStable`) és egy
negatív (`frettingFocus`) jelölt, mindkettő prioritás 50, mindkettő 0.95:

```
realtimeCue=frettingFocus dir=negative conf=0.95 prio=50
priorities: (frettingFocus:50, frettingStable:50)
```

`'visionInsightFrettingFocus' < 'visionInsightFrettingImproved' <
'visionInsightFrettingStable'` — vagyis az ábécé miatt **rendszeresen** a
kritikai cue nyer a pozitív fölött. Ugyanez hat a session-summaryra:
`feedback_policy_test.dart:82-87` szerint az öt jelöltből mindig a két `*Focus`
kerül be. A viselkedés determinisztikus (a §6 acceptance-t teljesíti), de a
döntetlen-feloldás iránya véletlenszerű melléktermék, és épp szembemegy a réteg
alapelvével („no feedback is better than false feedback" / az aszimmetrikus
küszöb szándékával). Egy szándékos, dokumentált tie-break kulcs (pl. magasabb
confidence, majd stabil kód-sorrend) ugyanolyan determinisztikus, de nem
véletlenül elfogult.

---

## NOTE-1 — a katalógus-bővítés mérten additív (a commit-üzenettől függetlenül)

`git show origin/main:…vision_safety_policy.dart` és `git show HEAD:…` kulcs–érték
párjainak halmaz-diffje:

```
main entries: 9   branch entries: 20
REMOVED: {}       CHANGED: {}       ADDED (11): a 11 visionInsight* kód
```

A `VisionSafetyClaimClass` enum, a `forbidden` halmaz és a **teljes**
`safety_claim_guard.dart` érintetlen (`git diff --stat` a guard-fájlra: üres).
Futtatva (`[probe2]`): `catalog size = 20`, `validateCatalog() = null`,
`forbidden set = (diagnosis, injuryPrediction, painExplanation, recoveryAdvice,
harmfulJudgment)`, és mind az öt tiltott osztály hard-reject a
regressziós próbán.

**Pontosítás az ADR 0191 Döntés 2 „bitre változatlan" megfogalmazásához:** a
meglévő 9 bejegyzés **szövegesen nem** bitazonos — a `catalog =` deklaráció
sortörése miatt a `dart format` az egész map-literált 2 szinttel kijjebb
tördelte (`vision_safety_policy.dart:98-124`), így a diff a 9 régi sort is
`-`/`+` párként mutatja. Kulcs, érték és sorrend **azonos**; a változás
kizárólag whitespace. Ez nem sérti a korlát szándékát, de a „bitre változatlan"
állítás szó szerint nem áll — a jövőbeli körökben érdemes „kulcs–érték szinten
változatlan"-ként fogalmazni, hogy a formázó ne tegye a korlátot hamis
riasztássá.

## NOTE-2 — a `setupNotObservable` ágon nincs confidence-kapu

`feedback_policy_engine.dart:52-55`: a setup-ág kizárólag
`observationState == notObservable`-t néz. Futtatva (`[D]`): 0.0 confidence-szel
is emittál (`setupNotObservable dir=setup conf=0.0 prio=100`). Ez védhető — a
kód osztálya `unobservable`, az ARB-mondat („Adjust the camera setup…") nem
állít semmit a felhasználó testéről, és a „nem látlak" jelzés visszatartása
rosszabb lenne —, de mivel a `FeedbackPolicies._policy` mégis ad neki
0.70-es pozitív küszöböt (`[probe2]`: `setupNotObservable dir=setup
effective=0.7`), amit soha semmi nem használ, a szándékot érdemes egy
komment/teszt-invariánssal rögzíteni, nehogy egy jövőbeli kör „javításnak"
higgye a kapu bekötését.

## NOTE-3 — a `minimumDuration` nem az SDD „cue minimum megjelenési idő"-je

`feedback_policy_engine.dart:48-49` a `policy.minimumDuration`-t az
**evidence-ablak** hosszára alkalmazza
(`candidate.evidence.provenance.window.duration`). Az SDD §23.3 külön
követelménye („cue **minimum megjelenési idő**") ebben a körben nincs
implementálva, és a névazonosság félrevezetheti az R24-et. Ennek hiánya teszi
a B1-et felhasználóig érővé: nincs semmi, ami a setup cue-t a képernyőn tartaná,
amíg a cooldown miatt a technikai kritika átveszi a helyét.

## NOTE-4 — a `declaredClass` override production-hívása

`grep -rn "declaredClass" lib/ test/` mérve: a `lib/` alatt kizárólag maga a
`safety_claim_guard.dart` (definíció + a `validateCatalog()` `:107` hívása)
használja; a kör **egyetlen új fájlja sem** hivatkozik rá, a
`feedback_policy_engine.dart:46` a production ágat hívja override nélkül. A
`validateCatalog()` R20-as kód, ebben a körben változatlan, és nem
claim-emissziós út (csak a katalógus önellenőrzése). A brief §5 pont 6 tilalma
(„a `declaredClass` production-hívási override használata") **betartva**.

---

## Amit végignéztem és tisztának találtam (tételes bizonyítékkal)

Az üres lelet is bizonyíték — az alábbiak nem „nem találtam semmit", hanem
mért PASS-ok:

| Dimenzió | Bizonyíték | Verdikt |
|---|---|---|
| **Katalógus-integritás** | halmaz-diff: 0 törölt, 0 módosított, 11 új; enum + `forbidden` + guard-fájl érintetlen; `validateCatalog() = null` | PASS (NOTE-1 formázási pontosítással) |
| **A 11 új kód osztálya** | mind `unobservable` / `neutralObservation` / `baselineRelative`; egyik sem forbidden; futtatva mind a 11 `allowed=true` a production ágon | PASS (MI1 a `*Focus` osztály-pontosságáról) |
| **A 11 új kód lexikailag** | mind a 10 tiltott lexémára „clean" (mechanikus substring-próba) | PASS |
| **Tiltott-osztály regresszió** | mind az 5 forbidden osztály hard-reject, futtatva | PASS |
| **ARB-tartalom (EN+HU)** | mind a 22 mondat kiírva és átolvasva: nincs diagnózis, jóslat, fájdalom-ok, kezelési tanács, „ártalmas" minősítés vagy populációs „helyes tartás" ítélet; a HU a EN szemantikai párja (nincs olyan magyar mondat, ami az angolnál erősebbet állít) | PASS (MI4 a hiányzó `@description`-ről) |
| **Confidence-aszimmetria terhelése** | `FeedbackPolicy` konstruktora futtatva elutasítja az EGYENLŐ és az INVERTÁLT küszöböt is; a `confidenceThreshold` getter (`feedback_policy.dart:37-39`) a negatív irányt 0.85-re, a pozitívat 0.70-re köti; a shippelt katalógus mind a 3 `*Focus` kódja `dir=negative effective=0.85` | PASS (a KIMENETRE nézve M2 rontja el) |
| **Fail-open ág az engine-ben** | `_accepts` (`:43-67`) nincs `try`/`catch`, nincs default-allow ág; ismeretlen kód → `policy == null` → `false`; a guard minden jelöltre lefut (`:46`), override nélkül | PASS (a megkerülő út MI2, nem az engine-ben) |
| **PII / nyers biometria** | `VisionInsight` mezői: enum kód, konstans `policyVersion` (`'e05-r23-v1'`), `evidenceIds`, `double confidence`, `int priority`, enum irány. Az `evidenceIds` production-ban `VisionEvidence.deterministicId` kimenete: `vision-evidence-<16 hex>` FNV-1a a `metric.key:startUs:endUs`-ből (`vision_evidence.dart:48-62`), a fúzió ezt használja (`observation_fusion.dart:125`). Nincs landmark-koordináta, képbájt, felhasználó-azonosító. A körben **nincs** új `toJson`/szerializáció és nincs perzisztencia. | PASS |
| **Log / analytics / diagnosztika** | `grep -rnE "print\(|debugPrint|developer\.log|Logger|analytics"` a 4 új `lib/` fájlon: nulla találat | PASS |
| **Hálózat / consent** | `grep -rnE "Dio|http|SharedPreferences|SecureStore|KeyValueStore|File\(|Platform\."` a 4 új fájlon: nulla találat; `dart:` import egyik új fájlban sincs. Offline alapélmény nem érintett. | PASS |
| **Ellátási lánc** | `pubspec.yaml` / `pubspec.lock` / `android/` / `ios/` a diffben nem szerepel — nincs új dependency, nincs új permission, nincs új asset | PASS |
| **Titkok** | a teljes `lib/`+`test/` diff `api_key|secret|token|password|bearer|PRIVATE KEY|AKIA|ghp_|sk-` mintákra: nulla találat; új fixture-fájl nincs | PASS |
| **Cross-feature határ (ADR 0188)** | `grep -rn "ai_tutor" lib/features/vision/` → 0; `grep -rn "features/vision" lib/features/ai_tutor/` → 0. A két safety-mechanizmus architekturálisan független marad. | PASS |
| **Prompt injection** | a réteg kimenete zárt enum-kód + hash-ID + szám; nincs szabad szöveg, nincs LLM-hívás, nincs prompt-építés, nincs külső tartalom, ami utasításként értelmeződhetne. A felhasználói/külső tartalom **nem** ér el a rétegig ebben a körben. | PASS |
| **Hibaüzenetek** | 3 `ArgumentError`, mind generikus (`'Feedback policy gates are invalid.'`, `'Practice and capability level are required.'`, `'A version, evidence, and finite confidence are required.'`) — nem szivárogtatnak értéket, azonosítót vagy belső állapotot | PASS |
| **Scope** | `git diff --name-status` 12 fájl = `allowed_paths` 12 bejegyzés, eltérés nincs | PASS |

---

## Merge-döntés

**Merge tilos**, amíg a **B1** nyitva van (`09-review-report.md`: BLOCKER →
„Merge tilos, amíg nyitva van"). Az **M1** és **M2** szintén merge-blokkoló
osztály ugyanezen tábla szerint (MAJOR). A B1 javításának a shippelt tesztet is
korrigálnia kell — jelenleg az kodifikálja a rést, ezért a zöld gate erre a
kritériumra nem bizonyíték.

A MINOR-ok közül a **MI1** és **MI2** a katalógus-szemantikát érinti, ezért
érdemes ugyanebben a javító körben zárni; az **MI3** és **MI4** legitim
follow-up, az **MI5** a javító körben egy sorral zárható.
