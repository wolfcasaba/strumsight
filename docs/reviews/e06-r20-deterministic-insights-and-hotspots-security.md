# E06-R20 biztonsági review — determinisztikus insight-motor és hotspot ranking

- **Kör:** E06-R20 · branch `codex/e06-r20-deterministic-insights-and-hotspots` · HEAD `4aec6d85`
- **Diff:** `7dbaa349..4aec6d85` (16 fájl, +2131/−9 — `git diff --stat $(git merge-base origin/main HEAD) HEAD`)
- **Reviewer:** `security-reviewer` ágens (READ-ONLY, AGENTS.md §15.1 — kötelező, a brief `ai-router` blokkja `risk = "high"`)
- **Referencia-kontraktus:** `docs/rounds/e06-r20-deterministic-insights-and-hotspots.md`, `docs/adr/0238-analysis-insight-evidence-and-ranking-boundary.md`, AGENTS.md §5 / §6 / §15.1
- **Kontext-ADR-ek:** [0141](../adr/0141-ai-tutor-prompt-output-schema-injection-boundary.md) (Tutor prompt injection boundary), [0132](../adr/0132-ai-tutor-privacy-and-consent.md) (privacy/consent, redakció), [0236](../adr/0236-analysis-technique-proxy-safety-and-naming.md) (Lab-only technique proxy), [0216](../adr/0216-analysis-confidence-calibration-and-abstention.md) (abstention). LESSONS: „user strings vs domain transforms".
- **Verifikációs környezet:** izolált worktree `/home/ubuntu/music-theory/.claude/worktrees/agent-a9d534af26080dce7`, a round-branch kicheckoutolva; minden lelet a lenti fájl:sor hivatkozásokkal reprodukálható.
- **Verdikt:** **PASS — nincs CRITICAL, nincs BLOCKER, nincs MAJOR.** 1 × MINOR (jelenben reprodukálható evidence-relevancia defektus) + 4 × NOTE (előre-mutató / defense-in-depth: a modul ebben a körben **egyetlen éles helyen sincs bekötve** — nincs UI, nincs Tutor-adapter, nincs perzisztencia, nincs hálózat, nincs V1-útvonal). A biztonsági oldal a merge-et **nem blokkolja.**

## Osztályozás

| Súlyosság | Darab | Blokkol? |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 1 | nem (körön belül javítható vagy follow-up) |
| NOTE | 4 | nem (a bekötő körre szóló follow-up) |

**Miért nincs MAJOR/BLOCKER:** a fegyelmi szabály szerint csak reprodukálható, éles hívóval bíró lelet emelhető MAJOR fölé. Ez a kör a modult **nem köti be**: a `public.dart` csak kontraktust exportál, és a `grep` szerint a `lib/`-ben **egyetlen** shipping hívó sem példányosítja az `InsightRegistry`/`AnalysisInsightContext`/`InsightRanker`/`HotspotRanker` típusokat (§0). Ezért minden „untrusted bemenet → felhasználónak megjelenő állítás / Tutor-evidence" kockázat a **KÖVETKEZŐ, bekötő körre** szóló NOTE. „Elvileg veszélyes, de nincs éles hívó" = NOTE, nem MAJOR (a precedens: `e99-r07` security review).

---

## 0. Scope- és bekötetlenség-audit (a kör legfontosabb védelmi állítása)

**Diff-scope kimerítő:** a `git diff --stat` pontosan a briefben felsorolt **16 fájlt** adja, semmi mást (10 `lib/`+`docs/`, 4 `test/`, 1 ADR, 1 round-doc). Scope-on kívüli production-változás **nincs**.

**A modul bizonyítottan bekötetlen:**

```text
$ grep -rln "InsightRegistry|buildInitialInsightRules|EvidenceBackedAnalysisInsight|AnalysisInsightContext|InsightRanker|HotspotRanker|RecommendedAnalysisAction|RankedAnalysisInsights" lib/ \
    | grep -v "domain/insights/|engine/insights/|public.dart"
(0 találat)
$ grep -rln "insights/insight_rule|insights/recommended_action|insights/insight_registry|insights/insight_ranker|insights/insight_rules|insights/hotspot_ranker" lib/ \
    | grep -v "public.dart|engine/insights/|domain/insights/"
(0 találat)
```

