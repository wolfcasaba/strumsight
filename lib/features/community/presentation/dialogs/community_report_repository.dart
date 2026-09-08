/// The production [ReportRepository] — the wiring M10 was missing.
///
/// The report sheet (`report_content_sheet.dart`) shipped complete in
/// E09-R26 together with the backend's `POST /community/reports` router,
/// and then had ZERO `lib/**` callers: the flow existed but nothing could
/// reach it. This file is the seam that closes that — the host screens
/// (the following feed and the comment thread) build one of these and
/// hand it to `showReportContentSheet`.
///
/// **Why the concrete post repository is type-checked here.** The submit
/// rides `HttpCommunityPostRepository.submitReport`, which lives OUTSIDE
/// the `CommunityPostRepository` contract on purpose: that contract is
/// implemented by a dozen test fakes, two of them inside pixel-pinned
/// golden files this round may not touch, so a new abstract member would
/// break the whole golden band. The account-disabled build resolves the
/// provider to `DisabledCommunityPostRepository` instead, and this class
/// then fails with the same [ConfigurationFailure] every other
/// disabled-mode community call raises — the sheet renders its localized
/// error rather than pretending the report went anywhere.
///
/// **Why `hideFromFeed` is a host-supplied callback.** "Hide from feed"
/// means different things to the two hosts (drop the post card; drop the
/// comment row), and a repository-level no-op for whichever host did not
/// match would be exactly the silent-no-op failure class this codebase
/// keeps paying for. The host passes the one that is true for it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../data/repositories/post_repository_impl.dart'
    show HttpCommunityPostRepository, communityPostRepositoryProvider;
import '../../data/repositories/relationship_repository_impl.dart'
    show socialGraphRepositoryProvider;
import '../../domain/repositories/post_repository.dart';
import '../../domain/repositories/social_graph_repository.dart';
import '../../domain/value_objects/public_user_id.dart';
import 'report_content_sheet.dart';

/// What the host does when the reporter picks "Hide from feed".
typedef CommunityHideTarget = Future<void> Function(String targetId);

/// The wired [ReportRepository].
final class CommunityReportRepository implements ReportRepository {
  const CommunityReportRepository({
    required this._postRepository,
    required this._socialGraph,
    required this._onHide,
  });

  /// Build one from a widget's `ref`. The two repository providers are
  /// the same ones every other community surface reads, so a test
  /// overrides them exactly as it already does for the feed and the
  /// comment thread.
  factory CommunityReportRepository.fromRef(
    WidgetRef ref, {
    required CommunityHideTarget onHide,
  }) => CommunityReportRepository(
    postRepository: ref.read(communityPostRepositoryProvider),
    socialGraph: ref.read(socialGraphRepositoryProvider),
    onHide: onHide,
  );

  final CommunityPostRepository _postRepository;
  final SocialGraphRepository _socialGraph;
  final CommunityHideTarget _onHide;

  @override
  Future<ReportSubmissionOutcome> submit({
    required String targetType,
    required String targetId,
    required ReportCategory category,
    required String idempotencyKey,
  }) async {
    final repository = _postRepository;
    if (repository is! HttpCommunityPostRepository) {
      // Account layer off: there is no client to send with. Failing
      // loudly is the honest branch — a swallowed submit would show the
      // reporter the thanks view for a report that never left the phone.
      throw const ConfigurationFailure();
    }
    final receipt = await repository.submitReport(
      targetType: targetType,
      targetId: targetId,
      category: category.wireValue,
      idempotencyKey: idempotencyKey,
    );
    return ReportSubmissionOutcome(
      reportPublicId: receipt.reportPublicId,
      deduplicated: receipt.deduplicated,
      action: null,
    );
  }

  @override
  Future<void> hideFromFeed({required String targetId}) => _onHide(targetId);

  @override
  Future<void> muteAuthor({required String authorPublicId}) =>
      _socialGraph.mute(
        target: PublicUserId(authorPublicId),
        idempotencyKey: _idempotencyKey('mute'),
      );

  @override
  Future<void> blockAuthor({required String authorPublicId}) =>
      _socialGraph.block(
        target: PublicUserId(authorPublicId),
        idempotencyKey: _idempotencyKey('block'),
      );

  static String _idempotencyKey(String verb) =>
      'r33-$verb-${DateTime.now().microsecondsSinceEpoch}';
}
