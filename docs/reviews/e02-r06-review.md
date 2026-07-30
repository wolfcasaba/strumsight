# E02-R06 review — Target compiler és beat-idő konverzió

- **Kör:** E02-R06 · **Brief:** [`docs/rounds/e02-r06-target-compiler.md`](../rounds/e02-r06-target-compiler.md)
- **ADR:** [0072](../adr/0072-practice-target-compiler.md) · **Implementer:** Codex
- **Branch:** `codex/epic-02-round-06-target-compiler` — első review `1fd6125`, javítás után **`09ed793`**
- **Reviewer:** Claude (Opus 5), read-only — production kód nem készült a review során
- **Verdikt:** első kör **CHANGES REQUESTED** (0 BLOCKER · 0 MAJOR · 1 MINOR · 2 NOTE)
  → két javító kör után **APPROVED** (lásd §9)

## 1. Gate-ek — a reviewer SAJÁT futtatása

Izolált klón (`/tmp/review-e02r06`, a kör-branchről), a parancsok külön hívásokként:

```text
$ ~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
Formatted 506 files (0 changed) in 1.72 seconds.

$ ~/flutter/bin/flutter analyze lib/ test/
Analyzing 2 items...
No issues found! (ran in 7.3s)

$ ~/flutter/bin/flutter test test/features/practice/
00:21 +289: All tests passed!
```

A Codex §10-ben bemásolt kimenete **egyezik** a független futtatással (506/0 changed,
No issues found, 289 zöld) — nincs csonkolt vagy szépített gate-jelentés.

## 2. Scope-audit

`git diff --stat main...1fd6125` → **13 fájl**, mind a brief §4 engedélyezett
listáján; a tilos zónából **nulla** érintés. Nevezetesen: a `lib/features/learn/**`
parity-referencia, a `test/support/practice_baseline_scenarios.dart` és a
`legacy_scorer_baseline.json` érintetlen — a legacy oldalt nem igazította a
kimenethez. A `docs/adr/` nem módosult (a brief tiltása betartva).

## 3. MINOR-1 — ugyanaz a zenei pillanat két különböző időt kap (kerekítés-halmozás)

**Fájl:** `lib/features/practice/domain/service/practice_target_compiler.dart:163–170`
(`_barBoundaries`)

**Állítás.** Az ütemhatárok **két külön kerekített** érték összegeként állnak elő
(`countInDuration + converter.timeOfTicks(bar * ticksPerBar)`), miközben az
eseményidők **egyszer** kerekítenek (`converter.timeOfTicks(countInTicks + absoluteTicks)`,
:158). Így egy ütem-downbeatre eső esemény ideje eltérhet attól az ütemhatártól,
ami ugyanazt a pillanatot jelöli. Ez ellentmond az [ADR 0072 §1](../adr/0072-practice-target-compiler.md)
kimondott invariánsának: „a kerekítés **egyszer**, a végén történik".

**Bizonyíték (reviewer próbateszt, eldobható, a jelentés után törölve).**
2 ütemes 4/4 definition, 90 BPM, `countInBars: 1`; az 1. indexű esemény pontosan a
második zenei downbeaten ül:

```text
PROBE-1 event=5333333us boundary=5333334us delta=1us
  Expected: Duration:<0:00:05.333334>   // barBoundaries[2]
    Actual: Duration:<0:00:05.333333>   // events[1].time

PROBE-3 single(3840)=5333333us sum(1920+1920)=5333334us   // a gyökérok izolálva
```

Egy 1 ütemes definition ugyanezen a tempón a `totalDuration`-t is elmozdítja
(három külön kerekített tag összege):

```text
PROBE-2 compiled=8000001us legacy=8000000us delta=1us
```

**Hatás.** Ma nincs felhasználói következménye (1 µs, öt nagyságrenddel az 50 ms-os
`perfect` ablak alatt), és a szállított korpuszon a parity-teszt 0 µs-t mér. A
kockázat downstream: az E02-R07 session clock és az E02-R08 metronóm/scorer
természetes ellenőrzése az `event.time == barBoundaries[i]` **egyenlőség** egy
downbeat-eseményre — ez ma hamis. A §10 handoff „minden duration-kompozíció pontos"
állítása ebben a formában nem áll meg.

**Miért csak MINOR.** A hiba korlátos (legfeljebb 1 µs, nem halmozódik a
`loopCount`-tal, mert a `musicalDuration` egyetlen konverzióból jön), a kimenet
determinisztikus marad, és a javítás a diffet nem hizlalja.

**Javasolt irány (nem kész patch).** Az ütemhatárokat is egyetlen konverzióból
képezni — abszolút tickből: `converter.timeOfTicks(countInTicks + bar * ticksPerBar)`,
a `countInDuration` hozzáadása nélkül. Ugyanígy érdemes megnézni a `totalDuration`
összegzését (`countInDuration + musicalDuration + ringOutDuration`, :117):
abszolút tickből számolva a legacy egyszeri képlettel bitre egyezne minden
tempón, nem csak a mai korpuszon.

