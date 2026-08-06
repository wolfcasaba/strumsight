# E05-R02 — Review

Brief: `docs/rounds/e05-r02-camera-technology-decision.md`
Diff: `git diff origin/main...codex/e05-r02-camera-technology-decision` (5 files, +317/-12)
Reviewer: Claude (orchestrátor, Sonnet 5) · Dátum: 2026-08-06
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Kritériumtábla 3 jelölt × 12 kritérium kitöltve, minden MÉRENDŐ cella kereszthivatkozva a runbookkal | ✅ | `docs/baseline/epic-05-camera-stack-evaluation.md` §2 — mind a 12 sor (init time … win32 conflict risk) mindhárom oszlopban (C1/C2/C3) kitöltve, minden MÉRENDŐ cellához `Mxx` runbook-azonosító a „Source / runbook link" oszlopban |
| 2 | ADR 0184 legalább 3 numerikus megdöntési küszöböt tartalmaz (init idő, tartós FPS, close-resource) | ✅ | ADR §Decision 4. pont: init p95 ≤ 2000 ms (M01), FPS ≥ 15.0/30s-ablak (M02), close ≤ 2000 ms + open_clients=0 + post-close RSS ≤ 20 MiB/30s (M06), timestamp monoton 1000 frame felett (M10) — négy küszöb, a kötelező három lefedve |
| 3 | Runbook: 20× preview start/stop, background/foreground, memory-snapshot lépés, mindegyik számmal kifejezett PASS-feltétellel | ✅ | runbook §3.1 (M01+M06, 2000 ms/0 client), §3.2 (M09, 2000 ms), §3.3 (memory-snapshot, ≤20 MiB/30s) |
| 4 | Device-mátrixba minden runbook-mérés PENDING sorként bekerül | ✅ | `vision-device-matrix.md` új §2.8, M01–M12 mind a 12 sor PENDING, a runbookra hivatkozva |
| 5 | `git diff --stat` nem érint `lib/`, `test/`, `android/`, `ios/`, `pubspec.yaml` fájlt | ✅ | lásd Scope-audit — kizárólag 5 doksi-fájl |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**. `git diff --stat origin/main...HEAD` pontosan a brief §4 öt sorát érinti (`docs/adr/0184-…`, `docs/baseline/epic-05-camera-stack-evaluation.md`, `docs/manual-testing/vision-camera-spike-runbook.md`, `docs/manual-testing/vision-device-matrix.md`, `docs/rounds/e05-r02-camera-technology-decision.md`). `lib/`, `test/`, `android/`, `ios/`, `pubspec.yaml` — 0 találat.

## Megállapítások

Nincs BLOCKER/MAJOR/MINOR lelet.

### N1 — NOTE — az implementer `blocked`-ot jelzett egy box-szintű infra-hiba miatt, nem tartalmi problémára

- **Fájl:** n/a (`/home/ubuntu/ss-terra-e05-r02/.codex-round-status`)
- **Megfigyelés:** a Terra futás `blocked`-ot jelzett — `analyze PIROS, 871 pre-existing package/l10n issues`. A reviewer izolált `/tmp` klónban reprodukálta: a friss munkapéldányban a `flutter analyze` ténylegesen **"No issues found!"**-t adott, de a Dart analysis-server `OS Error: Too many open files, errno=24` hibával nem-nulla kilépési kóddal tért vissza. Gyökérok: `fs.inotify.max_user_instances=512` majdnem kimerült (509/512), több száz elárvult `tail` processz (régi `codex-watch.sh`/`mm-watch.sh` futásokból) foglalta le a boxon. `sudo sysctl -w fs.inotify.max_user_instances=4096` után a gate (`tools/round-gate.sh test/tooling`) — mind a saját munkapéldányban, mind a független `/tmp` klónban — **teljesen zöld**: format, analyze, test, architecture, secrets, l10n.
- **Hatás:** nincs — a tartalmi diff érintetlen, a `blocked` jelzés kizárólag a megosztott box erőforrás-kimerülését tükrözte, nem a kör tartalmát. A H6 halt-feltétel ezért nem alkalmazandó: a mért gyökérok a boxon van, nem a kör artefaktumában.
- **Kötelező javítás:** nincs a kör számára; az inotify-instance kimerülés és az elárvult `tail` processzek boxhigiéniai kérdés, follow-up (pl. `Oracle server hygiene` memória-mintára hasonló periodikus takarítás).
- **Ellenőrzés:** két független `round-gate.sh test/tooling` futás (implementer munkapéldány + reviewer `/tmp` klón), mindkettő minden lépésben zöld a sysctl-emelés után.
- **Státusz:** NOTE — nem blokkol.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (reviewer `/tmp/review-e05-r02` klón) |
| analyze | zöld (a box inotify-limit emelése után) | ✅ |
| test test/tooling | zöld | ✅ |
| architecture | zöld (12 allowlisted deviation, nem ez a kör hozta) | ✅ |
| secrets | zöld (1791 fájl, 0 lelet) | ✅ |
| l10n | zöld (913 üzenet, en↔hu parity) | ✅ |
| CI (teljes suite + property + APK) | orchestrátor dispatch-eli merge előtt | pending — lásd §7 |

## Falszifikációs próba (§6.1 mérce-mátrix, docs-only kör)

Kód-alapú guard nincs egy docs-only körhöz; a próba manuális tartalom-ellenőrzés
volt (nem módosítottam a branchet):

- Az ADR §Decision 4. pontja számmal kifejezett küszöböket ad (2000 ms, 15.0
  FPS, 20 MiB/30s, 1000 frame) — szám nélküli „megdönthető" állítás NINCS.
- A runbook mind a 12 sorának `PASS condition` oszlopa numerikus küszöböt ad.
- A device-mátrix §2.8 mind a 12 `Mxx` azonosítót tartalmazza, egy sem hiányzik
  a runbookhoz képest.

## Merge-döntés

Az ADR 0052 szerint: minden helyi gate zöld ÉS nincs nyitott BLOCKER/MAJOR →
merge engedélyezett, miután az exact-SHA CI (Router CI a `docs/rounds/**`
érintés miatt; a CI-terv `full-gate.yml`/`build-apk.yml` közötti választását az
orchestrátor a `tools/round-ci-plan.py`-vel dönti el) zöld a merge SHA-n.
