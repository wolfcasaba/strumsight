# E13-R29 review — Coach Home, Tutor és Debrief UI

- **Kör:** `E13-R29` (Chapter 13, Kör 29)
- **Ág:** `sonnet-impl/e13-r29-coach-tutor-and-debrief`
- **Reviewer:** Claude (Opus 5), orchestrátor-session — READ-ONLY, production-kód
  nem módosult a review alatt (ADR 0055)
- **Implementer:** `sonnet-impl` (Claude Sonnet 5, `tools/mm-round.sh`)
- **Base → HEAD:** `388cdc2f` → `8e9490d4` (22 fájl)
- **Kockázat:** `risk = "high"` → a `security-reviewer` ügynök futtatása KÖTELEZŐ
  volt, és lefutott (lásd §4)

## 1. VÉGSŐ DÖNTÉS: **APPROVED**

0 BLOCKER · 0 MAJOR · 2 MINOR · 3 NOTE. Nyitott BLOCKER/MAJOR nincs, a merge
nincs blokkolva.

## 2. A mérce — a SAJÁT mérésem, nem az implementer bemondása

Az implementer futása a wrapper **3600 s abszolút időkorlátjába** ütközött
(`status=timeout`, `.codex-round-status`), miközben a §10 handoff zöld kaput
állított. A `timeout` jelzés mellett a §10 állítása **bizonyítatlan**, ezért a
teljes mércét újrafuttattam. A jelzésfájl mért mezői:

```
status=timeout   dirty_files=0   gate_shape=ok
scope_audit=ok   scope_audit_base=f9cd1a4e   scope_audit_changed=22
head=8e9490d4    branch=sonnet-impl/e13-r29-coach-tutor-and-debrief
```

### 2.1 A kör kapuja — újrafuttatva, TELJES egészében

`tools/round-gate.sh` a brief §7 szerinti mind a 12 teszt-útvonalon,
külön processzekben, csonkítatlanul (`GATE_EXIT=0`):

| Lépés | Eredmény |
|---|---|
| format · analyze | zöld · zöld |
| `test/features/tutor/ai_mode_visibility_test.dart` | zöld |
| `test/features/tutor/streaming_announcement_test.dart` | zöld |
| `test/features/tutor/tool_confirmation_test.dart` | zöld |
| `test/features/tutor/prompt_injection_ui_test.dart` | zöld |
| `test/features/ai_tutor/presentation/` (11 pinnelt teszt) | zöld |
| `test/app/navigation/adaptive_scaffold_test.dart` | zöld |
| `test/app/offline_network_guard_test.dart` | zöld |
| `test/ui/ui_inventory_test.dart` | zöld |
| `test/core/architecture_dependency_test.dart` | zöld |
| `test/tooling/{dio_factory,preferences_plugin_import,route_literal}_guard_test.dart` | zöld |
| architecture · secrets · l10n | zöld · zöld · zöld |

### 2.2 Golden a KAPU architektúráján (ADR 0426 §2–§3)

`tools/golden-x86.sh check test/ui/goldens/e13_r29_screens_golden_test.dart`
→ **6/6 zöld** (`GOLDEN_EXIT=0`), Flutter 3.44.2 / linux/amd64. A 6 PNG
(3 képernyő × {compact 412×915, `textScaleFactor` 2.0}) commitolva. A
`--update-goldens` **nem** futott — az ARM-felvétel tiltása betartva.

### 2.3 Scope-audit

`scope_audit=ok`, 22 fájl, mind a brief `allowed_paths`-án belül. Külön
ellenőrizve: a `lib/core/design_system/**`, `lib/features/ai_tutor/application/**`
és `…/domain/**` **érintetlen** — a kör a design system komponenseit kizárólag
a `public.dart` barrelen át importálja.

## 3. Az acceptance-mátrix — leletenként ellenőrizve

