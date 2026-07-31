# E02-R10 review — Timing, direction és chord scorer

- **Kör:** E02-R10, brief [`docs/rounds/e02-r10-practice-scorers.md`](../rounds/e02-r10-practice-scorers.md), [ADR 0076](../adr/0076-practice-scoring-dimensions.md)
- **Branch / commit:** `codex/e02-r10-practice-scorers` @ **`11ffc49`** (implementer-commit), brief+ADR: `4e2289e` (orchestrátor)
- **Implementer:** **Codex** (ADR 0069 §15.6 szerinti ajánlás: baseline-érzékeny kör)
- **Reviewer:** Claude (Opus 5), read-only — **production kód nem íródott a review alatt**
- **Dátum:** 2026-07-31

## Verdikt

**APPROVED** — **0 BLOCKER · 0 MAJOR · 0 MINOR · 3 NOTE**.

A kör a projekt eddigi legerősebb mérce-anyagát hozta: a három kötelező
valódi-sértés próbám **mind a hármat pirosra fordította a megfelelő teszt**,
tehát az őrök valódiak, nem díszletek. A gate-et **saját kézzel, izolált
klónban** futtattam újra, és minden számszerű handoff-állítást **függetlenül
reprodukáltam**.

## 1. Kör-jelzés és handoff

`.codex-round-status`: `status=done`, `head=11ffc49`, `dirty_files=0`.

**Külön rögzítendő:** az első futást az `codex-round.sh` **3600 s-os abszolút
időkorlátja** lőtte ki (`status=timeout`, `dirty_files=12`, commit nélkül) —
**nem elakadás**: a munka és a zöld gate készen volt, a kilövés a §10 kitöltése
közben ért. A zárást a projekt crash-resume mintájával fejeztük be (ugyanaz a
session-id, `019fb8d7-…`), és a resume-prompt **kötelezővé tette a teljes gate
újrafuttatását** — a kilövés utáni zöldet nem fogadtuk el bemondásra. A §10-ben
közölt kimenet a resume utáni friss futásé.

*(Eszköz-lelet, nem a köré: a `codex exec resume` nem fogadja el a `-C` és a
`-s` kapcsolót; a sandbox-beállítás `-c sandbox_mode='"danger-full-access"'`
alakban adandó át. Az első resume-kísérlet emiatt exit 2-vel, munka nélkül állt
meg. Follow-up: a `tools/codex-round.sh` kapjon resume-módot.)*

## 2. Gate-újrafuttatás — saját kéz, izolált klón

```
git clone --branch codex/e02-r10-practice-scorers /home/ubuntu/ss-codex-e02-r10 /tmp/review-e02r10
cd /tmp/review-e02r10
tools/round-gate.sh test/features/practice/ test/property/practice_scorer_property_test.dart
→ GATE EXIT: 0
```

