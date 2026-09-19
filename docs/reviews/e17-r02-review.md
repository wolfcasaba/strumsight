# E17-R02 — független review (Claude Opus 5, orchestrátor/reviewer)

- **Kör:** `E17-R02` · **Branch:** `sonnet-impl/e17-r02-analysis-v2-capture-wiring` · **PR:** [#602](https://github.com/wolfcasaba/strumsight/pull/602)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`) · **Implementációs commit:** `387ff542`
- **Brief:** [`docs/rounds/e17-r02-analysis-v2-capture-wiring.md`](../rounds/e17-r02-analysis-v2-capture-wiring.md) · **ADR:** [`0584`](../adr/0584-analysis-capture-flow-guard-and-open-contract.md)
- **Review módja:** read-only, IZOLÁLT klón (`/tmp/review-e17-r02`, `--no-local`, `387ff542` detached), saját `prepare-flutter-generated.sh`, eldobható próbatesztek.

## 1. Mit mértem magam

```
$ flutter test test/features/audio_analysis/capture_wiring_test.dart       # /tmp/review-e17-r02
00:02 +7: All tests passed!

$ python3 tools/scope-audit.py --repo /home/ubuntu/ss-sonnet-impl-e17-r02 \
    --brief docs/rounds/e17-r02-analysis-v2-capture-wiring.md --base bec50d48
Legacy scope audit OK (bec50d48acc0..387ff542a82a, 3 changed path(s), 0 generated/ignored)

$ git diff --stat bec50d48..387ff542
 docs/rounds/e17-r02-analysis-v2-capture-wiring.md  | 137 ++++++
 lib/app/routing/app_router.dart                    |  26 +-
 test/features/audio_analysis/capture_wiring_test.dart | 457 +++++++++++++++++++
```

### Eldobható próbatesztek (valódi-sértés, a review SAJÁT mérése)

| Próba | Mit rontottam el | Elvárt | Mért |
|---|---|---|---|
| **C** | `onOpenAnalysis` visszaírva a kör előtti `extra: summary` alakra | A6 PIROS | `+5 -2` — **mindkét A6 cella piros** ✅ |
| **B2** | a processing route-builder `ref.watch` → `ref.read` (a képernyő nem frissül az állapotváltásra) | A2 PIROS | `+7: All tests passed!` — **ZÖLD marad** ❌ (lásd MAJOR-1) |
| **B** | a route-builder a valós állapot helyett konstans `AnalysisIdle`-t ad | A2 PIROS | fordítási hiba (`AnalysisIdle` nincs importálva a routerben) — a próba nem értékelhető, B2 váltotta ki |

Az implementer két saját próbája (A3 kapun kívüli route, A6 visszaírás) a §10-ben
dokumentált; a C próbával az A6-ot függetlenül reprodukáltam.

## 2. Leletek

### MAJOR-1 — az A2 cella TÖBBET ígér, mint amit mér: a `watch` → `read` regresszió zölden átmegy

**Mérve** (B2 próba, izolált klónban): a `app_router.dart` processing-buildere

```dart
final state = ref.watch(analysisControllerProvider);   // eredeti
final state = ref.read(analysisControllerProvider);    // a próba
```

`read`-re állítva a képernyő az ELSŐ build állapotán ragad (soha nem lép tovább
`AnalysisAnalyzing` → `AnalysisCompleted`-re), tehát a felvevő-ág a
feldolgozó-képernyőn zsákutcába fut. **A kör kapuja ezt nem veszi észre:**
mind a 7 cella zöld marad.

A cella címe és a brief A2 sora ezzel szemben azt állítja, hogy „a processing
képernyő a `analysisControllerProvider` állapotát mutatja" / „renders exactly
that state". A mérés valójában (a) a controller állapotát olvassa a
`container`-ből és (b) a képernyő TÍPUSÁT keresi — a kettő között nincs
bizonyított kapcsolat. Ez pontosan az a hibaosztály, amiért ez a kör egyáltalán
létezik (`AGENTS.md` §12, [L09](../LESSONS.md#l09)): a szövegesen leírt előírás
mellé GÉPI mérce kell.

**Javítás (a kör `allowed_paths`-án belül, csak a tesztfájl):** az A2 cella az
állapotváltás UTÁN mérje a képernyő TARTALMÁT is — a `cancel()` hívás után a
`AnalysisCancelled` ág saját, kulcsolt/„restart" törzsének meg kell jelennie
(`_CancelledBody`), miközben az `AnalysisAnalyzing` törzse eltűnik. Egy ilyen
cella `read` mellett pirosra vált, mert a képernyő nem épül újra.

### MINOR-1 — a `_openStoredAnalysis` Future-je `unawaited` nélkül dobódik el

`app_router.dart:1102` — `onOpenAnalysis: (summary) => _openStoredAnalysis(...)`.
A fájl minden más helyen `unawaited(...)`-tel jelöli a szándékosan nem várt
Future-t (pl. a `onFinished` ág 4 sorral feljebb). Az analyzer ma nem panaszkodik
(a `void` kontextus elnyeli), de a fájl saját, következetes jelölése olvashatóbb
és a `discarded_futures` későbbi bekapcsolásakor nem lesz lelet. Nem blokkoló.

### NOTE-1 — a fail-closed ág egy köztes route-on keresztül megy

Hibánál `context.go(AppRoutes.analysisTimeline)` fut `extra` nélkül, és a route
SAJÁT `redirect`-je küld a Live képernyőre. Ez szándékos (ADR 0584 §5.4: a
fail-closed döntés EGY helyen, a route-ban él), és a A6 második cellája méri is.
Rögzítem, hogy a jövőbeli olvasó ne „fölösleges ugrásnak" olvassa.

### NOTE-2 — az A2 valós V2 isolate-futást indít

A cella a szállított `analyze()`-t hívja (ADR 0254 lánc), és a `cancel()`-lel
determinisztikusan zárja. Ez a legerősebb mérés, de a CI futásidejére érzékeny;
ha a jövőben flakyvé válik, a lezárás módját kell erősíteni, nem a cellát
gyengíteni.

## 3. Scope, tiltások

- **A5 teljesül:** `lib/features/analyze/**` nem szerepel a diffben.
- **A7 teljesül:** `lib/l10n/**` és `lib/app/config/feature_flags.dart` nem szerepel a diffben — az `audioAnalysisV2Enabled` alapértéke érintetlen.
- Egyetlen meglévő tesztcella sem törölve/`skip`-elve/gyengítve (a diff a `test/` alatt CSAK új fájlt visz).
- A gépi scope-audit 0 sértést mért (a wrapper `scope_audit` kulcsa hiányzott a jelzésfájlból → kézzel futtatva, l. §1).

## 4. Verdikt (első kör)

**CHANGES REQUESTED** — 1 nyitott MAJOR (MAJOR-1). A javító kör tárgya kizárólag
a `test/features/audio_analysis/capture_wiring_test.dart` A2 cellájának
megerősítése; MINOR-1 ugyanabban a körben elvégezhető.

## 5. Javító kör (`19ece76b`) — leletenkénti zárás

A javító kört UGYANAZ a motor (`sonnet-impl`) vitte, ugyanazon a branchen, a
fenti leletlistával. Diff: `+59 −1` három fájlon (`capture_wiring_test.dart`
+18, `app_router.dart` 1 sor, a brief §10 +40). Gépi scope-audit a wrappertől:
`scope_audit=ok`, `scope_audit_base=387ff542`, `scope_audit_changed=3`.

| Lelet | Zárás | A review SAJÁT mérése |
|---|---|---|
| **MAJOR-1** | **ZÁRVA** — az A2 cella a `cancel()` UTÁN a `AnalysisCancelled` törzs tartalmát is méri (`analysis-processing-cancelled-title`, `analysis-processing-restart` jelen, `analysis-processing-step` eltűnt) | a B2 próbát (`ref.watch` → `ref.read`) a `19ece76b`-n megismételtem az izolált klónban: **`+4 -1` — az A2 cella PIROS** (`Found 0 widgets with key [<'analysis-processing-cancelled-title'>]`), rontás nélkül `+7: All tests passed!` |
| **MINOR-1** | **ZÁRVA** — `unawaited(_openStoredAnalysis(context, ref, summary))` | a diffben látszik, az `analyze` zölden fut |
| NOTE-1, NOTE-2 | rögzítve, nem igényel változtatást | — |

```
$ flutter test test/features/audio_analysis/capture_wiring_test.dart   # /tmp/review-e17-r02 @ 19ece76b
00:02 +7: All tests passed!

$ # ugyanott, a watch -> read rontással:
00:02 +4 -1: A2 — ... renders exactly that state [E]
  Expected: exactly one matching candidate
    Actual: _KeyWidgetFinder:<Found 0 widgets with key [<'analysis-processing-cancelled-title'>]: []>
00:03 +6 -1: Some tests failed.
```

## 6. VÉGSŐ DÖNTÉS

**APPROVED** — 0 nyitott BLOCKER/MAJOR/MINOR. A merge feltétele változatlanul a
zöld kapu a merge SHA-n: `full-gate.yml` + `router-ci.yml` `success`.
