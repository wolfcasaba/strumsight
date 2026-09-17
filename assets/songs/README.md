# Seed practice songs (`assets/songs/`)

Three **project-original** practice songs shipped with the app so the Song
Trainer library is never empty on a fresh install. They are bundled as
`SongDocument` JSON — exactly the map `SongDocumentCodec.decodeFromMap`
consumes — and installed once at bootstrap by
`lib/features/song_trainer/application/seed/song_seed_installer.dart`.

| File | Title | Form |
|---|---|---|
| `seed-harom-akkord-g-c-d.song.json` | Három akkord (G–C–D) | 8 bars, 4/4, 100 BPM |
| `seed-blues-shuffle-a.song.json` | Blues shuffle A-ban (12 ütem) | 12 bars, 4/4, 80 BPM |
| `seed-keringo-g.song.json` | Keringő G-ben | 8 bars, 3/4, 120 BPM |

## Provenance and licence

Every file was authored for this repository from scratch: the chord
progressions are the generic teaching forms (I–IV–V, the 12-bar blues,
a three-quarter waltz) with no melody, no lyrics and no recording. There is
**no third-party musical content** in this directory, so nothing here is
covered by a third-party licence. The same statement is carried inside each
document in `metadata.copyright` and `metadata.notes`, so it survives an
export/import round trip.

`source.sha256` is a provenance token, not a file hash: it is the SHA-256 of
the document's own `id`, because the field is required to be 64 hex
characters and these documents were never imported from a source file.

The byte-level manifest lives in `tool/ci/check_song_fixture_licenses.dart`
(the `assets/songs` block) and is enforced on every CI run — editing a seed
song without updating its SHA-256 there turns the gate red.
