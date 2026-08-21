# UI baseline

This directory records the UI state measured before the Chapter 13 migration.
It is a regression baseline, not a design approval and not the Chapter 13
target design.

## Screenshot corpus

The corpus contains exactly the seven compact-portrait main states required by
E13-R01. Each image is a raster capture of a production screen widget, rather
than a hand-drawn placeholder.

Capture recipe:

1. Run `flutter test --update-goldens --dart-define=CAPTURE_UI_BASELINE=true test/ui/ui_baseline_screenshot_test.dart`.
2. The capture test sets a 390×844 logical-pixel viewport with device-pixel
   ratio 1, uses `StrumSightApp` for the five shell destinations, and renders
   the production `TunerScreen` and `OnboardingScreen` directly.
3. Before mounting a screen, the capture test loads the existing Poppins
   (Regular through ExtraBold), Montserrat and Material Icons bundle assets
   with `FontLoader`. It also derives the active Flutter SDK root from
   `Platform.resolvedExecutable` and loads its licensed Roboto Regular, Medium
   and Bold material fonts. This makes the raster use the production
   typography and icons instead of the Ahem test-font fallback or square icon
   placeholders; it adds no asset or pubspec change.
4. It replaces microphone engines and preference storage with the existing
   in-memory test fakes. Live receives a deterministic C/downstroke frame and
   Tuner receives a deterministic in-tune A reading; no network or platform
   microphone is used.
5. Open all seven generated PNGs before review. The ordinary corpus test runs
   `decodeImageFromList` in a plain asynchronous test with a 10-second timeout,
   so it verifies exact names, decodability, non-empty dimensions, and portrait
   shape without waiting in the widget test's fake-async zone. It is not a
   visual design assertion.

The standard validation command is:

```bash
tools/round-gate.sh test/ui/ui_inventory_test.dart test/ui/ui_baseline_screenshot_test.dart
```

## Inventory boundaries

`tool/ui_inventory.dart` defines a production screen as a
`lib/features/**/*_screen.dart` file. Test and fixture trees do not qualify.
The inventory and all documents below record the source tree at E13-R01; later
rounds must deliberately update them rather than treating this baseline as a
target design.
