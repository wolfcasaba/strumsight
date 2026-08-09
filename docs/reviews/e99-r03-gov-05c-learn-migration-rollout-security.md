# E99-R03 (GOV-05c) — Biztonsági / adatvédelmi / prompt-injection review

- **Kör:** `E99-R03` (GOV-05c) — Learn migráció a Practice Engine V2-re (governance-kör)
- **Branch:** `codex/e99-r03-gov-05c-learn-migration-rollout` · **PR** #206
- **Diff-tartomány:** `69ecc661` → `42f54b33` (7 fájl, +176/−42)
- **Reviewer:** dedikált `security-reviewer` ágens (AGENTS.md — kötelező, mert a
  brief `risk = "high"`), az orchesztrátor (Claude Sonnet 5) rögzítette a
  jelentést fájlba a review után. READ-ONLY — production/teszt fájlt nem
  módosított.
- **Verdikt:** **PASS** — nulla CRITICAL/BLOCKER/MAJOR/MINOR lelet. Egy
  pozitív (privacy-javító) megfigyelés és két forward-looking NOTE.

## Súlyossági összegzés

| Súlyosság | Darab | Jelentés |
|---|---|---|
| CRITICAL | 0 | — |
| BLOCKER | 0 | — |
| MAJOR | 0 | — |
| MINOR | 0 | — |
| NOTE | 2 | forward-looking, nem blokkol |

## Mit vizsgált a review és mi volt a bizonyíték

A kör hatása egyetlen sor: `feature_flags.dart:58` `migratedLearnEnabled:
false` → `nonProd`. Ettől a `learn_screen.dart` négy `_migratedLearnEnabled`-
kapuzott ága élessé válik development/lab buildben. A biztonsági kérdés tehát
nem a réteg újra-átvizsgálása (az már a Practice V2/GOV-05a köröknél
megtörtént), hanem: **nyit-e ez a flag-flip ÚJ adat-/hálózat-/log-felületet.**

**1. Változáskészlet integritása.** `git diff --name-status`: mind a 7 fájl
**M** (módosított), **0 hozzáadott fájl** → nincs új fixture/asset, ami
kulcsot hordozhatna. A `lib/` alatt egyetlen érintett fájl a
`feature_flags.dart`.

**2. A négy élessé váló ág osztályozva** (`learn_screen.dart`):

- **187. sor — V2 megfigyelés-gyűjtés:** `_v2Observations.add(StrumObservation(...))`.
  A `StrumObservation` mezői: `at` (Duration), `sequence` (int), `direction`
  (enum), `confidence` (double) — származtatott DSP-metaadat, **nyers audio
  nincs benne**. In-memory lista, `_restart()`-nál törlődik
  (`_v2Observations.clear()`, 264. sor), kizárólag a `scoreLessonV2` tiszta
  függvény olvassa; nincs sorosítás/log/hálózat sink.
- **253. és 303. sor — mikrofon-rés zárása pause/finish előtt:** reviewer
  saját olvasással megerősítve (`learn_screen.dart:248-306`) —
  `if (_migratedLearnEnabled) { _frameSub?.close(); _frameSub = null; }` mind
  a `_pause()`, mind a `_finish()` elején. A legacy úthoz képest ez **koráb-
  ban** engedi el a mikrofont (a legacy `_pause()` nyitva hagyja a
  `_frameSub`-ot) — nettó **adatvédelmi javulás**, nem regresszió.
- **313. sor — `scoreLessonV2` pontozás:** tiszta számítás a leckén +
  megfigyeléseken; `double`-t ad vissza. Nincs I/O, nincs log.
- **326. sor → `_recordLearnMomentV2`:** a `practiceSessionRecordingProvider.
  record()`-on át ír. A rögzítési sink — lásd 3. pont.

**3. A rögzítési sink NEM új felület.** A `_recordLearnMomentV2` a
`PracticeSessionRecording.record()`-ot hívja, ami a `practiceLogProvider` +
`streakProvider` + `lessonProgressProvider` sinkekbe ír — **pontosan azok a
sinkek, amiket a legacy Learn ág is ír**, azonos `PracticeEntry` alakkal.
Reviewer saját olvasással megerősítve (`lib/features/progress/model/
practice_entry.dart:46-53`), a `PracticeEntry.toJson()` kizárólag ezt
sorosítja:

```dart
Map<String, dynamic> toJson() => {
  'day': day,        // epoch day, int
  'src': source.name, // enum név, pl. "learn"
  'sec': seconds,     // int
  'str': strokes,     // int
  'chd': chords,      // int
  if (directionAccuracy != null) 'dir': directionAccuracy, // double
};
```