| # | Kritérium | Verdikt | Bizonyíték |
|---|---|---|---|
| A1 | AI-mód mindig látható | ✅ | `tutorAiModeFor()` (`tutor_providers.dart`), Home-kártya + Chat AppBar **és** üzenet-szint; `ai_mode_visibility_test.dart` zöld |
| A2 | Tool-akció nem fut megerősítés nélkül | ✅ | `confirm()` EGYETLEN hívási helye a sheet `onConfirm`-je (`tutor_action_card.dart:418`); a cella `executor.actions`-t mér, nem widget-típust |
| A3 | A visszahívás pontosan egyszer fut | ✅ | `tool_confirmation_test.dart:125` `hasLength(1)`; a sheet `guardedOnConfirm` + a `_confirm` state-őre kettős védelem |
| A4 | Nem megbízható tartalom sem indít akciót | ✅ | `prompt_injection_ui_test.dart` zöld; a modell-szöveg `sanitizeTutorDisplayText`-en át, markup-inert `Text`-ben |
| A5 | Összevont streaming bejelentés | ✅ | állandó `Semantics(liveRegion: true)`, sosem a növekvő szöveg; `streaming_announcement_test.dart` zöld |
| A6 | Terv-módosítás diff-fel | ✅ | `_confirmAndCommit` → sheet; `onSave`/`onStart` KIZÁRÓLAG `onConfirm`-ből; a diff az EREDETI `widget.draft` ellen mér |
| A7 | Nincs analitikába küldött beszélgetés | ✅ | a `lib/` diffen `analytics\|logEvent\|telemetry\|Sentry\|print\|debugPrint` → **0 találat** (saját grep + a security-reviewer független mérése) |
| A8 | A hiányzó bizonyíték kimondott | ⚠️ **MINOR-1** | a jelzés MEGVAN és mér, de TÍPUS-alapú, nem TARTALOM-alapú — lásd lent |
| A9 | Golden mindkét keretben, commitolva | ✅ | §2.2 |

### 3.1 A §6.1 kötelező valódi-sértés próba — elvégezve és hiteles

Az implementer a `_TutorToolConfirmationCardState.build()` `onAction`-jét
`_openSheet` helyett `_confirm`-re cserélte (a sheet KIHAGYÁSA), és az **A2**
cella pirosra váltott a §10-ben idézett tényleges kimenettel
(`Found 0 widgets with type "SsToolConfirmationSheet"`), majd visszaállt. A
visszaállást a `dirty_files=0` és a saját, zöld gate-futásom is igazolja.

### 3.2 A §0.0/B4 dedupe-csapda elkerülve

A „küszöb fölött" cella **két külön `clientActionId`-val** dolgozik
(`'above-1'`, `'above-2'`, `tool_confirmation_test.dart:130-170`), ezért a
szolgáltatás `_confirmedClientActionIds` dedupe-ja NEM ad hamis zöldet — pont
az a hibaosztály, amit a pre-flight §0.0/B4 megjelölt.

### 3.3 A §0.0/B9 gépi őr MŰKÖDÖTT

A `7efa1059` commit mért bizonyíték: a `TutorHomeScreen` `ConsumerWidget`-té
alakítása elbuktatta a **listán kívüli, pinnelt**
`test/app/navigation/adaptive_scaffold_test.dart`-ot, és az implementer a SAJÁT
kódját állította vissza — nem a tesztet írta át, nem `skip`-elte. A B9 döntése
(a pinek `gate_tests`-be, `allowed_paths`-ra NEM) ezzel a körrel igazolódott:
a lelet a LOKÁLIS kapun jött elő, nem CI-only leletként.

## 4. Biztonsági review (kötelező, `risk = "high"`)

A `security-reviewer` ügynök független futása: **PASS** — 0 CRITICAL, 0
BLOCKER, 0 MAJOR. Végigmérte a megerősítés-megkerülést (minden `confirm()`
hívási hely), a prompt/tool-injekciót, az adatvédelmi határt (ADR 0287 §7), az
idempotenciát és a bizonyíték-hamisítást. Kiemelt megállapítása: a kör a
megerősítési felületet **ténylegesen keményíti** — a `plan-save`/`plan-start`
korábban KÖZVETLENÜL hívta a callbacket, most a sheet mögött van.

## 5. Leletek

### MINOR-1 (A8) — a „nincs mért bizonyíték" jelzés TÍPUS-alapú, nem TARTALOM-alapú

**Hol:** `lib/features/ai_tutor/presentation/widgets/tutor_message_bubble.dart:24-35`
(`_hasEvidence` / `_showsMissingEvidenceNotice`).

**Mit mértünk:** a `_hasEvidence` csak a blokk TÍPUSÁT nézi
(`TutorEvidenceBlock` / `TutorSourceBlock` / `TutorMetricBlock` jelenléte), a
tartalmát nem. A három konstruktor (`tutor_content_block.dart:106,128,148`) és
a perzisztencia-codec `_requiredString`-je (`tutor_conversation_codec.dart:378`)
az üres `""`-t is elfogadja, tehát egy `TutorEvidenceBlock(evidenceId: '',
summary: '')` blokkot hordozó, lezárt tanár-üzenet `_hasEvidence == true`-t ad
→ a figyelmeztetés **elmarad**, miközben valós bizonyíték nincs. A
`TutorChatScreen` render-fáján keresztül elérhető.

