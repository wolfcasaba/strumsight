# E13-R22 review — Practice result, history és Speed Builder UI

- **Kör:** `E13-R22`
- **Branch:** `sonnet-impl/e13-r22-practice-results-and-speed-builder`
- **Reviewelt HEAD:** `dffb8b49`
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Reviewer:** Claude (Opus 5), orchestrátor-session, READ-ONLY
- **Izolált review-klón:** `/tmp/review-e13-r22` (a közös working tree-ben
  próbateszt nem futott)
- **Kockázat:** `high` (a diff a felhasználó teljes gyakorlási előzményét
  jeleníti meg) — a biztonsági/adatvédelmi pász a §5-ben

## 1. Verdikt

**VÉGSŐ DÖNTÉS: APPROVED** — EGY javító kör után (`0111e6e5`, `11e93d9d`,
`e3dab048`), **0 nyitott lelet**. A leletenkénti zárás a §8-ban, a reviewer
SAJÁT méréseivel.

Az első kör verdiktje **CHANGES REQUESTED** volt — 1 MAJOR, 2 MINOR, 1 NOTE.

A MAJOR **teljesen zöld kapu mögött él**: a lokális 16-lépéses gate a
reviewer saját, izolált klónjában is MINDEN lépésre zöld (§3), és a kör SAJÁT
cellája a hibás viselkedést **elvárásként pinneli** — pontosan az
[L495](../LESSONS.md#l495) hibaosztálya, egy körrel a mérése után.

## 2. Leletek

### MAJOR-1 — a Speed Builder aktív felülete GYÁRTOTT méréseket ad az engine-nek, és az eredményt mértként közli

`lib/features/practice/presentation/screens/speed_builder_screen.dart:59-69`,
`:105-136`, `:200-216`

Az aktív elrendezés két production gombot szállít — „Record pass" /
„Record miss" (`speedBuilderRecordPass`, `speedBuilderRecordFail`, mindkettő
lokalizálva `en` **és** `hu` nyelven) —, amelyek minden érintésre egy
`_syntheticAttempt(...)` hívással KITALÁLT `PracticeAttemptResult`-ot
(`completion: 0.98`, `rhythm: 0.9`, `resolvedTargets: 8/8`, `scorePoints: 800`)
adnak át a VALÓDI `SpeedBuilderEngine`-nek. Az engine ezekből szabályosan
felépíti a létrát, a `_ResultLayout` pedig a kapott
`highestStableTempo`-t „Highest stable BPM" felirattal közli.

Nincs `kDebugMode`-őr, nincs flag, nincs „szimulált" felirat: a felhasználói
úton (eredmény-képernyő → „Speed Builder" gyorslink → „Start") ez a
production viselkedés.

**Mérve — reviewer próbateszt** (`zz_reviewer_probe2_test.dart`, eldobható,
törölve; a képernyőt pusztán érintésekkel vezérelve, mikrofon, session és
egyetlen `PracticeObservation` NÉLKÜL):

```
PROBE2 rendered: Speed Builder result || You finished early ||
                 Highest stable BPM: 90 BPM || 6 attempts || Done || Speed Builder
```

