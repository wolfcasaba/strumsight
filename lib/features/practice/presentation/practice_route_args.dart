/// Safe resolution of the `/practice/setup?id=<definitionId>` query
/// argument (ADR 0078 §3, E02-R12).
///
/// The Setup screen needs a `definitionId` to look the definition up in the
/// catalog repository. The query argument is an opaque string the router
/// hands us; the resolver below separates the three observable states
/// (missing, blank, present) without ever throwing — the screen renders a
/// localized error state for the failure cases and never blows up.
library;

import 'package:strumsight/l10n/app_localizations.dart';

/// What the Setup route was asked to open.
enum PracticeSetupRequest {
  /// The query was present and non-blank — the screen tries to look it up.
  hasId,

  /// The `?id=` key was missing from the URI entirely.
  missing,

  /// The `?id=` key was present but its value was empty / whitespace.
  blank,
}

/// The arguments extracted from a `/practice/setup` navigation.
final class PracticeSetupArgs {
  const PracticeSetupArgs({required this.request, this.definitionId})
    : assert(
        (request == PracticeSetupRequest.hasId && definitionId != null) ||
            (request != PracticeSetupRequest.hasId && definitionId == null),
        'hasId must carry a non-null definitionId; the other states carry null',
      );

  /// The structural shape of the request — drives the localized error.
  final PracticeSetupRequest request;

  /// The opaque id, only present when [request] is [PracticeSetupRequest.hasId].
  final String? definitionId;

  /// The message the Setup screen should show when no id is available.
  String localizeMissing(AppLocalizations l10n) =>
      l10n.practiceErrorDefinitionNotFound;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSetupArgs &&
          other.request == request &&
          other.definitionId == definitionId;

  @override
  int get hashCode => Object.hash(request, definitionId);
}

/// Parses the raw `id` query parameter into a [PracticeSetupArgs]. Accepts
/// the `null` value as "no key" and an empty / whitespace string as "blank";
/// any other string is treated as a present id and forwarded as-is. The
/// catalog repository ([`practiceCatalogRepositoryProvider.byId`]) is the
/// single source of truth for whether the id actually resolves — this
/// function only classifies the SHAPE of the request, never the catalog.
PracticeSetupArgs parsePracticeSetupArgs(String? rawId) {
  if (rawId == null) {
    return const PracticeSetupArgs(request: PracticeSetupRequest.missing);
  }
  if (rawId.trim().isEmpty) {
    return const PracticeSetupArgs(request: PracticeSetupRequest.blank);
  }
  return PracticeSetupArgs(
    request: PracticeSetupRequest.hasId,
    definitionId: rawId,
  );
}
