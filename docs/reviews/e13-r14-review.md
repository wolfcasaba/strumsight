# E13-R14 — Review

- **Kör:** `E13-R14` — Accessibility foundation audit és semantics toolkit
- **Branch:** `sonnet-impl/e13-r14-accessibility-toolkit`
- **PR:** [#448](https://github.com/wolfcasaba/strumsight/pull/448)
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5)
- **Reviewer:** Claude Opus 5 (orchestrátor, read-only review — production kódot nem írtam)
- **Review dátuma:** 2026-08-24
- **Review-elt HEAD:** `76ddade93e98a4cbd816c0112c28d2891323e77b`
  (impl commit `845d3c93` + a §0.3 upstream-merge)
- **Verdikt:** ✅ **APPROVED** — nincs BLOCKER, nincs MAJOR. 4 MINOR + 3 NOTE, mind follow-up.

---

## 1. A kör előzménye — folytatás, nem újrakezdés

Ezt a kört egy korábbi, **megölt** orchestrátor-session indította (a
`heal/E13-R14-H-NOSIGNAL-1` / PR #447 pontosan ennek az elakadásnak az
ébresztő-őrét építette). A §0.2 örökség-ellenőrzés a
`/home/ubuntu/ss-sonnet-impl-e13-r14` munkapéldányt találta, benne:

- `5be0a3a3` — commitolt pre-flight (§0.0 revízió, D1–D7);
- `845d3c93` — a teljes implementáció, `status=done` jelzéssel.

Nyitott leletekkel bíró review **nem** volt, tehát a folytatás a normál
review → CI → merge útvonal, nem javító kör. A pre-flightot a §0.2 előírása
szerint **felhasználtam**, nem írtam újra.

### 1.1 Az örökölt jelzésfájl két gyanús mezője — mindkettő kivizsgálva

| Mező | Érték | Mérés | Ítélet |
|---|---|---|---|
| `dirty_files` | `1` | a fa MOST tiszta (`git status --porcelain -uall` üres) a `845d3c93` implementációs commiton, mind a 9 fájl commitolva | **nincs elveszett munka** — tranziens `.ai/` burkoló-artefaktum a jelzés pillanatában |
| `gate_shape` | `VIOLATION` | a naplóból kinyert TÉNYLEGES `Bash` hívások: 2 db, ebből a gate-futtatás a **helyes, csővezeték nélküli** alak; a VIOLATION-t a `cat …/tools/round-gate.sh \| head -60` (a script ELOLVASÁSA) váltotta ki | **hamis pozitív** — lásd az 5. szakasz őr-javaslatát |

---

## 2. Gate — ÚJRAFUTTATVA, saját kézzel, izolált klónban

Nem fogadtam el bemondásra a §10.4-et. Friss klón
(`/tmp/review-e13-r14`, `prepare-flutter-generated.sh` után), csonkítatlan,
csővezeték nélküli futás:

```
tools/round-gate.sh test/accessibility/semantics_contract_test.dart test/accessibility/tap_target_test.dart test/accessibility/screen_reader_copy_test.dart
```

```
    → [1] format: ZÖLD
    → [2] analyze: ZÖLD            (Analyzing 3 items... No issues found!)
    → [3] test semantics_contract_test.dart: ZÖLD
    → [4] test tap_target_test.dart: ZÖLD        (6/6)
    → [5] test screen_reader_copy_test.dart: ZÖLD
    → [6] architecture: ZÖLD
    → [7] secrets: ZÖLD
    → [8] l10n: ZÖLD
MINDEN GATE ZÖLD.
```

Kilépési kód: **0**. A §10.4 állítása igaz.

## 3. Scope-audit — `tools/scope-audit.py`, nem kézi `git diff`

```
A) --base origin/main   → Legacy scope audit OK (680dc206..76ddade9, 9 changed path(s))   scope_audit=ok
B) --base 5be0a3a3      → FAILED (13 changed path(s)) — HANDOFF.md, docs/LESSONS.md,
                          tools/round-pipeline.sh, tools/tests/test_round_pipeline_stall_nudge.py
```

