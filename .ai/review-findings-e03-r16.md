# E03-R16 independent review findings — CHANGES REQUESTED

Review baseline: `c037993a36bee62730cbc8c28f2c18fea27e37de`.
Isolated reviewer gate is green, but it does not establish the following
required user-visible behavior.

## F1 — MAJOR: backing attachment is unreachable from the editor UI

Evidence: `presentation/widgets/backing_asset_editor.dart` exposes only an
`onDetach` callback and renders no attach control. `song_editor_screen.dart`
passes only `hasBacking` and `onDetach`; it never invokes
`SongEditorController.attachBacking`, despite the controller implementation.
This violates brief §3 / §6 “backing attach/detach” and ADR 0124 decision 4.

Required repair: provide an editor-local, testable attach interaction that
creates a `SongAssetWriteRequest` and calls the controller, while preserving
the existing no-delete detach semantics. Add widget/controller coverage for a
successful attachment as well as the existing failed-copy case.

## F2 — MAJOR: required tempo/meter editing is unreachable and event edits are hard-coded

Evidence: `song_editor_screen.dart` renders `SongEventEditor` with fixed
`measureIndex: 0`, chord `C`, and note 60. Neither it nor any permitted widget
renders controls wired to `SongEditorController.setTempo` or `setMeter`; the
existing widgets do not expose those callbacks. Thus required brief §1/§6
meter/tempo marker editing and meaningful chord/strum/basic-note editing are
not usable through the route.

Required repair: expose localized, testable UI controls that call the existing
controller APIs with user-selected inputs (including selected measure), and
add widget tests that prove tempo/meter and at least two chord events per
measure reach the draft.

## F3 — MAJOR: create-new V2 document path is unreachable

Evidence: `SongEditorController.startNew` exists but has no provider/route/UI
consumer. `SongLibraryScreen` offers only import and existing-summary tap;
`SongEditorScreen` requires an existing `songId` and always calls `load`.
This violates the brief §6 “Create/edit”.

Required repair: add a canonical, flag-gated Library entry for new V2 document
creation and a route/controller flow that calls `startNew`, then prove the
first save calls `SongRepository.create` and the entry route remains canonical.

## Verified invariant

Disposable mutation: inserted `return true;` at the top of
`mayLeaveEditor` in the isolated clone. `flutter test
test/app/routing/route_guards_test.dart` then failed at
`route_guards_test.dart:79` (`Expected false, Actual true`). The mutation was
reverted; the unmodified isolated full local gate was green.