Mind az öt lépés (format · analyze · test ×2 · architecture) zöld, csővezeték
nélkül, külön processzként. **CI (teljes suite + randomizált property + APK):**
[run 30649405393](https://github.com/wolfcasaba/strumsight/actions/runs/30649405393),
a kör-branchre dispatch-elve.

## 3. Scope-audit — tiszta

Az **implementer-commit önmagában** (`git show --stat 11ffc49`) pontosan 13
fájl, mind a brief §4 engedélyezett listájáról:

- 6 production fájl (4 új service + `practice_metrics.dart` additív + `practice_verdict.dart` additív),
- 6 teszt (5 új unit/paritás + 1 property),
- `docs/rounds/e02-r10-practice-scorers.md` (kizárólag a §10).

`docs/adr/` a implementer-commitban **0 sor** (az ADR 0076 az orchestrátor
`4e2289e` commitjában van, ahogy a brief előírta). `lib/features/learn/`
**0 sor**. Az architektúra-allowlist **nem bővült** (`12 allowlisted deviation(s)`,
változatlan).

**A legszigorúbb scope-pont, tételesen ellenőrizve** — a `practice_verdict.dart`
diffje a §0.0/R2 szerinti **egyetlen** additív enum-érték, a végére fűzve:

```diff
-enum ChordOutcome { correct, wrong, insufficientData, notApplicable }
+enum ChordOutcome {
+  correct,
+  wrong,
+  insufficientData,
+  notApplicable,
+  noDetection,
+}
```

Se átnevezés, se átsorolás, se egyéb módosítás abban a fájlban.

## 4. Próbatesztek (eldobhatók, futtatva és visszaállítva)

A projekt mért tanulsága, hogy a zöld gate nem bizonyíték — ezért három
**valódi-sértés** próbát futtattam az izolált klónban, majd
`git checkout --`-ral visszaállítottam (a fa tiszta maradt).

| # | Beinjektált hiba | Elvárt őr | Eredmény |
|---|---|---|---|
| 1 | nulla-kitöltés a nem elérhető dimenzióra (`entry.value * (dimensionScore ?? 0)`, a `continue` nélkül) | A4 | **PIROS** — `does not fill an unavailable chord dimension with zero` + `pins every integer overall table cell` + egy továbbgyűrűző A5 cella |
| 2 | lebegőpontos `0.8 − 0.45 · ratio` alak a timing-képletben (§5.3 sértés) | A1 határcella | **PIROS** — `early 279999 us is exactly 351 per mille` **és** `late 279999 us …` |
| 3 | a `good` alappont 70 → **71** | A7 legacy paritás | **PIROS** — `matches score, combo, counters and direction across 51 scenarios` |

Mindhárom próba pontosan azt a tesztet fogta meg, amelyiknek a brief szerint
fognia kellett. A 3. próba a kör legfontosabb állítását igazolja: a
paritás-teszt **egyetlen pont elcsúszására** is érzékeny.

## 5. Acceptance criteria — független ellenőrzés

| # | Állítás | Ellenőrzés | Eredmény |
|---|---|---|---|
| A1 | timing-mátrix a származtatott ezrelékre | a megvalósított képletet `python3`-mal újraszámoltam mind a 6 nem-triviális cellára (50 001→800 · 120 000→800 · 200 000→575 · 279 999→351 · 280 000→350) | ✅ egyezik; `<=` határok, `~/` csonkítás, integer aritmetika |
| A2 | direction-mátrix + `notApplicable` vs. `insufficientData` | kódolvasás + a „volt jel, de nem talált be" eset külön keresése | ✅ fedve (lásd NOTE-1) |
| A3 | inkluzív aszimmetrikus `[−120 ms, +420 ms]` ablak, öt kimeneti ág | teszt-nevek + a `noDetection` ág megléte | ✅ mind a hat határcella + mind az öt ág |
| A4 | az el nem érhető dimenzió nem nulla | **1. próba** + a cellák újraszámolása | ✅ a helyes kód 1000-et ad, a hibás 650-et |
| A5 | completion-kapu és pass | teszt-nevek (16/17/18 × 699/700 mátrix + `incomplete` ág) | ✅ |
| A6 | combo a **növelés utáni** multiplierrel | kódolvasás (`combo++` → `points += base * _comboMultiplier(combo)`) + újraszámolás (5 perfect = 600) | ✅ legacy-sorrend |
| A7 | legacy paritás a védősávon kívül, egzakt | **saját futás:** `parity scenarios=51 excludedGuardBandEvents=0` + **3. próba** | ✅ 17 lecke × 3 latency = 51; **nulla** kizárt esemény, tehát a paritás mindenhol egzakt |
| A7b | a védősáv **mérve** | **saját futás:** `measuredEvents=348 maximumTimebaseDifferenceUs=0.489795919508 cell=anthem-drive[23]` | ✅ bitre az ADR 0075 §2b mért értéke, ugyanazon az eseményen |
| A7c | a sávba eső cellák kipinnelve, **valódi** eseménylistából | **saját futás:** `representativeDivergenceCells=18`, `exhaustiveDivergenceCells=3213 fingerprint=375672841`; a ciklus a tényleges `lesson.events`-en fut | ✅ (lásd NOTE-2) |
| A8 | minden verdict és az attempt `validate()`-je üres | teszt megléte + a gate zöldje | ✅ |
| A9 | randomizált property gate | a gate 4. lépése zöld, `PROPERTY_SEED=42`, 3 teszt az 5 invariánsra | ✅ |
| A10 | domain-tisztaság, nulla viselkedésváltozás | scope-audit (§3) + `architecture` lépés | ✅ hívó nincs, flagek OFF-ban, production viselkedés változatlan |

**A7b külön kiemelve:** az implementer által mért maximum
(`0.489795919508 µs`, `anthem-drive[23]`) **pontosan** az az érték és ugyanaz az
esemény, amit az E02-R09 az ADR 0075 §2b-ben kimért. Két egymástól független
kör, azonos szám — ez erős jel arra, hogy az időalap-eltérés valóban rendszeres
és lekötött, nem véletlen.

## 6. Leletek

### NOTE-1 — Az `observationsByTargetIndex` kettős szerepe alulspecifikált a párosítatlan megfigyelésekre

`lib/features/practice/domain/service/practice_direction_scorer.dart:117–125`

A map két dolgot szolgál: (a) a párosított célesemény irányának megadását,
(b) annak eldöntését, volt-e **egyáltalán** jel (`observationsByTargetIndex.isEmpty`
→ `noSignal`). A (b) szerep miatt a hívónak a **párosítatlan** megfigyeléseket
is bele kell tennie — de a map kulcsa `targetIndex`, és egy párosítatlan
megfigyelésnek nincs ilyen. A teszt
(`unmatched directional target is wrong when signal existed`) a `9`-es
sequence-értéket használja kulcsnak, ami működik, de nem szerződés.

**Nem hiba, és nem blokkol** — a viselkedés mindkét irányban helyesen tesztelt
(`MetricAvailable(0)`, ha volt jel; `noSignal`, ha nem). A kockázat az **R11-re**
száll: ha a controller csak a párosított megfigyeléseket teszi be, a „sokat
pengetett, de semmi nem talált be" eset **`noSignal`-ként** fog látszani, ami
hamis állítás az ellenkező irányba. Javasolt irány (R11 hatásköre): a hívó
oldalon nevesített kulcskonvenció, vagy a jel-jelenlét külön, explicit
paraméterként (`observedStrumCount`), hogy a (b) szerep ne a map ürességéből
következzen.

### NOTE-2 — Az A7c fingerprint diagnosztikája gyenge

`test/features/practice/domain/practice_scorer_legacy_parity_test.dart:213–286`

A brief A7c-je „minden hármas **saját tesztcellát** kap" előírást adott; az
implementáció 18 nevesített reprezentatív cellát + egy exhaustive bejárást ad,
`expect(divergenceCellCount, 3213)` és `expect(fingerprint, 375672841)`
lezárással. **Ez elfogadható, sőt tartalmilag erősebb** a 3213 külön `test()`-nél,
mert a bejárás **per-case** is állít (`|legacyTarget − compiledTarget| <= 0.5`,
a descriptorral mint `reason`), és az implementer az eltérést a §10-ben ki is
mondta.

A gyengeség a **hibaüzenet**: ha egy jövőbeli változás átmozgat egy divergenciát
egyik cellából a másikba, a fingerprint elhasal, de a kimenet csak két számot
mutat — nem mondja meg, melyik cella mozdult. Javasolt irány (follow-up, nem
ebben a körben): a fingerprint-eltérésnél a descriptorok halmazának diffje
kerüljön a `reason`-be.

### NOTE-3 — Ablakon kívüli párosított offset: fail-fast, ami nincs az ADR-ben

`lib/features/practice/domain/service/practice_timing_scorer.dart:150–154`

Ha egy **párosított** találat offsetje meghaladja a `matchWindow`-t, a scorer
`StateError`-t dob. Ez helyes védekezés (a matcher szerződése szerint ez az
állapot elő sem állhat) és illeszkedik a kör fail-fast vonalához, de az
ADR 0076 §3 táblázatában nincs nevesítve. Nem blokkol; az ADR egy mondattal
pontosítható, amikor legközelebb hozzányúlunk.

## 7. Termék- és architektúra-határok

- **Domain-tisztaság:** a négy service `package:meta`-n kívül csak domain-modellt
  és a matchert importálja; Flutter/Riverpod/Dio import nincs. Az `architecture`
  gate-lépés zöld, az allowlist nem bővült.
- **Audio/hálózat/mic/secret (AGENTS.md §5):** a kör egyikhez sem nyúl.
- **Lifecycle:** a service-ek `const`-példányosíthatók, állapotot nem tartanak,
  felszabadítandó erőforrásuk nincs.
- **Hívó nincs**, a practice flagek OFF-ban maradnak → **a production viselkedés
  bizonyíthatóan változatlan** (a `lib/` diff kizárólag új, senki által nem
  hívott fájlokat és két additív modell-bővítést tartalmaz).

## 8. Merge-döntés

A zöld kapu (ADR 0052) minden eleme:

| Gate | Állapot |
|---|---|
| format · analyze · architecture · a kör tesztjei · property | ✅ **saját** izolált futás, exit 0 |
| scope-audit az engedélyezett lista ellen | ✅ tiszta |
| valódi-sértés próbák | ✅ 3/3 a helyes tesztet fogta meg |
| CI: teljes suite + randomizált property + release APK | [run 30649405393](https://github.com/wolfcasaba/strumsight/actions/runs/30649405393) |

Nyitott BLOCKER/MAJOR/MINOR nincs → **a CI zöldje után squash-merge**, az
ADR 0086 §2 szerinti `origin/main` naprakészség-ellenőrzéssel.

## 9. Az R11-nek átadandó

1. **NOTE-1** — a jel-jelenlét szerződése a direction-scorer hívójánál dől el.
2. Az E02-R09 **NOTE-3** (rendezetlen, kézzel épített target) továbbra is nyitott,
   és az R11 hatásköre.
3. A `practiceCaptureActiveByStatus` tábla első valódi hívója és az E02-R07
   nyitott clock-NOTE-ja szintén az R11-ben zárul.
