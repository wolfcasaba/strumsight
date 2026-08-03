# Guitar Pro feasibility fixtures

These are technical parser fixtures for E03-R13 only. They are not user
content and do not grant a right to distribute Guitar Pro songs.

| Fixture | Provenance | SHA-256 | Expected alphaTab probe values |
| --- | --- | --- | --- |
| `minimal_gp3.gp3` | New, one-track score authored for this repository and written with PyGuitarPro 0.11.0. | `53ee2cc024d46a8fb3c761f857f589eb3d0901468a323adea2e98247d59fb473` | title `StrumSight Minimal`; one track/measure/note; tuning `[64,59,55,50,45,40]`; string 6, fret 3; tempo 120; 4/4. |
| `minimal_gp5.gp5` | Same newly authored score, written as GP 5.1 with PyGuitarPro 0.11.0. | `140cccae4b4cb228ce262cbf76a94326b0dcabea9c9e98f9dfc83e3cdb8cd216` | Same as GP3. |
| `minimal_gpx.gpx` | `packages/alphatab/test-data/guitarpro6/notes.gpx` from alphaTab commit `a186437bb3263e5ae3f8fd373aef1fef5ebbc7e7`, retained under its MPL-2.0 licence. | `b437b7a2b3e212822acadd67877807baee48837ea76d9b737bfbf9f5db9c07fc` | one track/measure; 28 notes; tuning `[64,59,55,50,45,40]`; first note string 1, fret 1; tempo 120; 4/4. |

The GP3/GP5 source note is on the highest string (1) at fret 3. alphaTab's
score API reports it as string 6; the GPX fixture gives the converse case.
The spike preserves string/fret data, but a future adapter must make this
ordering translation explicit.

Reproduce the isolated package outside the production app:

```bash
cd tool/guitar_pro_feasibility
npm pack @coderline/alphatab@1.8.4
tar -xzf coderline-alphatab-1.8.4.tgz
dart pub get
ALPHATAB_MODULE_PATH="$PWD/package" dart test test/gp_spike_test.dart
ALPHATAB_MODULE_PATH="$PWD/package" dart run bin/run_spike.dart ../../test/fixtures/song_trainer/guitar_pro/minimal_gp3.gp3 ../../test/fixtures/song_trainer/guitar_pro/minimal_gp5.gp5 ../../test/fixtures/song_trainer/guitar_pro/minimal_gpx.gpx
```

alphaTab is an MPL-2.0 candidate runtime, not a production dependency. The
current R13 decision is still conversion workflow C; see
[`docs/adr/0122-guitar-pro-import-strategy.md`](../../../../docs/adr/0122-guitar-pro-import-strategy.md).
