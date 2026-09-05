# E14-R11 — kör-review (ADR 0055, read-only)

- **Reviewer:** Claude (Opus 5), orchestrátor — a kör implementációját NEM ő írta
- **Implementer motor:** `sonnet-impl` (Claude Sonnet 5, `--effort high`)
- **Branch:** `sonnet-impl/e14-r11-chord-uncertainty-and-separate-confidence`
- **Review-alap:** `39b9e4cc` (pre-flight) → `e8687cde` (head)
- **Dátum:** 2026-09-05
- **ADR:** [0516](../adr/0516-live-chord-decision-wiring.md)

## 1. Amit a kör szállított

A Live pipeline akkord-verdiktje tipizálva lett a **MÁR MERGE-ELT**
`RecognitionDecision` / `RecognitionRejectReason` szótárral, és additívan
eljut a `LiveFrame`-ig. Diff: 3 produkciós/teszt fájl + a brief §10.

| Fájl | Sor |
|---|---|
| `lib/features/live/engine/dsp/live_pipeline.dart` | +144 / −10 |
| `lib/features/live/model/live_frame.dart` | +15 |
| `test/features/live/chord_uncertainty_test.dart` | +325 (ÚJ, 17 teszt) |

**Scope-audit:** `scope_audit=ok`, `scope_audit_base=39b9e4cc`,
`scope_audit_changed=4` — a listán kívüli fájl nem változott. Külön
ellenőrizve: a `docs/adr/**`, a `lib/features/live/domain/recognition/**`
(a merge-elt szerződés), a `dsp_config.dart` és a
`lib/features/live/widgets/**` **érintetlen**.

## 2. Acceptance-pontok — leletenként ellenőrizve

| # | Pont | Verdikt | Bizonyíték |
|---|---|---|---|
| 1 | tipizált akkord-verdikt | ✅ | `chordPrediction` getter; `ChordPrediction` termelő már nem nulla |
| 2 | `confirmed` ⟺ mai `showChord` | ✅ | **szó szerint azonos feltétel** (lásd §3) |
| 3 | a négy 5.4 leképezési sor | ✅ | 4 külön cella, mind a négy ág |
| 4 | rise-küszöb hármas (0.53/0.54/0.55) | ✅ | egzakt EMA-értékkel, audio nélkül |
| 5 | `calibratedConfidence == null` | ✅ | 2 cella (confirmed + rejected ág) |
| 6 | chord ≠ strum forrás | ✅ | 2 cella, `_FixedClassifier`-rel |
| 7 | kompatibilitás | ✅ | `empty` + `copyWith` cella |
| 8 | adapter-hézag pinnelve | ✅ | `LiveFrameAdapter` kimenetén `chordDecision == null` |

### A 2. pont külön igazolása (a kör legfontosabb invariánsa)

```dart
// _buildFrame():
final showChord = _lastChord != null && _chordLatched;
// debugDeriveChordDecision():
if (chordLatched && hasMatch) return (RecognitionDecision.confirmed, null);
//   ahol hasMatch := (_lastChord != null), chordLatched := _chordLatched
```

A két feltétel **azonos**, és a `confirmed` ág **elsőként** fut le, tehát a
jel-minőség-ág nem tudja felülírni. A viselkedés így bit-azonos: a
felhasználó által látott akkord nem változik (§5.6 teljesül).

### A viselkedés-azonos refaktor ellenőrizve

Az `_applyChordConfEma` kiemelés nem változtat számítást:
`_chordConfEma += α*(conf−_chordConfEma)` → `_applyChordConfEma(_chordConfEma + α*(conf−_chordConfEma))`,
a metódus első sora `_chordConfEma = ema`. Ugyanaz a művelet, ugyanabban a
sorrendben, ugyanazok a `>=` / `<` összehasonlítások. A `chordPrediction`
getter **tiszta**: csak olvas (`_lastChord`, `_chordLatched`,
`_signalQuality.snapshot`), állapotot nem mutál — a `_buildFrame`-ből
hívása nem okoz mellékhatást.

### Falszifikáció (§7.1)

Az implementer TÉNYLEGES kimenetet dokumentált (nem állítást): a
chord-match confidence strum-confidence-re cserélésével **4 teszt piros**
(pt.6 két cellája + pt.1 + pt.2), visszaállítva **17/17 zöld**. A cella
tehát valóban fog — a mérce nem üres.

## 3. Leletek

**BLOCKER: nincs. MAJOR: nincs.**

### MINOR-1 — a `chordPrediction` getter sosem ad `null`-t, de `?`-os a típusa