**Regressziós teszt a javításhoz (kötelező).** Olyan eset, ami MA PIROS: egy
downbeatre eső esemény `time`-ja legyen azonos a hozzá tartozó `barBoundaries`
elemmel, **90 BPM-en** (a 120 BPM nem fogja meg — ott a konverzió maradék nélküli).

## 4. Acceptance criteria — tételes ellenőrzés

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| §6.1 konverter (1042 µs/tick @120, round-trip, fail-fast, negatív `Duration`) | `beat_time_converter_test.dart` (116 sor); a `_ensureValid()` `StateError`-ja mindkét ágra tesztelt | ✅ |
| §6.2 szerkezet (bar-boundary hossz, 3/4 count-in, `loopCount: 3`, loop-rebase, érvénytelen loop, 5 hibakód, Free Practice, egy-eseményes, determinisztikus egyenlőség) | `practice_target_compiler_test.dart` (907 sor) — a `barBoundaries.length == countInBars + musicalBars + 1`, a `[countInBars] == countInDuration` és a `last` mind kipinnelve | ✅ (a `[i]` vs. `event.time` egyezés nincs mérve → MINOR-1) |
| §6.3 legacy parity | `practice_target_legacy_parity_test.dart`: 10 baseline scenario **és** 17 lecke × 3 speed, a teszt `expect(maximumEventDifference, 0)`-t állít — **szigorúbb**, mint a brief ≤ 1 µs-a; kihagyott tempó nincs | ✅ |
| §6.4 korpusz no-op | 28 nevesített ID (17 lecke + 10 builtin + 1 Daily Challenge) tételesen listázva, `totalBeats.ticks % ticksPerBar == 0` mind a 28-ra | ✅ — a szám nem bemondás |
| §6.5 expected-chord | `const ExpectedChordSegment` listák pontos µs-értékekkel kipinnelve; `first.start == Duration.zero`, `last.end == totalDuration`, hézagmentesség és „nincs két azonos szomszéd" ciklusban ellenőrizve | ✅ |
| §6.6 higiénia | `domain_purity_test.dart` zöld az új fájlokkal (a value-equality helper saját, nem `flutter/foundation`); az 5 új kód + `practice.target_uncompilable` kipinnelve | ✅ |
| §4 scope | 13/13 fájl a listán | ✅ |

## 5. Architektúra és termékhatárok

- **Domain-tisztaság:** az új fájlok framework-mentesek; a `listEquals` a saját
  `practice_value_equality.dart`-ból jön, nem `package:flutter/foundation.dart`-ból
  — ez a purity-guardot valóban kielégíti, nem megkerüli.
- **Production viselkedés változatlan:** a `compilePracticeTarget`-nek nincs hívója
  a `lib/` fában (a `PracticeTargetCompiler` és a `compilePracticeTarget` nevekre a
  grep csak a domaint és a tesztjeit hozza), a flagek OFF-ok, a Learn út érintetlen.
- **Védekező immutabilitás:** a `CompiledPracticeTarget` a konstruktorban készít
  `List.unmodifiable` snapshotot a három listamezőről — tehát nem a hívó
  jóhiszeműségére épít. A doc-comment állítása tesztben bizonyított.
- **Fail-fast következetesség:** a konverter `StateError`-ja illeszkedik a
  `Meter.ticksPerBar` E02-R02-ben lezárt mintájához; a validációs hibák
  kontrollált `Failure`-ök, nincs csendes clamp — az érvénytelen loop tesztje ezt
  kifejezetten méri.

## 6. NOTE-1 — a brief §6.5 saját kritériuma pontatlan volt

A brief a szegmens-kezdetet `timeOf(BeatPosition(360)) + countInDuration` alakban
írta elő — ez maga is kerekítés-halmozó forma. Az implementáció a jobbat választotta
(egyetlen konverzió abszolút tickből), és nem a brief betűjét másolta. **Ez helyes
döntés volt**; a brief kritériuma a hibás, nem a kód. A MINOR-1 javításakor a §6.5
szövegét is érdemes ehhez igazítani.

## 7. NOTE-2 — a „0 µs" korpusz-tulajdonság, nem invariáns

A parity-teszt `expect(maximumEventDifference, 0)`-ja a MAI 17 leckére és 10
scenarióra igaz, és jó, hogy szigorúbb a brief tűréshatáránál. Ugyanakkor a
PROBE-2 mutatja, hogy 90 BPM-es együtemes tartalomra a `totalDuration` már 1 µs-ot
tér el a legacy egyszeri képlettől — tehát a 0 µs a mai korpusz tulajdonsága, nem
a compiler bizonyított invariánsa. A MINOR-1 javítása ezt invariánssá tenné.

