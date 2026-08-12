# ADR 0239 — Analysis document storage

- **Státusz:** Elfogadva (E06-R21 pre-flight, 2026-08-12)
- **Kör:** E06-R21 — AnalysisRepository V2 és legacy Library migráció
- **Implementer motor:** sonnet-impl
- **Epic:** [Chapter 7 — Epic 6: Audio Analysis 2.0](../sdd/07-epic-06-audio-analysis-2.md)
  Kör 21; §24.1–24.6
- **Kontext-ADR-ek:** [0215](0215-analysis-document-versioning.md),
  [0217](0217-analysis-raw-audio-retention.md),
  [0220](0220-audio-analysis-v2-parallel-rollout-boundary.md),
  [0221](0221-legacy-analysis-v2-migration-mapping.md).

## Kontextus

**Mért 2026-08-12-én, `main` @ `9703254d`:** a V1 Library egyetlen
`ss.library.sessions` SharedPreferences dokumentumban legfeljebb 100 teljes
`AnalyzedSession` rekordot tárol. A V2 `AnalysisDocument` nagy, verziózott
timeline-okat hordoz; nincs benne `title` vagy `customTitle`. Az E06-R03
`LegacyAnalyzeAdapter` a V2 dokumentum mellett `LegacyAnalysisMigration`
kísérőben tartja a címet és a custom-title jelölőt. A meglévő
`AnalysisDocumentCodec` determinisztikus JSON boundary, a `crypto` SHA-256
dependency jelen van. A Song Trainer file store-ja az atomikus temp→verify→rename
mintát használja, de a feature belső fájlját az Audio Analysis nem importálhatja.

## Döntés

1. **Egy AnalysisDocument = egy fájl** az app-support `analysis/` könyvtárában;
   a gyors lista külön, újraépíthető summary-indexet használ. A document-fájl
   a codec JSON-ját és SHA-256 ellenőrzőösszegét hordozza.
2. **Minden document- és index-írás atomikus.** Az audio-analysis local adapter
   a bizonyított temp→flush/verify→rename mintát saját data-layer kódban
   ismétli meg. A régi célfájl csak sikeres verify után cserélődik le.
3. **A korrupció rekord-szintű.** Hibás checksum vagy codec-dekódolás esetén az
   érintett fájl `<file>.corrupt` néven karanténba kerül, az indexből kikerül,
   és a többi summary tovább listázható. A `getById` typed storage failuret ad.
4. **Az index nem igazságforrás.** Hiányzó vagy sérült indexet a repository a
   document-fájlokból épít újra. A `list()` csak ezt az indexet olvassa; teljes
   dokumentumot nem dekódol.
5. **A V1 migráció nem destruktív és idempotens.** A migrátor a
   `LibraryRepository` publikus `load()` contractján át kapja a legacy rekordokat,
   dokumentumonként ment, checkpointot vezet, és a régi
   `ss.library.sessions` kulcsot ebben a körben sem törli, sem írja át. A cím és
   `customTitle` kizárólag a V2 summary-indexben él; az `AnalysisDocument` és
   codec nem változik.
6. **Nyers audio nem perzisztálható.** Az `AudioRetentionPolicy.keepOriginal`
   alapértéke `false`; a repository kizárólag V2 document JSON-t és summary/
   migration metadata-t ír. PCM, waveform vagy más audio bájt nem kerül fájlba.
7. **A cap 100.** A 101. sikeres mentéskor createdAt szerint a legrégebbi
   document és index-entry törlődik. Pontosan 100-nál nincs törlés.

## Következmények

- Az átmeneti V1 és V2 másolat szándékosan együtt él; a V1 törlése csak egy
  későbbi rollout-döntés része lehet.
- A migráció részleges hiba után folytatható: a már sikeres documentek és a
  checkpoint megmaradnak, az ismételt futás nem duplikál ID alapján.
- A path_provider hívás kizárólag application providerben él; teszt temp
  `Directory`-t injektál, ezért data/domain nem hív platform plugint.

## Elutasított alternatívák

- **Egyetlen SharedPreferences JSON tömb.** A nagy timeline dokumentumokkal
  nem skálázható és egy írási hiba túl nagy korrupciós sugarú.
- **SQLite/Drift.** Új dependencyt és `pubspec.yaml` módosítást kérne, ami e
  kör tiltott scope-ja.
- **A Song Trainer AtomicFileWriter közvetlen importja.** Feature-internal
  függőséget hozna létre; a közös core storage primitive külön későbbi kör.
- **A legacy store törlése a migráció végén.** Megszakítás vagy későbbi V2
  validációs hiba esetén adatvesztési kockázatot teremtene.

## A visszavonás feltétele

Felülvizsgálandó, ha a document-cap vagy a retention policy tényleges eszközös
tárhelymérése más határt indokol, illetve ha a V1→V2 rollout bizonyítottan
visszafordítható és külön kör jóváhagyja a legacy store eltávolítását.