**Miért MINOR és nem MAJOR:** kihasználásához a modellnek/ingesztálásnak üres
evidence-blokkot kell előállítania, és az üres blokk **láthatóan üresen**
renderelődik — a felhasználó nem kap hamis tartalmat, csak a kimondott
figyelmeztetés marad el. Az ADR 0287 §8 elve sérül, a §5 adatvédelmi határa nem.

**Ez a [L403](../LESSONS.md#l403) hibaosztálya**, amit a brief §6.1-e KI IS
MONDOTT — de kifejezetten az A2/A3 cellákra szabva („a végrehajtás TÉNYÉT
mérjék"), és ott az implementer hibátlanul be is tartotta. Az A8 nem kapta meg
ugyanezt az előírást; a hiány tehát a BRIEF-é, nem az implementeré.

**Javítás iránya (követő kör):** `_hasEvidence` az érdemi tartalmat mérje
(`evidenceId.trim().isNotEmpty && summary.trim().isNotEmpty`, source/metric
megfelelője), VAGY az üres evidence-blokk már a konstruktorban/ingesztálásnál
elutasításra kerüljön. Mérő cella: üres evidence-blokkos üzenet → a
figyelmeztetés MEGJELENIK.

### MINOR-2 — a kör két tool-akció-kártyája továbbra sincs bekötve

**Hol:** `lib/features/ai_tutor/presentation/widgets/tutor_action_card.dart`
(`TutorActionCard`, `TutorToolConfirmationCard`).

**Mit mértünk:** `grep -rn "TutorActionCard\|TutorToolConfirmationCard" lib/`
→ egyik osztálynak SINCS fogyasztója a `lib/` fán; `git grep` a base
`388cdc2f`-en ugyanez. Tehát **nem regresszió**: a legacy kártya sem volt
bekötve, a kör nem távolított el élő huzalozást, és élő megkerülési út SEM
keletkezett (a tutor chat ma nem renderel action-proposalt).

**Miért nem MAJOR:** a bekötés a `TutorChatState`-be egy proposal-folyamot
kívánna, ami a `lib/features/ai_tutor/application/**` rétegben él — a kör §3
szerinti **tilos zónája**. A bekötés tehát scope-sértés (H3) lett volna; az
implementer helyesen döntött. A hiány a Ch5/Epic-4 (tanár-pipeline) sávjára
tartozik, nem erre a UI-körre.

### NOTE-1 — az AI-mód konnektivitásból származtatva „cloud"-ot mondhat lokális válaszra

`tutor_providers.dart` `tutorAiModeFor()`: a mód `isOnline ? cloud : local` (a
`fallback` kivételével). Produkcióban ma kizárólag a
`LocalTutorModelGatewayStub` van bekötve, tehát egy online, ténylegesen
lokálisan megválaszolt turn „cloud"-ként jelenhet meg. **Adatvédelmileg
konzervatív irányú** (túlbecsli a felhő-használatot, sosem rejti el az
eszközelhagyást), ezért nem ADR 0287 §5 sértés. A §0.0/B6 kifejezetten ezt a
két meglévő jelet engedte a kör számára; a proveniencia-alapú levezetés a
tanár-réteget érintené (tilos zóna).

### NOTE-2 — forrás-blokk cím/hivatkozás nem sanitizált (PRE-EXISTING)

`tutor_message_bubble.dart:180` (`'${b.title} (${b.reference})'`) — a diff
**nem érinti**, markup-inert `Text`, nincs aktiválható link. Konzisztencia
kedvéért érdemes lenne `sanitizeTutorDisplayText`-en átvinni; biztonsági
kockázat nincs.

### NOTE-3 — a brief-lint `S11` lelete szándékosan nyitva marad

A pre-flight §0.0/B9 a lint MÁSODIK ágát választotta (a kör MÓDOSÍT, nem cserél
típust), mert az első ág (a pinek `allowed_paths`-ra vétele) az orchestrátornak
tágítás, azaz H3 ([L478](../LESSONS.md#l478)). A lint `--level base` (a CI-kapu
szintje) **tiszta**. A kör lefutása igazolta a döntést (§3.3).

## 6. Merge-előfeltételek

| Feltétel | Állapot |
|---|---|
| Független review, 0 nyitott BLOCKER/MAJOR | ✅ (ez a dokumentum) |
| `security-reviewer` (risk=high) | ✅ PASS |
| `tools/round-gate.sh` a §7 szerint, saját futás | ✅ `GATE_EXIT=0` |
| Golden a kapu architektúráján | ✅ 6/6 zöld |
| Scope-audit | ✅ `ok`, 22 fájl |
| exact-SHA Full Gate a merge SHA-n | a merge-lépésben |
| exact-SHA Router CI a merge SHA-n | a merge-lépésben |
