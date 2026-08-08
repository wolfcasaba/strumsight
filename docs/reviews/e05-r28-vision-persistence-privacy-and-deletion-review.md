# E05-R28 — Review

Brief: docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md
Diff: `git diff 1bbcc97..1f769a4` (`origin/main` pre-flight tip → végleges round
tip; javító kör #1: `ee154cc..bd938a3`; javító kör #2: `bd938a3..1f769a4`),
equivalently `git diff origin/main...codex/e05-r28-vision-persistence-privacy-and-deletion`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-08
Verdikt: **APPROVED** (F1 + F2 zárva, 2 javító kör után)

## Összegzés

BLOCKER: 0 · MAJOR: 0 nyitva (2 zárva: F1, F2) · MINOR: 0 · NOTE: 1

**Végső frissítés (javító kör #2 UTÁN, saját independens re-review):** F2
javítása (`1f769a4`) helyes és teljes — a `VisionModelManifestReader`/
`dart:io` függőség TELJESEN kikerült a `vision_session_repository.dart`-ból
(`grep -rn "FileVisionModelManifestReader|dart:io|VisionModelManifestReader"
lib/features/vision/data/persistence/` → 0 találat), a `save()` most
kötelező, explicit `Map<String, String> modelVersions` paramétert vár —
fordítás-idejű garancia, nem futásidejű teszt, hogy egy jövőbeli hívó nem
felejtheti el. Friss, izolált `/tmp` klónban (`/tmp/review-e05-r28-v2`)
teljes gate újra lefuttatva zöld, és egy ÚJ adversarial próba (a
`modelVersions` mező kivétele az encode-ból → piros → visszaállítva)
megerősítette, hogy a mező load-bearing, nem díszítő. Lásd F1/F2 lezárása
lent.

**Frissítés (javító kör #1 UTÁN, javító kör #2 ELŐTT — történeti, már
lezárva):** F1 tartalmi javítása helyes és teljes volt, DE a javítás módja
egy ÚJ, súlyosabb hibát vezetett be — lásd **F2** —, amit a reviewer saját, a
kódot a Flutter asset-rendszer és a testvér-osztályok
(`NativeHandLandmarkProvider`/`NativePoseLandmarkProvider`) ellen mérő
vizsgálattal talált, NEM a gate pirosából (a gate zöld maradt, mert a
teszt-környezet véletlenül elfedi a hibát — ld. F2 „Gyökérok").

**Frissítés (javító kör #1 előtt):** a dedikált security-review (risk=high,
`docs/reviews/e05-r28-vision-persistence-privacy-and-deletion-security.md`)
független módszerrel egy tartalmi (nem privacy-sértő) contract-rést talált —
lásd F1 lent —, amit a security-reviewer MINOR-nak minősített (a privacy-lens
alapján helyesen: az adat HIÁNYA sosem szivárgás), de ami ennek a fő
review-nak az architektúra/contract-lencséjéből MAJOR: az ADR 0183 Döntés 2
egy explicit „Elvetve" alternatívát ír le, és a szállított kód pontosan azt
teszi. A lelet ÉRDEMBEN javítható R28 saját `allowed_paths`-án belül (nincs
szükség H2/H3 halt-ra) — lásd F1 „Kötelező javítás".

Independent re-verification in an isolated `/tmp` clone (`/tmp/review-e05-r28`,
uncontaminated by the implementer's own worktree). Two disposable adversarial
mutation probes performed BY THE REVIEWER (not just re-reading the
implementer's self-reported probe) — both correctly caught by the round's own
tests, then reverted. All eight acceptance criteria hold with direct evidence.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Round-trip + jövőbeli-verzió mátrix (§0.0 R3 revised: vN round-trip + vN+1 quarantine, not a fabricated four-cell legacy matrix) | ✅ | `test/features/vision/data/vision_session_repository_test.dart:11-49` — `'vN round-trip is byte-stable...'` (byte-identical `encode`↔`decode`↔`encode`) + `'vN+1 item shape is skipped fail-loud...'` (a `schemaVersion: 2` item is dropped, not misread, history key stays present). Both green in the independent gate run. |
| 2 | Privacy-snapshot teszt (a kör kulcsbizonyítéka) | ✅ | `test/features/vision/data/vision_export_privacy_test.dart` pins the exact recursive key-path set on BOTH the raw stored envelope and the export, and asserts the two sets are equal. **Reviewer-performed adversarial probe:** injected a `'landmarkTimeline': const <double>[0.1, 0.2]` field into `VisionSessionCodec._encodeEntry` in the isolated clone → `flutter test test/features/vision/data/vision_export_privacy_test.dart` failed red with the extra key listed in `Actual`; reverted → green again (byte-clean, `git status --short` empty). |
| 3 | Delete-mátrix: egy session / delete-all / törlés sérült rekord mellett — nyers store ellenőrizve | ✅ | `vision_session_repository_test.dart`: `'deleting one session changes raw history but preserves another'` (raw `items` list checked), `'one malformed record is skipped while a valid session remains readable'` (delete after corruption, raw `items` empty afterward), `'delete all removes every Vision key and quarantine shadow from raw store'` (iterates `StorageKeys.visionData` against the raw store). **Reviewer-performed mutation-kill:** commented out the quarantine-shadow `_store.remove()` call inside `deleteAllVisionData()` in the isolated clone → the delete-all test failed red (`Expected: null, Actual: 'history-corrupt'`); reverted → clean. |
| 4 | Karantén-teszt: csonka rekord → csak az érintett karanténba | ✅ | Same `'one malformed record is skipped...'` test: a `{'schemaVersion': 1, 'sessionId': 'broken'}` record without required fields is silently skipped via `JsonCollectionStore`'s existing per-record `JsonRecordException` path; the sibling valid record remains readable. |
| 5 | Network-spy teszt: session → persistence → export nulla hálózati kérés; meglévő offline-guard bővítve | ✅ | `test/app/offline_network_guard_test.dart` new scenario `'vision enabled: session route stays offline'`: boots the full app with `visionEnabled: true`, navigates to the real `AppRoutes.visionSession` route (confirmed registered in `lib/app/routing/app_router.dart:246`, gated only by `visionEnabled`), then — through the SAME app-booted `keyValueStoreProvider` — calls `VisionSessionRepository.save()` and `VisionExport.exportJson()`, and asserts `_expectNoNetwork` (zero Dio client creations, zero requests) still holds. This is a real exercise of the full path, not a structural argument alone. Green in the independent gate. |
| 6 | Privacy panel widget-teszt: destruktív megerősítés, megerősítés nélkül hívásszámláló 0 | ✅ | `test/features/settings/vision_privacy_screen_test.dart`: taps `visionPrivacyDeleteAll` → confirms the `AlertDialog` (`visionPrivacyDeleteAllConfirm`) appears → taps **Cancel** → asserts `store.writeLog` is **empty** (stronger than a bare call-counter: it proves zero writes reached the storage boundary) and the history key is still present → then confirms via the dialog and asserts both `visionSessionHistory` and `visionCalibration` are gone. |
| 7 | Lokalizációs paritás zöld | ✅ | `lib/l10n/app_en.arb` / `app_hu.arb` diff: 17 matching keys added to each file, same key names, semantically translated (not copy-pasted English). Gate's `l10n` step green. |
| 8 | Valódi-sértés próba (§10) | ✅ | Implementer self-reported doing this with a `landmarkSeries` field (§10 handoff). **Independently reperformed by the reviewer** with an equivalent field (`landmarkTimeline`) — see AC #2 evidence — red→revert→green confirmed directly, not taken on the implementer's word. |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

- `python3 tools/scope-audit.py --repo /home/ubuntu/ss-terra-e05-r28 --brief docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md --base 1bbcc97` → `Legacy scope audit OK (1bbcc97..ee154cc, 14 changed path(s), 0 generated/ignored)`.
- Independently cross-checked via `git diff --stat origin/main...codex/e05-r28-vision-persistence-privacy-and-deletion` in the isolated `/tmp` clone — same 14 files, same shape, matches the brief's §4 table exactly (4 new `lib/` files, 1 new test-support-adjacent screen, 2 existing files touched additively — `storage_keys.dart`, `vision/public.dart` — 2 ARB files additively, 4 test files, 1 brief self-reference for the §10 handoff write-up).
- No file under `lib/features/vision/application/`, `lib/features/vision/domain/vision_session_result.dart`, `lib/features/ai_tutor/`, `lib/app/routing/`, `lib/features/settings/screens/settings_screen.dart`, or `backend/` was touched — matches the round's explicit forbidden-zone list (implementer prompt) and the brief's §4 "Tilos zóna".

## Megállapítások

### F1 — MAJOR — Model-version is never persisted, contradicting ADR 0183 Döntés 2's explicit rejection of omitting it

- **Fájl:** `lib/features/vision/data/persistence/vision_session_codec.dart:183-214` (the persisted DTO has no model-version key anywhere — not top-level, not per-insight).
- **Probléma:** the brief's own §3 Scope lists "model-verzió" as one of the five categories in "mentendő adatkör" (aggregátum, insight, capability, quality, **model-verzió**). [ADR 0183](../adr/0183-vision-no-raw-frame-persistence.md) — the very ADR this round's §0.0 pre-flight correction points to as the authoritative source for what the persistence layer may store — states in **Döntés 2**: "A model-verzió a résznek eredetet ad... hogy egy későbbi modellváltás után is értelmezhető maradjon", and explicitly rejects the alternative in **Elutasított alternatívák**: "Model-verzió elhagyása a helytakarékosságért. **Elvetve**: eredet nélkül a tárolt eredmény egy modellváltás után értelmezhetetlenné válik (SDD §30)." The shipped code does exactly the rejected thing: no field in `VisionSessionHistoryEntry`/`VisionInsightSnapshot` carries a model version, and the §10 handoff's "A briefhez nincs funkcionális eltérés" (no functional deviation) claim is therefore inaccurate.
- **Gyökérok (mérve, nem feltételezve):** `VisionSessionResult` (`vision_session_result.dart`, E05-R24, egy MÁR MERGE-ELT kör típusa, **nincs** R28 `allowed_paths`-án) nem hordoz model-verziót, és a belőle levezetett `VisionInsight` (ami a `sessionSummary`-t alkotja) sem — csak `code`/`policyVersion`/`evidenceIds`/`confidence`/`priority`/`direction`. A tényleges `modelVersion` mező kizárólag `EvidenceProvenance`-on él (`evidence_provenance.dart:33,51`), amit a codec sosem lát (csak az `evidenceIds` ID-string-lista jut el hozzá, nem a teljes `VisionEvidence`/`provenance` lánc).
- **Hatás:** egy jövőbeli modellváltás után egy régi, tárolt/exportált session-összefoglaló nem köthető ahhoz a modellhez, ami előállította — pontosan az az értelmezhetetlenségi kockázat, amit az ADR 0183 kifejezetten elutasított.
- **Miért NEM H2/H3 halt, és miért R28 saját hatáskörében javítható:** a hiányzó adat NEM igényli a `vision_session_result.dart` (lezárt E05-R24 kör, R28 tiltott zónája) módosítását. A `core/ml/vision_model_manifest.dart` (MEGLÉVŐ, a wide barrel már exportálja) `VisionModelManifestReader`/`FileVisionModelManifestReader` interfésze (`read() → Future<VisionModelManifestReport>`, `entries: List<VisionModelEntry>`) egy független, injektálható forrás — a `VisionSessionRepository.save()`/`VisionSessionCodec.fromResult()` (MINDKETTŐ R28 saját, ÚJ fájlja, benne van az `allowed_paths`-on) ebből egészítheti ki a rekordot a mentés pillanatában, `VisionSessionResult` érintése nélkül. Ez tisztán R28 saját, még nem merge-elt artefaktumainak (a kör saját codec/repository fájljai) a módosítása — nem tilos zóna feloldása (H3) és nem egy lezárt kör viselkedésének megváltoztatása (H2), mert `vision_session_result.dart` bitre érintetlen marad.
- **Kötelező javítás:** a `VisionSessionCodec`/`VisionSessionRepository` kapjon egy model-verzió forrást (pl. injektált `VisionModelManifestReader`, vagy a hívó által átadott resolt String — a pontos wiring az implementer döntése), és a persisztált/exportált alak kapjon egy `modelVersion`-mezőt (session-szintű, vagy insight-onkénti, ha több modell egyszerre aktív — a `VisionModelManifestReport.entries` több bejegyzést is tartalmazhat). A privacy-snapshot teszt `_expectedPaths` halmaza bővüljön az új kulccsal/kulcsokkal. Ha az implementer mérve úgy találja, hogy ez GENUINELY nem oldható meg R28 `allowed_paths`-án belül, `stopped`-dal jelezze — ne hallgassa el.
- **Ellenőrzés:** a privacy-snapshot teszt (`vision_export_privacy_test.dart`) bővített `_expectedPaths`-szal zöld; a delete-mátrix és a network-spy tesztek változatlanul zöldek.
- **Státusz:** **FIXED** (`dd717cd`/`bd938a3`, javító kör #1) — `VisionSessionHistoryEntry.modelVersions: Map<String, String>` (modelId→version, determinisztikus `SplayTreeMap`-rendezéssel, nem-üres validációval), `VisionSessionCodec.fromResult()` explicit `required Map<String, String> modelVersions` paramétert kapott, `_expectedPaths` bővült (`modelVersions`, `modelVersions.hand_landmarker`, `modelVersions.pose_landmarker`), round-trip teszt asszerál a visszaolvasott `modelVersions`-re. Tartalmilag helyes és teljes — de a WIRING módja (a `VisionSessionRepository` konstruktorába rejtett, OPCIONÁLIS, alapértelmezett `FileVisionModelManifestReader()`) egy ÚJ hibát vezetett be → **F2**.

### F2 — MAJOR (ÚJ, javító kör #1 mellékhatása) — `VisionSessionRepository`'s default `manifestReader` cannot resolve on a real device; `save()` would always throw in production

- **Fájl:** `lib/features/vision/data/persistence/vision_session_repository.dart:18-23` — `VisionModelManifestReader? manifestReader` optional constructor param, defaulting to `FileVisionModelManifestReader()` when omitted.
- **Probléma:** `FileVisionModelManifestReader.read()` (`lib/core/ml/vision_model_manifest.dart:112-148`) looks for `'${Directory.current.absolute.path}/assets/ml/model_manifest.json'` via plain `dart:io File` reads — a **project-directory-relative** lookup. Measured, not assumed:
  1. `pubspec.yaml`'s `flutter.assets` list (`:6-20`) bundles `assets/ml/*.bin` as **individual files**, and `assets/tutor_knowledge/`/`assets/tutor_prompts/` as **directories** — `assets/ml/model_manifest.json` is declared **nowhere**. It is not packaged into the APK/IPA at all.
  2. Even if it were declared, Flutter assets are reached via `rootBundle`/`AssetBundle` at runtime, never via a raw `dart:io File` path — `Directory.current` inside an installed app is an arbitrary sandbox path, not the repo root.
  3. The two EXISTING sibling classes that already consume `VisionModelManifestReader` in production code — `NativeHandLandmarkProvider` (`data/landmarks/native_hand_landmark_provider.dart:34-39`) and `NativePoseLandmarkProvider` (`data/landmarks/native_pose_landmark_provider.dart:22-27`) — both take it as a **required** constructor parameter with **no default**, i.e. the established, reviewed pattern in this codebase is "the caller must supply a working reader", never "fall back to the file-based one". This round's optional default is a **new, unprecedented deviation**.
- **Miért nem kapta el a gate:** every test added in javító kör #1 explicitly injects a fake `VisionModelManifestReader` (`_ManifestReader`/`_UnreadableManifestReader`) — **none exercises the default**. The gate ran via `flutter test` from the repo root, where `Directory.current` happens to equal the project root, so if the default HAD been exercised there, it would have accidentally succeeded too — CI/dev coincidence masking a production failure, not a genuine proof. This is exactly the "zöld gate NEM bizonyíték" principle this skill opens with.
- **Hatás:** the moment a future round wires a real caller to `VisionSessionRepository()` without explicitly injecting a reader (an easy, unflagged mistake — the parameter is optional and compiles fine), every `save()` call throws `StateError` on a real device, and **no Vision session ever persists** — the opposite of this round's entire purpose. Silent-until-runtime, unit-untestable-by-construction (the default can only be proven broken on a real device or an environment where `Directory.current` isn't the repo root).
- **Kötelező javítás:** remove the silent default. Two acceptable directions (implementer choice), either is fine as long as there is **no fallback that can resolve on CI/dev but not on a device**:
  1. Make `manifestReader` a `required` constructor parameter (matching the `NativeHandLandmarkProvider`/`NativePoseLandmarkProvider` precedent) — forces every future caller to consciously supply one; update `VisionExport`'s internal `VisionSessionRepository(store: store, codec: codec)` construction to also take/thread one (even though export never calls `save()`, so a trivial dummy is technically safe there but a `required` parameter is more honest — implementer's call how to thread it cleanly); or
  2. **Simpler, no new dependency at all:** drop `VisionModelManifestReader` from the repository entirely — thread `modelVersions: Map<String, String>` as an explicit **required parameter of `save()` itself**, exactly like `VisionSessionCodec.fromResult()` already does. The future caller (session-end wiring, out of this round's scope) resolves the map however is appropriate for its own context. `VisionExport` needs no change at all under this direction (it never calls `save()`).
  Either way: update the one existing test call site that currently relies on the implicit default without injecting a fake reader —
  `test/features/settings/vision_privacy_screen_test.dart:16` (`await repository.save(_result());` via a bare `VisionSessionRepository(store: store)`) — so it keeps compiling/passing for the RIGHT reason, not by coincidence.
- **Ellenőrzés:** grep the final diff for `FileVisionModelManifestReader(` with zero arguments used as a *default value* anywhere reachable without an explicit override — there should be none. `flutter analyze` must show no unused-import warning on `dart:io`/`vision_model_manifest.dart` if direction 2 is taken (the import should be removed from the repository file entirely). All four vision persistence test files green.
- **Státusz:** **FIXED** (`1f769a4`, javító kör #2, B irány) — a
  `VisionSessionRepository`-ból teljesen kikerült a `VisionModelManifestReader`/
  `dart:io` függőség; `save()` most `required Map<String, String> modelVersions`
  paramétert vár (ugyanaz a minta, mint a `VisionSessionCodec.fromResult()`
  már eddig is használt). A két meglévő hívó-teszt
  (`test/app/offline_network_guard_test.dart`,
  `test/features/settings/vision_privacy_screen_test.dart`) frissítve, hogy
  explicit map-et adjon át — egyik sem támaszkodik többé egy hallgatólagos
  alapértelmezésre. Reviewer saját ellenőrzése: `grep` 0 találat a tiltott
  szimbólumokra a persistence-rétegben; friss `/tmp` klónban teljes gate zöld;
  adversarial próba (a `modelVersions` mező kivétele az encode-ból) piros lett,
  majd visszaállítva.

### N1 — NOTE — Cross-feature import goes through the wide `vision/public.dart` barrel, not the narrow `domain/integration/public.dart` one

- **Fájl:** `lib/features/settings/screens/vision_privacy_screen.dart:12`
- **Megfigyelés:** Recent sibling rounds (E05-R26/R27) established a convention where NEW cross-feature vision consumers should prefer the narrow, domain-safe nested barrel (`lib/features/vision/domain/integration/public.dart`) over the wide `vision/public.dart`, because the wide barrel also exports raw landmark/geometry/provider types with no symbol-level boundary (HANDOFF.md §3, open follow-up). This round's `vision_privacy_screen.dart` imports the wide barrel instead.
- **Miért nem BLOCKER/MAJOR itt:** the narrow barrel only carries the insight/evidence CONTRACT types (`vision_practice_contract.dart`, `vision_song_contract.dart`, and now the R27 Tutor/Analysis adapters) — it does not, and was never intended to, carry persistence types (`VisionSessionRepository`, `VisionExport`, `VisionSessionHistoryEntry`). There is currently no narrower barrel this screen could use instead; the R10 calibration repository is exported the same way (through the wide barrel) with no prior objection. This is the same precedent, not a regression.
- **Javasolt irány (follow-up, nem e kör):** if a future round wants to tighten this, it would add a THIRD, persistence-scoped narrow barrel (or extend the architecture checker to be symbol-aware instead of file-glob-based, per the open item already tracked in HANDOFF.md §3). Not required for this round's merge.
- **Státusz:** NOTE, nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer §10, javító kör #2 után) | Ellenőrizve (reviewer, saját futtatás izolált `/tmp` klónban, `1f769a4`) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld, 0 issue | ✅ zöld |
| test test/features/vision | zöld, 7 teszt | ✅ zöld |
| test test/features/settings | zöld, 1 teszt | ✅ zöld |
| test test/app/offline_network_guard_test.dart | zöld, 4 teszt | ✅ zöld |
| architecture | (part of round-gate) | ✅ zöld |
| secrets | (part of round-gate) | ✅ zöld |
| l10n | (part of round-gate) | ✅ zöld |
| Full Gate (no APK) | dispatch-elve az orchestrátor által | ✅ zöld — [31276986778](https://github.com/wolfcasaba/strumsight/actions/runs/31276986778) a végleges `1f769a4` tipen |
| Router CI | dispatch-elve az orchestrátor által (`docs/rounds/**` diff miatt kötelező) | ✅ zöld — [31276984787](https://github.com/wolfcasaba/strumsight/actions/runs/31276984787) a végleges `1f769a4` tipen |

**Módszertani jegyzet a gate-újrafuttatásokról:** az F1 utáni első saját
gate-futtatás közben a reviewer PÁRHUZAMOSAN, UGYANABBAN a klónban végezte az
adversarial próbáit, ami egy valódi (de a reviewer saját ideiglenes
mutációjából eredő, nem az implementer kódjából eredő) piros találatot
okozott — a klón tisztaságát megerősítve a gate-et TELJESEN ÚJRA, érintetlen
fán futtattam. Az F2 utáni végső ellenőrzésnél ezt a hibát elkerülve a
próbákat SZEKVENCIÁLISAN, a gate teljes befejezése UTÁN végeztem, egy
teljesen friss klónban (`/tmp/review-e05-r28-v2`) — a fenti eredmény ebből
származik (`/tmp/review-e05-r28-v2-gate.log`, „═══ Gate-összegzés" blokk).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
F1 ÉS F2 lezárva (2 javító kör), 0 nyitott BLOCKER/MAJOR, helyi gate zöld friss
`/tmp` klónban a végleges `1f769a4` tipen, Full Gate + Router CI mindkettő
zöld ugyanezen a SHA-n (lásd fent). **Minden feltétel teljesült — merge
mehet, külön jóváhagyás nélkül** (a merge SHA-n való zöldséget az
orchesztrátor a `main` mozdulása esetén ADR 0086 §2 szerint újra ellenőrzi
merge előtt).

_(Az alábbi, most már elavult megjegyzés a javító kör #2 dispatch-elése
ELŐTTI állapotot rögzítette, megőrizve a döntési nyomvonal olvashatóságáért:)_
Javító kör #2 dispatch-elve F2 leletlistával; a review ezután frissül
(APPROVED vagy ismételt CHANGES REQUESTED), és mind a helyi gate-et, mind a
Full Gate / Router CI workflow-kat újra kell futtatni a javító kör #2
commitján (a jelenlegi zöld futások a `bd938a3` SHA-n élnek, ami maga sem a
végleges tip).
