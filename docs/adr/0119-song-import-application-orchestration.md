# ADR 0119 — Song import application orchestration

**Státusz:** elfogadva (E03-R10 pre-flight, 2026-08-03).

## Kontextus

Az ADR 0091 kétfázisú, fail-closed import security boundaryt ír elő, az ADR
0118 pedig egyetlen in-memory `NativeJsonImporter` contractot valósított meg.
Az alkalmazásban még nincs közös registry, operation ownership, preview vagy
repository commit-határ. A picker platformobjektuma, egy teljes source byte
tömbje és a temporary-workspace elérési útja nem kerülhet Riverpod state-be.

## Döntés

1. A R09 `data/importers/song_importer.dart` contract a canonical
   `ImportSourceFile` és `CancellationToken`; R10 nem hoz létre második
   cancellation típust. A controller operation-local, visszavonható tokennel
   hívja az importert.
2. A `SongImportController` explicit, operation-ID-vel védett state machine:
   `idle → selecting → probing → preview → importing → validating →
   committing → success|failure|cancelled`. Régi callback csak a saját
   operation ID-ját módosíthatja. Terminal cleanup idempotens.
3. Az `ImporterRegistry` a probe eredményére választ, nem kiterjesztésre
   önmagában. Első tagja a R09 `NativeJsonImporter`; ismeretlen tartalom
   kontrollált failure. Minden importer a konfigurálható `ImportLimits`
   policyt kapja.
4. A temporary workspace a data-layer tulajdona. Csak a kijelölt root alatt
   hozhat létre egy operation-könyvtárat; abszolút, `..`-t tartalmazó vagy
   symlinkkel a rooton kívülre mutató út tiltott. Az operation cancel,
   dispose, failure és success útvonalán bezár és takarít. A workspace útja
   nem része a state/effect contractnak.
5. A terminal commit sorrendje: importer output → `SongNormalizer` →
   `SongValidator` → `SongCapabilityResolver` → `SongRepository.create`.
   Fatal validáció vagy bármely hiba előtt nincs repository rekord; a
   repository saját ADR 0090 szerinti atomikus írása az egyetlen persistent
   commit. Warning previewban látható, de nem válik fatallá.
6. A R10 picker adapter csak platform-független port. Nincs új plugin vagy
   licence-kötelezettség; konkrét platform picker későbbi, külön kör.

## Következmények

- Az application state kis, immutable és replay-safe marad; nem tartalmaz
  picker objektumot, byte arrayt, streamet vagy filesystem pathot.
- A R10 tesztek mindegyik terminal cellát, stale callbacket, limit-failuret és
  workspace takarítást közvetlenül mérik.
- Format-specifikus XML/MIDI parser, picker plugin és UI továbbra is kívül van.
