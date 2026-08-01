# E03-R14 — Jóváhagyott Guitar Pro út

- **Státusz:** **PREPARED** (2026-08-01, tervezési baseline: `main` @ `eeb4f6d`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 14; §17.2–17.4
- **Branch:** `codex/e03-r14-guitar-pro-path`
- **Előfeltétel:** E03-R13 merge és elfogadott GP ADR
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "pubspec.yaml",
  "pubspec.lock",
  "lib/features/song_trainer/data/importers/guitar_pro_importer.dart",
  "lib/features/song_trainer/data/importers/guitar_pro_parser_adapter.dart",
  "lib/features/song_trainer/data/importers/guitar_pro_mapper.dart",
  "lib/features/song_trainer/data/importers/importer_registry.dart",
  "test/features/song_trainer/data/importers/guitar_pro_importer_test.dart",
  "test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart",
  "lib/features/song_trainer/presentation/widgets/guitar_pro_conversion_guidance.dart",
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/user-guide/guitar-pro-conversion.md",
  "docs/rounds/e03-r14-guitar-pro-path.md",
]
gate_tests = [
  "test/features/song_trainer/data/importers/guitar_pro_importer_test.dart",
]
native_gate = false
```

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** ellenőrizd az `origin/main` és az
> elődkör merge-jét; olvasd újra az `AGENTS.md`, Chapter 1/3/4,
> `HANDOFF.md`, a releváns ADR-eket és a `docs/LESSONS.md` fájlt. `rg`-vel
> igazold minden útvonal, symbol, producer, resource owner, dependency/licence
> és numerikus cella mai állapotát. Drift esetén dokumentáld §0.0-ban,
> módosítsd a scope/fájllistát, majd commitold a `PLANNING` briefet a
> körbranchre az implementer előtt. A `PREPARED` brief nem futtatható vakon.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Az implementer nem hív `gh`-t, nem pushol
és nem nyit PR-t. Listán kívüli fájl, ellenőrizetlen contract/licence,
ellentmondó acceptance, hiányzó fixture vagy nem reprodukálható mérce esetén
`stopped`; nincs néma scope-tágítás vagy acceptance-gyengítés.

## 0.0 Tervezési baseline és pre-flight revízió

- R13 egyetlen A/B/C stratégiát és exact licence/security feltételeket ad.
- A PREPARED brief mindkét teljes út fájljait dokumentálja, de nem engedi egyszerre végrehajtani.
- A pre-flight az inaktív ág minden fájlját törli a §4-ből és explicit tiltott zónává teszi.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Az R13 ADR-rel egyező, pontosan egy aktivált Guitar Pro út szállítása: izolált parser adapter vagy őszinte MusicXML/MIDI konverziós UX.

## 2. Jelenlegi állapot

- R13 egyetlen A/B/C stratégiát és exact licence/security feltételeket ad.
- A PREPARED brief mindkét teljes út fájljait dokumentálja, de nem engedi egyszerre végrehajtani.
- A pre-flight az inaktív ág minden fájlját törli a §4-ből és explicit tiltott zónává teszi.

## 3. Scope

**Benne:**

- A ág: auditált parser adapter, probe, mapper, registry és versioned fixture snapshot
- C ág: GP unsupported result, konverziós guidance, l10n és user guide
- az aktív ág licence/security/capability evidenciája

**Kívül — ebben a körben TILOS:**

- mindkét ág egyidejű implementációja
- saját nagy binary parser az ADR megkerülésére
- nem támogatott GP verzió támogatottnak jelzése
- külső/jogsértő tartalomforrás automatizálása

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `pubspec.yaml` | A ág | jóváhagyott parser dependency |
| `pubspec.lock` | A ág | lock |
| `lib/features/song_trainer/data/importers/guitar_pro_importer.dart` | A ág ÚJ | adapter |
| `lib/features/song_trainer/data/importers/guitar_pro_parser_adapter.dart` | A ág ÚJ | package/native boundary |
| `lib/features/song_trainer/data/importers/guitar_pro_mapper.dart` | A ág ÚJ | domain mapping |
| `lib/features/song_trainer/data/importers/importer_registry.dart` | A vagy C | active/unsupported registration |
| `test/features/song_trainer/data/importers/guitar_pro_importer_test.dart` | A ág ÚJ | version/fidelity |
| `test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart` | C ág ÚJ | stable unsupported |
| `lib/features/song_trainer/presentation/widgets/guitar_pro_conversion_guidance.dart` | C ág ÚJ | őszinte UX |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | C ág ÚJ | guidance belépési pont; R15 pre-flight meglévőként auditálja |
| `test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart` | C ág ÚJ | widget/a11y/l10n |
| `lib/l10n/app_en.arb` | C ág | angol copy |
| `lib/l10n/app_hu.arb` | C ág | magyar copy |
| `docs/user-guide/guitar-pro-conversion.md` | C ág ÚJ | offline user guide |
| `docs/rounds/e03-r14-guitar-pro-path.md` | meglévő | §10 handoff |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Pre-flight pontosan egy aktív ág; inaktív sorok eltávolítandók a végrehajtható §4-ből.
2. A ág parser/natív típusa data boundaryn belül marad; worker/crash boundary az ADR szerint kötelező.
3. C ágban GP extension nem aktív importer; válasz stabil unsupported és MusicXML/MIDI guidance.
4. Feature/capability csak az ADR által bizonyított GP verziókra igaz.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Működés és copy exact egyezik az R13 ADR-rel; nincs félkész támogatás.
- [ ] A ágban támogatott verziók metadata/tuning/capo/tempo/meter/measure/repeat/note/string-fret/tie/chord/section snapshotja stabil; unsupported warning.
- [ ] A ág licence/fixture és natív worker/crash gate zöld, ha releváns.
- [ ] C ágban GP fájl 0 parse/commit mellett érthető unsupported választ ad, accessible HU/EN konverziós útmutatással.
- [ ] Inaktív ág fájljai nem szerepelnek a diffben.

### Kötelező megkülönböztető mátrix

| ADR ág | Input | Várt |
|---|---|---|
| A/B | támogatott GP verzió | probe+import+capability |
| A/B | nem támogatott/malformed | stable warning/failure, 0 commit |
| C | bármely GP extension/header | unsupported, 0 parser, 0 commit |
| C | guidance action | MusicXML/MIDI saját-fájl workflow |
| bármely | licence/provenance gate hiányzik | STOP |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

**A/B ág — kizárólag akkor marad meg, ha ezt választotta az R13 ADR:**

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/guitar_pro_importer_test.dart
```

