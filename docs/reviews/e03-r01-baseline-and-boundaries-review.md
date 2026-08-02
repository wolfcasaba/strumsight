# E03-R01 — Review

Brief: `docs/rounds/e03-r01-baseline-and-boundaries.md`
Diff: `git diff origin/main...codex/e03-r01-baseline-and-boundaries` (HEAD `9abe708`)
Reviewer: Claude Sonnet 5 (orchestrátor) · Dátum: 2026-08-02
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 1

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | A baseline tételesen rögzíti a storage kulcsot, JSON sémát, meter-, timing-, Builder-, Learn- és setlist-combine viselkedést. | ✅ | `docs/baseline/epic-03-song-trainer-start.md` §"Perzisztencia kulcsok" / "JSON séma" / "Támogatott meterek" / "Song Builder funkciók" / "Learn integráció" / "Setlist combine viselkedés" — mind a hat téma külön szakaszban, konkrét fájl:sor hivatkozásokkal. |
| 2 | A hét fixture licence/provenance megjegyzése és event count, total beats, chord/direction sequence, duration, meter, setlist order parityje stabil. | ✅ | Mind a 7 fixture (`test/fixtures/song_trainer/legacy/*.json`) tartalmaz `provenance` mezőt (ön-készítésű, technikai tartalom); a `legacy_fixture_parity_test.dart` 9/9 zöld saját (reviewer-oldali) futtatásban is. Két független mutáció-próba (lásd "Próbatesztek") mindkettő pirosra váltott. |
| 3 | A feature flag default-off, a public boundary nem exportál félkész contractot, a meglévő Song/Setlist tesztek változtatás nélkül zöldek. | ✅ | `lib/features/song_trainer/public.dart` csak `library;`-t tartalmaz, nulla export; `FeatureFlags.forEnvironment` mind a 3 `AppEnvironment`-re `false`, a const-konstruktor default-ja is `false` — mindkettő tesztelt (`E03-R01 rollout guard` csoport). `git diff origin/main...HEAD -- test/features/songs` üres — a legacy tesztkészlet egyetlen fájlja sem módosult, és a gate futtatásban 100%-ban zöld. |
| 4 | A pre-flight exact ADR-számokat ütközésvizsgálattal oszt ki; PREPARED állapotban nincs ADR-path jogosultság. | ✅ | Pre-flight commit `6c75bca`: `docs/adr/0089-0092-*.md` — a `docs/adr/` legmagasabb korábbi sorszáma 0088/0111/0112 volt, nincs ütközés (mérve: `ls docs/adr | sort -V | tail`). A brief §4 táblázata a négy ADR-t "ÚJ (pre-flight írta, orchestrátor)" jelöléssel tartalmazza; az `ai-router` TOML `allowed_paths` szándékosan NEM tartalmazza a `docs/adr/**`-t — az implementer diffje ténylegesen egyetlen ADR-t sem érintett. |

## Scope-audit

`git diff --stat origin/main...HEAD` (16 fájl, `/tmp/review-e03-r01` izolált klónban mérve):

- 4 ADR (`docs/adr/0089-0092-*.md`) — a pre-flight (orchestrátor) írta, dokumentáltan a §4 táblázat kivétele.
- A brief maradék 11 engedélyezett fájlja mind szerepel, **listán kívüli fájl nincs**:
  `docs/baseline/epic-03-song-trainer-start.md`, `lib/app/config/feature_flags.dart`,
  `lib/features/song_trainer/public.dart`, a 7 fixture JSON, a parity teszt,
  és maga a `docs/rounds/e03-r01-baseline-and-boundaries.md` brief (§10 handoff).

**Engedélyezett fájlokon kívüli változás: nincs.**

## Megállapítások

### F1 — MINOR — Két hibás ADR-hivatkozás a baseline dokumentumban

- **Fájl:** `docs/baseline/epic-03-song-trainer-start.md:94,329,356`
- **Probléma:** három link nem létező vagy rossz-nevű ADR-fájlra mutat:
  - 94. sor: `[docs/adr/0010-storage-migrator.md](../adr/0010-storage-migrator.md)`
    — **ADR 0010 nem létezik** a `docs/adr/` alatt (a legalacsonyabb sorszámok
    0001-0004, utána 0050-től folytatódik). A valódi tartalom feltehetően
    [`ADR 0054`](../adr/0054-versioned-user-content-documents.md)
    ("versioned-user-content-documents") alá tartozik.
  - 329. és 356. sor: `[docs/adr/0084-history-v2.md](../adr/0084-history-v2.md)`
    — a tényleges fájlnév
    [`0084-practice-history-v2-and-coaching.md`](../adr/0084-practice-history-v2-and-coaching.md).
- **Hatás:** a baseline dokumentum — amelynek kifejezett célja a jövőbeli
  körök mért referenciapontja lenni — két helyen törött vagy fabrikált
  hivatkozást hordoz. Nem befolyásol tesztet, gate-et vagy futó kódot.
- **Kötelező javítás:** a 94. sort `0054-versioned-user-content-documents.md`-re
  javítani (vagy ha a migrátor ADR-je valójában máshol dokumentált, arra
  mutatni), a 329./356. sort `0084-practice-history-v2-and-coaching.md`-re.
- **Ellenőrzés:** `grep -n "0010-storage-migrator\|0084-history-v2"
  docs/baseline/epic-03-song-trainer-start.md` nulla találatot adjon.
