# E03-R03 — Review

Brief: `docs/rounds/e03-r03-song-structure-and-time-map.md`
Diff: `git diff 053376a...7433c0e` (PR [#59](https://github.com/wolfcasaba/strumsight/pull/59), branch `codex/e03-r03-song-structure-and-time-map`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-02
Verdikt: **APPROVED** (javító kör #1 után, `7433c0e`)

## Összegzés

Első menet: BLOCKER 0 · MAJOR 1 (F1) · MINOR 2 (F2/F3) · NOTE 2 (F4/F5).
Javító kör #1 (M3, `7433c0e`) után: **F1/F2/F3 FIXED, ellenőrizve.** F4/F5
nyitva maradnak nem-blokkoló follow-upként (ld. lent). BLOCKER: 0 · MAJOR: 0
nyitott · MINOR: 0 nyitott · NOTE: 2 nyitott (nem blokkol).

**Folyamat-megjegyzés (nem M3 hibája — orchestrátor-oldali eljárási hiba,
utólag dokumentálva a lessons-nek):** a javító kör első `resume` hívása a
router saját scope-audit-jában `BLOCKED`-ba futott, mert az orchestrátor a
READY_FOR_REVIEW diffet ÉS a review-jelentést commitolta a `resume` hívás
ELŐTT (HEAD elmozdult a router által rögzített baseline-tól), és egy
`review-findings-fix1.md` fájl track-eletlenül maradt a munkapéldányban. A
router emiatt jelzett `blocked`-ot — de a `.ai/runs/E03-R03/router-result.json`
és a munkapéldány git-státusza szerint M3 a hívás során ténylegesen lefutott
(`m3_attempts: 2`) és PONTOSAN a kért javításokat készítette el, hibátlanul,
scope-tisztán. Az orchestrátor a diffet kézzel auditálta (tartalom, scope,
gate, purity — mind zöld) és `7433c0e` alatt saját authorship-szel commitolta
— ugyanaz a minta, mint a `docs/LESSONS.md` L50 (E03-R02 H6): a diff a
bizonyíték, nem az őt előállító hívási útvonal. Ez NEM H4/H6 halt-ok — az
ütköző előfeltétel az orchestrátor SAJÁT, még nem merge-elt munkamenetének
git-kezelése volt, nem a modell képessége vagy a router infrastruktúrája.

Implementer: **auto MiniMax-first router** (ADR 0088), 1 M3 attempt,
`READY_FOR_REVIEW`. Orchestrator (Claude Sonnet 5) audited scope, ran the
local gate + the out-of-round-scope domain-purity test, committed the diff
under its own authorship (`72eea92`), opened PR #59, dispatched CI.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | 3/4 és 4/4 teljesen, 6/8 reprezentációként támogatott; pickup explicit rövidebb lehet | ✅ (implementáció), ⚠️ (teszt-lefedettség, ld. F2) | `Meter(3,4).beatsPerMeasure==3`, `Meter(6,8).beatsPerMeasure==3` tesztelve (`song_structure_test.dart:54-55`); `Meter(4,4).beatsPerMeasure==4` NEM tesztelt a körben, reviewer-próbával igazolva helyesnek (`song_time_map_review_probe_test.dart`, törölve) |
| 2 | Beat→time→beat property érvényes a dokumentált tolerancián belül és output monoton | ✅ | `test/property/song_time_map_property_test.dart` — 500 rendezett, seedelt minta, ≤1 tick tolerancia, monoton; reviewer független round-trip próba emelkedő tempóra is (60→120bpm) zöld |
| 3 | Tempo/meter change előtt, pontosan rajta és utána folytonos, determinisztikus eredmény születik | ✅ (implementáció), ⚠️ (teszt-lefedettség, ld. F3) | A round saját `song_time_map_test.dart` csak egy határpontot (beat 4) és egy ms-tartománybeli "előtte" pontot (1999 ms) fed le, tick-pontos ±1 nincs a körben; reviewer független referencia-formulával (nem az implementáció saját `microsecondsForTicks`-ja) igazolta tick 1919/1920/1921-en, hogy a left-closed policy helyes és szigorúan monoton — ld. F3 |
| 4 | Speed 0.5 kétszeres, 1.0 parity, 2.0 fele durationt ad source-mutáció nélkül | ✅ | `song_time_map_test.dart:38-53` — közvetlenül teszteli mindhárom speedet és `source.changes.single.bpm` változatlanságát |
| ADR 0093 (§5.4) — nincs Practice Engine import | ✅ | `grep -rnE 'package:strumsight/features/practice/...' lib/features/song_trainer/domain/` üres; `flutter test test/features/song_trainer/domain/song_document_test.dart` (Domain purity csoport) zöld a review-klónban is |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.** `git diff --stat 053376a..7433c0e` 14 fájlt érint: a brief §4 pontosan 13 útvonala (a pre-flight-hozzáadott `docs/adr/0093-...md`-vel együtt) + `docs/reviews/e03-r03-song-structure-and-time-map-review.md` — utóbbi a review-folyamat saját, a `docs/execution/09-review-report.md` szabálya szerinti artefaktuma (merge előtt commitolva, ugyanaz a minta, mint az E03-R02 review-jé). A modell egyik kör (kezdeti vagy javító) alatt sem committolt — mindkét tartalmi commitot (`72eea92`, `7433c0e`) az orchestrátor auditálta és commitolta saját authorship alatt.

## Megállapítások

### F1 — MAJOR — `SongDocument.operator==`/`hashCode` nem veszi figyelembe az ebben a körben bevezetett strukturális mezőket

- **Fájl:** `lib/features/song_trainer/domain/models/song_document.dart:161-186`
- **Probléma:** a kör a `sections`/`measures`/`tempoMap`/`meterMap`/`keyMap` mezőket `late final`-ként a konstruktor TÖRZSÉBEN adta hozzá (a `assets`/`markers`-szel ellentétben, amik az initializer listában vannak), de az `operator==` és a `hashCode` egyike sem lett kiterjesztve ezekre az új mezőkre — mindkettő pontosan a R02-ből változatlan mezőkészletet (`schemaVersion`/`id`/`revision`/`metadata`/`source`/`assets`/`markers`/`createdAt`/`updatedAt`) hasonlítja.
- **Hatás:** két `SongDocument`, amely `id`/`revision`/`metadata`/`source`/`assets`/`markers`/időbélyegek tekintetében azonos, de **teljesen eltérő** `sections`/`measures`/`tempoMap`/`meterMap`/`keyMap` tartalommal rendelkezik, `==`-lel EGYENLŐNEK és azonos `hashCode`-únak minősül. Ez pontosan az a fajta silent-corruption minta, amit a projekt kifejezetten kerülni akar (ADR 0089 §Döntés 3: a `revision` optimistic-concurrency célja, hogy két versengő szerkesztés ne írja felül némán egymást — de ha az equality maga vak a strukturális tartalomra, a repository-rétegben (E03-R04+) épülő konfliktus-észlelés és bármilyen `Set`/`Map<SongDocument,...>`-alapú dedup/cache némán rossz eredményt ad).
- **Bizonyíték (eldobható próba, futtatva, PIROS a jelenlegi kódon, törölve a review után):** két dokumentum, amely kizárólag `tempoMap`-ben (120 vs 200 BPM) és `sections`-ben (Intro 0-2 vs Outro 5-9) tér el, mindkettő `revision: 1` és egyébként azonos mezőkkel — `expect(a, isNot(equals(b)))` **elbukik**: `a == b` igaz, és (bár külön nem loggoltam) az `Object.hash` bemenete is azonos, tehát `a.hashCode == b.hashCode` szintén igaz. Reprodukció: `test/features/song_trainer/domain/song_document_equality_probe_test.dart` (a review jelentéssel együtt mellékelve, NEM része a végleges diffnek).
- **Kötelező javítás:** `operator==` és `hashCode` bővítése a hiányzó öt mezővel (`sections`/`measures` lista-egyenlőséggel — a meglévő `_listEquals` mintát követve vagy `SongSection`/`SongMeasure`-ön `==` hozzáadásával, amennyiben azok maguk még nem value-equal; `tempoMap`/`meterMap`/`keyMap`-hoz hasonlóan value-equality kell a saját osztályaikon, amik jelenleg SEM definiálnak `==`/`hashCode`-ot — ld. `tempo_map.dart`, `meter_map.dart`, `key_map.dart`: `TempoMap`/`MeterMap`/`KeyMap`/`TempoChange`/`MeterChange`/`KeyChange` egyike sem override-olja az `Object` alapértelmezett identity-equalityt, tehát MA két, tartalmilag azonos de külön példányosított `TempoMap` sem egyenlő egymással — ezt is javítani kell, különben az öt mező hozzáadása a `SongDocument`-en nem old meg semmit).
- **Ellenőrzés:** a mellékelt reprodukciós teszt (vagy azzal ekvivalens, a `test/features/song_trainer/domain/song_structure_test.dart`-ba felvett eset) PIROSBÓL ZÖLDRE váltása, plusz egy pozitív eset (két, mezőnként azonos tartalmú, de külön példányosított dokumentum/map egyenlő marad és azonos hash-t ad).
- **Státusz:** **FIXED** (`7433c0e`) — `SongSection`/`SongMeasure`/`TempoChange`+`TempoMap`/`MeterChange`+`MeterMap`/`KeyChange`+`KeyMap` mind kaptak value-equal `operator==`/`hashCode`-ot, a `SongDocument` equality/hash az öt új mezővel bővült. Reprodukciós teszt felvéve `song_structure_test.dart` "compares structural fields by value" néven — pozitív (egyenlő tartalom → egyenlő + azonos hash) ÉS negatív (eltérő `sections`/`tempoMap` → nem egyenlő + eltérő hash) esettel. Reviewer újra futtatta friss `/tmp` klónban: zöld.

### F2 — MINOR — `Meter(4,4)` nincs közvetlenül tesztelve a kör saját suite-jában

- **Fájl:** `test/features/song_trainer/domain/song_structure_test.dart:45-56`
- **Probléma:** az acceptance criteria #1 explicit "4/4 teljesen támogatott" állítást tesz, a teszt viszont csak 3/4-et és 6/8-at fed le.
- **Hatás:** alacsony (az implementáció maga helyes, reviewer-próbával igazolva), de egy jövőbeli regresszió a `beatsPerMeasure` számításban (`numerator * 4 ~/ denominator`) 4/4-en a kör saját gate-je mellett észrevétlen maradhatna.
- **Kötelező javítás:** egy `expect(Meter(4, 4).beatsPerMeasure, 4)` sor a meglévő "supports pickup and common meters" teszthez.
- **Ellenőrzés:** a kiegészített teszt fut és zöld.
- **Státusz:** **FIXED** (`7433c0e`) — `expect(Meter(4, 4).beatsPerMeasure, 4)` felvéve.

### F3 — MINOR — a brief §6 kötelező megkülönböztető mátrix "tempo change −ε/pontosan/+ε" sora nincs tick-pontosan lefedve a kör saját suite-jában

- **Fájl:** `test/features/song_trainer/domain/song_time_map_test.dart:25-36`
- **Probléma:** a meglévő "tempo boundary is continuous and invertible" teszt csak a beat-4 határpontot és egy ms-tartománybeli "előtte" időpontot (1999 ms, ami idő-, nem tick-domain) ellenőrzi; nincs tick-pontos −1/pontosan/+1 eset a tempóhatáron sem `timeAt`, sem — ami külön hiányosság — `durationBetween` nem-nulla kezdőponttal (a `SongTimeMap._tempoIndex` szegmens-kereső logikáját a kör egyetlen meglévő tesztje sem hívja meg nullától eltérő induló pozícióval).
- **Hatás:** alacsony (a reviewer független referencia-formulával igazolta, hogy a viselkedés helyes és a left-closed policy konzisztens mindkét irányban, ÉS hogy a `_tempoIndex` egy off-by-one hiba esetén is önkorrigál a fő ciklus szerkezete miatt — ez utóbbi robusztusság dokumentálásra érdemes, nem hiba), de a brief §6 kifejezetten "kötelező" mátrixcellaként nevezi meg ezt, és a kör saját gate-je ma nem bizonyítja.
- **Kötelező javítás:** legalább egy tick-pontos −1/pontosan/+1 eset felvétele `song_time_map_test.dart`-ba (timeAt-tal), és egy `durationBetween`-hívás nem-nulla, határponton lévő kezdőpozícióval.
- **Ellenőrzés:** a kiegészített tesztek futnak és zöldek.
- **Státusz:** **FIXED** (`7433c0e`) — új "uses the new tempo from the exact tick boundary" teszt: tick −1/pontosan/+1 a `timeAt`-tal (1998958 µs / 2 s / 2002083 µs, egyezik a reviewer független referencia-számításával), plusz `durationBetween(boundary, boundary+1tick)` nem-nulla, határponton lévő kezdőponttal (2083 µs).

### F4 — NOTE — SDD §9.5 section/measure kereszt-határ szabálya nincs kikényszerítve

- **Fájl:** `lib/features/song_trainer/domain/models/song_document.dart`
- **Megfigyelés:** az SDD §9.5 ("range nem léphet ki a dalból") szabályt a `SongDocument` konstruktora ma nem validálja `sections` és `measures` között — egy `SongSection` `endMeasureExclusive` értéke tetszőlegesen túlnyúlhat a `measures.length`-en. A brief §6 acceptance criteria ezt nem nevezi meg explicit R03-mérceként, ezért NEM blokkoló, de érdemes egy jövőbeli körben (vagy egy §0.0-stílusú brief-pontosításban) tisztázni, hogy ez R03 vagy egy későbbi kör (pl. az importer/edit-flow) felelőssége.
- **Státusz:** nem blokkol, follow-up jelölt

### F5 — NOTE — `KeySignature.tonic` (-6..11) tartománya dokumentálatlan

- **Fájl:** `lib/features/song_trainer/domain/models/key_map.dart:7-11`
- **Megfigyelés:** a `tonic` érvényes tartománya (-6..11, összesen 18 érték) nem szokványos kódolás (sem a hagyományos ±7 kvint-kör, sem a 0-11 kromatikus skála), és nincs doc-comment, ami megmagyarázná a választott reprezentációt. A round scope-ja ("locale-független minimális reprezentáció") ezt technikailag teljesíti, de karbantarthatósági szempontból egy rövid komment megérne.
- **Státusz:** nem blokkol, MINOR-szintű follow-up javasolt egy javító körben, ha F1/F2/F3 úgyis nyitva van

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ (friss `/tmp/review-e03-r03-fix1` klónban, `7433c0e`-n újrafuttatva) |
| analyze | zöld | ✅ |
| célzott tesztek (3 fájl, §7) | zöld | ✅ (friss klónban újrafuttatva) |
| architecture | zöld (12 allowlisted deviation, változatlan) | ✅ |
| domain purity (`song_document_test.dart`, kör-scope-on kívüli, de a teljes suite futtatja) | zöld | ✅ (friss klónban külön futtatva) |
| CI (teljes suite + property + APK) | dispatch alatt (`7433c0e`-re újradispatchelve a javító kör miatt) | ⏳ — az orchestrátor a merge ELŐTT ellenőrzi a run `headSha`-ját a lokális HEAD-del |

## Merge-döntés

Az ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
F1/F2/F3 zárva, ellenőrizve. Merge feltétele: a CI (teljes suite + randomizált
property + APK) zöld legyen PONTOSAN a `7433c0e` SHA-n — ezt az orchestrátor a
merge előtt `gh run list --json headSha` ↔ `git rev-parse HEAD` összevetéssel
igazolja (AGENTS.md §3 kötelező ellenőrzés, L21).