**C ág — kizárólag akkor marad meg, ha ezt választotta az R13 ADR:**

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart
```

A brief pre-flightja az inaktív blokkot törli, így a `PLANNING` briefben
egyetlen futtatható `tools/round-gate.sh ...` parancs marad. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Pre-flightban válaszd ki az ADR ágát, töröld az inaktív fájlsorokat és gate-et.
2. Írd meg az aktív ág RED fixture/widget tesztjeit.
3. Implementáld kizárólag az aktív adaptert vagy guidance-ot.
4. Futtasd az aktív ág gate-jét és licence/capability auditját.
5. Igazold diffből, hogy az inaktív ág érintetlen.

Javasolt commit: `Az aktív ág szerint: feat(song-import): implement approved Guitar Pro import path — vagy — feat(song-import): add safe Guitar Pro conversion guidance`.

## 9. Kockázatok

- Az R15 import screen még nem létezhet; C ágban eltéréskor pre-flight exact UI belépési pontot jelöl vagy R15-re halasztott contractot dokumentál.
- Parser támogatási állítás verziószinten túl széles lehet; fixture nélküli verzió disabled.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

A kör még nem indult; nincs implementációs vagy tesztsiker-állítás. Végrehajtáskor
ide kerül a fájlonkénti összefoglaló, tényleges parancs/kimenet, eltérés,
nem futtatott ellenőrzés és follow-up. Minden viselkedési állításhoz konkrét
teszt vagy mérés tartozik.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r14-guitar-pro-path-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
