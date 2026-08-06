# Review — E04-R21 Song Trainer struktúra-debrief, capability-gate & redaction

- **Kör:** E04-R21
- **Branch:** `codex/e04-r21-song-trainer-debrief-range-actions`
- **Implementer commit:** `8b3b991` (Codex / Terra, gpt-5.6-terra), újrabázisolva `818ebcf` a javított `main`-re
- **Base:** eredetileg `fbbb75b` (pre-flight §0.0-R1) — javító újra-review base: `542a023` (main, ADR 0176 arch-fix + heal #154/#155 után)
- **Reviewer:** Claude Opus 4.8 (orchestrátor, read-only review)
- **Verdikt:** **APPROVED** — a korábbi egyetlen BLOCKER-1-et a merge-elt **ADR 0176** (heal #155) feloldotta; lásd „Feloldás" alább.

## Feloldás (2026-08-06, javító újra-review — ADR 0112 pipeline)

A BLOCKER-1 (cross-feature import a `song_trainer/domain/public.dart` **nested**
barrelre) **nem** kódhiba volt, hanem a `tool/check_architecture.dart` mérő
false-positive-ja: a checker CSAK a feature-gyökér `public.dart`-ot fogadta el.
Két önjavító kör landolt a `main`-en:

- **#154** (`8cabae0`) — a brief re-scope-ja a már-publikus struktúra+capability+
  redaction szeletre (§0.0);
- **#155** (`135a304`, **ADR 0176**) — `tool/check_architecture.dart`: a
  cross-feature import bármely `public.dart` barrelt (gyökér VAGY nested)
  célozhat; nem-`public.dart` belső fájl továbbra is sértés. Regressziós teszt:
  `test/core/architecture_dependency_test.dart` „allows nested public.dart
  barrels but blocks feature internals".

Az orchestrátor a változatlan implementációt (`8b3b991`) a javított `main`-re
újrabázisolta (`818ebcf` = `542a023` + implementáció, cherry-pick tiszta), NEM
nyúlt a mérő eszközhöz (§4). Újra-verifikáció a rebase-elt fán:

| Ellenőrzés | Eredmény |
|---|---|
| `tools/round-gate.sh …/application …/presentation` | **MINDEN ZÖLD** (format, analyze, mindkét test-suite, **architecture**, secrets, l10n) |
| scope-audit (`542a023..818ebcf`) | **OK** — 9 fájl, 0 sértés |
| redaction-falszifikáció | változatlanul valódi (private lyric + backing-asset a bemenetben, kizárás mérve) |
| capability-gate | változatlanul őszinte (pitch/chord scoring=false → nincs axis-action) |

Az egyetlen korábbi PIROS lépés (architecture) most **ZÖLD**. Nincs nyitott
BLOCKER/MAJOR. A halasztott song_trainer-oldali (result/range/route/setlist)
felület továbbra is külön prerekvizit kör (§0.0) — ez a kör azt **nem** építi.

### Eredeti (H3) review-verdikt — megőrizve az alábbiakban

## Összegzés

Az implementáció tartalmilag **kiváló és a re-scoped brief §6 minden pontját
lefedi**: publikus-struktúra context-adapter, `getSongSections` read-only tool,
capability-őszinte belépőkártya, szigorú lyrics/backing-redaction — mind valódi
falszifikációs tesztekkel (a redaction-teszt a dokumentumba **valódi** privát
tartalmat tesz — `LyricsTrack('private lyric line')` + `BackingAudioTrack('backing-audio-private')`
— és kizárást bizonyít). A scope tiszta (9 fájl, 0 sértés), a tesztek zöldek.

**DE:** a kód architekturálisan **nem építhető** a kör engedélyezett-fájllistáján
belül — ez egy MÉRT BLOCKER, amit sem az implementer, sem egy azonos scope-ú
javító kör nem tud feloldani.

## Gate-újrafuttatás (izolált klón, `tools/prepare-flutter-generated.sh` után)

`/tmp/review-e04-r21` @ `8b3b991`, `prepare-flutter-generated.sh` → majd
`tools/round-gate.sh test/features/ai_tutor/application test/features/ai_tutor/presentation`:

| Lépés | Eredmény |
|---|---|
| format | **zöld** |
| analyze | **zöld** |
| test `.../application` | **zöld** (redaction + capability-gate + struktúra) |
| test `.../presentation` | **zöld** (capability-honest kártya) |
| **architecture** | **PIROS (exit 1)** — lásd BLOCKER |

CI: `full-gate.yml` [31064059711] = **failure** (ugyanaz az architecture-sértés);
`router-ci.yml` [31064052221] = success.

## BLOCKER-1 — cross-feature import a nem-publikus `domain/public.dart`-ra

**Fájl:** `lib/features/ai_tutor/application/context/adapters/song_result_context_adapter.dart:1`
és `lib/features/ai_tutor/application/tools/song_tutor_tools.dart:3`

**Mérés (`tool/check_architecture.dart`):**

```
- .../song_result_context_adapter.dart -> lib/features/song_trainer/domain/public.dart [cross-feature imports must target public.dart]
- .../song_tutor_tools.dart -> lib/features/song_trainer/domain/public.dart [cross-feature imports must target public.dart]
```

**Gyökérok (mérve):** a `tool/check_architecture.dart` §214–223 **kemény
határszabálya** szerint a cross-feature import CSAK a **feature-gyökér**
`lib/features/<feature>/public.dart`-ot célozhatja
(`targetPath != 'lib/features/$targetFeature/public.dart'` → sértés; a szabály
NEM némítható allowlist nélkül, és az allowlistben **nincs** song_trainer-bejegyzés).
A `song_trainer` feature-gyökér `public.dart`-ja viszont **csak prezentációs
képernyőket** exportál (`song_import_screen`, `song_library_screen`) — a
`SongDocument`/`SongSection`/`SongMeasure`/`SongCapabilityReport` a **nested**
`song_trainer/domain/public.dart`-ban él, ami cross-feature importként tilos.

**Repró:**
```bash
git clone --branch codex/e04-r21-song-trainer-debrief-range-actions <repo> /tmp/r
cd /tmp/r && tools/prepare-flutter-generated.sh
dart run tool/check_architecture.dart   # → exit 1, a fenti két sértés
```

**Mérés, hogy ez ÚJ (nem örökölt) sértés:**
`grep -rn "song_trainer/domain/public.dart" lib/ | grep -v "lib/features/song_trainer/"`
→ **0 találat** a körön kívül: R21 az ELSŐ cross-feature fogyasztója a domain
boundarynak, és ez architekturálisan nem engedett.

**Miért nem javítható a körön belül (a halt oka):** a helyes javítás vagy
(a) a `lib/features/song_trainer/public.dart` **additív re-exportja** a domain
felületre (`export 'domain/public.dart';` vagy a konkrét modellek) — ez egy
**song_trainer-oldali fájl az allowed_paths-on KÍVÜL**, a §0.0 által épp
**halasztott prerekvizit** (song_trainer public boundary additív export saját
ADR-rel); vagy (b) egy allowlist-bejegyzés a `tool/check_architecture.dart`-ban,
ami ADR-t és a **mérő eszköz** módosítását igényli (§4 tiltja). Mindkettő az
orchestrátor autonómiáján kívül → **H3**.

**A §0.0 re-scope mért hiányossága:** a healer (és a pre-flightom) igazolta, hogy
a `domain/public.dart` **exportálja** a struktúrát+capabilityt, de **nem mérte**,
hogy a cross-feature **fogyasztása** a nested `domain/public.dart`-ból az
architecture-checker kemény szabályába ütközik. Emiatt a re-scoped „már-publikus"
szelet valójában **szintén** a halasztott song_trainer-oldali additív exporttól
függ.

## Ajánlott következő lépés (prerekvizit kör)

Egy külön kör additívan tegye ki a song_trainer domain-struktúra + capability
felületét a **feature-gyökér** `lib/features/song_trainer/public.dart`-on át
(saját ADR-rel a song_trainer oldalon, `export 'domain/public.dart';`). Ezután az
R21 adapter+tool importja `song_trainer/public.dart`-ra vált, és a kör az
`allowed_paths` bővítésével (a song_trainer feltétel után) újraindítható. A többi
halasztott pont (measure-range, revision-stale, stb.) ugyanennek a prerekvizitnek
a része marad (§0.0).

## Nem-blokkoló megjegyzések

- NOTE: a tesztlefedettség és a redaction-falszifikáció **példaértékű** — a
  privát tartalmat a bemenetbe teszi, és kizárást mér; nem kell erősíteni.
- NOTE: a placeholder `song_trainer_context_adapter.dart` (unavailable stub)
  megmarad; a prerekvizit kör után eldönthető, hogy az új adapter leváltja-e.