## 8. Mit kér a review

1. **MINOR-1 javítása** a §3 javasolt irányában + a megadott regressziós teszt
   (90 BPM, downbeat-esemény vs. ütemhatár).
2. A §10 handoff „minden duration-kompozíció pontos" mondatának pontosítása a
   javítás után mért állapotra.
3. Újrafuttatott záró gate-sor a javító commit után; a review ekkor frissül.

A javítás után a kör **APPROVED**-ra állítható; BLOCKER/MAJOR nincs, a merge-et
kizárólag a MINOR-1 tartja vissza (a diff nem nő érdemben, ezért körön belüli
javítás indokolt, nem follow-up).

---

## 9. Javító körök és zárás — **APPROVED** @ `09ed793`

### 9.1 A javítás két körben ment, mindkét megállás helyes volt

**Javító kör #1 → `stopped`.** Az ütemhatárok átállítása egyetlen konverzióra
rendben lement, a két kért regressziós teszt megszületett — de a review 2. pontja
(`totalDuration` egyszeri konverziója) a kör **saját** korpusz-tesztjének
kompozíciós állításába ütközött: `lesson.first-strums.v1` → 20 571 429 µs
(egyszeri) vs 20 571 428 µs (a három komponens összege). A Codex nem gyengítette
csendben a saját állítását, hanem megállt és jelentette a számokat.

**A lelet valós volt, és a review kérése hiányos.** Egész mikroszekundum mellett
nem tartható egyszerre, hogy (a) minden időtartam a saját tickszámának egyszeri
konverziója, és (b) a részek összege kiadja az egészet. A feloldás tervezői
döntést igényelt, ezért az **ADR 0072 új §1.1** szakaszt kapott
(*pillanat pontos, időtartam származtatott*, commit `c5e71e0`): minden abszolút
pillanat a nullponttól vett tickszám egyetlen konverziója, minden időtartam két
pillanat különbsége — így mindkét tulajdonság egyszerre teljesül.

**Reviewer-önkorrekció.** Az első javító prompt „meglévő tesztet ne írj át"
kitétele túl tág volt: a Codex ezért a saját, ebben a körben írt tesztjét is
érinthetetlennek vette. A második prompt megkülönbözteti a **befagyasztott**
teszteket (baseline, korábbi körök — zártak) a kör saját tesztjeitől
(a szerződés változásakor igazíthatók). A megállás emiatt volt indokolt, nem
a Codex hibája.

**Javító kör #2 → `done`** (`09ed793`, „fix(practice): derive durations from
timeline moments"): a compiler `countInEnd` / `musicalEnd` / `sessionEnd`
pillanatokból származtatja a három időtartamot, az ütemhatárok abszolút tickből
jönnek. Diff: 5 fájl, +133/−16 — nem hizlalta a kört.

### 9.2 MINOR-1 zárva — a reviewer próbateszt ELŐTTE/UTÁNA

Ugyanaz a próbateszt a javított kódon (`/tmp/review-e02r06b`, friss klón):

```text
                        ELŐTTE (1fd6125)         UTÁNA (09ed793)
PROBE-1 (downbeat)      5333333 vs 5333334us     5333333 vs 5333333us  → delta 0
PROBE-2 (totalDuration) 8000001 vs 8000000us     8000000 vs 8000000us  → delta 0
PROBE-3 (kompozíció)    —                        total == sum (13333333us)
```

A MINOR-1 tehát nem „elvileg javítva", hanem **mérten**: a downbeat-esemény és az
ütemhatára ma azonos időt kap, és a `totalDuration` maradékos tempón (90 BPM) is
bitre egyezik a legacy egyszeri képlettel. A NOTE-2 ezzel szintén rendeződött: a
0 µs már nem a korpusz tulajdonsága, hanem a §1.1-ből következő invariáns.

### 9.3 Gate-ek a javítás után — újra a reviewer saját futtatása

Friss izolált klón a javított branchről:

```text
$ ~/flutter/bin/dart format --output=none --set-exit-if-changed lib test
Formatted 506 files (0 changed) in 1.70 seconds.

$ ~/flutter/bin/flutter analyze lib/ test/
Analyzing 2 items...
No issues found! (ran in 7.0s)

$ ~/flutter/bin/flutter test test/features/practice/
00:21 +291: All tests passed!
```

289 → **291** (a két új regressziós teszt). A korpusz-teszt kompozíciós állítása
változatlanul benne van és zöld — ez a legerősebb bizonyíték, hogy a §1.1 nem
lazítás, hanem szigorítás.

### 9.4 Verdikt

**APPROVED** @ `09ed793`. BLOCKER/MAJOR nincs, a MINOR-1 mérten zárva, a NOTE-1
(brief §6.5 pontatlan kritériuma) és a NOTE-2 rendezve. A kör mehet a zöld
kapura: CI-dispatch a kör-branchre, majd merge.
