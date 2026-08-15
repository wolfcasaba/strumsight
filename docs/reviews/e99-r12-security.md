# E99-R12 (GOV-30c-4) — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** E99-R12 — Dokumentum-összeállítás és insights (GOV-30c-4)
- **Branch:** `codex/e99-r12-gov-30c-4-document-assembly-and-insights` @ `b376dbe9b001477b87d95aabc91541d69ee45db1`
- **Baseline:** `origin/main` @ `8ece7327c84618063caf16c60ad74801031e6c4b` (= merge-base; a diff lineáris a baseline fölött, a baseline a HEAD közvetlen szülője)
- **Reviewer:** Claude (security-reviewer, READ-ONLY — AGENTS.md §15.1)
- **Kötelezettség:** a brief `risk = "high"` → dedikált security review kötelező (CLAUDE.md / AGENTS.md §15.1)
- **Dátum:** 2026-08-15
- **Verdikt:** **PASS** — 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 0 MINOR, 2 NOTE (előretekintő)

---

## Összefoglaló

Tisztán számítási, on-device engine-bővítés az Audio Analysis V2 láncban: két új stage (`DocumentAssemblyStage`, `InsightsStage`) a `document_stages.dart`-ban, egy opcionális immutable `document` mező a munkaállapotban, és a fázis-térkép 18→20 stage-re bővítése. **Nincs** hálózat, mic/kamera, nyers-audio export, secret, auth, AI-provider, prompt, tool-calling vagy logolás érintés (grep + olvasás + scope-audit igazolva). A lánc terméke, az `AnalysisDocument`, **bekötetlen**: az `analysisV2RunnerProvider` a kör után is `StateError`-t dob (`application/analysis_providers.dart:213-215`), és az `application/` byte-azonos a baseline-nal — így a dokumentumot MA semmi nem fogyasztja, szerializálja, exportálja vagy továbbítja. Minden észrevétel ezért **latens** (előretekintő), éles adatútja nincs.

A kör a három legvalószínűbb, korábban mért hibaosztályt **helyesen kerüli el**:

1. **Nincs kitalált érték hiányzó nyersanyag helyett (ADR 0253 §3 / A6).** A `metrics` változatlanul, pass-through kerül a dokumentumba (üres marad, ha üres); a hiányzó pitch-nyersanyag capability-je `unavailable` + confidence 0 (nem hamis-pozitív); a hiányzó `beatGrid`/`tempoCurve` üres listát ad (a hiány őszinte reprezentációja, nem kitalált érték); a hiányzó `signalQuality` esetén a stage **dob** (`document_stages.dart:83-86`), nem defaultol. Reprodukálva a suite A6 és „minden degradálható elbukott" celláival.
2. **Az insight-szabályok a PUBLIKÁLANDÓ dokumentumpéldányt kapják (A3).** Az `InsightsStage` a `preliminary = input.document` **ugyanazon** példányát adja át a kontextusnak (`document_stages.dart:161-165`), és a végleges dokumentumot ennek minden mezőjét megőrizve, csak az `insights`/`hotspots`-ot cserélve állítja elő (`_withInsightOutputs`, `document_stages.dart:307-326`). A teszt `same(assembled.document)` identitást ellenőriz (`document_stages_test.dart:88-89`). Nincs ál-dokumentum.
3. **Nincs PCM / PII szivárgás (ADR 0253 §4).** A dokumentum `AnalysisInputSummary` mezője kizárólag enum `source`-ot, hosszból számított `duration`-t, `sampleRate`/`channelCount`-ot és egy **SHA-256 fingerprintet** hordoz; a nyers `samples` csak a hossz (duration) és a hash számítására olvasódik, sehol nem tárolódik. A PII-hordozó `sourceDisplayName`/`sourceName` mezőt a stage **szándékosan nem tölti ki** (null marad), az `originalAudioRetained` false.

