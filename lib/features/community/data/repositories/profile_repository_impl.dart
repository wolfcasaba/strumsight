/// Dio-backed implementation of [CommunityProfileRepository] (E09-R06,
/// ADR 0400 §5).
///
/// The repository uses the **shared** ``accountApiClientProvider`` —
/// the same ``ApiClient`` the auth + settings layers ride on, so the
/// JWT and base-URL wiring stays in one place. The client is
/// ``null`` when the account layer is disabled for the build; the
/// repository detects that and returns a ``ConfigurationFailure``
/// for every call (the same shape ``DisabledAuthRepository`` and
/// ``DisabledSettingsRepository`` use, so the controller does not
/// have to special-case the disabled build).
///
/// The 409 (``handle_taken`` / ``profile_exists``) is translated
/// to ``FailureCode.communityConflict`` at the data layer; the
/// controller inspects the code and, before submitting, checks
/// ``fetchMyProfile()`` so a 409 from the create path is unambiguous
/// — if the controller already saw ``null`` from
/// ``fetchMyProfile``, a 409 from the create call MUST be
/// ``handle_taken`` (the only remaining conflict source on the
/// create path). The two domain exceptions
/// (``ProfileAlreadyExistsException`` / ``HandleTakenException``)
/// are part of the [CommunityProfileRepository] interface for
/// future callers (CLI, scripts) that do not parse the failure
/// code; the current data layer returns them through the
/// ``Failure.code`` channel only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../features/auth/public.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/repositories/community_profile_repository.dart';
import '../../domain/value_objects/community_handle.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../../domain/value_objects/audience.dart';
import '../dto/profile_dto.dart';

/// The single ``communityAccountClient`` provider. Built lazily so
/// the account-disabled build never constructs the Dio client at
/// all (the ``accountApiClientProvider`` is the same ``ApiClient``
/// the auth + settings layers use; reusing it is the only
/// dependency surface this repository contributes to).
final communityApiClientProvider = Provider<ApiClient?>(
  (ref) => ref.watch(accountApiClientProvider),
);

/// Disabled-mode fallback: returns ``ConfigurationFailure`` for every
/// call. Mirrors the pattern of ``DisabledAuthRepository`` /
/// ``DisabledSettingsRepository`` so the controller code path is
/// uniform across the three repository flavors.
final class DisabledCommunityProfileRepository
    implements CommunityProfileRepository {
  const DisabledCommunityProfileRepository();

  static const Failure<Never> _disabled = Failure(ConfigurationFailure());

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    // The Kör 5 contract returns ``null`` for "no profile yet"; the
    // disabled build also has no profile — the controller sees the
    // same null and treats it as "go to onboarding" (which itself
    // shows the disabled gate, so the user is never stuck).
    return null;
  }

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) async =>
      throw _disabled.error;

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) async =>
      throw _disabled.error;

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) async => throw _disabled.error;

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) async => _disabled;

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) async => _disabled;
}

class HttpCommunityProfileRepository implements CommunityProfileRepository {
  HttpCommunityProfileRepository(this._client);

  final ApiClient _client;

