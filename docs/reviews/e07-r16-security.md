# E07-R16 — Security review

- **Kör:** E07-R16 — Progression és regression policy (Epic 7, AI Practice Generator)
- **Brief:** `docs/rounds/e07-r16-progression-policy.md` (`risk = "high"`)
- **Diff:** `git diff ea6569fb..29be136a` (branch `terra/e07-r16-progression-policy`, 7 fájl, +1015 sor)
- **Head:** `29be136a` · **Base:** `ea6569fb`
- **Reviewer:** Claude (security-reviewer, READ-ONLY) · **Dátum:** 2026-08-16

## Verdikt

**PASS** — CRITICAL: 0 · BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 2

A kör tiszta, unwired domain-logika: nincs hálózat, fájl-I/O, óra, `Random`,
perzisztencia, log- vagy serializálás-sink, és nincs production hívója
(`AdaptationDecider`/`AdaptationDecision`/`AdaptationRequest` fogyasztója
`lib/`-ben nulla — a `practiceGeneratorEnabled`/`plannerAssistEnabled` flag-ek
`false`-ban). A legérzékenyebb termékhatár — **discomfort/fájdalom sosem
írható felül teljesítménnyel** (AGENTS.md §5 „jóllét", ADR 0265 §3) — mind
szerkezetileg, mind adverzáriális teszttel bizonyítottan teljesül. A két NOTE
kizárólag jövőbeli, még be nem kötött integrációs pontra vonatkozik; egyik sem
blokkol.

## Scope-audit (persona + 09-review-report §2)

`git diff --name-only` = 7 fájl, mind az `ai-router` `allowed_paths`-on belül:

| Fájl | Engedélyezett | Megjegyzés |
|---|---|---|
| `docs/rounds/e07-r16-progression-policy.md` | ✅ | handoff (§10) |
| `.../domain/model/adaptation_decision.dart` | ✅ | ÚJ modell |
| `.../domain/policy/progression_policy.dart` | ✅ | ÚJ policy |
| `.../domain/service/adaptation_decider.dart` | ✅ | ÚJ döntéshozó |
| `.../practice_generator/public.dart` | ✅ | barrel +3 export |
| `test/.../adaptation/adaptation_decider_test.dart` | ✅ | gate teszt |
| `test/.../adaptation/progression_policy_test.dart` | ✅ | gate teszt |

Listán kívüli változás: **nincs.** A `test/fixtures/practice_generator/adaptation/`
engedélyezett útvonal használatlan (nem került fixture-fájl a diffbe) — ez nem
sértés. `docs/adr/**`, más `lib/features/**`, `tools/**`, `.github/**`
érintetlen.

## Termékhatár-ellenőrzés (a brief kiemelt kérdései + AGENTS.md §5)

### 1. Discomfort MINDIG blokkolja az emelést (a legkárosabb hiba ellen — ADR 0265 §3)

**Bizonyíték — szerkezeti.** `adaptation_decider.dart:19–112` `decide()`
egyetlen, korai-visszatérésű őrlánc, egyetlen `advance` ággal
(`adaptation_decider.dart:105–111`; grep: pontosan 1 db `AdaptationAction.advance`).
A discomfort-őr (`:37–47`) **az egyetlen advance ág ELŐTT** `maintain`-nel
tér vissza, és `_hasDiscomfort` (`:135–139`) **egyáltalán nem olvas
teljesítményt** — csak `discomfort?.category != none`-t. Az explicit „túl
nehéz" (`selfReport` + `frustration`) ág (`:27–35`, `_hasExplicitTooHard`
`:129–133`) még ez előtt `regress`-el. Következésképp az `advance` ág (`:105`)
kizárólag akkor érhető el, ha `_hasDiscomfort(validEvidence) == false`. Nincs
olyan kódút, amelyen erős teljesítmény felülírhatná a discomfortot.

**Bizonyíték — adverzáriális teszt.** `adaptation_decider_test.dart:152–171`
(A4): az `evidence(3, discomfort: pain)` a helper alapértelmezett
`performance: 0.9`-ét is megtartja, így mindhárom evidence sikeresnek számít
(`successCount = 3 >= min 3`), `uncertainty = 0.1 (<= 0.4)`, nincs cooldown —
**minden emelési előfeltétel teljesül**, a döntés mégis `maintain` +
`discomfortBlocksAdvance`. Ez pontosan az „erős teljesítmény ELLENÉRE fáj"
forgatókönyv; a teszt piros lenne, ha a discomfort-őrt eltávolítanák vagy az
advance mögé sorolnák.

### 2. Van-e mód a tanulót fájdalom ELLENÉRE nehezíteni? — NINCS

