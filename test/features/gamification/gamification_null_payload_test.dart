import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/data/gamification_repository.dart';
import 'package:strumsight/features/gamification/data/gamification_storage_schema.dart';
import 'package:strumsight/features/gamification/data/migration/gamification_migrator.dart';
import 'package:strumsight/features/gamification/providers/gamification_providers.dart';

// Audit H21 — `read.value!` on a nullable payload. `GamificationRead
// .available` takes a `T?`, so an "available" read can legitimately carry
// null; the `!` turned that into a null-check crash on the hub, the inbox and
// the legacy migration resume. Every site now reads the value ONCE into a
// local and states what happens when it is absent.

/// A repository whose reads are `available` but carry no payload.
final class _NullPayloadRepository implements GamificationRepository {
  @override
  GamificationRead<GamificationProfileSnapshot> readProfileSnapshot() =>
      const GamificationRead<GamificationProfileSnapshot>.available(null);

  @override
  Future<void> replaceProfileSnapshot(
    GamificationProfileSnapshot snapshot,
  ) async {}

  @override
  Stream<GamificationRead<GamificationProfileSnapshot>>
  watchProfileSnapshots() =>
      const Stream<GamificationRead<GamificationProfileSnapshot>>.empty();

  @override
  GamificationRead<GamificationCatalogVersion> readCatalogVersion() =>
      const GamificationRead<GamificationCatalogVersion>.missing();

  @override
  Future<void> replaceCatalogVersion(
    GamificationCatalogVersion version,
  ) async {}

  @override
  GamificationRead<List<GamificationInboxItem>> readInbox() =>
      const GamificationRead<List<GamificationInboxItem>>.available(null);

  @override
  Future<GamificationInboxWriteReport> replaceInbox(
    List<GamificationInboxItem> items,
  ) async => const GamificationInboxWriteReport(trimmedCount: 0);

  @override
  GamificationRead<GamificationMigrationState> readMigrationState() =>
      const GamificationRead<GamificationMigrationState>.available(null);

  @override
  Future<void> replaceMigrationState(GamificationMigrationState state) async {}

  @override
  Future<void> dispose() async {}
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      gamificationRepositoryProvider.overrideWithValue(
        _NullPayloadRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('an available-but-empty profile read reads as zero XP', () {
    final profile = _container().read(gamificationProfileProvider);

    expect(profile.totalXp, 0);
  });

  test('an available-but-empty inbox read reads as an empty inbox', () {
    final inbox = _container().read(gamificationInboxProvider);

    expect(inbox, isEmpty);
  });

  test('an available-but-empty checkpoint fails as a stated error', () async {
    final migrator = GamificationMigrator(
      gamificationRepository: _NullPayloadRepository(),
    );

    // A null-check error would be an opaque crash; the migrator states that
    // the checkpoint is unusable instead.
    await expectLater(migrator.migrate(const []), throwsStateError);
  });
}
