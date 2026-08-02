# E03-R06 — Review

Brief: `docs/rounds/e03-r06-legacy-song-setlist-adapters.md`
Diff: `git diff main...codex/e03-r06-legacy-song-setlist-adapters`
ADR: `docs/adr/0116-legacy-song-setlist-migration-boundary.md`
PR: https://github.com/wolfcasaba/strumsight/pull/65
Reviewer: Claude Sonnet 5 (independent, read-only, isolated `/tmp` klón) · Dátum: 2026-08-02
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 3 · NOTE: 1

Független gate-újrafuttatás izolált `/tmp` klónban: minden lépés zöld
(format, analyze, mindhárom cél-teszt, architecture). Scope-audit: a diff
pontosan a 7 engedélyezett kód/teszt fájl + a pre-flight írta két docs-fájl
(brief + ADR 0116), semmi más. A négy production forrásfájl teljes
elolvasása és mind a négy ADR 0116 döntés kód-szintű ellenőrzése (nem a §10
handoff szövegének elfogadása). 9 eldobható, adverzariális próbateszt írva
és futtatva (a review után törölve) — olyan éleket fed, amit a kör saját
tesztjei nem: mind a 9 zöld, megerősítve, hogy az implementáció helyes ott
is, ahol a kör saját teszt-lefedettsége hiányos (F1/F2).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Minden R01 fixture migrálható, determinisztikus, ismételt futtatásra azonos | ✅ | `legacy_parity_test.dart` mind zöld; idempotency/determinism tesztek; független codec-byte-identity próba |
| 2 | Event count, total beats, chord/direction sequence, duration, meter, Analyze timing parity | ✅ | `legacy_parity_test.dart` per-fixture assertion; független referencia-képlet kereszt-ellenőrzés (BPM 37, 7 measure) |
| 3 | Setlist sorrend, duplikáció, mixed BPM dalhatár változatlan; missing ID recoverable report | ✅ (ld. F1) | duplicate/missing/mixed-bpm tesztek zöldek; kombinált eset saját próbával megerősítve |
| 4 | Nincs legacy delete, persistent write vagy presentation import | ✅ | grep: nulla valódi import/storage-hívás, csak doc-comment említés |

### Kötelező megkülönböztető mátrix

| Legacy eset | V2 kötelező eredmény | Státusz |
|---|---|---|
| 4/4 chord+pattern | measure-enként esemény, beat-0 map | ✅ PASS |
| 3/4 | 3 beat measure, parity duration | ✅ PASS |
| rest | nincs kitalált chord | ✅ PASS (függetlenül megerősítve) |
| corrupt pattern | dokumentált repair+warning parity | ✅ PASS — a kör saját tesztje csak a rövidebb/pad esetet fedi; **a review próbája a hosszabb/truncate esetet**, bájtra egyezik a legacy `_fitToMeter`-rel |
| duplicate setlist | mindkét item, eredeti sorrend | ✅ PASS |
| missing ID | unresolved item, nincs crash | ✅ PASS |

## ADR 0116 döntések — forráskód ellenében ellenőrizve

Mind a négy döntés (önálló report-típus, `Meter(x,4)` mindig, közvetlen
szorzásos időzítés, `custom`/„Full Song" section) fájl:sor bizonyítékkal
megerősítve közvetlen forrás-vizsgálattal, nem a §10 handoff elfogadásával.

## Scope-audit

Pontosan 9 megváltozott fájl `main`-hez képest: a 7 engedélyezett kód/teszt
fájl + `docs/rounds/e03-r06-...md` + `docs/adr/0116-...md` (pre-flight írta,
pontosan egy commit — `a90f644` — érinti, az implementer sosem nyúlt hozzá).
Semmi a listán kívül.

## Próbatesztek (eldobható, törölve)

`zz_review_probe_test.dart` néven írva, 9/9 zöld, majd törölve (a klónban
`git status --short` csak az új review-report fájlt mutatja). Lefedés:
független rest-szlot ellenőrzés, corrupt-pattern truncation (hosszabb, mint
`beatsPerBar*2` — a kör saját tesztje ezt nem fedi), codec-byte determinizmus,
kombinált duplicate+missing setlist id, `SongValidator` integráció mind a 4
fixture-alakon, független referencia-képletes időzítés kereszt-ellenőrzés.

## Megállapítások

**F1 — MINOR** — `legacy_setlist_adapter_test.dart:84-104`,
`legacy_parity_test.dart:250-283`: a `setlist_missing_song.json` fixture
(`songs: ["song_a","ghost","song_a"]`) már tartalmaz egy kombinált
duplicate+missing esetet, de egyik teszt sem állítja, hogy a
`setlistDuplicateRetained` is megjelenik a reportban (csak a
`setlistReferenceUnresolved`-ot ellenőrzik). Saját próbával megerősítve
helyes. Nem blokkoló; follow-up körben pótolandó assertion.

**F2 — MINOR** — a kör egyetlen tesztje sem futtatja az E03-R05
`SongValidator`-t az adapter kimenetén, holott a brief §2 pontosan ezt
nevezi meg valódi integrációs határként. Saját próbával megerősítve:
`hasFatalIssue == false` mind a 4 reprezentatív fixture-ön. Nem blokkoló;
follow-up körben pótolandó `legacy_parity_test.dart`-ba.

**F3 — MINOR** — `legacy_song_reader.dart:21,25`: a `crypto` importot
`// ignore_for_file: depend_on_referenced_packages` némítja; a
`pubspec.lock` alapján csak tranzitív függőség, nincs a `pubspec.yaml`-ban
direktként deklarálva. Jogos, a körön belüli tradeoff (a `pubspec.yaml`
helyesen a scope-on kívül maradt, §10.5 dokumentálja) — kis follow-up
körben lezárandó (`dart pub add crypto`).

**F4 — NOTE** — `legacy_song_reader.dart:456-464`: `_expectObject`
docstringje olyan eseteket ír le, amiket a statikus `Map<String, dynamic>`
paramétertípus már kizár; a hibakód (`songNotAnObject`) csak egy literál
`{}`-re tud ténylegesen elsülni. Kozmetikai.

## Gate-bizonyíték

| Gate | Ellenőrizve |
|---|---|
| format | ✅ `Formatted 688 files (0 changed)` |
| analyze | ✅ `No issues found!` |
| test migration | ✅ 33/33 |
| test songs | ✅ 49/49 |
| test setlist_expected_hint | ✅ 1/1 |
| architecture | ✅ `Architecture dependencies OK (12 allowlisted deviation(s))` |
| Gate-összegzés | ✅ `MINDEN GATE ZÖLD` |

## Merge-döntés

Minden lokális gate zöld, nincs nyitott BLOCKER/MAJOR → **merge
engedélyezett**, feltéve az orchestrátor az exact-SHA CI teljes suite-ját is
zöldre látta (ADR 0053, ez már az orchestrátor felelőssége).
