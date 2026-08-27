/// Edit-profile screen — the create / edit form (E09-R06, ADR 0400
/// §5, brief §3.5).
///
/// One screen, two modes:
///
/// * **Create** — the user has no profile yet. The handle field is
///   shown (and required); the privacy step is shown as the last
///   step; the submit button creates the profile and pops back to
///   the gate, which then transitions to ``ready``.
/// * **Edit** — the user already has a profile. The handle field
///   is hidden (the brief §5.3 / ADR 0400 §3 contract: a handle
///   change endpoint is a future round's job); the privacy step
///   is also hidden (privacy is owned by the Kör 4 ``privacy.py``
///   router, not wired into the module in this round); only the
///   display name is editable.
///
/// The screen holds the **form draft** in its own state — this is
/// the A3 invariant: a network failure does NOT clear the field.
/// The controller only sees the final payload on submit; it does
/// NOT mirror the draft.
///
/// The **submit debounce** is a double-defense (the brief A5 cell):
///
/// 1. The submit button is ``null`` (disabled) while
///    ``isSubmitting`` is true. The button's ``onPressed`` is
///    ignored in that state, so a fast double-tap cannot fire two
///    submits.
/// 2. The controller's ``isSubmitting`` guard (in
///    ``profile_controller.dart``) returns a ``busy`` result if a
///    second call lands, so even a programmatic double-fire would
///    collapse to a single round-trip.
///
/// The two real-violation probes (A5 in §6.1) take the debounce
/// out and watch the test go red, then put it back.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/profile_controller.dart';
import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/value_objects/community_handle.dart';
import '../widgets/community_theme_scope.dart';