**Nincs PII, nincs nyers audio, nincs szabad szöveg, a `lessonId` sem kerül a
bejegyzésbe.** A tároló helyi JSON (`JsonCollectionStore<PracticeEntry>`,
„persisted locally… not synced"). A `PracticeSessionRecording` use case már
ma is élő dev/lab-ban a testvér-flagek (`practiceEngineV2Enabled`/
`songTrainerV2Enabled`, szintén `nonProd`) miatt — a flag-flip **egy új
hívási helyet ad, nem új sinket.**

**4. Hálózat / consent-felület bizonyítottan érintetlen.**
`usesNetwork => accountEnabled || diagnosticsEnabled` (`feature_flags.dart:144`)
— a `migratedLearnEnabled` **nem** járul hozzá (reviewer saját olvasással
megerősítve). Grep a `lib/features/{learn,practice,progress}` fában Dio/
http/supabase/upload-ra a rögzítési úton: nincs találat. A kijelentkezett/
diagnostics-off állapot hálózati viselkedése változatlan → **AGENTS.md §5.2
nem sérül.**

**5. Log-szivárgás.** Grep `print`/`debugPrint`/`developer.log`/`logger` az
élessé váló úton: nincs valódi találat. **AGENTS.md §5.3 nem sérül.**

**6. Doc-comment állítások igazolva** (a kör átírta őket):
- `feature_flags.dart:43-44` „Practice V2, detailed history, and migrated
  Learn are available outside production. None of the practice flags has a
  dart-define override." → **IGAZ.**
- `feature_flags.dart:90-93` „[forEnvironment] enables it outside
  production; the default constructor remains OFF" → **IGAZ** (factory
  `nonProd`, konstruktor-default `false`, `app_config.dart:115` invariáns
  kielégül, mert mindkét flag `nonProd`).

**7. Prompt injection — nem alkalmazható.** A `lib/` diff egyetlen AI/
vision-releváns sora az `aiTutorEnabled: false,` — **változatlan** kontextus-
sor. Nincs új provider-hívás, nincs külső tartalom promptba-adás,
`aiTutorEnabled`/`visionEnabled` `false` marad.

**8. Import / ellátási lánc — nem alkalmazható.** Nincs új dependency,
asset, sem kicsomagolási/parszolási útvonal a diffben.

## Leletek

Nulla blokkoló, MAJOR és MINOR lelet.

### Pozitív megfigyelés (nem lelet)

- **`learn_screen.dart:253, 303`** — a V2 út a mikrofon-frame feliratkozást
  pause/finish előtt zárja, ezzel a legacy útnál **korábban** engedi el a
  mikrofont. A flag-flip nettó adatvédelmi hatása pozitív.

### NOTE-1 (forward-looking, nem blokkol)

- **`learn_screen.dart` (`_v2Observations` mező)** — az egyetlen ténylegesen
  új adatstruktúra egy in-memory `List<StrumObservation>`. Ma nincs sinkje
  (sem `toJson`, sem log, sem hálózat), és `StrumObservation` DSP-metaadat,
  nem PII/nyers audio. *Hipotetikus forgatókönyv (jelenleg nem
  reprodukálható):* ha egy jövőbeli kör crash-reportert vagy widget-state
  sorosítást vezetne be, ami elkapja a `State` mezőit, ez a lista
  strum-időzítést + confidence-t tartalmazna. Irány: ha valaha sink kerül a
  Learn képernyő state-jére, a `_v2Observations`-t tekintsd elemzendő
  adatmezőnek. Súlyosság ma: NOTE.

### NOTE-2 (scope-jelzés, a funkcionális/GOV-06 sávba tartozik)

- **ADR 0198 §Negatív + `learn_screen.dart:313`** — a pontozómotor-csere
  (`scoreLessonV2`) ugyanarra a játékra más lecke-csillag/irány-pontosság
  értéket adhat, és valós hangon még nincs visszaigazolva. Ez
  **korrektség/accuracy** kérdés (a paritás-mátrix méri, a GOV-06 valós-audio
  mérés zárja), **nem** §5.5 „gyenge confidence biztos állításként"
  biztonsági határsértés: egyik út sem jelenít meg confidence-sávot, a
  UI-prezentáció (accuracy %) a két úton azonos. Biztonsági szempontból nincs
  teendő; a teljesség kedvéért jelezve.

## Nem tárgyalható termékhatárok (AGENTS.md §5) — ellenőrzés

| Szabály | Állapot | Bizonyíték |
|---|---|---|
| §5.1 Nyers audio/kamera nem hagyja el az eszközt | **OK** | `StrumObservation` = metaadat; `PracticeEntry` = numerikus; nincs hálózati sink |
| §5.2 Kijelentkezve/diagnostics-off nincs rejtett kérés | **OK** | `usesNetwork` nem függ a flagtől; nincs Dio/http a rögzítési úton |
| §5.3 Secret/token/nyers audio nem kerül logba/commitba | **OK** | 0 új fájl; 0 log-hívás az úton; diff csak flag+teszt+doksi |
| §5.4 Cloud/community nem rontja az offline élményt | **OK (n/a)** | végig offline funkció (helyi pontozás + helyi tároló) |
| §5.5 Gyenge confidence nem biztos állításként | **OK** | a prezentáció változatlan a legacy-hez; lásd NOTE-2 |

## Verdikt

**PASS.** A GOV-05c flag-flip nem nyit új titok-, hálózati vagy log-
felületet: az egyetlen élessé váló perzisztens sink (`practiceLogProvider`)
már ma is élő testvér-flageken át fut, és a `PracticeEntry` alakja bájtra
azonos a legacy Learn úttal; a hálózat-consent felület (`usesNetwork`)
bizonyítottan független a flagtől; a mikrofon-életciklus a V2 úton
szigorúan jobb. A doc-comment állítások pontosak. Prompt-injection és
import-felület nem érintett. A kör biztonsági/adatvédelmi szempontból
mergelhető.