- **Státusz:** OPEN — a diffet nem hizlalja érdemben (3 sornyi link-javítás),
  a következő körben (vagy egy dokumentum-only mini-javító körben) javítható;
  nem blokkolja ezt a merge-öt, mert az acceptance criteria egyike sem az ADR
  linkek helyességéről szól, és a hivatkozott ADR-témák (storage migrator,
  Practice History V2) egyébként helyesen vannak leírva szövegben.

### F2 — NOTE — `FeatureFlags.hashCode` szándékosan nem tartalmazza az új mezőt

- **Fájl:** `lib/app/config/feature_flags.dart:97-107` (kb.)
- **Megfigyelés:** a `==` és a `toString()` felveszi a `songTrainerV2Enabled`
  mezőt, a `hashCode` explicit módon nem — az implementer ezt a §10.5-ben
  dokumentálta: a bővítés pirosra váltaná a `test/app/app_config_test.dart:264`
  rögzített 6-argumentumos `Object.hash(...)` sorát, az a fájl viszont **nincs**
  a kör engedélyezett listáján. Ez NEM sérti az `==`/`hashCode` Dart-kontraktust
  (két egyenlő objektum hash-e egyezik — ez teljesül, mert a hashCode-ból
  kihagyott mező nem befolyásolja az egyenlőket), csak a hash-eloszlás romlik
  enyhén a nem egyenlő objektumok között.
- **Miért nem MINOR/MAJOR:** ez egy explicit, a brief §3 "Kívül" listájával
  összhangban lévő scope-döntés (a kör nem nyúlhat `test/app/`-hoz), és az
  implementer maga jelezte a §10.5/10.6-ban — pontosan azt a fegyelmet
  mutatja, amit a STOP-protokoll elvár (nincs néma workaround).
- **Follow-up:** a `test/app/app_config_test.dart:264` sort egy jövőbeli
  (bármelyik `test/app/`-ot is érintő) kör frissítse 7-argumentumos
  `Object.hash(..., songTrainerV2Enabled)`-re, és akkor a `hashCode` is
  bővíthető.

## Próbatesztek (eldobható, merge előtt visszaállítva)

Mindkét próba `/tmp/review-e03-r01` izolált klónban futott, a mutáció után
`git checkout --` állította vissza a fixture-t; a `git status --short` a
próbák után tiszta volt.

1. **`song_multiple_chords.json` — `directionSequence` megfordítása.**
   `['d','d','u','u',...]` → megfordítva. Eredmény: **PIROS**
   (`song_multiple_chords direction sequence`, `at location [1] is 'd'
   instead of 'u'`). Igazolja, hogy a direction-sorrend valóban ellenőrzött,
   nem csak a multiset.
2. **`setlist_missing_song.json` — `unresolvedIds` kiürítése** (`['ghost']` →
   `[]`). Eredmény: **PIROS** (`setlist_missing_song unresolved ids`,
   `['ghost'] which longer than expected`). Igazolja, hogy a hiányzó
   setlist-referencia felismerése valóban tesztelt, nem csak a `resolve`
   sorrendje.

Ezek a próbák az implementer §10.4-ben bemutatott három mutáció-tesztjét
(durationSec, beat-warp, rest-dropping) egészítik ki két másik invariánssal
(direction-sorrend, unresolved-id lista) — összesen öt független invariáns
igazoltan diszkriminatív.

## Architektúra és termékhatárok (AGENTS.md §5/§6)

- `lib/features/song_trainer/public.dart` üres — nem exportál félkész
  contractot, nincs Practice-belső import. ✅
- `lib/app/config/feature_flags.dart` az új flaghez **nincs dart-define**
  override — konzisztens a másik három Practice flaggel, amelyeknek
  szintén nincs. ✅
- `tool/check_architecture.dart` a gate részeként lefutott, "12 allowlisted
  deviation(s)" — **ugyanannyi**, mint a pre-implementer baseline gate
  futtatásban (nincs új architektúra-kivétel bevezetve). ✅
- Nincs érintett audio/mikrofon/hálózat/secret útvonal — a kör kizárólag
  dokumentációt, egy bool flaget, egy üres boundary fájlt és tesztfixture-öket
  ad hozzá. §5 nem tárgyalható termékhatár nem érintett.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (§10.2) | Ellenőrizve (saját futtatás, `/tmp/review-e03-r01`) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld ("No issues found") | ✅ zöld |
| test test/features/songs | zöld | ✅ zöld (a gate-parancs része) |
| test test/features/learn/setlist_expected_hint_test.dart | zöld | ✅ zöld |
| test test/features/song_trainer/baseline | zöld (9/9) | ✅ zöld (9/9, saját futtatás) |
| architecture | zöld (12 allowlisted) | ✅ zöld (12 allowlisted, egyezik) |
| CI (teljes suite + property + APK) | — | run [30729257720](https://github.com/wolfcasaba/strumsight/actions/runs/30729257720), dispatch a `codex/e03-r01-baseline-and-boundaries` branch `9abe708` HEAD-jére; a review írásakor `in_progress` — a merge-döntés a run zöld lezárására vár. |

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
BLOCKER/MAJOR nulla; az egy MINOR (F1) nem blokkol (dokumentum-only, nem
befolyásol tesztet/gate-et/acceptance criteria-t). A merge feltétele a CI-run
([30729257720](https://github.com/wolfcasaba/strumsight/actions/runs/30729257720))
zöld lezárása a `9abe708` `headSha`-n — ezt az orchestrátor a merge előtt
külön ellenőrzi (`gh run view --json headSha,conclusion`).