  @override
  Future<CommunityProfile?> fetchMyProfile() async {
    // The Kör 5 contract: ``GET /community/profiles/me`` returns the
    // caller's own profile, or 404 when none exists. The Kör 6
    // endpoints (POST/PUT) read the same row, so the gate's
    // "profile-missing" state maps to a 404 here. The repository
    // maps 404 -> null silently so the controller can branch on
    // the value alone.
    final result = await _client.getJson<CommunityProfileDto?>(
      '/community/profiles/me',
      decode: (json) => CommunityProfileDto.fromJson(json),
      conflictCode: FailureCode.validationInvalidInput,
    );
    return switch (result) {
      Success(:final value) => _dtoToDomain(value),
      Failure(:final error) when _isNotFound(error) => null,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      // Out of scope for E09-R06 — Kör 5 contract, Kör 7+
      // implementation. Throw an explicit unsupported so the
      // ``Future<CommunityProfile>`` (non-nullable) return type is
      // honest: the call site is wrong, not the data.
      throw UnsupportedError(
        'CommunityProfileRepository.fetchById is not yet implemented',
      );

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      // Same as above — Kör 5 contract, Kör 7+ implementation.
      throw UnsupportedError(
        'CommunityProfileRepository.fetchByHandle is not yet implemented',
      );

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) async {
    // E09-R09 — the Kör 9 profile-search endpoint. The path is
    // built manually because ``ApiClient.getJson`` does not
    // accept a query-parameter map (its four endpoints all carry
    // no params — same constraint the Kör 7 unfollow DELETE
    // runs into, ADR 0401 §1). Encoding both ``q`` and the
    // cursor here keeps the api_client.dart surface untouched
    // and the wire shape aligned with the backend
    // ``GET /community/profiles/search`` router.
    final queryValue = Uri.encodeQueryComponent(query);
    final params = <String>[if (queryValue.isNotEmpty) 'q=$queryValue'];
    final cursorValue = _cursorQueryValue(cursor);
    if (cursorValue != null) {
      params.add('cursor=${Uri.encodeQueryComponent(cursorValue)}');
    }
    params.add('limit=50');
    final path = '/community/profiles/search?${params.join('&')}';
    final result = await _client.getJson<dynamic>(path, decode: _decodePage);
    return switch (result) {
      Success(:final value) => value as CommunityPage<CommunityProfile>,
      Failure(:final error) => throw error,
    };
  }

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) async {
    final payload = communityProfileCreatePayload(
      handle: handle,
      displayName: displayName,
      visibility: visibility,
      audienceDefault: audienceDefault,
    );
    final result = await _client.postJson<CommunityProfileDto>(
      '/community/profiles/me',
      data: payload,
      decode: CommunityProfileDto.fromJson,
      // The 409 detail is ``profile_exists`` / ``handle_taken`` —
      // both surface as the same ``ValidationFailure`` here. The
      // controller disambiguates by reading the failure code and
      // the pre-submit ``fetchMyProfile()`` result.
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => Success(
        _dtoToDomain(
          value,
          handle: handle,
          displayName: displayName,
          visibility: visibility,
        ),
      ),
      Failure(:final error) => Failure(error),
    };
  }

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) async {
    final payload = communityProfileUpdatePayload(displayName: displayName);
    final result = await _client.putJson<CommunityProfileDto>(
      '/community/profiles/me',
      data: payload,
      decode: CommunityProfileDto.fromJson,
      conflictCode: FailureCode.communityConflict,
    );
    return switch (result) {
      Success(:final value) => Success(
        _dtoToDomain(
          value,
          // The update response carries the new display name; the
          // handle + visibility come from the server's stored
          // values, but the controller already knows them from the
          // ``fetchMyProfile()`` call that bootstrapped the edit
          // form. The repository passes the bare DTO up; the
          // controller stitches the rest together.
          displayName: displayName,
        ),
      ),
      Failure(:final error) => Failure(error),
    };
  }

  CommunityProfile _dtoToDomain(
    CommunityProfileDto? dto, {
    CommunityHandle? handle,
    String? displayName,
    ProfileVisibility? visibility,
  }) {
    if (dto == null) {
      throw const FormatException('community profile DTO was null');
    }
    final handleValue = handle?.value ?? dto.handle;
    if (handleValue == null) {
      throw const FormatException(
        'community profile wire: missing handle; the controller must '
        'pass the locally-known handle to the DTO->domain converter.',
      );
    }
    final displayValue = displayName ?? dto.displayName;
    if (displayValue == null) {
      throw const FormatException(
        'community profile wire: missing display_name; the controller '
        'must pass the locally-known display name to the DTO->domain '
        'converter.',
      );
    }
    final visibilityValue =
        visibility ??
        profileVisibilityFromWire(null) ??
        ProfileVisibility.private;
    return dto.toDomain(
      handle: CommunityHandle(handleValue),
      displayName: displayValue,
      visibility: visibilityValue,
    );
  }

  static bool _isNotFound(AppFailure error) {
    if (error is NetworkFailure) {
      return error.code == FailureCode.networkBadResponse;
    }
    return false;
  }

  /// Decode the Kör 9 ``GET /community/profiles/search`` envelope.
  ///
  /// The wire shape is the same shape the Kör 7
  /// ``HttpSocialGraphRepository._decodePage`` consumes
  /// (``{public_ids, next_cursor}``); the search endpoint does
  /// NOT enrich the response with full profile rows (the brief
  /// §A2 stays a thin search index — the controller
  /// follow-up-fetches each entry through the canonical
  /// ``fetchById`` path). Mirrors the Kör 7 placeholder
  /// factory so the page envelope satisfies
  /// ``CommunityPage<CommunityProfile>`` without forcing the
  /// data layer to round-trip N rows on a 50-row page.
  CommunityPage<CommunityProfile> _decodePage(Map<String, Object?> json) {
    final rawIds = json['public_ids'];
    if (rawIds is! List) {
      throw const FormatException(
        'community search wire: public_ids must be a list',
      );
    }
    final publicIds = rawIds
        .whereType<String>()
        .map(PublicUserId.new)
        .toList(growable: false);
    final nextCursor = json['next_cursor'];
    final cursorPage = nextCursor == null
        ? (publicIds.isEmpty
              ? const CursorPage.haltedAfterRequest()
              : const CursorPage.initial())
        : CursorPage.continued(nextCursor as String);
    final items = publicIds.map(_placeholderProfile).toList(growable: false);
    return CommunityPage<CommunityProfile>(items: items, cursor: cursorPage);
  }

  String? _cursorQueryValue(Object cursor) {
    if (cursor == const CursorPage.initial()) return null;
    if (cursor is CursorPage) {
      return cursor.cursor;
    }
    throw ArgumentError.value(
      cursor,
      'cursor',
      'cursor must be a CursorPage (initial / continued / haltedAfterRequest)',
    );
  }
}

/// The Community profile repository wired against the live
/// ``accountApiClientProvider`` — null on a build where the account
/// layer is disabled, the http impl otherwise.
final communityProfileRepositoryProvider = Provider<CommunityProfileRepository>(
  (ref) {
    final client = ref.watch(communityApiClientProvider);
    if (client == null) return const DisabledCommunityProfileRepository();
    return HttpCommunityProfileRepository(client);
  },
);

/// Build a placeholder [CommunityProfile] for a search hit.
///
/// The Kör 9 wire shape carries only public_ids; the canonical
/// full profile arrives through ``fetchById``. The placeholder
/// mirrors the Kör 7 ``HttpSocialGraphRepository._placeholderProfile``
/// contract — a non-empty handle + display name so the page
/// boundary satisfies ``CommunityPage<CommunityProfile>`` without
/// throwing ``ArgumentError`` on construction.
CommunityProfile _placeholderProfile(PublicUserId userId) {
  return CommunityProfile(
    userId: userId,
    handle: CommunityHandle('placeholder-x1'),
    displayName: 'placeholder',
    visibility: ProfileVisibility.public,
    avatarUrl: null,
    bio: null,
    skillInterests: const <String>[],
    badges: const <String>[],
    relationship: CommunityRelationshipToViewer.notRelated,
    createdAt: DateTime.utc(2026),
  );
}