**A mérvadó az (A).** A (B) négy „sértése" PONTOSAN az a négy fájl, amit a
§0.3 kötelező upstream-merge hozott be az `origin/main`-ből (`680dc206`, a
HEAL-kör) — nem a kör munkája. A kör SAJÁT diffje a brief `allowed_paths`
kilenc útvonala, hiánytalanul. **Nem H3.**

> Ez a különbség dokumentálandó: folytatáskori köröknél a `scope_audit_base`
> a régi induló HEAD, a merge után viszont az `origin/main` a helyes bázis.

## 4. Acceptance criteria — tételes bizonyíték

| # | Kritérium | Bizonyíték | Ítélet |
|---|---|---|---|
| A1 | Az élő régió betartja a bejelentés-költségvetést | a §6.1/D3 négy cellája (1/2/3/1 bejelentés) + egy `testWidgets` cella, ami a felépített `SsLiveRegionAnnouncer`-t pumpálja és `find.bySemanticsLabel`-lel olvassa a szemantika-fát. **M1 mutációs próbával megerősítve** (5.1) | ✅ |
| A2 | Tuner cents + strum-irány felolvasható szöveg | `screen_reader_copy_test.dart`; a `tunerAccuracyLabel`/`strumDirectionLabel` a VALÓDI delegate-en át (`AppLocalizations.delegate.load`) | ✅ |
| A3 | Nincs csak színnel közölt siker/hiba/confidence | minden `SsStatusBadgeKind`-re saját, EGYEDI szemantika-címke (`seenLabels.add(...) isTrue`) + a tuner három állapota `hasLength(3)` | ✅ |
| A4 | Minden kritikus akció címkézett | `SsIconButton('')` ⇒ `throwsArgumentError`; destruktív `SsButton` `matchesSemantics(label:, hint:, …)` EGY node-on | ✅ |
| A5 | Kritikus komponensek érintési célja ≥ 48 dp | 5 nevesített komponens FELÉPÍTETT mérete `tester.getSize` + `SsTapTarget.meetsMinimum` — nem a konstans újra-assertálása (D4 teljesítve) | ✅ |
| A6 | Felolvasó-szöveg en ÉS hu | a hu kimenet `isNot(en)` minden kulcsra. **M2 mutációs próbával megerősítve** (5.2) | ✅ |
| A7 | Kézi TalkBack/VoiceOver ellenőrzőlista | `docs/ui/accessibility.md` — „What the automated tests cannot tell you" + 8 pontos kézi lista; kimondja, hogy a zöld `flutter test` **nem** bizonyíték az akadálymentességre | ✅ |
| A8 | Csökkentett mozgás mellett a visszajelzés megmarad | `SsMotionScope(appOverride: true)` mellett `durationOf(...) == Duration.zero`, DE a bejelentés és a címke megmarad — a cella ÖNMAGÁT hitelesíti (előbb bizonyítja, hogy a reduced motion tényleg aktív) | ✅ |

**D2 (nincs új ARB-kulcs) külön megmérve:** mind az 5 kulcs
(`tunerCentsFlat/Sharp`, `tunerInTune`, `strumDown/Up`) létezik a
`lib/l10n/base` + `lib/l10n/features` FORRÁS-ARB-okban `_en` ÉS `_hu`
oldalon is; a kör egyetlen ARB-forrást sem módosított.

## 5. Próbatesztek (eldobhatók — a klónban lefuttatva, utána visszaállítva)

### 5.1 M1 — valódi-sértés: a költségvetés-ellenőrzés kivétele

A `report()` küszöb-ága törölve → az A1 cella PIROS, **szó szerint azzal az
üzenettel, amit a §10.3 dokumentál**:

```
A1 … below the threshold: rapid readings collapse into the first one [E]
  Expected: ['C']
    Actual: ['C', 'G', 'D']
```

