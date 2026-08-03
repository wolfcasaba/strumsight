# E03-R11 — Review

Brief: `docs/rounds/e03-r11-musicxml-mxl-importer.md`
Diff: `origin/main...codex/e03-r11-musicxml-mxl-importer` @ `593cbf7`
Reviewer: Terra fallback, isolated `/tmp/review-e03-r11.G01eur` clone
Dátum: 2026-08-03
Verdikt: **CHANGES REQUIRED — HALT H3**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Dokumentált MusicXML subset | Részben | A mapper title/meter/key/tempo/harmony/note/lyric/marker részhalmazt kezel; F1/F2 nyitva. |
| 2 | Stabil 3/4, 4/4, 6/8, pickup és map snapshot | Részben | `musicxml_importer_test.dart` a 4/4 és pickup/map esetet méri; a kötelező 3/4 és 6/8 fixture nincs assertionszel lefedve. |
| 3 | Part preview note count/pitch range/polyphony/tab | ❌ | F1. |
| 4 | MXL/XML security határ | ✅ | Isolated gate; MXL limit-mutatáció RED; `mxl_security_test.dart`. |
| 5 | Unsupported elem stabil warningot ad | ❌ | F2. |

## Scope-audit

A model által készített `593cbf7` diffjében 25/25 út a brief `allowed_paths`
listájában volt; `git diff --check` zöld. Ez a reviewer-jelentés reviewer-oldali
artefaktum, nem modell-diff.

## Megállapítások

### F1 — MAJOR — A multipart fixture második partja elveszik, és nincs part-preview contract

- **Fájl:** `lib/features/song_trainer/data/importers/musicxml_mapper.dart:51,69`
- **Probléma:** a mapper kiolvassa az összes `part` elemet, majd csak
  `parts.first.findElements('measure')` fölött iterál. A committed
  `multipart_polyphonic.musicxml` P1 Guitar és P2 Bass partot tartalmaz, de a
  P2 sosem kerül a `SongDocument`-be. A `SongImportResult`
  (`data/importers/song_importer.dart:62-70`) csak documentet és warningokat
  tárol, az R10 `ImportPreview` (`application/import/import_preview.dart`) is
  csak displayName/format/warnings mezőket tartalmaz; ezért nincs út a briefben
  kötelező note-count/pitch-range/polyphony/tab preview közlésére.
- **Hatás:** a multipart score adatvesztéssel importálódik, a felhasználó nem
  tud partot választani vagy a kért previewt látni.
- **Kötelező javítás:** a MusicXML result/probe és application preview contract
  bővítésével őrizd meg minden partot és add át a preview statisztikákat; írj
  assertionset a committed multipart fixture P1/P2 note count, pitch range,
  polyphony és tab jelenlét értékeire.
- **Ellenőrzés:** új, a multipart fixture mindkét partjára érvényes teszt;
  a korábbi `parts.first` implementációval RED.
- **Státusz:** OPEN — a szükséges `song_importer.dart` és
  `application/import/*` utak nincsenek az R11 allowlistban, ezért ADR 0087
  H3 szerint e körben nem javítható.

### F2 — MAJOR — Unsupported MusicXML elemek néma elvesztése

- **Fájl:** `lib/features/song_trainer/data/importers/musicxml_mapper.dart:21-22,137-180`
- **Probléma:** a stabil `MusicXmlMapWarningCode.unsupportedElement` konstans
  deklarálva van, de az `rg` csak deklarációkat talál. A child-loop minden
  `backup`, `forward`, `harmony` és `note` elemen kívüli MusicXML elemet néma
  `continue`-val kihagy; az acceptance által kért warning sosem kerül az
  eredménybe.
- **Hatás:** a felhasználó sikeres importot kap anélkül, hogy tudna a
  megőrizhetetlen notation/display információról.
- **Kötelező javítás:** felismerhetetlen/unsupported child esetén egyszeri,
  stabil warningot adj, és erre XML fixture/assertion legyen.
- **Ellenőrzés:** unsupported direction/notation elem importja tartalmazza a
  warning code-ot, a javítás előtti kód RED.
- **Státusz:** OPEN.

## Ejtett valódi-sértés próba

Az izolált review-klónban a `mxl_archive_reader.dart:91` archive-entry
összehasonlítását ideiglenesen `>`-ről `>=`-re módosítottam. A
`flutter test test/features/song_trainer/data/importers/mxl_security_test.dart`
RED lett: a pontos limitre elfogadott 2-entry archívum `archiveEntryCount`
hibát adott. A módosítást azonnal visszaállítottam; a review-klón nem maradt
szennyezett a próbától.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzött eredmény |
|---|---|
| isolated `tools/round-gate.sh test/.../musicxml_importer_test.dart test/.../mxl_security_test.dart` | ✅ format, analyze, 4 + 5 tests, architecture zöld |
| CI (full suite + property + APK) | ⏳ [Build Android APK 30801576746](https://github.com/wolfcasaba/strumsight/actions/runs/30801576746), exact `593cbf7`, fut |

## Merge-döntés

Nyitott MAJOR leletek vannak. A normál javító router-kör sem indulhat, mert F1
javításához a brief tiltott zónájába tartozó contract/application utak kellenek.
ADR 0087 H3 szerint merge tilos és self-heal / új, review-zható brief-revízió
szükséges.

---

## Post-merge independent addendum (2026-08-03)

Reviewed final tree: `47baded` (PR #95 squash merge), which is tree-identical
to CI branch head `c79e9e0`. Verdict: **APPROVED — 0 BLOCKER / 0 MAJOR**.

The H3 scope revision authorized the exact result/probe/preview/controller
owners required by F1. Final `musicxml_importer_test.dart` asserts both real
fixture parts, their note-count/pitch/polyphony/table values and both resulting
note tracks; F1 is **FIXED**. It also asserts a single stable unsupported
notation warning; F2 is **FIXED**.

Independent isolated post-merge gate:
`tools/round-gate.sh test/features/song_trainer/data/importers/musicxml_importer_test.dart test/features/song_trainer/data/importers/mxl_security_test.dart test/features/song_trainer/application/import/song_import_controller_test.dart`
was green (format, analyze, 8 + 5 + 6 tests, architecture). A disposable
mutation of `mxl_archive_reader.dart` changed the entry-count boundary from
`>` to `>=`; `mxl_security_test.dart` failed (including the exact-limit accept
case). The mutation was reverted and the isolated clone was clean. CI
[30814057328](https://github.com/wolfcasaba/strumsight/actions/runs/30814057328)
is success for full suite, randomized property gate and APK.
