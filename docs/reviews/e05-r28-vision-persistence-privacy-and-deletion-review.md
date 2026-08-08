# E05-R28 — Review

Brief: docs/rounds/e05-r28-vision-persistence-privacy-and-deletion.md
Diff: `git diff 1bbcc97..ee154cc` (`origin/main` pre-flight tip → round tip),
equivalently `git diff origin/main...codex/e05-r28-vision-persistence-privacy-and-deletion`
Reviewer: Claude Sonnet 5 (orchestrator) · Dátum: 2026-08-08
Verdikt: CHANGES REQUESTED (1 MAJOR — javító kör dispatch-elve)

## Összegzés

BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

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
- **Státusz:** OPEN — javító kör #1-ben dispatch-elve.

### N1 — NOTE — Cross-feature import goes through the wide `vision/public.dart` barrel, not the narrow `domain/integration/public.dart` one

- **Fájl:** `lib/features/settings/screens/vision_privacy_screen.dart:12`
- **Megfigyelés:** Recent sibling rounds (E05-R26/R27) established a convention where NEW cross-feature vision consumers should prefer the narrow, domain-safe nested barrel (`lib/features/vision/domain/integration/public.dart`) over the wide `vision/public.dart`, because the wide barrel also exports raw landmark/geometry/provider types with no symbol-level boundary (HANDOFF.md §3, open follow-up). This round's `vision_privacy_screen.dart` imports the wide barrel instead.
- **Miért nem BLOCKER/MAJOR itt:** the narrow barrel only carries the insight/evidence CONTRACT types (`vision_practice_contract.dart`, `vision_song_contract.dart`, and now the R27 Tutor/Analysis adapters) — it does not, and was never intended to, carry persistence types (`VisionSessionRepository`, `VisionExport`, `VisionSessionHistoryEntry`). There is currently no narrower barrel this screen could use instead; the R10 calibration repository is exported the same way (through the wide barrel) with no prior objection. This is the same precedent, not a regression.
- **Javasolt irány (follow-up, nem e kör):** if a future round wants to tighten this, it would add a THIRD, persistence-scoped narrow barrel (or extend the architecture checker to be symbol-aware instead of file-glob-based, per the open item already tracked in HANDOFF.md §3). Not required for this round's merge.
- **Státusz:** NOTE, nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer §10) | Ellenőrizve (reviewer, saját futtatás izolált `/tmp` klónban) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld, 0 issue | ✅ zöld |
| test test/features/vision | zöld | ✅ zöld (after excluding the reviewer's own transient mutation-probe collision — see below) |
| test test/features/settings | zöld | ✅ zöld |
| test test/app/offline_network_guard_test.dart | zöld, 4 teszt | ✅ zöld |
| architecture | (part of round-gate) | ✅ zöld |
| secrets | (part of round-gate) | ✅ zöld |
| l10n | (part of round-gate) | ✅ zöld |
| Full Gate (no APK) | dispatch-elve az orchestrátor által | ✅ zöld — [31274920630](https://github.com/wolfcasaba/strumsight/actions/runs/31274920630) (PR #202 branch tip `ee154cc`) |
| Router CI | dispatch-elve az orchestrátor által (`docs/rounds/**` diff miatt kötelező) | ✅ zöld — [31274905440](https://github.com/wolfcasaba/strumsight/actions/runs/31274905440) |

**Módszertani jegyzet a gate-újrafuttatásról:** az első saját gate-futtatás
közben a reviewer PÁRHUZAMOSAN, UGYANABBAN a klónban végezte az AC #2/#3
adversarial próbáit, ami egy valódi (de a reviewer saját ideiglenes
mutációjából eredő, nem az implementer kódjából eredő) piros találatot
okozott a `test/features/vision` lépésben. A klón tisztaságát (`git status
--short` üres) megerősítve a gate-et TELJESEN ÚJRA, a próbák befejezése UTÁN,
érintetlen fán futtattam — ez adta a fenti, végleges "minden gate zöld"
eredményt (`/tmp/review-e05-r28-gate.log`, „═══ Gate-összegzés" blokk).

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
A gate-ek (helyi + Full Gate + Router CI) mind zöldek, de **F1 (MAJOR) nyitva
van** → **merge jelenleg TILOS**. Javító kör #1 dispatch-elve F1
leletlistával; a review ezután frissül (APPROVED vagy ismételt CHANGES
REQUESTED), és a CI-t a javító kör commitja után újra kell dispatch-elni
(a concurrency a jelenlegi zöld futásokat a régi SHA-n hagyja, az új SHA-n
kell újra zöldnek lennie).