A két NOTE előretekintő és nem határsértés: (NOTE-1) a `provenance` audit-mezői részlegesek (`featureFlagSnapshot` mindig üres, `dspConfigHash` valójában verzió-string, a verzió-konstansok placeholderek) — de üres ≠ hamis érték, és nincs elérhető forrás ebben a körben; (NOTE-2) az inline `_fingerprint` az auditált `AudioFingerprint.compute`-ot reimplementálja és attól eltér — adatvédelmileg egyenértékű, de a dokumentum-fingerprint nem fog egyezni a cache-kulcs fingerprintjével (correctness-pointer).

---

## Módszer és bizonyíték

- **Izolált fresh clone:** `git clone --no-checkout /home/ubuntu/music-theory /tmp/security-review-e99-r12` → a pontos review-commit (`b376dbe9`) checkoutolva; a `/home/ubuntu/music-theory` hub és a saját worktree érintetlen (READ-ONLY).
- **Teljes diff:** `git diff 8ece7327..b376dbe9` — 7 fájl, 753 beszúrás, 10 törlés. A 7 fájl pontosan a brief `allowed_paths` halmaza (2 új: `document_stages.dart`, `document_stages_test.dart`; 5 módosított). Nincs pubspec/lock/generated fájl a diffben.
- **Scope-audit (gépi kapu):** `python3 tools/scope-audit.py --repo /tmp/security-review-e99-r12 --brief docs/rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md --base 8ece7327` → `Legacy scope audit OK (8ece7327..b376dbe9b001, 7 changed path(s), 0 generated/ignored)`.
- **Tiltott zóna (A9/A10 + brief §4):** üres diff a következőkre — `application/**` (0 diff-sor, byte-azonos), `domain/**`, `public.dart`, `lib/core/flags/**`, `docs/adr/**`, `tools/**`, `.github/**`, valamint `engine/stages/{ingest,evaluation}_stages.dart`. Igazolva `git diff --stat 8ece7327..b376dbe9 -- <path>` mindegyikre.
- **Bekötetlenség (A9/§5.5):** `analysisV2RunnerProvider` (`application/analysis_providers.dart:213`) a HEAD-en is `throw StateError('analysisV2RunnerProvider has no concrete V2 DSP stage list yet. …')`; az `application/` byte-azonos a baseline-nal.
- **Sink-grep** a három módosított/új production-fájlon (`document_stages.dart`, `analysis_work_state.dart`, `analysis_stage_phases.dart`):
  - hálózat (`Dio|http|HttpClient|Socket|Uri\.|\.get\(|\.post\(|supabase|10\.0\.2\.2`): **0** találat.
  - logolás/analytics (`print\(|debugPrint|log\(|logger|analytics|telemetry|diagnostics|Sentry|Crashlytics`): **0 valódi** találat (a két „találat" a `_fingerprint` szó „print" részlete — nem logolás).
  - secret/preferencia (`SecureStorage|SharedPreferences|token|password|apiKey|secret|signingKey`): **0 valódi** találat (a „token" a `cancellationToken` — lemondási token, nem auth).
- **Dependency-provenance:** a `crypto` **nem új** — `pubspec.yaml:46` (`crypto: ^3.0.7   # source SHA-256 provenance`), a baseline-en már 10+ fájl használja (`audio_fingerprint.dart`, `analysis_cache_key.dart` stb.). Ellátási lánc: nincs új felület.
- **Típus-nyomkövetés a PCM/PII-úthoz:** `AnalysisInputSource` (`analysis_mode.dart:5-10`) **enum** (microphone/importedFile/practiceSession/songSession) — nem fájl-út; `SourceDisplayName` (`analysis_input.dart:6-18`) redaktált PII-hordozó, amit a stage nem olvas ki.

---

## Leletek

**Nincs CRITICAL / BLOCKER / MAJOR / MINOR lelet.** Az alábbi két észrevétel NOTE (előretekintő), nem merge-blokkoló és nem termékhatár-sértés.

---

## Megjegyzések (NOTE)

### NOTE-1 — a `provenance` audit-mezői részlegesek (`featureFlagSnapshot` üres, `dspConfigHash` verzió-string) — előretekintő

- **Fájl:sor:** `lib/features/audio_analysis/engine/stages/document_stages.dart:100-112` (a `provenance` blokk), különösen `:111` (`featureFlagSnapshot: const <String, bool>{}`), `:105-106` (`dspConfigHash: 'preprocessing:${…preprocessingVersion ?? 'unavailable'}'`), `:49-52` + `:100-104` (a `_appVersion='strumsight'`, `_analyzerVersion`, `_pipelineVersion` konstansok).
- **Scenario:** a `provenance` reprodukálhatósági/audit-struktúra. A `featureFlagSnapshot` MINDIG üres map — egy jövőbeli auditor a dokumentumból azt olvashatja ki, hogy „egyetlen flag sem volt aktív", holott valójában a flag-állapot nincs rögzítve. A `dspConfigHash` a nevével ellentétben nem a teljes DSP-konfig hashe, hanem csak a preprocessing-verzió string. Az `appVersion` konstans (`'strumsight'`) placeholder, nem valódi build-verzió.
- **Miért nem lelet:** ez **üres/hiányos**, nem **hamis** adat — nem sérti az ADR 0253 §3 kitalált-érték tilalmát (az üres map nem hazudik flag-értékeket). A flag-állapotnak nincs elérhető forrása a munkaállapotban, a `lib/core/flags/**` pedig ebben a körben **tiltott zóna**, tehát a stage nem is tudná helyesen kitölteni. A §5.2 „minden más mező végleges" sem sérül: nem az insight-stage tölti ki később (az lenne a két-igazságforrás hiba), hanem véglegesen üres marad. A dokumentum ráadásul bekötetlen, tehát nincs éles audit-adatút.
- **Sértett szabály:** nincs — audit/reprodukálhatóság teljességi hiány.
- **Javasolt irány:** a GOV-30c-5 (runner-bekötés) körben, amikor a flag-snapshot forrása elérhetővé válik és a `provenance` valóban perzisztálódik/exportálódik, a `featureFlagSnapshot` a tényleges flag-állapotot kapja, a `dspConfigHash` a konfig valódi hashét, és a verzió-konstansok a build-metaadatot. Most csak jelezve, hogy ne maradjon el a bekötéskor.

### NOTE-2 — az inline `_fingerprint` reimplementálja és eltér az auditált `AudioFingerprint.compute`-tól — adatvédelmileg egyenértékű, correctness-pointer

- **Fájl:sor:** `lib/features/audio_analysis/engine/stages/document_stages.dart:273-295` (`_fingerprint`) vs. a meglévő, dokumentált `lib/features/audio_analysis/data/cache/audio_fingerprint.dart:15-56` (`AudioFingerprint.compute`).
- **Scenario:** az inline verzió is SHA-256-ot ad, int16-ra kvantálva (`(sample.clamp(-1,1)*32767).round()`, `document_stages.dart:280-284`) — a privacy-tulajdonságok azonosak: egyirányú hash, kvantált (nem nyers float) PCM, se fájlnév, se út, se eszköz-identitás. **Adatvédelmileg tehát egyenértékű**, nincs szivárgás. DE két ponton **eltér** a kanonikus helpertől:
  1. **Header-kódolás:** az inline egy string-headert (`"sampleRate:channelCount:preprocessingVersion"`, `:286-290`) UTF-8-ban hashel, míg a kanonikus egy bináris `ByteData(20)`-t (hossz+sampleRate+channelCount+versionLen, `audio_fingerprint.dart:32-36`).
  2. **Sample-forrás:** az inline a **nyers** `input.input.input.samples`-t hasheli, de a preprocessing-verzióval címkézi (`:289`), míg a kanonikus a kanonikus/normalizált PCM-re való.
  Következmény: a dokumentum `input.fingerprint` / `provenance.inputFingerprint` **nem fog egyezni** a `AudioFingerprint.compute` cache-kulcs-fingerprintjével.
- **Miért nem security-lelet:** nincs éles fogyasztó (a runner-út a GOV-30c-5 dolga), és a privacy-garanciák egyenértékűek; nincs reprodukálható rossz kimenet ebben a körben. Az eltérés correctness/DRY jellegű. (Ugyanezt a duplikációt a párhuzamosan futó correctness review is önállóan megtalálta — N2 — ami megerősíti, hogy valódi, follow-up-ra érdemes megfigyelés.)
- **Sértett szabály:** nincs (security). Két kockázat előretekintve: (a) két, külön karbantartott PCM-feldolgozó út — egy jövőbeli módosítás az egyikben auditálatlanul maradhat; (b) a fingerprint-egyezésre építő bármely dedup/cache-illesztés (ha a GOV-30c-5 ilyet köt be) elromlik.
- **Javasolt irány:** a correctness-reviewer és a GOV-30c-5 mérje ki, kell-e a két fingerprintnek egyeznie; ha igen, az engine-stage a kanonikus `AudioFingerprint` úton menjen (réteg-megengedettség szerint), vagy egyértelműsítsék a két fingerprint szándékoltan eltérő célját.

---

## Amit végignéztem és tisztának találtam (üres-lelet bizonyíték)

- **PCM / nyers-audio / PII (ADR 0253 §4, termékhatár 1/3):** a dokumentumba folyó `AnalysisInputSummary` (`document_stages.dart:93-99`) mezői: enum `source` (`:94`), `duration` (a `samples.length`-ből, `:266-271`), `sampleRate`/`channelCount` (`:96-97`), `fingerprint` (SHA-256 hash, `:98`). A `sourceName` és `originalAudioRetained` **nem kap értéket** → default null / false (`analysis_input_summary.dart:11-12`), tehát a redaktált `sourceDisplayName` soha nem másolódik a dokumentumba. A nyers `samples` **kizárólag** a hosszra (`_duration`) és a hashre (`_fingerprint`) olvasódik — sehol nem tárolódik. A `provenance` sem hordoz PCM-et. Igazoltan megfelel a §4-nek.
- **Kitalált-érték tilalom (ADR 0253 §3 / A6 / §6.1 három cella):** `metrics` pass-through (`:116`); `_capabilityFor` a nem elérhető capability-t `unavailable` + confidence 0 értékkel adja (`:215-226`), nem hamis-pozitívként; `_timeline` a hiányzó `beatGrid`/`tempoCurve`-öt üres listával (`?? const []`, `:239-254`), ami a hiány őszinte reprezentációja, nem kitalált érték; a hiányzó `signalQuality` **fail-closed** dobással (`:83-86`), nem defaulttal. A suite fedi: A6 (`document_stages_test.dart:100-123`, üres metrics + pitch unavailable) és a „minden degradálható elbukott" cella (`:125-150`, dokumentum létrejön, minden capability unavailable, metrics üres, completion `degraded`).
- **Insight-kontextus = publikálandó dokumentum (A3):** `document_stages.dart:161-165` (a `preliminary` példány megy a kontextusba) + `:307-326` (`_withInsightOutputs` minden nem-insight/hotspot mezőt megőriz). Teszt: `same(assembled.document)` identitás-ellenőrzés (`document_stages_test.dart:88-89`), injektált registryvel.
- **Insight-konverzió / kimeneti biztonság:** `_toDocumentInsight` (`document_stages.dart:328-356`) a `priority`/`kind`/`recommendedAction` leképezést **kimerítő `switch`-csel** (default ág nélkül) végzi — ismeretlen enum-értékre fordítási hiba (fail-closed). A `messageKey`/`messageArgs` a determinisztikus, kódban definiált szabályokból jön (`buildInitialInsightRules`), nem külső tartalomból; nincs prompt-injection felület.
- **AI-provider / prompt / tool-calling (ADR 0131–0136, termékhatár 1–5):** **N/A, igazoltan.** A kör nem kapcsol be providert, nincs `Dio`/HTTP hívás, nincs tool-allowlist, nincs külső tartalom→prompt út. A dokumentum bekötetlen (`StateError`). Nincs consent-kapu, mert nincs hálózati/adatkiadási művelet.
- **Hotspot-építés (nem document-injection):** a `_buildTimingHotspots` (`document_stages.dart:297-305`) a munkaállapot `alignment`-jéből épít, a `AnalysisHotspotBuilder` typedef kommentje (`:37-40`) explicit rögzíti, hogy „does not accept caller-supplied document data" — ez tudatos, **biztonságos** tervezés (a hotspot-építőbe nem injektálható tetszőleges dokumentum-adat). Az ADR 0253 §1 szerinti `HotspotRanker.rank(...)` folyamatot követi; a hotspotok forrás-metrikái (`TimingMetricSuiteIds.target`) a dokumentum `metrics`-ében is jelen vannak, így a user által látott adatból következnek.
- **Hibaüzenetek (termékhatár 3):** a stage-ek `UnknownFailure(cause: error, …)`-t adnak (`:72-76`, `:184-188`). A dobott hibák: két `StateError` fix szöveggel (`:85`, `:163`) és `ArgumentError.value(sample, 'samples', 'must be finite')` (`:278`) — utóbbi csak **nem-véges** (NaN/Inf) mintára tüzel, ami zéró audio-információt hordoz. Nincs érzékeny adat a hibaszövegben; ráadásul a hiba-út bekötetlen.
- **`document` mező a munkaállapotban:** additív, opcionális (`AnalysisDocument?`), immutable, default null, a `copyWith` propagálja (`analysis_work_state.dart:54, 125-127, 186, 188`). Nincs mellékhatás, nincs perzisztálás.
- **Fázis-térkép:** additív — a két új stage a `buildingInsights`/`finalizing` fázist kapja (`analysis_stage_phases.dart:49-50`), a teljes lánc 20 stage-re bővül (`:60-66`). A suite halmaz-egyezéssel fedi (A5, `analysis_stage_phases_test.dart`) és élő pipeline-ban futtatja (A1/A7/A8, `full_pipeline_composition_test.dart`).
- **Teszt-fixture-ök (termékhatár 3, „valóban fake?"):** a `document_stages_test.dart:164` szintetikus konstans PCM-et használ (`List<double>.filled(5000, 0.1)`), enum `source` (`practiceSession`, `:167`), fake üzenet-kulcsokat (`analysis.test_*`). **Nincs** valódi audio, fájl-út, PII vagy secret egyetlen fixture-ben sem.
- **§10 handoff:** az implementer beszámolója (a diff `docs/rounds/…md:283-315` része) dokumentálja a RED-lépést, a kötelező valódi-sértés próbát (az A3 pirosra váltott, majd visszaállítva) és a zöld round-gate-et. Nincs secret/PII a szövegben.

---

## Verdikt

**PASS.** 0 CRITICAL, 0 BLOCKER, 0 MAJOR, 0 MINOR, 2 NOTE (előretekintő). Nem tárgyalható termékhatár nem sérül: nincs nyers-audio/PII szivárgás, nincs rejtett hálózati kérés, nincs consent-megkerülés, nincs secret/log-felület, nincs prompt-injection út (a kör nem érint AI-providert). A scope tiszta (7/7 engedélyezett fájl, tiltott zóna érintetlen, `application/**` és `domain/**` byte-azonos), a dokumentum bekötetlen (`StateError`). A kör a három kritikus invariánst — nincs kitalált érték, az insights a publikálandó dokumentumot kapja, nincs PCM a dokumentumban — helyesen tartja. A két NOTE a GOV-30c-5 bekötési körnek szól, nem merge-blokkoló.
