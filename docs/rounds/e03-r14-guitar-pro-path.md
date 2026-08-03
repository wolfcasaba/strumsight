# E03-R14 — Jóváhagyott Guitar Pro út

- **Státusz:** **PLANNING** (2026-08-03, pre-flight baseline: `origin/main` @ `0c69248`)
- **SDD-kör:** [`docs/sdd/04-epic-03-song-trainer.md`](../sdd/04-epic-03-song-trainer.md) Kör 14; §17.2–17.4
- **Branch:** `codex/e03-r14-guitar-pro-path`
- **Előfeltétel:** E03-R13 merge és elfogadott GP ADR
- **Brief szerzője:** Codex · **Implementáció:** Codex vagy a pre-flightban kijelölt agent

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/song_trainer/data/importers/importer_registry.dart",
  "test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart",
  "lib/features/song_trainer/presentation/widgets/guitar_pro_conversion_guidance.dart",
  "lib/features/song_trainer/presentation/screens/song_import_screen.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
  "lib/l10n/app_en.arb",
  "lib/l10n/app_hu.arb",
  "docs/user-guide/guitar-pro-conversion.md",
  "docs/rounds/e03-r14-guitar-pro-path.md",
  "docs/reviews/e03-r14-guitar-pro-path-review.md",
]
gate_tests = [
  "test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart",
  "test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart",
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

### Módosítás (ADR 0112 önjavító kör, 2026-08-03)

- **Mérés:** a független, exact-head review a kötelező
  `docs/reviews/e03-r14-guitar-pro-path-review.md` artefaktumot írja és a
  merge előtti commit megköveteli, miközben a korábbi §4 és az `ai-router`
  `allowed_paths` listája ezt az egyetlen útvonalat tiltottá tette.
- **Feloldás:** a review-artefaktum azonos, explicit útvonalként §4-be és a
  router metadatajába került. Csak a független reviewer írhatja; a kör
  implementere nem gyárt és nem módosít review-jelentést.
- **Védelem:** `Epic3BriefMetadataTest.test_r14_scope_includes_the_mandatory_review_artifact`
  őrzi, hogy a kötelező merge-evidence később sem kerülhessen vissza a tiltott
  zónába.

**2026-08-03 pre-flight revízió (baseline `origin/main` @ `0c69248`):**
`docs/adr/0122-guitar-pro-import-strategy.md` Döntés 5 és
`docs/research/epic-03-guitar-pro-feasibility.md` „Döntés és R14 aktiválási
szerződés” sora egyértelműen a **C** ágat választja. A ma mért production
owner `songImporterRegistryProvider`
(`lib/features/song_trainer/application/song_trainer_providers.dart:141-149`)
csak `NativeJsonImporter`, `MusicXmlImporter`, `MxlImporter` és
`MidiImporter` példányait adja; `ImporterRegistry.probe`
(`lib/features/song_trainer/data/importers/importer_registry.dart:34-58`) a
felismert tartalomhoz importer-t választ, a többi bemenetre
`songImport.unsupportedContent` hibával leáll. Ezért a C-ág nem ad hozzá
`SongImporter`-t, GP parser/dependency-t, registryben támogatott extensiont,
vagy parse/commit utat. A megengedett `importer_registry.dart` csak a
stabil, parser nélküli GP-unsupported választ különítheti el; a tényleges
support-lista a fenti providerben változatlan marad.

`lib/features/song_trainer/presentation/` ma nem létezik, a teljes
Library/import routing pedig SDD Kör 15 scope. A Kör 14 ezért az SDD §17 C
ágának önálló, később route-olható, l10n- és accessibility-tesztelt
`SongImportScreen`/guidance felületét hozza létre, de nem módosít app-routing,
picker vagy application-controller fájlt. Ez nem rejtett/automatikus
konverter: a képernyő és a user guide kizárólag a felhasználó saját,
app-on-kívüli konverziója utáni már támogatott MusicXML/MXL/MIDI fájl
importját írja le. Az A/B sorok és a hozzájuk tartozó gate inaktívak, ezért a
§4-ből és az `ai-router.allowed_paths`-ból törölve vannak.

A pre-flight minden állítást újramér. Eltérésnél itt rögzíti a mért tényt, a
feloldást és indokát. Üres vagy implicit revízióval nincs `PLANNING` státusz.

## 1. Cél

Az R13 ADR-rel egyező, pontosan egy aktivált Guitar Pro út szállítása: izolált parser adapter vagy őszinte MusicXML/MIDI konverziós UX.

## 2. Jelenlegi állapot

- R13 egyetlen A/B/C stratégiát és exact licence/security feltételeket ad.
- A PREPARED brief mindkét teljes út fájljait dokumentálja, de nem engedi egyszerre végrehajtani.
- A pre-flight az inaktív ág minden fájlját törli a §4-ből és explicit tiltott zónává teszi.

## 3. Scope

**Benne (C ág):**

- parser nélküli, stabil Guitar Pro unsupported-result a meglévő registry
  support-listájának megváltoztatása nélkül;
- önálló, hozzáférhető MusicXML/MXL/MIDI konverziós guidance és HU/EN l10n;
- offline user guide a felhasználó által választott külső konverzióhoz;
- a 0 parser / 0 commit és az inaktív A/B út gépi bizonyítéka.

**Kívül — ebben a körben TILOS:**

- A/B parser-adapter, package dependency, GP fixture vagy GP importer
- mindkét ág egyidejű implementációja
- saját nagy binary parser az ADR megkerülésére
- nem támogatott GP verzió támogatottnak jelzése
- külső/jogsértő tartalomforrás automatizálása

## 4. Engedélyezett fájlok

| Útvonal | Állapot/ág | Miért |
|---|---|---|
| `lib/features/song_trainer/data/importers/importer_registry.dart` | C ág | parser nélküli stable unsupported eredmény; nem support-lista |
| `test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart` | C ág ÚJ | stable unsupported |
| `lib/features/song_trainer/presentation/widgets/guitar_pro_conversion_guidance.dart` | C ág ÚJ | őszinte UX |
| `lib/features/song_trainer/presentation/screens/song_import_screen.dart` | C ág ÚJ | route-olható guidance belépési pont; R15 pre-flight meglévőként auditálja |
| `test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart` | C ág ÚJ | widget/a11y/l10n |
| `lib/l10n/app_en.arb` | C ág | angol copy |
| `lib/l10n/app_hu.arb` | C ág | magyar copy |
| `docs/user-guide/guitar-pro-conversion.md` | C ág ÚJ | offline user guide |
| `docs/rounds/e03-r14-guitar-pro-path.md` | meglévő | §10 handoff |
| `docs/reviews/e03-r14-guitar-pro-path-review.md` | független review | kötelező, merge előtti APPROVED/CHANGES REQUESTED artefaktum; csak reviewer írja |

**Tilos zóna:** minden más fájl, különösen `HANDOFF.md`, RTM,
nem felsorolt `.github/**`, más feature belső fájlja és más kör briefje.
`docs/adr/**` csak akkor engedett, ha a pre-flight ütközésmentes exact pathként
hozzáadta a táblához. A fent felsorolt review-artefaktum kivétel: azt csak a
független reviewer írhatja. Új fixture/helper is fájl; listán kívül → `stopped`.

## 5. Kötött architekturális döntések

1. Kizárólag C ág aktív; az A/B sorok nem részei a végrehajtható scope-nak.
2. GP extension nem aktív importer és a meglévő four-importer support-lista nem változhat.
3. A GP input parser és commit nélkül stabil unsupported választ, a guidance csak a felhasználó saját MusicXML/MXL/MIDI konverziós workflow-ját mutatja.
4. Nincs direct-GP feature/capability állítás vagy külső hálózati kérés.

E döntések nem lazíthatók azért, hogy egy teszt zöld legyen.

## 6. Acceptance criteria

- [ ] Működés és copy exact egyezik az ADR 0122 C döntésével; nincs félkész támogatás.
- [ ] GP nevű/extensionű bemenet 0 parser/0 commit mellett stabil, dedikált unsupported eredményt ad; a registry support-listája továbbra is pontosan négy importer.
- [ ] A guidance HU/EN, billentyűzet/screen-reader számára címkézett, és csak offline MusicXML/MXL/MIDI saját-fájl workflow-t mond.
- [ ] A user guide nem linkel/automatizál tartalomforrást vagy konvertert, és nem ígér GP-fidelityt.
- [ ] A/B parser/dependency/fixture fájl nem szerepel a diffben.

### Kötelező megkülönböztető mátrix

| Input | Várt |
|---|---|
| GP név/extension vagy GP header | stable unsupported, 0 parser, 0 commit |
| nem-GP, ismeretlen tartalom | a meglévő generic unsupported contract változatlan |
| guidance | MusicXML/MXL/MIDI saját-fájl, offline workflow |
| teljes registry | a négy meglévő importer; GP nincs a support-listában |

A reviewer legalább egy központi invariánst eldobható mutációval vagy független
reference-számítással pirosra vált; bemásolt zöld output nem önálló evidencia.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/song_trainer/data/importers/guitar_pro_unsupported_test.dart test/features/song_trainer/presentation/guitar_pro_conversion_guidance_test.dart
```

A `PLANNING` briefben egyetlen futtatható `tools/round-gate.sh ...` parancs
marad. A gate
format → analyze → célzott test → architecture külön processzekben fut; nincs
`&&`, pipe, `tail` vagy csonkítás. Full suite + property + APK CI-t az
orchestrátor indít exact `headSha`-ra.

## 8. Implementációs sorrend

1. Írd meg a parser nélküli unsupported és guidance RED tesztjeit.
2. Implementáld kizárólag a C-ág registry-guardját, guidance-át és guide-ját.
3. Futtasd az egyetlen C-ág gate-jét és az ADR 0122 scope-auditját.
4. Igazold diffből, hogy az A/B út érintetlen és a registry four-importer support-listája változatlan.

Javasolt commit: `feat(song-import): add safe Guitar Pro conversion guidance`.

## 9. Kockázatok

- Az R15 teljes import routing/picker munkája még nincs meg; R14 csak az ott
  route-olható, önálló guidance felületet szállítja, route-módosítás nélkül.
- A dedikált GP-unsupported guard nem válhat support-listává vagy parserre
  utaló capability-állítássá.

**STOP:** listán kívüli javítás, bizonyítatlan fallback vagy gyengített mérce
helyett dokumentált brief-revízió szükséges.

## 10. Implementation handoff — az implementer tölti ki

### Implementáció (2026-08-03)

- `importer_registry.dart`: a GP/GP3–GP8/GPX fájlnév, illetve a legacy
  `FICHIER GUITAR PRO` header parser indítása nélkül a stabil
  `songImport.guitarPro.unsupported` hibával áll meg. A négy production
  importer listája változatlan; dedikált GP ágban nincs selection, parse vagy
  import/commit út.
- `guitar_pro_conversion_guidance.dart` és `song_import_screen.dart`: route-ra
  készen átadható, olvasható, HU/EN lokalizált és saját szemantikai összefoglalót
  adó conversion-only UI. Nem indít pickert, konvertert vagy hálózati kérést.
- `app_en.arb`, `app_hu.arb` és `docs/user-guide/guitar-pro-conversion.md`:
  kizárólag saját fájl, eszközön végzett offline MusicXML/MXL/MIDI konverzió;
  nincs külső szolgáltató-link vagy GP-fidelity ígéret.
- A két új teszt a GP extension/header 0 importer-probe, generic unsupported
  regresszió, négy-importer lista, EN/HU copy és screen-reader összefoglaló
  celláit méri.

### Tényleges ellenőrzés

```text
RED: flutter test test/features/song_trainer/data/importers/
     guitar_pro_unsupported_test.dart
     → a hiányzó ImportRegistryFailureCode.guitarProUnsupported miatt fordítási
     hiba (elvárt test-first piros).

RED: flutter test test/features/song_trainer/presentation/
     guitar_pro_conversion_guidance_test.dart
     → a hiányzó SongImportScreen és GuitarProConversionGuidance miatt fordítási
     hiba (elvárt test-first piros).

GREEN: tools/round-gate.sh test/features/song_trainer/data/importers/
       guitar_pro_unsupported_test.dart test/features/song_trainer/presentation/
       guitar_pro_conversion_guidance_test.dart
       → format 745 fájl (0 változás), analyze: No issues found,
       importer: 4/4, guidance: 2/2, architecture: OK.
```

`flutter gen-l10n` lefutott az ARB-változás után; a keletkező
`app_localizations*.dart` fájlok gitignore-olt build-outputok, nem részei a
diffnek. Full suite, property gate és APK CI nem futott: ezek az orchestrátor
exact-headSHA CI-feladatai. Eltérés vagy scope-bővítés nincs.

## 11. Review — a független reviewer tölti ki

Tervezett review: `docs/reviews/e03-r14-guitar-pro-path-review.md`.
Merge csak exact-SHA zöld CI, §4-en belüli diff és nulla OPEN BLOCKER/MAJOR után.