…és **a felépített widget cellája is** piros lett
(`Found 0 widgets with a semantics label named "C"`). Az őr tehát a valódi
kibocsátási utat méri, nem egy tiszta predikátumot — **L443 teljesítve**.

### 5.2 M2 — valódi-sértés: angolra drótozott `tunerAccuracyLabel`

Az `l10n` argumentum figyelmen kívül hagyva, a szövegek beégetve → az A6
cella PIROS:

```
A6 … tuner sharp/flat/in-tune copy differs between en and hu [E]
  Expected: not '18 cents sharp'
    Actual: '18 cents sharp'
```

Mutációs futás összegzése: `+18 -3` (3 cella pirosra váltott). Mindkét
mutáció **visszaállítva**, a fa utána tiszta, TEMP-kód nem maradt.

### 5.3 Él-próbák (a kör celláin túl)

| Próba | Mért eredmény | Következtetés |
|---|---|---|
| `SsButton(label: 'A')` — 1 karakteres címke | `Size(64.0, 48.0)`, `meetsMinimum=true` | az `ss_button.dart` csak `minHeight`-et köt, de a vízszintes padding miatt a „mindkét tengely ≥ 48" MÉG a legrövidebb címkénél is áll — **nincs lelet** |
| `SsButton(label: 'Save')` @ `textScale` 1.0 → 2.0 | `104.4×48` → `136.4×48`, nőtt | a `textScaler` valóban átmegy a `MediaQuery`-n (de a kör cellája ezt nem méri — MINOR-2) |
| `region.announcements.add('X')` | `throwsUnsupportedError` | a doc-comment `List.unmodifiable` állítása **bizonyítva** |
| `('C'@0) → ('G'@400, eldobva) → ('C'@2000)` | `['C']` | az „utoljára BEJELENTETT, nem utoljára LÁTOTT" doc-comment állítás **bizonyítva** |
| visszafelé ugró idő: `('C'@5000) → ('G'@0)` | `announced=false` | egy nem-monoton időbélyeg **nem** nyit ki bejelentést — biztonságos irány |

## 6. Leletek

