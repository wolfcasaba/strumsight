# ADR 0123 — Song Trainer V2 presentation activation boundary

**Status:** accepted for the E03-R15 pre-flight (2026-08-03).
Builds on [ADR 0090](0090-song-storage-files-and-assets.md),
[ADR 0091](0091-song-import-security-boundary.md), and
[ADR 0119](0119-song-import-application-orchestration.md).

## Context

The existing import application controller deliberately keeps source files and
picker objects out of state. It emits `RequestFilePickerEffect` and accepts an
`ImportSourceFile` only through `selectSource`. The only picker type is the
`FilePickerAdapter` interface; no production adapter is currently registered.

Likewise, `songRepositoryProvider` is a deliberate bootstrap seam that throws
unless the app composition root supplies a production repository. The current
application `ProviderScope` does not supply it. Registering a Song Trainer V2
route that reads the import or library provider would therefore expose an
interaction that either cannot obtain a source file or fails before it can use
the file-backed repository.

## Decision

1. An interactive Song Trainer V2 library or import route may be registered
   only when the composition root supplies a production `SongRepository` and
   the presentation/application boundary receives a concrete
   `FilePickerAdapter` through an explicit provider or constructor seam.
2. A widget must not invoke a platform picker directly, retain a platform
   picker object in state, or substitute a test fake in production. The picker
   returns only the existing reopenable `ImportSourceFile` contract to the
   application controller.
3. The production implementation must preserve the existing controller
   lifecycle guarantees: route disposal cancels the operation and closes its
   workspace; cancellation or probe failure creates no library record.
4. Every prepared round that requires a mandatory committed review report must
   list that exact report path in both its human scope table and its router
   metadata before model dispatch.

## Alternatives

- **Render a static import screen and call it complete:** rejected. It cannot
  execute the required picker/probe/preview/import flow.
- **Have the widget import a picker plugin directly:** rejected. It violates
  the data/platform boundary and prevents a fake adapter from proving the
  interaction.
- **Use `InMemorySongRepository` or an implicit fake in production:** rejected.
  It loses the file-based, restart-safe repository contract from ADR 0090.
- **Register the route before composition-root wiring exists:** rejected. It
  makes a feature-flag opt-in lead to the measured provider `StateError`.

## Consequences

- E03-R15 cannot safely activate its V2 route under its original allowlist.
  A follow-up pre-flight must explicitly authorize the concrete picker and
  composition-root owners, their focused tests, and the mandatory review
  artifact; it must preserve the default-OFF feature flag.
- This ADR does not add a picker dependency, production route, or new network
  behavior. Import remains local and subject to ADR 0091's limits and
  cancellation boundary.