**Miért MAJOR.** A kör kötött döntéseit adó, merge-elt
[ADR 0283](../adr/0283-results-never-overstate-certainty.md) épp azt tiltja,
hogy a felület többet állítson, mint amit mértünk („a néma, magabiztos
tévedés veszélyesebb, mint a látható hiba"), a brief §5.5 pedig kimondja:
*„a felület azt jeleníti meg, amit kap"* — itt a felület **maga gyártja**,
amit kap. A projekt állandó szabálya („nincs demó — valódi funkcionalitás")
ugyanezt mondja. A `docs/rag/chunks/` DSP-igazsághoz képest a 0,98-as
`completion` nem konzervatív default, hanem egy sikeres felismerés
szimulációja.

**A kör SAJÁT cellája pinneli a hibát** —
`test/features/practice/speed_ladder_test.dart:135-150`: a cella elvárja,
hogy a „Record pass" gomb a Start után megjelenjen, kétszer megnyomható
legyen, és a Finish eredményt adjon. Ez az [L495](../LESSONS.md#l495)
megismétlődése: *egy zöld cella nemcsak elmulaszthatja a hibát, rögzítheti
is.* Az A6 két ÉRDEMI cellája (`:88`, `:113`) ezzel szemben a `initialState`
teszt-varraton át, valódi engine-állapottal mér — azok érintetlenül
maradhatnak.

**Javasolt irány (nem kész patch).** A képernyő ne állítson elő
`PracticeAttemptResult`-ot. Az aktív réteg a kapott `SpeedBuilderState`-et
RENDERELJE (a `SpeedBuilderProgress` már ezt teszi), a próbák forrása pedig
legyen kívülről injektált varrat, amit egy későbbi kör köt az élő
sessionhöz. A belépőnek addig **kimondottan** kell jeleznie, hogy élő
Speed-Builder-session még nincs — tiltott a „Start" gomb, ami mérés nélkül
mér. A `speed_ladder_test.dart:135-150` cellája ennek megfelelően írandó át
(a szintetikus út pinnelése helyett annak ABSZENCIÁJÁT mérje), az A6 két
engine-cellája változatlanul marad.

### MINOR-1 — a `finishReasonCode` nyers sztring-literállal hasonlítva, a meglévő stabil-kód elérés helyett

`lib/features/practice/presentation/screens/practice_result_screen.dart:40-42`

```dart
bool practiceResultIsPartial(PracticeHistoryEntry entry) {
  return entry.finishReasonCode != 'completedAllTargets';
}
```

A perzisztált kód szerződését a domain már hordozza
(`PracticeFinishReason.completedAllTargets.code`, illetve a nevesített
`practiceFinishReasonFromCode(...)` feloldó,
`lib/features/practice/domain/model/practice_session_result.dart:11-31`). A
literál megduplázza a szerződést a presentation rétegben: egy jövőbeli
kód-átnevezés a domainben némán „részlegessé" tenné MINDEN teljes session
eredményét, és a fordító nem szólna. Javasolt irány: az enum `code`-ját
(vagy a feloldót) használni.

### MINOR-2 — a sérült előzmény-rekord NÉMÁN eltűnik; a brief §5.2 „a sor hibásként jelenik meg" előírása nem teljesül, és a §10.5 nem mondja ki korlátként

`lib/features/practice/presentation/screens/practice_history_screen.dart:1-10`

A képernyő doc-commentje őszintén rögzíti a viselkedést: a repository
read-time szűri a dekódolási hibákat, a képernyő pedig „unaware of how many
(if any) were skipped". A merge-elt ADR 0283 §Döntés 5 minimumát (izoláció, a
többi rekord elérhető) ez **teljesíti**, és az A3 cella ezt méri — a brief
§5.2 szigorúbb szövegét (*„a sor hibásként jelenik meg"*) viszont nem.

**A hiányzó darab nem az implementeré:** a kihagyott rekordok száma MEGVAN a
tárolóban (`lib/core/storage/json_document_store.dart:211-240` — `skipped`
számláló + `storage.document.records_skipped` esemény), de a
`PracticeHistoryRepository.load()` `AppResult<List<...>>` visszatérése nem
hordozza tovább, és mind a `lib/core/storage/**`, mind a practice `data/`
réteg a kör listáján KÍVÜL van (§0.0/B/R6). Javasolt irány: a §10.5-be
NEVESÍTETT korlátként bekerülni (a felhasználó ma jelzés nélkül veszít egy
sort a saját előzményéből), a tényleges jelzés egy későbbi, a data-réteget is
érintő kör dolga.

### NOTE-1 (nem blokkoló) — a jutalom-varrat Noop alapértelmezése MÉRVE őszinte

`lib/features/practice/presentation/providers/practice_result_providers.dart:16-40`

A `rewardLedgerRepositoryProvider` production-alapértelmezése üres főkönyvet
ad. Ez első ránézésre a „néma no-op" hibaosztály, ezért megmértem:

```
grep -rn "GamificationPracticeAdapter" lib/ | grep -v presentation/providers
→ csak az OSZTÁLY DEKLARÁCIÓJA (gamification_practice_adapter.dart:162-163)
grep -rn "LocalRewardLedgerRepository" lib/
→ csak a saját definíciója (local_reward_ledger_repository.dart:8-9)
```

A practice-adapter tehát ma sehol nincs példányosítva, és a valódi főkönyv-
implementáció sincs providerbe kötve: a főkönyv production-ban **valóban
üres**. Az „üres főkönyv → nincs jutalom" kiírás így a MÉRT jelen állapot, nem
elhallgatott hiba — pontosan az ADR 0283 §Döntés 4 szerinti viselkedés (a
felület nem becsül). A §10.5 ezt nevesített follow-upként rögzíti.

## 3. A gate ÚJRAFUTTATVA — reviewer, izolált klón

`/tmp/review-e13-r22` (friss klón a kör-branchről), a brief §7 pontos
parancsa, csonkítatlanul:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/result_confidence_test.dart    zöld
    test test/features/practice/history_corrupt_record_test.dart zöld
    test test/features/practice/speed_ladder_test.dart         zöld
    test test/features/practice/reward_idempotency_test.dart   zöld
    test test/features/practice/presentation/                  zöld
    test test/core/screen_size_guard_test.dart                 zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/tooling/dio_factory_guard_test.dart              zöld
    test test/tooling/preferences_plugin_import_guard_test.dart zöld
    test test/tooling/route_literal_guard_test.dart            zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

**Scope-audit** (`tools/scope-audit.py`, ADR 0138 §1) a kör induló HEAD-jétől:

```
Legacy scope audit OK (b3ce202714e1..dffb8b49d191, 22 changed path(s), 0 generated/ignored)
```

## 4. Acceptance criteria — tételes ellenőrzés

| # | Verdikt | A reviewer bizonyítéka |
|---|---|---|
| A1 | ✅ | `practice_result_screen.dart:27` `const … = 0.60`, `:167` `confidence < threshold` — a határ INKLUZÍV, ahogy a §6.1 `12/20` éle előírja; a bemenet a `:31-34` lefedettségi arány, nem kitalált mező |
| A2 | ⚠️ (MINOR-1) | a `partial` badge helyesen jelenik meg, de a feltétel nyers literál (`:41`) |
| A3 | ✅ | a lista túléli a sérült rekordot (a cella valódi repositoryval mér) |
| A4 | ✅ | a providerlánc `keyValueStore` → local repository; a diffben **nulla** `Dio`/`http`/`Uri` (§5) |
| A5 | ✅ | `practice_result_providers.dart:53-71` — TISZTA olvasás, `appendIfAbsent` sehol; a kulcs a determinisztikus `stableEventId(sessionId)` |
| A6 | ❌ (MAJOR-1) | a két engine-cella (`:88`, `:113`) érdemi, de a `:135-150` cella a gyártott-mérés utat PINNELI |
| A7 | ✅ | a „Practice again" ugyanazzal a `definitionId`-vel nyitja a Setupot |
| A8 | ✅ | `practiceResultShareSummaryFrom` öt mezője kézzel válogatott; a `skillTags`/per-attempt adat abszenciája állítva |
| A9 | ✅ | 6 PNG a diffben, `tools/golden-x86.sh record`+`check` a MERGE-KAPU architektúráján (ADR 0426) — a §10.3 kimenete a `record` során talált VALÓS `RenderFlex overflowed` leletet is rögzíti, javítással |
| A10 | ✅ | a `PracticeResultScreen` típusa/útvonala/`entry:` változatlan; a három listán kívüli pin zöld a reviewer saját futásában is |

**Érintési célok — reviewer próbateszt** (eldobható, törölve). Az ADR 0280
§Döntés 5 (≥ 48 dp) az E13-R20 és az E13-R21 EGYMÁS UTÁNI bukásának oka volt,
ezért külön mértem az összes ÚJ affordanciát 412×915-ön:

```
PROBE OutlinedButton[0] "Share"         size=Size(380.0, 48.0)
PROBE OutlinedButton[1] "History"       size=Size(184.0, 48.0)
PROBE OutlinedButton[2] "Speed Builder" size=Size(184.0, 48.0)
PROBE FilledButton[0]   "Practice again" size=Size(380.0, 48.0)
```

Mind a négy pontosan a küszöbön — **nincs lelet**, a hibaosztály ezúttal
lezárt.

## 5. Biztonsági / adatvédelmi pász (`risk = "high"`)

READ-ONLY mérés a diff három képernyőjén és a provider-fájlon:

| Ellenőrzés | Eredmény |
|---|---|
| hálózati hívás (`Dio`, `http`, `Uri.`) | **nulla találat** — az előzmény helyi adat marad (ADR 0283 §Döntés 6) |
| naplózás (`print`, `debugPrint`, `log(`) | **nulla találat** — személyes gyakorlási adat nem kerül logba |
| új plugin / engedély / secret | nincs; a `secrets` gate-lépés zöld |
| megosztás-teher | öt kézzel válogatott mező; fiók-/eszközazonosító, nyers audio, per-attempt DSP nincs benne |
| tárolás | csak olvasás a meglévő `practiceHistoryRepositoryProvider`-en át; a kör nem ír perzisztens adatot |

**Nincs biztonsági lelet.** Megjegyzés (nem lelet): a megosztás-kártya a nyers
`sessionId`-t is kiírja a felhasználónak — belső azonosító, kockázata
elhanyagolható, de egy későbbi, valódi megosztás-bekötésnél mérlegelendő, hogy
a wire-payloadban maradjon-e.

## 6. Próbatesztek (eldobhatók, a merge előtt törölve)

| Fájl | Mit mért | Eredmény |
|---|---|---|
| `test/features/practice/zz_reviewer_probe_test.dart` | az új affordanciák érintési célja 412×915-ön | 4/4 pontosan 48,0 dp — nincs lelet |
| `test/features/practice/zz_reviewer_probe2_test.dart` | a Speed Builder felhasználói útja mikrofon és session nélkül | „Highest stable BPM: 90 BPM" PUSZTA érintésekből → MAJOR-1 |

Mindkettő törölve; a review-klón a törlés után futtatta a teljes gate-et.

## 7. Következő lépés (az első kör után)

Javító kör UGYANAZZAL a motorral (`sonnet-impl`), a MAJOR-1 + MINOR-1 +
MINOR-2 leletlistával. A javítás után: a gate ÚJRA, friss klónban; a
`speed_ladder_test.dart` érintett cellájának záró ellenőrzése leletenként;
exact-SHA CI ÚJRA-dispatch (a kód változik).

## 8. Javító kör — leletenkénti zárás (reviewer, `e3dab048`)

A javító kör három commitja: `0111e6e5` (MAJOR-1), `11e93d9d` (MINOR-1),
`e3dab048` (MINOR-2 dokumentálás + §10.6 handoff). A diff a `420bd5f1`-hez
képest 10 fájl, mind a listán belül:

```
Legacy scope audit OK (b3ce202714e1..e3dab0480511, 23 changed path(s), 1 generated/ignored)
```

### MAJOR-1 — ZÁRVA

`speed_builder_screen.dart` mérve a javított fán:

```
grep -n "_syntheticAttempt|Record pass|speedBuilderRecordPass|PracticeAttemptResult|onRecordPass"
→ NULLA találat
```

A `_syntheticAttempt(...)` függvény, a `PracticeAttemptResult` import, a
„Record pass"/„Record miss" gombok és a `Start` CTA is megszűnt. Az
állapotmentes belépő most `_UnavailableLayout` — `EmptyState`-alapú, ADR
0277-stílusú, nem büntető állapot, amely KIMONDJA, hogy élő mérés még nincs,
és nem kínál olyan vezérlőt, ami mérés nélkül eredményt szülne. Az aktív réteg
már csak a kapott `SpeedBuilderState`-et rendereli.

**Valódi-sértés próba (REVIEWER SAJÁT, nem bemondás).** A javított
képernyőbe visszatettem egy `Start` CTA-t a `_UnavailableLayout`-ba, majd
lefuttattam a kör cellájára:

```
Expected: no matching candidates
  Actual: _TextWidgetFinder:<Found 1 widget with text "Start": [
00:01 +2 -1: no live session → no fabricated measurement (E13-R22 review MAJOR-1)
             with no initialState the screen never offers a Start/Record path … [E]
00:01 +2 -1: Some tests failed.
```

Az új őrcella tehát VALÓBAN pirosra vált a visszaesésre. A mutációt
visszaállítottam (`git checkout --`), a klón tiszta.

A korábban a hibás utat PINNELŐ cella
(`speed_ladder_test.dart:135-150`) helyére a fenti abszencia-cella került; az
A6 két érdemi, `initialState`-tel mérő cellája (`:88`, `:113`) változatlan.

### MINOR-1 — ZÁRVA

```dart
return entry.finishReasonCode !=
    PracticeFinishReason.completedAllTargets.code;
```

A nyers literál helyett a domain stabil enum-kódja. A `presentation/`
gate-lépés zöld, az A2 cellák változatlanul zöldek.

### MINOR-2 — ZÁRVA (dokumentálás, ahogy a lelet kérte)

A brief §10.5 mostantól nevesített korlátként rögzíti, hogy a sérült
előzmény-rekord ma JELZÉS NÉLKÜL tűnik el, és hogy a jelzés a `core/storage/**`
+ practice `data/` réteget érintő, KÉSŐBBI kör dolga. A lelet nem kódjavítást
kért — a réteg a kör listáján kívül van.

### NOTE-1 — változatlan (nem blokkoló)

### A gate ÚJRAFUTTATVA a javított fán — reviewer, ÚJ izolált klón

`/tmp/review-e13-r22b` (friss klón `e3dab048`-ról), a brief §7 pontos
parancsa:

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/features/practice/result_confidence_test.dart    zöld
    test test/features/practice/history_corrupt_record_test.dart zöld
    test test/features/practice/speed_ladder_test.dart         zöld
    test test/features/practice/reward_idempotency_test.dart   zöld
    test test/features/practice/presentation/                  zöld
    test test/core/screen_size_guard_test.dart                 zöld
    test test/ui/ui_inventory_test.dart                        zöld
    test test/core/architecture_dependency_test.dart           zöld
    test test/tooling/dio_factory_guard_test.dart              zöld
    test test/tooling/preferences_plugin_import_guard_test.dart zöld
    test test/tooling/route_literal_guard_test.dart            zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

`l10n parity: 1975 message(s)` (a javító kör előtt 1973 — a két új
`speedBuilderUnavailable*` kulcs, `en` és `hu` FORRÁSBAN, regenerált
aggregátummal).

### Golden

A Speed Builder képernyője megváltozott, ezért a két érintett PNG
(`e13_r22_speed_builder_compact{,_scale2}.png`) újra fel lett véve a
MERGE-KAPU architektúráján (`tools/golden-x86.sh record` + `check`, ADR 0426),
és a diffben van. A másik négy PNG érintetlen.

## 9. Merge-döntés

A zöld kapu (ADR 0052) minden eleme teljesült: a lokális 16-lépéses gate a
reviewer SAJÁT, izolált klónjában zöld, a scope-audit `OK`, a leletek zárva,
és az exact-SHA CI a merge SHA-ján zöld (a run-link a PR-ben). **Merge
engedélyezve.**
