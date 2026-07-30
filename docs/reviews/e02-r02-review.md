# E02-R02 — Review

Brief: `docs/rounds/e02-r02-musical-time.md`
Diff: `git diff 22636ac..8c313d1` (10 fájl a briefen felül, +1053 / −2 a
`main`-hez képest, ebből a brief §10-kitöltése +113/−3)
Reviewer: Claude · Dátum: 2026-07-30
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 3

A kör pontosan azt szállítja, amit a brief kötött: a négy pure-Dart domain-fájl
az ADR 0066 tick-modelljét sorról sorra követi, a 24 új unit-teszt a §6 minden
pipáját fedi, és az architektúra-őr kiterjesztése valódi, kétirányban
bizonyított gépi invariánssá teszi a „domain Flutter-független" feltételt.
Scope-sértés nincs: a diff tételesen a §4 tábla, meglévő production-fájl nem
változott, a brief-fájlban kizárólag a §10 placeholder cserélődött (−3/+113).
A TDD-evidencia (öt valódi RED → GREEN pár) és a valódi-sértés próba kimenete
a §10-ben dokumentált, és reviewer-oldalon függetlenül reprodukálva lett — más
fájllal és más tiltott importtal, lásd „Gate-bizonyíték".

## Acceptance criteria — tételesen

| # | Kritérium | Bizonyíték | Állapot |
|---|---|---|---|
| 1 | Exact fractions (480/240/120/160; 3 triola == 1 negyed, 2 tizenhatod == 1 nyolcad, egzakt `==`) | `beat_position_test.dart` „uses 480 ticks…" + „represents supported fractions with exact integer equality" — tolerancia-argumentum sehol | ✅ |
| 2 | Triola-precizitás (6 triola == 2 negyed == 960; legacy `1/3` → 160, dokumentálva) | ugyanott: `eighthTriplets(6) == quarters(2)`, `.ticks == 960`; „rounds one third of a beat…" — a doc-comment a ≤ 1/960 beat hibát számszerűen rögzíti (`beat_position.dart:46-49`) | ✅ |
| 3 | Roundtrip fix tick-listán + nyolcad-grid nulla eltéréssel | „round-trips every supported deterministic subdivision position" (0…1920, benne 160/320 triola-tickek) + „converts the current half-beat grid without deviation" | ✅ |
| 4 | Legacy `0.5 → 240`, `1.0 → 480`, `1.5 → 720` | a grid-teszt páros listája indexre pontosan ezt állítja | ✅ |
| 5 | Negatív elutasítás valódi kivétellel mindhárom úton | „rejects negative data-driven positions in every runtime path": `fromTicks(-1)`, `fromLegacyBeats(-0.5)`, `eighths(-1)`, kivonás-alulcsordulás — mind `ArgumentError`, a `beatPosition.negative` kóddal az üzenetben; a const-assert külön tesztben | ✅ |
| 6 | Rendezés + `compareTo`/`==` konzisztencia + aritmetika | „sorts deterministically…" fix kevert lista, `orderedEquals`; azonos tick ⇒ `compareTo == 0`, `==`, azonos hash; összeadás/kivonás egzakt | ✅ |
| 7 | Tempo: 30.0/300.0 VALID, 29.999/300.001 `outOfRange`, NaN/±∞ `notFinite`, nincs clamp | `tempo_test.dart` mindhárom csoportja; a „without clamping" teszt a nyers `bpm`-et is visszaellenőrzi | ✅ |
| 8 | Meter: 4/4 és 3/4 valid; 0/17, beatUnit 5 invalid; `ticksPerBar` 1920/1440/1440; aggregáció | `meter_test.dart` — plusz a 2/2 (1920) eset és a kéthibás `unorderedEquals` aggregáció | ✅ |
| 9 | Flutter-függetlenség géppel + valódi-sértés próba | checker-diff `tool/check_architecture.dart:229-232` (csak a prefix + a szabályleírás); §10-ben a flutter-import piros/zöld kimenete; reviewer-oldali független törés-próba lásd lent | ✅ |
| 10 | A négy lib-fájl importlistája csak `dart:` core és egymás | diff-ből ellenőrizve: kizárólag relatív importok (`practice_validation.dart`, `beat_position.dart`), külső package-import nulla | ✅ |
| 11 | `git diff --stat` a §4 listán belül | 11 érintett útvonal = a §4 tábla 11 sora; meglévő fájl csak a checker és az architektúra-teszt (ott is csak bővítés) | ✅ |
| 12 | Meglévő tesztek zöldek | reviewer-oldali független újrafuttatás: `test/core` +287, `test/app` +47, `test/features/learn` +131 ~1 | ✅ |

## MINOR-1 — `Meter.ticksPerBar` őrzése aszimmetrikus