`ChordPrediction? get chordPrediction` minden ágon konstruál (nincs match
esetén `'N.C.'` label-lel), tehát a `null` visszatérés **elérhetetlen**. A
`_buildFrame` emiatt fölöslegesen `chord?.decision`-t ír. Nem hiba, de a
típus többet ígér (halott nullability), mint amit a kód valaha produkál.

### MINOR-2 — a `stabilityFrames: 0` a kód doc-commentjében nincs indokolva

A merge-elt szerződés a mezőt így dokumentálja: „How many consecutive
frames agreed on this verdict". A pipeline **mindig `0`-t** ír bele (a
Viterbi-dekóder nem számol streaket). Ez a brief §10-ben le van írva, a
**getter doc-commentjében viszont nem** — pedig ugyanaz a doc-comment a
`calibratedConfidence`-t és a `pNoChord`/`pUnknown`-t kifejezetten
megindokolja. Egy truthfulness-körben egy szerződés-mező néma, mindig
hamis értéke érdemel egy mondatot.

### MINOR-3 — a `pNoChord` hard 0/1 egy „raw model probability" mezőben

`pNoChord: match == null ? 1.0 : 0.0`. Amikor a döntés `uncertain` (van
match, de a kapu alatt), a `pNoChord = 0.0` teljes bizonyosságot állít
arról, hogy VAN akkord — miközben épp az a kérdéses. A getter
doc-commentje ezt kimondja és indokolja („hard, deterministic match/no-
match state"), és fogyasztója ma nincs, ezért nem MAJOR; de a
`toJson()`-on keresztül exportálható, tehát egy későbbi diagnosztikai
fogyasztó félreértheti.

### NOTE-1 — `@visibleForTesting` a produkciós úton

A `debugDeriveChordDecision` `@visibleForTesting` és `debug` előtagú, de a
`chordPrediction` getter (produkciós út) hívja. Ugyanabban a library-ben
van, ezért az `invalid_use_of_visible_for_testing_member` lint nem üt (az
`analyze` zöld ezt megerősíti), de a név „csak teszt"-et sugall arról, ami
az EGYETLEN produkciós levezetési hely.

### NOTE-2 — allokáció frame-enként

A `chordPrediction` minden `_buildFrame`-nél (~15 Hz) új
`ChordPrediction`-t, tuple-t és két substringet allokál. Izolátumon fut,
elhanyagolható; feljegyezve, ha a Live perf-profil később szűkül.

## 4. Amit a kör NEM szállított (nevesítve, nem elfelejtve)

A **Chapter 14 §9/6 UI-adóssága NYITVA marad**: a szállított Live felület
továbbra is kalibrálatlan százalékot ír ki
(`live_screen.dart:350`, `chord_timeline_card.dart:225`), és bizonytalan
döntésnél nincs szöveges állapot. Ennek oka a pre-flightban MÉRT tény: az
eredeti brief UI-céljai (`confidence_pill.dart`, `chord_display.dart`)
**halott kódra** mutattak (nulla `lib/` importőr), a valódi javítás pedig a
`lib/features/live/screens/**`-ot kívánná — az `allowed_paths` tágítása az
orchestrátornak nem hatásköre (ADR 0087 §2 H3). Lásd ADR 0516 D6 és a
brief §0.0.

**Következő kör igénye:** UI-kör, amelynek `allowed_paths`-a tartalmazza a
`lib/features/live/screens/live_screen.dart`-ot és a
`lib/features/live/widgets/chord_timeline_card.dart`-ot, és amely a most
szállított `LiveFrame.chordDecision` / `chordRejectReason` mezőket
jeleníti meg szöveges állapotként.

## 5. Kapu

- `tools/round-gate.sh test/features/live/chord_uncertainty_test.dart test/features/live`
  → mind a 7 lépés ZÖLD (format, analyze, 2× test, architecture, secrets,
  l10n); `[3]` 17/17, `[4]` 389/389 — nincs regresszió a Live fában.
- Full Gate + Router CI a **pontos** `e8687cde` head SHA-n (§6-ban rögzítve).

## 6. VÉGSŐ DÖNTÉS

**APPROVED** — 0 BLOCKER, 0 MAJOR. A három MINOR és a két NOTE nem
blokkolja a merge-et (ADR 0052); a MINOR-2 és MINOR-3 doc-comment-szintű
pontosítás, amit a következő, ezt a mezőt ténylegesen FOGYASZTÓ kör
olcsóbban végez el, mint egy külön javító kör.

A merge feltétele változatlan: a teljes CI-suite (`full-gate.yml`) és a
`router-ci.yml` `success` a merge SHA-n.
