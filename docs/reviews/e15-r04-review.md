# E15-R04 — független review (Practice és Learn képernyők migrálása)

- **Reviewer:** Claude (Opus 5), orchestrátor-szék — READ-ONLY, produkciós kódot
  nem szerkesztett
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Review-zott diff:** `0ba14f5b..d0a466b7` (a `07d2200d` merge-commit csak az
  `origin/main` szinkront hozza, ADR 0087 §0.3)
- **Kötelező agentek (a brief `risk = "high"` miatt):** `flutter-reviewer`,
  `flutter-devil-advocate`
- **Dátum:** 2026-08-29

## Verdikt (első kör): CHANGES REQUESTED — 3 MAJOR

A kör CÉLJA teljesült: mind a 8 képernyő migrált (A1), a kapu 37/37 zöld, a
goldenek a merge-kapu architektúráján újra fel vannak véve (ADR 0426), és
**egyetlen típus-pinnelő cella sem lett törölve, `skip`-elve vagy gyengítve**
(A4 — mérve: a `test/` diff MINDEN törölt sora `MaterialApp`-konstruktor vagy
`_pump` helper aláírás; nulla törölt `expect`, nulla `skip`, nulla tágított
matcher). A három MAJOR mind ugyanabból a mintából jön: a migráció **átlépte a
§0.0 határt** (megjelenés, nem viselkedés).

### MAJOR-1 — a Practice History elvesztette a képernyő-specifikus hibaszövegét

`lib/features/practice/presentation/screens/practice_history_screen.dart:65-73`

A hibaállapot a `SsFailureState` GENERIKUS tároló-hiba szövegére váltott. MÉRVE:

```
grep -rn "practiceHistoryErrorTitle\|practiceHistoryErrorBody\|practiceHistoryErrorAction" lib/ test/ --include=*.dart
  → 0 találat (a generált app_localizations*.dart-on kívül)
git show 0ba14f5b:…/practice_history_screen.dart | grep -n practiceHistoryError
  → 63, 69, 76
```

A felhasználó eddig „Az előzmények nem tölthetők be / Something went wrong
reading your local history" szöveget látott, most „Tárolási probléma"-t. A
brief §3 tiltja a szöveg-jelentés megváltoztatását, a §5.1 pedig kimondja, hogy
„egyszerűsítettük a hibaállapotot" nem elfogadható gyengítés. Három ARB-kulcs
árván maradt. Ezt egyetlen acceptance-cella sem fogta meg (az A2 csak a
`ss-failure-state-retry` kulcs LÉTÉT nézi).

### MAJOR-2 — a valódi `AppFailure` eldobva, hamis `retryable: true` gyártva

Ugyanaz a hely. Az `AppResult.fold` `onFailure`-je megkapja a valódi
`AppFailure`-t, a kód mégis `onFailure: (_) => …` alakú, és kézzel gyárt egy
`StorageFailure(code: storageRead, retryable: true)`-t.

MÉRVE: a `StorageFailure` alapértelmezése `retryable = false`
(`lib/core/foundation/app_failure.dart:163-170`), és a `SsFailurePresentation`
az akciót PONTOSAN a `retryable` mezőre kulcsolja
(`failure_presentation.dart:107-116`). Következmény: tartósan olvashatatlan
tároló esetén a felhasználó örökké „Újra" gombot kap a design-rendszer által
előírt út helyett — végtelen holt hurok. A `flutter-reviewer` próbatesztje ezt
futtatva is megerősítette (`retryable: false` fixture → `ss-failure-state-retry`
mégis jelen van, a támogatás-akció hiányzik).

Súlyosbító: a kör SAJÁT új cellája a hibát PINNELI —
`test/features/practice/history_corrupt_record_test.dart:29-31` egy
`retryable: false` fixture-t ad, a cella mégis a retry-akciót követeli.

### MAJOR-3 — kitalált viselkedés egy megjelenés-körben (két helyen)