Az új szimbólumokra a shipping kódban (provider, UI, V1 Analyze, Tutor-adapter, codec) **nulla** hivatkozás. Ez megerősíti ADR 0238 Döntés 1-et („új, önálló és bekötetlen modul") és a brief állítását. Következmény: e körben **nincs** olyan adatfolyam, amelyen felhasználói/importált tartalom eljutna a felhasználóig vagy a providerig.

**Nincs tiltott felület (AGENTS.md §6 — brief 5. pont):** a `domain/insights/` és `engine/insights/` fájlok importjai **kizárólag** testvér-domain-típusok (`analysis_capability`, `analysis_document`, `analysis_hotspot`, `analysis_metric`, `analysis_metric_catalog`, `recommended_action`, `insight_rule`). **Nincs** `dio`/`http`, **nincs** `flutter_riverpod`, **nincs** `flutter_secure_storage`/`KeyValueStore`, **nincs** platform-plugin, **nincs** `dart:io`/`dart:isolate`, **nincs** `logging`/`print`. Tiszta domain/engine Dart. A `grep print|debugPrint|log(|TODO|FIXME` a két új production-könyvtárban **0 találat** → nincs napló-sink, ahol titok/PII/nyers adat kiszivároghatna.

---

## 1. Referenciális-integritás — a factory MÉRTEN nem megkerülhető (brief 3. pont)

ADR 0238 Döntés 2 („minden szabályeredmény referenciálisan zárt") a `AnalysisInsightContext.insight()` factory-n áll (`insight_rule.dart:136–140`): üres `factIds`/`evidenceIds` → `null`; bármely `factId`, amelyre `metric(id) == null`, vagy bármely `evidenceId`, amely nincs a `_evidenceIds` halmazban → `null`. A **publikus** `EvidenceBackedAnalysisInsight` konstruktor (`insight_rule.dart:13–49`) viszont **csak** nem-üresre és `confidence ∈ [0,1]`-re validál — referenciális zártságra **nem**. Tehát a garancia kizárólag akkor áll, ha minden szabály a factory-n megy át, nem a konstruktoron.

**Mérés — mind a kilenc szabály a factory-t hívja, a konstruktort egyik sem:**

```text
$ grep -rn "EvidenceBackedAnalysisInsight(" lib/ | grep -v "insight_rule.dart"
(0 találat)
```

A közvetlen konstruktor-hívás a `lib/`-ben **kizárólag** a factory belsejében fordul elő (`insight_rule.dart:141`). A kilenc `return context.insight(...)` helye: `insight_rules.dart:66, 100, 139, 182, 221, 251, 284, 317, 357`. A brief a `RushBiasInsightRule`-t manuálisan (mutációs próbával) ellenőrizte; a fenti grep a **maradék nyolcat** is lefedi: egyikük sem tudja megkerülni a factory-t, mert nem létezik alternatív konstrukciós hely. ✔

---

## 2. Confidence-keretezés — nincs túlbecsült bizonyosság hiányos/degradált inputból (brief 2. pont)

Két csatornán ellenőriztem: (a) hogy honnan jön a `confidence`, és (b) hogy a felső invariánsok kizárják-e a konstruktor-dobást (robustness/DoS).

- **Metric-alapú szabályok** (`rush_bias`, `drag_bias`, `large_outliers`, `second_half_drift`, `weak_upstroke`, `low_signal`, `compatible_improvement`) a `confidence`-et `context.metric(id)!.confidence`-ből veszik, ahol az `id` egy **használható** metrikáé (`_firstUsableId`/`scalar` előbb `null`-t ad, ha a státusz nem `available`/`degraded` vagy az érték `null` — `insight_rule.dart:83–99`). Az `AnalysisMetricResult` konstruktora a `confidence`-et **`[0,1]`-re kényszeríti** (`analysis_metric.dart:98–100`). A `large_outliers` átlaga `(c1+c2)/2` két `[0,1]` értékből → `[0,1]`.
- **`chord_transition_hotspot`** a `confidence`-et `hotspot.confidence`-ből veszi (`insight_rules.dart:260`); az `AnalysisHotspot` konstruktora ezt is **`[0,1]`-re** kényszeríti (`analysis_hotspot.dart:22–24`).
- **`data.insufficient`** `confidence: 1`-et állít (`insight_rules.dart:365`), de ez **abstention**-állítás („nincs elég időzítési bizonyíték") — a bizonyosság a *hiányra* vonatkozik, nem a játékra; kifejezetten csak akkor tüzel, ha a kötelező timing-metrikák jelen vannak, de **nem használhatók** (`insight_rules.dart:350–354`). Ez ADR 0216 abstention-mintája, nem túlbecslés.

**Következmény 1 (helyes):** nincs olyan szabály, amely `unavailable`/`notApplicable` metrikából `confidence`-et fabrikálna — az abstention-guardok (`scalar`→`null`) mindenhol előbb futnak.
**Következmény 2 (robustness):** mivel minden `confidence`-forrás felső-invariánsból `[0,1]`, a `EvidenceBackedAnalysisInsight` konstruktor `confidence`-dobása (`insight_rule.dart:34–36`) a gyakorlatban **elérhetetlen** — nincs kivétel-alapú DoS a `registry.evaluate` map-jén (`insight_registry.dart:17–22`). ✔

*(Kapcsolódó, alacsony súlyú relevancia-rés a `chord_transition_hotspot` factjainál: lásd NOTE-2.)*

---

## 3. Lab-only `technique.*` kizárás — háromszorosan fail-closed (brief 4. pont)

A brief szerint „az `AnalysisInsightContext` konstruktor-guardja és az `isPublicMetricId` az egyetlen kapu". Mérve: **valójában három, egymással konzisztens, fail-closed kapu** van, és nincs kerülő út a `document.hotspots[].metricIds`-en át.

1. **Context-konstruktor** (`insight_rule.dart:64–66`): ha `document.metrics` **bármely** eleme `technique.`-cal kezdődik → `ArgumentError`. Az egész context elutasítva (fail-closed). Teszt fedi: `analysis_insight_property_test.dart:99–109`.
2. **`metric(id)` lookup** (`insight_rule.dart:76`): `technique.` prefix → `null`. Így a factory `metric(id) == null` ága bármely `technique.*` `factId`-t elutasít.
3. **`isPublicMetricId`** (`insight_rule.dart:253–254`) = `AnalysisMetricId.contains(id) && !id.startsWith('technique.')`.

A katalógus valós adatán ellenőrizve: az öt `technique.*` ID (`analysis_metric_catalog.dart:117–125`, pl. `technique.chord_change_gap.v1`) **tagja** a `known` halmaznak (`:177–181`), tehát a `contains()` önmagában **átengedné** őket — ezért az `isPublicMetricId` extra `!startsWith('technique.')` feltétele **teherhordó**, nem dísz. A verziós utótag (`.v1`) nem rontja el a `startsWith('technique.')`-et.

**A `hotspot.metricIds`-csempészés zárva:** az egyetlen szabály, amely `hotspot.metricIds`-t olvas, a `chord_transition_hotspot`, és ott `facts = hotspot.metricIds.where(isPublicMetricId)` (`insight_rules.dart:249`) → `technique.*` kiszűrve; ha minden metricId `technique.*`, `facts` üres → `null` (`:250`). Utána a factory `metric(id)==null` ágon **másodszor** is elbukna. Kettős védelem. Az `AnalysisHotspot` konstruktora ráadásul katalógus-tagságot követel a metricIds-en (`analysis_hotspot.dart:25–27`), így ismeretlen (nem-katalógus) ID be sem jut. ✔ ADR 0238 Döntés 3 teljesül.

---

## 4. ADR 0238 — a kód a döntéseket követi (brief 6. pont)

| Döntés | Kód-megfelelés | Bizonyíték |
|---|---|---|
| **1** — új, önálló, bekötetlen | Nincs shipping hívó; `public.dart` csak kontraktot exportál; az R02 `AnalysisDocument.insights`/codec **változatlan** (az új modulnak nincs codeca). | §0 grep-ek; `public.dart:67–72` |
| **2** — referenciálisan zárt | Factory nem-üres + létező metric + létező evidence. | §1; `insight_rule.dart:136–140` |
| **3** — `technique.*` kemény kizárás | Háromszoros fail-closed kapu; egy szabály sem importálja a `technique_proxies.dart`-ot. | §3; import-grep §0 |
| **4** — state-mentes, determinisztikus rangsor | `InsightRanker`: priority-index majd lexikografikus `ruleId` (**total order**, mert a `ruleId`-k egyediek — `insight_registry.dart:7–10`); `HotspotRanker`: severity↓, confidence↓, `id`↑. | `insight_ranker.dart:33–37`; `hotspot_ranker.dart:9–14` |
| **5** — csak `messageKey` + string `messageArgs`; sealed action | `EvidenceBackedAnalysisInsight` csak `messageKey` + `Map<String,String>`; `RecommendedAnalysisAction` sealed, plain adat-mezőkkel, `BuildContext`/route/callback nélkül. | `insight_rule.dart:45–46`; `recommended_action.dart:4–41` |

A `Dart` `List.sort` nem stabil, de mindkét ranker komparátora **total order** (egyedi `ruleId`, illetve `id` végső tiebreak), így a determinizmus a stabilitástól függetlenül áll. *(Egyetlen elméleti rés — duplikált hotspot-`id` — lásd NOTE-4.)* ✔

---

## 5. Titkok, PII, fixture-valódiság

- **Titok-minta grep** (`password|secret|api key|token|bearer|BEGIN RSA/EC/OPENSSH/PGP|AKIA|ghp_|sk-|xox…`) az új production-fájlokon, ADR-en és round-docon: **egyetlen** találat, a round-doc `:509` sora, amely a **CI-gate lépéseit** sorolja fel („…architecture, secrets, l10n zöld") — nem valódi titok.
- **Fixture-valódiság** (`insight_fixtures.dart`): a placeholder-értékek szemantikailag **valódi fake-ek** — `fingerprint: 'fixture'`, `dspConfigHash: 'test'`, `appVersion/platform: 'test'`. Nincs valós kulcs/token/PID. A gépi kapu (`tool/ci/check_secrets.dart`) az authoritatív; a szemantikai ellenőrzés is tiszta. ✔
- **Hibaüzenet-szivárgás:** az új kód `ArgumentError`-jai statikus szövegek vagy **korlátozott számérték** (`ArgumentError.value(confidence, 'confidence')`, `[0,1]`); egyik sem echózza a `hotspot.id`-t, `metricId`-t, `messageArgs`-ot vagy bármilyen szabad felhasználói szöveget. ✔

---

## Megállapítások

### F1 — MINOR — `firstEvidenceFor` fallbackje a ténytől független bizonyítékot csatol

- **Fájl:** `lib/features/audio_analysis/domain/insights/insight_rule.dart:101–120` (fallback-ágak: `:110–112` első event, `:113–115` első chord-segment, `:116–118` első hotspot). Fogyasztók: `rush_bias`, `drag_bias`, `large_outliers`, `low_signal`, `data.insufficient` (`insight_rules.dart:64, 98, 137, 282, 355`).
- **Failure scenario (jelenben reprodukálható, éles hívó nélkül):** legyen egy **használható** (`available`) `timing.target_signed_bias.v1` metrika `value = -30` ms-mal, de **üres** `evidence: []` listával (az `AnalysisMetricResult` az üres evidence-t megengedi — `analysis_metric.dart:88–91` nem követel nem-üreset), miközben a timeline-ban vannak eventek. Ekkor `rush_bias` tüzel, `firstEvidenceFor(['timing.target_signed_bias.v1'])` a metrika saját (üres) evidence-listáján túllép, és **a teljes felvétel első eventjének ID-ját** adja vissza — ami nincs ok-okozati kapcsolatban a bias-ténnyel. Az így előálló `EvidenceBackedAnalysisInsight.evidenceIds = [<első event id>]` a *nevében* „evidence-backed", de a csatolt bizonyíték nem a tényt támasztja alá.
- **Hatás / sértett szabály:** ADR 0238 Döntés 2 **betűjét** (az evidence-ID *létezik* a dokumentumban) teljesíti, a **szellemét** (evidence-first) nem. Bekötéskor közvetlenül gyengíti AGENTS.md §5.5-öt („gyenge confidence nem jelenhet meg biztos állításként") és ADR 0141-et („a Tutor csak validált evidence-t kaphat"): egy Tutor a `[<első event>]`-et hivatkozná a bias-állítás bizonyítékaként.
- **Teszt-rés (megerősítő):** a property-gate referenciális-zártság-állítása (`analysis_insight_property_test.dart:88–94`) ezt az ágat **soha nem futtatja**, mert a fixture `metric` helper minden metrikának `evidence: const ['event-1']`-et ad (`insight_fixtures.dart:123`), és `event-1` mindig benne van az evidence-halmazban. A gate tehát zöld marad, miközben a fallback-viselkedést se nem gyakorolja, se nem tiltja.
- **Kötelező javítás iránya:** a `firstEvidenceFor` **ne** essen vissza a globális első event/segment/hotspot ID-ra, ha a ténynek nincs saját, halmazbeli evidence-e — inkább adjon `null`-t (a szabály absztaháljon), vagy a fallback szűküljön a tényhez ok-okozatilag kötött bizonyítékra (pl. a metrika időablakába eső eventekre). Adj egy property/unit tesztet, amely üres/halmazon-kívüli metrika-evidence esetén **nincs insight**-et vagy **tényhez kötött** evidence-t követel.
- **Státusz:** OPEN.

### NOTE-1 — `hotspot.id` szanitálatlanul folyik felhasználónak megjelenő `messageArg`-ba és action-payloadba (brief 1. pont — a bekötő körre)

- **Fájl:** `lib/features/audio_analysis/engine/insights/insight_rules.dart:259` (`messageArgs: {'hotspotId': hotspot.id}`) és `:261–263` (`OpenChordTransitionExerciseAction(hotspotId: hotspot.id)`). A `hotspotId` az ARB-mondatba interpolálódik: `analysisInsightChordTransitionHotspot` = „A chord transition needs focused practice ({hotspotId})." (`app_en.arb`, `app_hu.arb`).
- **Provenance-elemzés (ez teszi éllé a kérdést):** a `hotspot.id`-t az `AnalysisHotspot` konstruktora csak **nem-üresre** validálja (`analysis_hotspot.dart:19`) — nincs charset/hossz/formátum-megkötés. A `hotspot.id` két helyen keletkezik: (a) az éles `buildTimingHotspots` gépi ID-t ad (`'timing-hotspot-' + observed.id`, `timing_hotspots.dart:42`), és **csak `timing`-kind** hotspotot gyárt (`:43`); (b) a codec `_hotspotFromJson` a `id`-t **szó szerint** veszi a JSON-ból (`analysis_document_codec.dart:521`), a `_string` helper pedig **csak típust** ellenőriz (`:609–613`), semmilyen tartalmat. A `chord_transition_hotspot` szabály **kizárólag `harmony`-kind** hotspotot fogyaszt (`insight_rules.dart:247` → `firstChordTransitionHotspot` → `hotspot.kind == harmony`), és **nincs éles `harmony`-hotspot-gyártó** a kódban (`buildTimingHotspots` csak `timing`; `legacy_analyze_adapter.dart:144` üres listát ad). Így a szabály egyetlen lehetséges trigger-forrása a **deszerializáció** — ahol a `hotspot.id` tetszőleges JSON-string (pl. 10 000 karakter, control/RTL-override karakterek, `{placeholder}`-szerű szöveg, „ignore previous instructions…").
- **Failure scenario (a bekötő körre):** ha egy jövőbeli integráció egy **kevésbé megbízható forrásból** (szinkron, megosztott/importált vagy manipulált lokális fájl) dekódolt `AnalysisDocument`-et ad az insight-motornak, a támadó-befolyásolt `hotspot.id` (1) a coaching-mondatban szó szerint megjelenik a felhasználónak, és (2) egy `OpenChordTransitionExerciseAction.hotspotId` payloadba kerül, amit egy jövőbeli UI **kulcsként/route-ként** használhat. Ha egy Tutor-adapter az insight `messageArgs`/evidence-ét a prompt **trusted** szakaszába fűzi, az ADR 0141 Döntés 2 elsődleges injection-vektora valósul meg (untrusted → trusted átfolyás), consent nélkül a providerhez is juthat (ADR 0132).
- **Miért NOTE és nem MAJOR:** ebben a körben **nincs éles hívó**, és nincs bekötött untrusted-dekódolási útvonal, amely idáig érne — így *jelenleg* nem lép át trust-határt. A reprodukálható tény a *szanitálás hiánya* + az, hogy a trigger egyetlen forrása a deszerializáció; a *kár* a bekötéskor kristályosodik ki. (Ugyanez a fegyelem, mint a precedens `e99-r07` NOTE-2-nél.)
- **Teszt-rés:** egyik teszt sem próbál nem-gépi-formátumú `hotspot.id`-t; a két hotspot-teszt a biztonságos `'hotspot-1'`-et drótozza (`insight_rules_test.dart:237, 510`).
- **Javasolt irány (a bekötés ELŐTT kötelező):** a context/document-határon korlátozd a `hotspot.id`-t gépi-ID charsetre/hosszra (fail-closed), **vagy** ne echózd a nyers `hotspot.id`-t felhasználói mondatba (használj pozíció-indexet/címkét); és garantáld, hogy egy jövőbeli Tutor-adapter az insight `messageArgs`/evidence-et **untrusted**-ként kezeli (ADR 0141 D2/D3, ADR 0132). Adj adversarial-`id` tesztet. Ez a „user strings vs domain transforms" LESSONS-minta közvetlen esete.
- **Státusz:** OPEN (a bekötő körre).

### NOTE-2 — `chord_transition_hotspot` factjai `available`-guard nélkül, present-but-`unavailable` metrikára is hivatkozhatnak

- **Fájl:** `lib/features/audio_analysis/engine/insights/insight_rules.dart:249` (`facts = hotspot.metricIds.where(isPublicMetricId)`) — `isPublicMetricId` csak katalógus-tagságot + nem-`technique.`-ot ellenőriz, **használhatóságot (`isUsable`) nem**.
- **Failure scenario:** egy **inkonzisztens** (dekódolt) dokumentumban egy `harmony`-hotspot `metricIds`-e egy olyan publikus metrikára mutat, amely `document.metrics`-ben `unavailable` státuszú. A factory `metric(id) != null` ága (a metrika *létezik*) átengedi, így az insight `factIds`-e egy `unavailable` metrikát idéz, miközben a `confidence` a hotspoté. A `compatible_improvement` szabály ezzel szemben **explicit** `isUsable`-t követel (`:313`) — az inkonzisztencia csak itt áll fenn.
- **Miért NOTE:** csak inkonzisztens (ma kizárólag dekódolt) dokumentummal érhető el; a `confidence` valós (hotspot-alapú, `[0,1]`), így nem „gyenge mint biztos". Éles, önkonzisztens dokumentumban egy metricId-t hivatkozó hotspot implikálja a metrika elérhetőségét.
- **Javasolt irány:** a hotspot-eredetű factokra is követeld meg a `context.isUsable(context.metric(id))`-t, a `compatible_improvement`-tel konzisztensen.
- **Státusz:** OPEN (a bekötő körre).

### NOTE-3 — A randomizált property-gate nem fedi a hotspot-ágat és a `technique.*`-a-hotspot-metricIds-ben esetet

- **Fájl:** `test/property/analysis_insight_property_test.dart:25–35` (a random dokumentum `hotspots` nélkül épül — `buildInsightDocument` alap `hotspots: const []`, `insight_fixtures.dart:79`).
- **Failure scenario:** mivel a property-gate 200 trialja **soha nem** ad hotspotot, a `chord_transition_hotspot` szabály és a `hotspot.id`-passthrough (NOTE-1) teljesen **kívül esik** a randomizált anti-reward-hacking kapun; a HARD (random seed) CI-lépés sem gyakorolja. Külön nincs teszt olyan `harmony`-hotspotra, amelynek `metricIds`-e `technique.*`-ot tartalmaz (az `isPublicMetricId`-szűrő a hotspot-úton így korrekt-kódú, de teszttel nem igazolt — a meglévő technique-teszt csak a `document.metrics`-utat fedi, `:99–109`).
- **Javasolt irány:** bővítsd a property-generátort randomizált `id`-jú `harmony`-hotspotokkal (köztük `technique.*` metricIds-szel és nem-gépi-formátumú ID-kkal), és állítsd, hogy (a) a kimenet referenciálisan zárt marad, és (b) `technique.*` sosem szivárog `factId`-be.
- **Státusz:** OPEN (follow-up).

### NOTE-4 — `HotspotRanker` duplikált `id` esetén nem-specifikált sorrend (determinizmus-rés)

- **Fájl:** `lib/features/audio_analysis/engine/insights/hotspot_ranker.dart:9–14`. A végső tiebreak `left.id.compareTo(right.id)`; azonos `id` + azonos severity + azonos confidence esetén a `List.sort` (nem stabil) sorrendje nem-specifikált.
- **Failure scenario:** két azonos `id`-jú hotspot (malformált/dekódolt dokumentum) sorrendje futásonként eltérhet — ellentétben ADR 0238 Döntés 4 determinizmus-állításával. Éles úton a `hotspot.id`-k egyediek (`observed.id`-ből származnak), így gyakorlati hatás nincs.
- **Javasolt irány:** vagy dokumentáld, hogy a duplikált hotspot-`id` kontrakton kívüli, vagy kényszerítsd/asszertáld az `id`-egyediséget a document/ranker határon.
- **Státusz:** OPEN (follow-up, alacsony súly).

---

## Amit végignéztem és a bizonyíték (üres-lelet-fegyelem)

| Ellenőrzés | Módszer | Eredmény |
|---|---|---|
| Diff-scope kimerítő (16 fájl) | `git diff --stat` merge-base ellen | scope-on kívül **0** production-változás (§0) |
| Modul bekötetlensége | szimbólum- és import-grep a `lib/`-ben | **0** shipping hívó (§0) |
| Tiltott felület (Dio/Riverpod/storage/plugin/log) (brief 5) | import-grep + `print/log/TODO` grep | csak testvér-domain import; **0** sink (§0) |
| Factory nem megkerülhető (brief 3, mind a 9 szabály) | `EvidenceBackedAnalysisInsight(` grep a factory-n kívül | **0** közvetlen konstruktor-hívás (§1) |
| Confidence nem túlbecsült hiányos inputból (brief 2) | forrás-követés + felső `[0,1]` invariáns | abstention-guardok mindenütt; konstruktor-dobás elérhetetlen (§2) |
| `technique.*` kemény kizárás (brief 4) | 3 kapu + katalógus valós adat + hotspot-út | háromszoros fail-closed; smuggling zárva (§3) |
| ADR 0238 D1–D5 kód-megfelelés (brief 6) | döntésenkénti fájl:sor összevetés | mind az öt teljesül (§4) |
| Titok/PII/fixture-valódiság | titok-minta grep + fixture-szemantika + hibaüzenet-audit | **0** valódi titok; fake-ek valódiak; hibaüzenet nem echóz (§5) |
| Rangsor-determinizmus | komparátor total-order elemzés | determinisztikus (egy duplikált-`id` rés: NOTE-4) (§4) |
| Evidence-relevancia (`firstEvidenceFor`) | fallback-ág + property-gate lefedettség | ténytől független evidence lehetséges (F1 MINOR) |
| `hotspot.id`/`metricId` messageArg-provenance (brief 1) | két konstrukciós hely + codec `_string` + kind-elemzés | numerikus/katalógus-argok biztonságosak; `hotspot.id` szanitálatlan, forrása a dekódolás (NOTE-1) |

**Következtetés:** a kör mind az öt kötött ADR 0238-döntést és a brief hat kiemelt biztonsági invariánsát **mérve** teljesíti; a referenciális-zártságot (mind a 9 szabály), a `technique.*` kizárást (háromszoros fail-closed), a confidence-korlátokat és a bekötetlenséget önállóan igazoltam. **Nincs CRITICAL/BLOCKER/MAJOR.** Egy MINOR (evidence-relevancia) jelenben reprodukálható; a négy NOTE a KÖVETKEZŐ, bekötő körre szóló előre-mutató teendő — közülük a NOTE-1 (`hotspot.id`-szanitálás) a bekötés ELŐTT rendezendő, mert a `chord_transition_hotspot` trigger egyetlen forrása a deszerializáció. **Biztonsági verdikt: PASS — a merge nem blokkolt biztonsági okból.**