`meter.dart:41-53`: a nem támogatott `beatUnit` `StateError`-t dob, de az
out-of-range `beatsPerBar` csendben számol (`Meter(beatsPerBar: 0).ticksPerBar
== 0`, negatívnál negatív bar-hossz). A doc-comment kimondja, hogy előbb
validálni kell, a brief §5/6 pedig csak a három beatUnit-ágat kötötte — ez
tehát nem brief-sértés, hanem következetlenség: ugyanazon getter az egyik
invalid mezőre fail-fast, a másikra nem. Kockázattá az R06 target compilernél
válna (bar-boundary aritmetika negatív/nulla bar-hosszal). **Nem kér javítást
ebben a körben**; az R03 (domain-modellek validációja) vagy legkésőbb az R06
input-validációja zárja: vagy mindkét mező fail-fast a getterben, vagy
egyik sem, a compiler kötelező `validate()`-je mellett.

## NOTE-1 — `Tempo.==` double-egyenlőség NaN-nal

`tempo.dart:38-40`: két külön példányú `Tempo(double.nan)` nem egyenlő
(`NaN != NaN`), miközben `identical`-re igen. Gyakorlati hatása nincs — a
`validate()` a NaN-t `notFinite`-ként elutasítja, NaN tempó nem kerülhet
tovább —, de ha a Tempo később map-kulcs lenne, ez meglepetés. Nem kér
javítást; a viselkedés a Dart `double` szemantikájából következik.

## NOTE-2 — A checker-teszt kétirányú, ez maradjon minta

Az új „keeps the practice domain framework-free" eset egyszerre bizonyítja a
sértés-detektálást (flutter-import → violation) ÉS a nem-sértést (`dart:math`
→ tiszta) egyetlen szintetikus fában. Ez a helyes minta minden későbbi
guard-bővítéshez (R03+ domain-fájlok automatikusan védettek, mert a prefix
könyvtár-szintű).

## NOTE-3 — Codex follow-up lelet: `docs/LESSONS.md` nem létezik

A Codex §10-ben jelzett lelete governance-kérdés, nem e kör hibája: a globális
együttműködési szabályzat hivatkozik egy `docs/LESSONS.md`-re, ami ebben a
repóban sosem jött létre. Döntés Claude/user-oldalon: vagy létrehozni (a
handoff-archívum mintájára), vagy a hivatkozást kivezetni. Nem blokkoló.

## Scope, architektúra, termékhatárok

- **Production viselkedés:** változatlan — a négy új fájlnak nincs hívója a
  `lib/` fában (grep: a `BeatPosition`/`Tempo`/`Meter` neveket csak a domain
  és a tesztjei említik), a Learn/Progress/Streak érintetlen.
- **R03+ előrehozás nincs:** se PracticeEvent/Definition, se JSON, se
  `public.dart`, se Lesson-adapter.
- **ADR-megfelelés:** ADR 0066 §1–§3 és §5 tételesen implementálva; §4
  (perzisztencia tick-ben) helyesen csak doc-commentként jelenik meg — kód
  majd a perzisztencia-körökben.
- **Új ADR nem született, `docs/adr/` érintetlen** — a brief §2.5 szerint.
- A checker allowlist és a tiltott dependency-készlet változatlan; a
  szabályleírás-szöveg frissítése a meglévő teszt-elvárásokkal kompatibilis
  (a `test/core` +287 zöld bizonyítja).

## Gate-bizonyíték — reviewer-oldali független újrafuttatás

Izolált klónban (`/tmp/ss-review-e02r02`, `8c313d1`), külön hívásokként:

```text
dart format --output=none --set-exit-if-changed lib test tool
Formatted 460 files (0 changed) in 1.54 seconds.

flutter analyze lib/ test/ tool/
No issues found! (ran in 9.9s)

flutter test test/features/practice   → +24: All tests passed!
flutter test test/core                → +287: All tests passed!
flutter test test/app                 → +47: All tests passed!
flutter test test/features/learn      → +131 ~1: All tests passed!

dart run tool/check_architecture.dart
Architecture dependencies OK (12 allowlisted deviation(s)).
```

**Független guard-törés próba** (szándékosan MÁS fájl és MÁS tiltott import,
mint a Codex §10-beli próbája): `flutter_riverpod` import injektálva a
`tempo.dart`-ba →

```text
Architecture dependency check failed.
- lib/features/practice/domain/model/tempo.dart ->
  package:flutter_riverpod/flutter_riverpod.dart
  [shared music/audio and practice domains must remain framework-independent]
exit=1
```

→ visszaállítás után ismét `Architecture dependencies OK`. Az őr tehát nem a
Codex által próbált egy útvonalra van hangolva, hanem a teljes prefixre és a
teljes tiltólistára működik.

## Kért javítások (Codex)

Nincs — a MINOR-1 és a NOTE-ok nem e kör javítási kötelezettségei; a MINOR-1
az R03/R06 briefjébe kerül át.