| # | Súly | Hely | Lelet |
|---|---|---|---|
| 1 | MINOR | `test/accessibility/tap_target_test.dart:17-24` | a `setViewport` deklarál egy `textScale` paramétert, amit a törzse **soha nem használ** (a skálázás valójában a `wrap(..., textScale:)`-en át megy). Holt paraméter — az analyze nem jelzi, de félrevezető. |
| 2 | MINOR | `test/accessibility/tap_target_test.dart:149-162` | a cella neve azt állítja, hogy „the textScaler travels through MediaQuery (not physicalSize)", de KIZÁRÓLAG `SsTapTarget.meetsMinimum(size)`-t assertál, ami **minden** skálán igaz. Egy inert `textScaler` mellett is zöld maradna — a cella nem méri, amit a neve ígér. (Megmértem: a skálázó valóban átmegy, `104.4 → 136.4`, tehát **nincs termék-hiba**, csak az őr gyenge.) Javasolt irány: assertáld, hogy a skálázott szélesség szigorúan nagyobb, vagy nevezd át a cellát. |
| 3 | MINOR | `lib/core/design_system/foundations/ss_semantics.dart:19-33` | a `tunerAccuracyLabel` **megduplázza** a `lib/features/tuner/widgets/cents_gauge.dart:29-34` kerekítés + `cents >= 0` elágazását, és a doc-comment ki is mondja, hogy tükrözi. A tükör MA áll (megmértem, karakterre egyezik), de **semmi nem méri** — bármelyik oldal szerkesztése némán szétcsúsztatja. A `cents_gauge.dart` az `allowed_paths`-on kívül van, tehát ebben a körben nem hívhatja a DS-építőt; egy őrcella viszont scope-on belül fért volna (a teszt IMPORTÁLHATJA). → a tuner migrációs körének feladata. |
| 4 | MINOR | `lib/core/design_system/accessibility/ss_live_region.dart:21,26` | a `_announcements` lista **korlátlanul nő** egy olyan osztályban, amit kifejezetten folyamatos Stage Mode-használatra terveztek (a költségvetés mellett is ~3600 bejegyzés/óra). A teljes történetet a terméken semmi nem fogyasztja — a `SsLiveRegionAnnouncer` csak a `current`-et olvassa. Javasolt irány: korlátozott történet, vagy a teljes lista teszt-only láthatósága. |
| 5 | NOTE | brief §0.0/D2 | „mérve: 11 meglévő DS-fájl" importálja az `AppLocalizations`-t — a **tényleges** szám 8 (a körrel együtt 9). A D2 lényege (a DS-réteg importálhat l10n-t) áll, csak a szám pontatlan. |
| 6 | NOTE | `lib/core/design_system/foundations/ss_semantics.dart:1` | ez az **első** `foundations/` fájl, amely l10n-függőséget vesz fel; a másik 7 (`ss_colors`, `ss_spacing`, …) tiszta `const` token-tartó. A két szöveg-építő természetesebben ülne az `accessibility/` mappában. Az `architecture` kapu zöld, és a brief `allowed_paths`-a tételesen engedi ezt az útvonalat, tehát **nem sértés** — ízlés, a jövőbeli DS-refaktor számára jegyezve. |
| 7 | NOTE | `ss_semantics.dart:27` | `tunerAccuracyLabel(cents: 0, inTune: false)` „0 cents sharp"-ot ad (`cents >= 0` ág). Ez PONTOSAN egyezik a `cents_gauge.dart` viselkedésével, tehát nem drift; csak jelzem, hogy ezt az élt az ADR 0280 nem mondja ki. |

**Egyik MINOR sem érint acceptance-kritériumot és egyik sem termék-hiba** —
kettő teszt-higiénia (1, 2), kettő jövőbeli karbantarthatóság (3, 4). A
protokoll szerint (`MINOR → körben javítható, ha nem hizlalja a diffet;
különben follow-up`) ezeket **follow-upra** teszem: egy javító kör +
kötelező exact-SHA CI-újradispatch ára aránytalan két teszt-elnevezési
nithez képest, miközben mind a 8 acceptance-pont és mindkét kötelező
valódi-sértés próba **függetlenül bizonyított**.

## 7. Architektúra és termékhatárok (AGENTS.md §5–§6)

- `core ↛ feature`: a kör kódja nem importál `lib/features/**`-ot. A tesztek
  igen (`cents_gauge` NEM, csak DS-komponenseket) — ez teszt, nem termékkód.
- `public.dart` contract: a két új fájl exportálva, a katalógus rendje
  megmarad; az `architecture` kapu zöld.
- UI ↛ plugin, audio/hálózat/mic/secret: a diff egyikhez sem nyúl; a
  `secrets` kapu zöld. A DSP-t és a felismerési frekvenciát a kör **nem**
  módosította (AGENTS.md §9).
- Lifecycle: az `SsLiveRegion` `ChangeNotifier`; a `SsLiveRegionAnnouncer`
  `ListenableBuilder`-t használ, ami a listenert maga köti/oldja. A
  kontroller `dispose()`-a a hívó dolga — feature még nem használja.

## 8. Verdikt

✅ **APPROVED.** Nincs BLOCKER, nincs MAJOR. A gate saját kézzel újrafuttatva
zöld, a scope-audit tiszta, mind a 8 acceptance-kritérium tételes
bizonyítékkal áll, és a két kötelező valódi-sértés próbát **magam is
lefuttattam** — mindkettő a várt cellát váltotta pirosra. A 4 MINOR + 3 NOTE
follow-up.

**Merge-feltétel:** a `full-gate.yml` és a `router-ci.yml` `success` a merge
SHA-ján (ADR 0086 §2 exact-SHA).