Az `_advance` (`:159–166`) az egyetlen nehezítő transzformáció, és csak a
`:105` ágból hívódik, ami — az 1. pont szerint — discomfort esetén elérhetetlen.
`safetyBlocked` (`:49–57`) szintén `maintain`, az advance előtt. A többlépéses
ugrás gépi lehetetlen: `maximumDifficultyStep` konstruktora `_requireOneStep`
(`progression_policy.dart:175–184`) `!= 1`-re dob — tehát még hibás/rosszindulatú
hívó sem tud 2 fokot lépő policyt építeni (tesztelve:
`progression_policy_test.dart:55–58`).

### 3. Szabad szöveg / PII perzisztálás vagy logolás — NINCS

- `AdaptationDecision` (`adaptation_decision.dart:187–209`) kizárólag
  strukturált mezőket hordoz: `action`/`reasons` (enum + stabil `code`),
  `current`/`next` (`DifficultyProfile` — csupa `int`/`bool`), `evidenceIds`
  (charset-zárt id-k, lásd lentebb), `policyVersion` (fix string konstans).
  Nincs `note`, nincs nyers self-report szöveg.
- `AdaptationRequest` (`:123–184`) ugyanígy: `skillId`, `DifficultyProfile`,
  `SkillEstimate`, `SkillEvidence` lista, `DateTime`-ok, `bool`. Nincs
  free-text mező.
- A forrás-oldalon (`skill_evidence.dart`, R05/ADR 0260) a `DiscomfortReport`
  **szándékosan mezőtelen a szövegre**: „intentionally has NO free-text field
  … a learner's self-report note is transient input at the ingestion boundary
  … and is discarded there". A decider csak `discomfort?.category`-t
  (`DiscomfortCategory` enum: none/tension/pain/fatigue/frustration) olvas.
  Nyers `discomfortNote` tehát ide már nem is jut el.
- `evidenceIds` = `sourceOutcomeId.value` (`adaptation_decider.dart:20–22`);
  az `OutcomeId` a `_validateId`/`_validIdPattern`
  (`planner_ids.dart:158`, `^[A-Za-z0-9._:-]+$`) charset-zárral épül — nincs
  szóköz, sortörés vagy szabad szöveg.
- **Sink-hiány igazolva:** grep a 3 új lib-fájlon `print|log|logger|toJson|`
  `toString|jsonEncode|debugPrint|stderr|stdout` — NULLA találat. Nincs mit
  szivárogtatni; a modellek tisztán memóriabeli domain-objektumok.
- Hibaüzenetek (`ArgumentError.value(...)`) csak strukturált domain-értékeket
  visszhangoznak (skillId mint katalógus-id, numerikus szintek) — nem secret,
  nem PII, nem szabad szöveg; ráadásul konstruktor-idejű programozói hibák,
  nem futásidejű user-facing üzenetek, és nincs log-sink.

### 4. Secret / token / kulcs a diffben — NINCS

A hozzáadott `lib/`+`test/` sorokon `secret|token|api_key|password|`
`private_key|bearer|authorization|aws_|sk-…` mintára nulla találat (a gépi
`secrets` kapu is zöld volt). A tesztek csak beszédes domain-literálokat
használnak (`'skill.chordChanges'`, `'outcome-1'`) — ezek valódi fixture-adatok,
nem álcázott titkok.

### 5. Gyenge confidence nem jelenik meg biztos állításként (AGENTS.md §5)

A bizonytalanság-kapu (`adaptation_decider.dart:69`) `uncertainty > max` →
`maintain (insufficientConfidence)`. A `SkillEstimate.uncertainty`
konstruktora `_unitInterval` (`skill_estimate.dart` — `!isFinite || <0 || >1`
→ dob), így a kapu **nem tud NaN-ra fail-open-ozni** (a klasszikus
`NaN > x == false` csapda konstrukcióból zárva). Az `unknown()` becslés
`uncertainty = 1`-et állít → mindig `> 0.4` → sosem emel. Ismeretlen/bizonytalan
skill tehát soha nem lép fel. Ugyanez zárja a `performance.value`/`confidence`
NaN-t is (`skill_evidence.dart` `isFinite`-őrök), így `_successCount`/
`_struggleCount` (`:141–157`) sem nyílik meg NaN-on.

### 6. Fail-closed input-integritás (kiegészítő pozitívum)

`AdaptationRequest` dob üres evidence-re (`:143–149`), skill-id eltérésre
becslésnél és evidence-nél (`:136–142`, `:150–158`), és duplikált
`sourceOutcomeId`-ra (`:159–165`). `AdaptationDecision` dob üres `reasons`-re
(`:198–201`) és üres `evidenceIds`-re (`:217–227`). Így döntés **sosem** jöhet
létre evidence-hivatkozás és indok nélkül (a §5.6 magyarázhatóság-határ
fail-closed módon érvényesül).

