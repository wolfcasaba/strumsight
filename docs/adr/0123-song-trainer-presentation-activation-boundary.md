# ADR 0123 — Song Trainer V2 presentation activation boundary

**Státusz:** elfogadva (ADR 0112 önjavító kör, E03-R15/H3, 2026-08-03).
Épít az [ADR 0090](0090-song-storage-files-and-assets.md),
[ADR 0091](0091-song-import-security-boundary.md) és
[ADR 0119](0119-song-import-application-orchestration.md) döntéseire.

## Kontextus

Az import application controller a source file-t és a picker objektumot
szándékosan nem tartja state-ben: `RequestFilePickerEffect`-et bocsát ki, és
csak a platformfüggetlen `ImportSourceFile`-t fogadja a `selectSource` úton.
A jelenlegi `FilePickerAdapter` csupán interface, nincs production adapter vagy
hozzá tartozó függőség.

Hasonlóan, a `songRepositoryProvider` tudatos bootstrap seam: override nélkül
hibát dob. A jelenlegi app `ProviderScope` nem köti be a file-alapú production
repository-t, ezért egy flagelt V2 route import vagy library providert olvasva
az első interakciónál nem működő képernyőt adna.

## Döntés

1. Interaktív Song Trainer V2 library vagy import route csak akkor regisztrálható,
   ha a composition root production `SongRepository`-t szolgáltat, és a
   presentation/application határ concrete `FilePickerAdapter`-t kap explicit
   provider- vagy konstruktor-seamen keresztül.
2. A widget nem hívhat platform pickert közvetlenül, nem tarthat platform
   picker-objektumot state-ben, és productionben nem helyettesítheti fake-kel.
   A concrete adapter kizárólag a meglévő, újranyitható `ImportSourceFile`
   contractot adhatja át a controllernek.
3. A production megvalósítás megőrzi a controller lifecycle-garanciáit: route
   dispose cancelálja az operationt és lezárja a workspace-t; cancel vagy probe
   failure nem hozhat létre library rekordot.
4. Kötelező, commitolt review reportot igénylő prepared kör a report pontos
   útvonalát mind a human scope táblában, mind az `ai-router` metadata
   `allowed_paths` listájában feltünteti a model dispatch előtt.

## Elutasított alternatívák

- **Statikus import screen késznek nyilvánítása:** nem hajtja végre a picker →
  probe → preview → commit folyamatot.
- **Közvetlen widget-pluginhívás:** megsérti a data/platform határt és a fake
  adapteres tesztelhetőséget.
- **`InMemorySongRepository` vagy implicit fake productionben:** elveszíti az
  ADR 0090 szerinti restart-safe, fájl-alapú repository contractot.
- **Route regisztráció bootstrap wiring előtt:** feature-flag opt-in után a mért
  `StateError`-hoz vezet.

## Következmények

- E03-R15 eredeti allowlistjével a V2 route nem aktiválható biztonságosan. A
  scope-revízió explicit felveszi a picker-portot, manifesteket, composition
  rootot, célzott teszteket és a review artefaktumot; a metadata regresszió
  védi ezt a minimumot.
- A feature flag alapértéke OFF marad. Ez az ADR nem vezet be hálózati
  viselkedést; az import lokális marad, és az ADR 0091 limit-, cancellation- és
  privacy határai változatlanok.