**(a)** `practice_hub_screen.dart:71-78` — az üres katalógus `SsEmptyState`-je
`onAction: () => ref.invalidate(practiceCatalogProvider)` akciót kapott
`practiceSessionRetry` („Újra", a *session* kontextusból kölcsönzött) címkével.
MÉRVE: a `practiceCatalogProvider` szinkron `Provider` a **const**
`BuiltinPracticeCatalog` felett
(`lib/features/practice/application/practice_catalog_controller.dart:10-23`) —
az invalidálás ugyanazt az immutable listát olvassa vissza. Bizonyíthatóan holt
affordancia, ami a kör előtt nem létezett.

**(b)** `practice_result_screen.dart:774-784` — a fallback állapot ÚJ
navigációt kapott (`context.go(AppRoutes.practiceHub)`). MÉRVE:
`git show 0ba14f5b:…/practice_result_screen.dart | grep AppRoutes` → 0 találat.

Mindkettő viselkedés-bővítés, nem megjelenés-migráció (§0.0, §5.1).

## MINOR

- **m1** — a §10 handoff azt állítja, „egyéb kompromisszum: nincs", miközben a
  `speed_builder_screen.dart:88-97` saját kommentje dokumentálja, hogy az
  akció nélküli információs állapot NEM `SsEmptyState`/`SsFailureState`, mert
  azok kötelező akciót írnak elő. A mérnöki döntés helyes; a jegyzőkönyv téves.
- **m2** — a `learn_screen.dart:558-559, 570` a hit-burst és milestone
  részecske-színeket továbbra is `AppColors`-ból olvassa (a nyolc képernyő
  közül az EGYETLEN maradvány), miközben ugyanaz a widget a visszajelzés
  szövegét már a fényerő-tudatos `colors.confidenceHigh`-ból — világos témában
  elcsúszó pár. Az A1 `grep -q design_system` mérése ezt elvből nem látja
  (§6.1 pont ezt az esetet nevesíti A1-pirosként).
- **m3** — az A3 (textScale 2.0) két képernyőn nem teljes cellával van
  bizonyítva; a hivatkozott ok (a listán KÍVÜLI `lesson_highway.dart`,
  `ss_chord_diagram.dart`, `lesson_score_card.dart` már meglévő túlcsordulása)
  MÉRVE igaz, és a kör NEM vitt be új túlcsordulást. Ugyanakkor a migráció
  néhány gombnál `minimumSize: Size.fromHeight(56)` (padló) helyett fix
  `SizedBox(height: …)` (plafon) alakot vezetett be — 2.0-n mérve rendben, e
  fölött hamarabb vág, mint a régi kód.
- **m4** — 29 új teszt-fájl közvetlenül a `design_system/themes/ss_*`
  fájlokat importálja a `public.dart` barrel helyett (6 → 35 fájl). Az ADR 0466
  §6 / ADR 0273 §1 a barrelt írja elő; `test/`-re nincs gépi őr, tehát
  konvenció-elcsúszás, nem törés — de a kör egy lépésben megháromszorozta.

## NOTE

- **n1** — a golden-tesztek `AppTheme.dark()` → `SsDarkTheme.data()` cseréje
  (`d62520f9`) INDOKOLT, és **erősíti** a mércét: az app futásidejű témája az
  ADR 0466 óta a design-rendszer témája (`strumsight_app.dart:33-34`), a régi
  fejléc-komment tehát elavult volt. Nem elfedés: a `record` után a NEM ennek a
  körnek a képernyőihez tartozó `e13_r20_chord_*` PNG-k **változatlanok**, csak
  a 6 migrált-képernyő PNG mozdult.
- **n2** — a `_HistoryRow` `ListTile` → `InkWell + Row` cserével elvesztette a
  `ListTile` `Semantics(selected:, enabled:)` csomópontját; a
  `practice_a11y_audit_test.dart`-ban nincs `PracticeHistoryScreen` cella,
  tehát ezt semmi nem pinneli. Hatás alacsony (minden sor engedélyezett).
- **n3** — a letiltott `_HubCard` elvesztette a háttér-jelzését; a különbség
  már csak ikon-szín + hiányzó chevron (ADR 0381 „ne csak színnel" határán).
- **n4** — a `Theme.of(context).extension<Ss…>()!` bang-idióma a ház mintája
  (a kör 8 képernyőjén kívül 29 előfordulásból 26 ilyen), tehát önmagában NEM
  lelet.
- **n5** — Riverpod 3 konvenciók tiszták: nincs `StateProvider`, nincs
  `.valueOrNull`, a `Notifier`/`NotifierProvider` pár megmaradt, az újrarajzolás
  hatóköre nem tágult.
- **n6** — az új ARB-kulcsok (`practiceHistoryLoading`,
  `practiceResultUnavailableAction`) mind a négy fájlban jelen vannak, valódi
  magyar fordítással; az `arb_parity_test` zöld.

## Mérések, amikre a verdikt támaszkodik

| Mérés | Eredmény |
|---|---|
| §7 migrációs mérés | 8/8 `MIGRATED` |
| `tools/round-gate.sh` (§7 sor, 37 lépés) | zöld (implementer), a CI ismétli |
| `tools/golden-x86.sh check` (merge-kapu architektúra) | exit 0, 12/12 cella |
| `scope_audit` | `ok` (a `allowed_paths` betartva) |
| `test/` diff törölt sorai | csak téma-huzalozás; 0 törölt `expect`, 0 `skip` |
| Router CI a `07d2200d` SHA-n | `success` |

---

## Javító kör (`179513d1`) — újra-ellenőrzés

A javító kör a lánc NORMÁL útja (user-döntés 2026-07-31), ugyanaz a motor, a
fenti leletlistával. Leletenkénti zárás, MÉRVE:

| Lelet | Zárás | Mérés |
|---|---|---|
| **MAJOR-1** | ZÁRVA | a képernyő saját `practiceHistoryErrorTitle`/`Body` szövege visszatért a hibaállapotba; a `SsFailureState` komponens-migráció megmaradt |
| **MAJOR-2** | ZÁRVA | `onFailure: (failure) => _HistoryError(failure: failure, …)` — a VALÓDI `AppFailure` megy a `SsFailurePresentation.from`-ba; a retry-akció a valódi `retryable` mezőből jön |
| **MAJOR-3a** | ZÁRVA | a holt „Újra" gomb eltűnt: `const _EmptyCatalogLayout()` (akció nélküli, tokenekből épített információs állapot, a kör `speed_builder` precedense szerint) |
| **MAJOR-3b** | ZÁRVA | `grep -n "AppRoutes\|context.go" practice_result_screen.dart` → **0 találat**; a kör előtti viselkedés visszaállt |

**Új őrcellák (a lelet nem térhet vissza némán)** —
`test/features/practice/history_corrupt_record_test.dart`:

- „a NON-retryable load failure (`retryable: false`) … NO retry action" →
  `ss-failure-state-retry` `findsNothing`, és a képernyő SAJÁT szövege
  jelenik meg (MAJOR-1 + MAJOR-2 együtt);
- „a RETRYABLE load failure (`retryable: true`) renders the retry action, and
  tapping it reloads" → `_RetryableThenSucceedsRepository`, a megnyomás után
  a `loadCount` nő ÉS a bejegyzés megjelenik.

A javító kör TÖRÖLTE a korábbi, hibás alakot pinnelő cellát — ez megengedett
és helyes: azt a cellát UGYANEZ a kör vette fel, és a fenti kettő szigorúbb
nála. A kör ELŐTTI pinnelő cellák érintetlenek.

### Új MINOR a javításban

- **m5** — a MAJOR-1 javítása egy privát `_HistoryFailureL10n implements
  AppLocalizations` burkolóval oldja meg a szöveg-felülírást, `noSuchMethod`
  kifutóval; a `SsFailurePresentation` konstruktora privát és a fájl nincs a
  kör `allowed_paths`-án, tehát a képernyő-fájlon belüli megoldás a kör
  keretei között az egyetlen út volt. MÉRVE ma biztonságos: a produkciós
  `local_practice_history_repository.dart` **kizárólag** `StorageFailure`-t ad
  (5 hívási hely), és a burkoló pontosan a storage-ág négy getterét
  (`dsFailureStorageTitle/Message`, `dsFailureRetryAction`,
  `dsFailureContactSupportAction`) fedi le. Ha viszont ezen az úton valaha más
  hibatípus (auth/network/unknown) jelenne meg, a `noSuchMethod` kifutó
  `NoSuchMethodError`-t dobna — fordítási hiba nélkül. Következő kör számára:
  a tiszta megoldás a `SsFailurePresentation` cím/üzenet-felülíró paramétere
  (a design-rendszer fájljaiban, ami ennek a körnek tilos zóna).

## VÉGSŐ DÖNTÉS: APPROVED

0 nyitott BLOCKER, 0 nyitott MAJOR. A MINOR-ok (m1–m5) és a NOTE-ok nem
merge-blokkolók; az m2 (`learn_screen.dart` `AppColors`-maradék) és az m5 a
következő Ch15 kör bemenete. A merge feltétele változatlanul az ADR 0052 zöld
kapu az EXACT merge SHA-n.