## Megállapítások

### N1 — NOTE — A discomfort-blokk a `validUntil` lejáratot tiszteli

- **Fájl:** `adaptation_decider.dart:23–25` és `:37` (`validEvidence` szűrő);
  `skill_evidence.dart` `isValidAt` (`validUntil == null || asOf <= validUntil`).
- **Megfigyelés:** a discomfort- és „túl nehéz"-őr a `validEvidence`-en fut
  (ugyanaz a szűrő, mint a siker/küzdelem számlálókon). Ha egy discomfort
  self-report `validUntil`-ja `asOf` elé kerül, kiöregszik és többé nem
  blokkol. Ez önmagában konzisztens és védhető (a régi fájdalom nem blokkolhat
  örökké), és **nem** e diff hibája — a decider a helyesen érvényes evidence-t
  használja.
- **Failure scenario (jövőbeli):** ha a majdani ingesztáló/orchestrátor kör
  (Kör 18) túl rövid `validUntil`-t rendel a discomfort-jelekhez, egy még
  releváns fájdalomjelzés kieshet, és elég friss siker-evidence mellett
  emelés következhet. Bemenet: N érvényes siker + 1 lejárt `pain` evidence,
  alacsony `uncertainty`, nincs cooldown → `advance`.
- **Irány:** a jövőbeli ingesztációs kör válasszon olyan érvényességi ablakot a
  discomfort self-reportokhoz, amely nem öregíti ki idő előtt a fájdalomjelet
  (vagy kezelje a discomfortot „sticky"-ként explicit törlésig). A decider
  változtatást nem igényel.
- **Státusz:** OPEN (forward-looking, unwired — ma nincs hívó).

### N2 — NOTE — Self-reportált `pain` → `maintain`, nem `regress`

- **Fájl:** `adaptation_decider.dart:129–133` (`_hasExplicitTooHard` csak
  `frustration`-re regressz) vs `:135–139` (minden más discomfort → `maintain`).
- **Megfigyelés:** az explicit „túl nehéz" gyors-regress ág kulcsa a
  `selfReport + frustration`. A `selfReport + pain` így nem a regress-ágra, hanem
  a `maintain`-re fut (blokkolja az emelést, de nem könnyít). Ez
  **spec-konform** (ADR 0265 §3 = „nincs nehezítés" = `maintain` elég; a brief
  §5.5 a regresszt kifejezetten az explicit „túl nehéz"/frustration jelre
  tartja fenn) és **nem termékhatár-sértés** — semmilyen úton nem nehezít
  fájdalom ellenére.
- **Irány:** amikor egy hívó bekötésre kerül, a jólléti/UX-review erősítse meg,
  hogy a „pain → tartás" (nem „pain → könnyítés") szándékolt viselkedés. Ha a
  szándék a fájdalomra való azonnali könnyítés, a `_hasExplicitTooHard`
  bővíthető a `pain`/`tension` kategóriákra.
- **Státusz:** OPEN (forward-looking, product/UX döntés — nem blokkoló).

## Gate- és bizonyíték-ellenőrzés

| Gate | Állított | Ellenőrizve |
|---|---|---|
| Scope (allowed_paths) | listán belül | ✅ `git diff --name-only` |
| Secret-scan | zöld | ✅ diff-grep, nulla találat |
| Domain-tisztaság | nincs I/O/net/clock/random | ✅ grep a 3 lib-fájlon, nulla |
| Sink-hiány (log/serialize) | nincs | ✅ grep, nulla |
| A4 discomfort-blokk | teszt fedi | ✅ `adaptation_decider_test.dart:152–171` |
| Egy-lépés cap | teszt fedi | ✅ `progression_policy_test.dart:55–58` |
| Célzott tesztek + full suite/property/APK | round-gate PASS lokálisan; teljes suite CI | ⏳ CI (ADR 0053) — a merge-bar így is CI-zöldet követel |

A lokális heavy-suite futtatása nem e review dolga (CLAUDE.md/ADR 0053: teljes
suite + property gate + APK CI-ben). Lelet híján nincs reprodukálandó hiba; a
POZITÍV állításokat statikus nyomkövetés + az adverzáriális A4 teszt
konstrukciója igazolja.

## Merge-döntés

ADR 0052: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → **merge engedélyezett**
(a CI teljes-suite zöld feltételével). Biztonsági/adatvédelmi/prompt-injection
szempontból nincs blokkoló lelet. A prompt-injection felület N/A: e kör nem
érint AI-providert, tool-callingot, tudásbázist vagy külső tartalmat — tisztán
determinisztikus, strukturált domain-döntés.
