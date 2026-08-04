# Review — E03-R17 (Song Overview, track/range választás és Trainer Setup)

- **Kör:** E03-R17 · **Branch:** `codex/e03-r17-overview-track-range-setup`
- **Reviewelt HEAD:** `4b4ef88` · **Baseline:** `origin/main` @ `4c51009`
- **Motor:** Codex · **Reviewer:** Claude (Opus 4.8), read-only
- **Verdikt:** **APPROVED** — nyitott BLOCKER/MAJOR nélkül.

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=4b4ef88`. A `dirty_files=1` a jelzés
pillanatában a még nem trackelt `.codex-round-status` maga volt; a commit utáni
working tree tiszta (`git status --short` üres). A brief §10 handoff kitöltve,
tényleges gate-kimenettel.

## 2. Gate-újrafuttatás (izolált `/tmp/review-e03-r17` klón)

Friss checkout → `tools/prepare-flutter-generated.sh` (a gitignore-olt l10n/
package output helyreállítása; enélkül a klón `AppLocalizations`-hiánnyal RED —
ez a HEAL E03-R14/H7 mért osztály, nem a kör hibája) → `tools/round-gate.sh`
a négy gate-teszttel:

```
format        zöld
analyze       zöld
test (×4 külön processz) zöld
architecture  zöld  (12 allowlisted deviation)
MINDEN GATE ZÖLD.
```

A teljes suite + property + APK a CI-ban (run
[30898027117](https://github.com/wolfcasaba/strumsight/actions/runs/30898027117),
exact head `4b4ef88`).

## 3. Scope-audit

`git diff --stat origin/main...4b4ef88`: **21 fájl, mind az allowed_path-on
belül** (a §0.0 R1 után felvett `lib/app/routing/app_route.dart`-tal együtt),
plusz az orchestrátor-tulajdonú docs (ADR 0125, brief, ez a review). **Nulla
listán kívüli production fájl.** A `song_trainer_providers.dart` érintetlen (a
setup controller a §0.0 R2 szerint co-located providert deklarál és tiszta
domain service-t példányosít).

## 4. Acceptance criteria — tételes bizonyíték

| Kritérium | Bizonyíték | Verdikt |
|---|---|---|
| Full/section/inclusive→exclusive measure range + bookmark validálható | `MeasureRange`/`SectionRange`/`FullSongRange`/`BookmarkRange`; eldobható reviewer-próba (lásd §5/a) | ✅ |
| Chord/strum/mono/poly/backing/missing-asset helyes control-állapot | `_modeAvailabilities` mátrix; mutation-próba (§5/b) | ✅ |
| Unsupported mode disabled + indokolt; valid setup EGY immutable config | `TrainerModeAvailability.disabled(reason)`; `TrainerConfig` `final`/`==`; kontroller teszt | ✅ |
| Tuning/capo reminder + resume CTA feltételes | `showTuningReminder`/`showCapoReminder` a metadatából; `canResume` (default false = rejtett CTA, R21 producer) | ✅ |
| 200% text scale, HU/EN; setup után SongDocument equality változatlan | widget-teszt „remains scrollable at 200 percent text scale"; a kontroller csak `repository.get()`-et hív, sose mutál | ✅ |

## 5. Próbatesztek (eldobhatók, merge előtt törölve)

**(a) Range off-by-one él (a §9 nevesített kockázata) — független referencia.**
8-measure-es dalon: inkluzív `[0..7]` → exclusive `[0,8)` resolve OK (utolsó
measure csak a határon bent); inkluzív `[0..8]` → `[0,9)` **null** (nem léphet
ki a dalból); egy-measure `[3..3]` → width-1 `[3,4)`; üres/degenerált dobás;
üres dalon `FullSongRange` → null. **Mind zöld** a kézzel számolt referenciával
szemben.

**(b) Capability-mátrix diszkrimináció — mutációs próba.** A kontrollerben a
pitch-kapu (`capability.pitch.scoring && capability.pitch.isMonophonic`) →
`true` mutáció után a kör saját `song_trainer_setup_controller_test.dart`-ja
**PIROSRA vált** („disables polyphonic pitch" eset), visszaállítás után zöld. A
teszt tehát valóban méri az invariánst, nem csak együtt fut vele.

## 6. Architektúra + termékhatárok

- Capability a report chord/pitch tengelyéről (`report.chord.scoring`,
  `report.pitch.scoring && isMonophonic`); a rhythm strukturális (track-altípus
  + `canTrain`) — megegyezik a §0.0 R3 / ADR 0125 mért döntéssel.
- Backing playback-rate őszintén `pending` (`trainer-backing-rate-pending`
  kulcs), nincs „supported" állítás (kötött döntés 3 / ADR 0125 §4).
- Missing backing asset különálló jelzés (`hasMissingBackingAsset`), a scoringot
  nem törli.
- Termékhatár tiszta: nincs `MethodChannel`/mic/`http`/`dio`/`SharedPreferences`
  a kör fájljaiban; a setup csak olvas és egyetlen immutable `TrainerConfig`-ot
  ad tovább. Lifecycle: a co-located provider `autoDispose`, `ref.onDispose` a
  stream-controllert zárja.

## 7. Leletek

| Súlyosság | Lelet |
|---|---|
| BLOCKER | — |
| MAJOR | — |
| MINOR | — |
| NOTE | `canResume` jelenleg mindig false (R21 producer előtt); a rejtett-CTA szándékos (§9). Follow-up: R21-ben a resume-producer bekötése + a CTA láthatóság tesztje. |

**Merge-döntés:** a zöld kapu (ADR 0052) minden lokális eleme zölden mérve;
CI exact-head `4b4ef88` zöldjének megerősítése után squash-merge.