enum EditProfileMode { create, edit }

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.mode,
    required this.initialProfile,
  });

  final EditProfileMode mode;
  final CommunityProfile? initialProfile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _handleController;
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final List<String> _interestTags;
  late ProfileVisibility _visibility;
  late CommunityAudience _audienceDefault;
  String? _handleError;
  String? _displayNameError;
  String? _topError;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialProfile;
    _handleController = TextEditingController(
      text: initial?.handle.value ?? '',
    );
    _displayNameController = TextEditingController(
      text: initial?.displayName ?? '',
    );
    _bioController = TextEditingController();
    _interestTags = <String>[];
    _visibility = initial?.visibility ?? ProfileVisibility.followers;
    _audienceDefault = CommunityAudience.followers;
  }

  @override
  void dispose() {
    _disposed = true;
    _handleController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final isCreate = widget.mode == EditProfileMode.create;
    final state = ref.watch(communityProfileControllerProvider).value;
    final isSubmitting = state?.isSubmitting ?? false;

    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            isCreate
                ? localizations.communityEditCreateTitle
                : localizations.communityEditEditTitle,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isCreate) ..._buildHandleSection(localizations),
                ..._buildDisplayNameSection(localizations),
                ..._buildBioSection(localizations),
                ..._buildInterestSection(localizations),
                ..._buildBadgesSection(localizations),
                if (isCreate) ..._buildPrivacySection(localizations),
                if (_topError != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: _topError!),
                ],
                const SizedBox(height: 24),
                _SubmitButton(
                  isSubmitting: isSubmitting,
                  isCreate: isCreate,
                  localizations: localizations,
                  onPressed: isSubmitting ? null : _onSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHandleSection(AppLocalizations l) {
    return [
      TextField(
        controller: _handleController,
        enabled: true,
        decoration: InputDecoration(
          labelText: l.communityEditHandleLabel,
          helperText: l.communityEditHandleHelper,
          errorText: _handleError,
        ),
        onChanged: (_) {
          if (_handleError != null) {
            setState(() => _handleError = null);
          }
        },
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildDisplayNameSection(AppLocalizations l) {
    return [
      TextField(
        controller: _displayNameController,
        decoration: InputDecoration(
          labelText: l.communityEditDisplayNameLabel,
          helperText: l.communityEditDisplayNameHelper,
          errorText: _displayNameError,
        ),
        onChanged: (_) {
          if (_displayNameError != null) {
            setState(() => _displayNameError = null);
          }
        },
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildBioSection(AppLocalizations l) {
    return [
      TextField(
        controller: _bioController,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: l.communityEditBioLabel,
          helperText: l.communityEditBioHelper,
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildInterestSection(AppLocalizations l) {
    return [
      Text(
        l.communityEditInterestLabel,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      Text(
        l.communityEditInterestHelper,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in _interestTags)
            InputChip(
              label: Text(tag),
              onDeleted: () {
                setState(() => _interestTags.remove(tag));
              },
            ),
          ActionChip(
            label: Text(l.communityEditAddInterestCta),
            onPressed: () => _onAddTag(l),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildBadgesSection(AppLocalizations l) {
    return [
      Text(
        l.communityEditBadgesLabel,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 4),
      Text(
        l.communityEditBadgesBody,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildPrivacySection(AppLocalizations l) {
    return [
      Text(
        l.communityEditPrivacyTitle,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      Text(
        l.communityEditPrivacyBody,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      RadioGroup<ProfileVisibility>(
        groupValue: _visibility,
        onChanged: (value) {
          if (value == null) return;
          _onVisibilityChanged(l, value);
        },
        child: Column(
          children: [
            for (final option in ProfileVisibility.values)
              RadioListTile<ProfileVisibility>(
                title: Text(_visibilityLabel(l, option)),
                subtitle: Text(_visibilityBody(l, option)),
                value: option,
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        l.communityEditPrivacyAudienceLabel,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      RadioGroup<CommunityAudience>(
        groupValue: _audienceDefault,
        onChanged: (value) {
          if (value == null) return;
          _onAudienceDefaultChanged(l, value);
        },
        child: Column(
          children: [
            for (final option in CommunityAudience.values)
              RadioListTile<CommunityAudience>(
                title: Text(_audienceLabel(l, option)),
                value: option,
              ),
          ],
        ),
      ),
    ];
  }

  String _visibilityLabel(AppLocalizations l, ProfileVisibility v) {
    return switch (v) {
      ProfileVisibility.public => l.communityEditPrivacyOptionPublic,
      ProfileVisibility.followers => l.communityEditPrivacyOptionFollowers,
      ProfileVisibility.private => l.communityEditPrivacyOptionPrivate,
    };
  }

  String _visibilityBody(AppLocalizations l, ProfileVisibility v) {
    return switch (v) {
      ProfileVisibility.public => l.communityEditPrivacyOptionPublicBody,
      ProfileVisibility.followers => l.communityEditPrivacyOptionFollowersBody,
      ProfileVisibility.private => l.communityEditPrivacyOptionPrivateBody,
    };
  }

  String _audienceLabel(AppLocalizations l, CommunityAudience a) =>
      _visibilityLabel(l, _audienceToVisibility(a));

  ProfileVisibility _audienceToVisibility(CommunityAudience a) {
    return switch (a) {
      CommunityAudience.public => ProfileVisibility.public,
      CommunityAudience.followers => ProfileVisibility.followers,
      CommunityAudience.private => ProfileVisibility.private,
    };
  }

  /// ADR 0291 §2 — the default audience/visibility is never public without
  /// an explicit, irreversibility-naming confirmation (brief §6.1, the
  /// "above threshold" cell). A `followers`/`private` pick applies
  /// immediately; a `public` pick is held behind [showCommunityConfirmationSheet]
  /// and only committed if the user confirms.
  void _onVisibilityChanged(AppLocalizations l, ProfileVisibility value) {
    if (value != ProfileVisibility.public) {
      setState(() => _visibility = value);
      return;
    }
    showCommunityConfirmationSheet(
      context,
      title: l.communityPublicConfirmTitle,
      consequence: l.communityPublicConfirmBody,
      confirmLabel: l.communityPublicConfirmCta,
      cancelLabel: l.communityPublicConfirmCancel,
      onConfirm: () {
        if (!mounted) return;
        setState(() => _visibility = value);
      },
    );
  }

  /// Same guard as [_onVisibilityChanged], for the per-post default
  /// audience selector.
  void _onAudienceDefaultChanged(AppLocalizations l, CommunityAudience value) {
    if (value != CommunityAudience.public) {
      setState(() => _audienceDefault = value);
      return;
    }
    showCommunityConfirmationSheet(
      context,
      title: l.communityPublicConfirmTitle,
      consequence: l.communityPublicConfirmBody,
      confirmLabel: l.communityPublicConfirmCta,
      cancelLabel: l.communityPublicConfirmCancel,
      onConfirm: () {
        if (!mounted) return;
        setState(() => _audienceDefault = value);
      },
    );
  }

  Future<void> _onAddTag(AppLocalizations l) async {
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(l.communityEditAddInterestCta),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (tag == null || tag.isEmpty) return;
    if (_interestTags.length >= 16) return;
    if (_interestTags.contains(tag)) return;
    setState(() => _interestTags.add(tag));
  }

  String? _validateHandle(AppLocalizations l) {
    final raw = _handleController.text.trim();
    if (raw.isEmpty) return l.communityEditHandleRequired;
    if (raw.length < 3) return l.communityEditHandleTooShort;
    if (raw.length > 24) return l.communityEditHandleTooLong;
    final normalized = CommunityHandle.normalizeForBackend(raw);
    final re = RegExp(r'^[\w][\w\-]{1,22}[\w]$|^[\w]$');
    if (!re.hasMatch(normalized)) return l.communityEditHandleBadChars;
    return null;
  }

  String? _validateDisplayName(AppLocalizations l) {
    final raw = _displayNameController.text.trim();
    if (raw.isEmpty) return l.communityEditDisplayNameRequired;
    if (raw.length > 40) return l.communityEditDisplayNameRequired;
    return null;
  }

  Future<void> _onSubmit() async {
    final l = AppLocalizations.of(context);
    final handleError = _validateHandle(l);
    final displayNameError = _validateDisplayName(l);
    setState(() {
      _handleError = handleError;
      _displayNameError = displayNameError;
    });
    if (handleError != null || displayNameError != null) return;

    final controller = ref.read(communityProfileControllerProvider.notifier);
    final isCreate = widget.mode == EditProfileMode.create;
    final result = isCreate
        ? await controller.createProfile(
            handle: CommunityHandle(_handleController.text.trim()),
            displayName: _displayNameController.text.trim(),
            visibility: _visibility,
            audienceDefault: _audienceDefault,
          )
        : await controller.updateProfile(
            displayName: _displayNameController.text.trim(),
          );
    if (_disposed) return;
    switch (result) {
      case CommunityProfileSubmitSuccess():
        if (!mounted) return;
        Navigator.of(context).pop();
      case CommunityProfileSubmitHandleTaken():
        if (!mounted) return;
        setState(() => _handleError = l.communityEditHandleTaken);
      case CommunityProfileSubmitFailure(:final error):
        if (!mounted) return;
        setState(() => _topError = _formatFailure(l, error));
      case CommunityProfileSubmitBusy():
        // Guarded above by the disabled submit button.
        break;
    }
  }

  String _formatFailure(AppLocalizations l, AppFailure error) {
    if (error is NetworkFailure) {
      return l.communityEditNetworkError;
    }
    return l.communityEditServerError;
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.isSubmitting,
    required this.isCreate,
    required this.localizations,
    required this.onPressed,
  });

  final bool isSubmitting;
  final bool isCreate;
  final AppLocalizations localizations;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SsButton(
      onPressed: onPressed,
      loading: isSubmitting,
      label: isSubmitting
          ? (isCreate
                ? localizations.communityEditSubmitting
                : localizations.communityEditUpdating)
          : (isCreate
                ? localizations.communityEditSubmit
                : localizations.communityEditUpdate),
    );
  }
}
