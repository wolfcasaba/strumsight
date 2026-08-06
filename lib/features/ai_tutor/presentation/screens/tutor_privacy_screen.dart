/// Tutor Privacy (consent) screen (E04-R22 §3).
///
/// Presents the three granular consent axes from
/// `tutorConsentControllerProvider` as independent switches (ADR 0132).
/// Toggling any one axis leaves the other two untouched — enforced by
/// the model's own grant/revoke copy-methods (R03). Below the switches
/// the screen renders the EXACT delete-all scope list
/// (`StorageKeys.tutorAiData` + each `.corrupt` quarantine shadow) so
/// the user can see what "Delete all AI data" actually deletes.
///
/// Pure presentation: the screen reads/writes the consent controller
/// only. Persistence is a future cross-feature concern (§0.0).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_keys.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/tutor_privacy_providers.dart';

class TutorPrivacyScreen extends ConsumerWidget {
  const TutorPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(tutorConsentControllerProvider);
    final controller = ref.read(tutorConsentControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tutorPrivacyTitle)),
      body: SafeArea(
        child: Semantics(
          container: true,
          label: l10n.tutorPrivacyScreenSemantics,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.tutorPrivacyIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  key: const Key('tutorConsentAxisModelUse'),
                  title: Text(l10n.tutorConsentAxisModelUseTitle),
                  subtitle: Text(l10n.tutorConsentAxisModelUseBody),
                  value: consent.modelUseGranted,
                  onChanged: (value) => value
                      ? controller.grantModelUse()
                      : controller.revokeModelUse(),
                ),
                SwitchListTile(
                  key: const Key('tutorConsentAxisPersistentStorage'),
                  title: Text(l10n.tutorConsentAxisPersistentStorageTitle),
                  subtitle: Text(l10n.tutorConsentAxisPersistentStorageBody),
                  value: consent.persistentStorageGranted,
                  onChanged: (value) => value
                      ? controller.grantPersistentStorage()
                      : controller.revokePersistentStorage(),
                ),
                SwitchListTile(
                  key: const Key('tutorConsentAxisEvaluationWithRedaction'),
                  title: Text(
                    l10n.tutorConsentAxisEvaluationWithRedactionTitle,
                  ),
                  subtitle: Text(
                    l10n.tutorConsentAxisEvaluationWithRedactionBody,
                  ),
                  value: consent.evaluationWithRedactionGranted,
                  onChanged: (value) => value
                      ? controller.grantEvaluationWithRedaction()
                      : controller.revokeEvaluationWithRedaction(),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.tutorPrivacyScopeTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tutorPrivacyScopeBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final key in StorageKeys.tutorAiData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('•'),
                        const SizedBox(width: 8),
                        Expanded(child: Text(key)),
                      ],
                    ),
                  ),
                for (final key in StorageKeys.tutorAiData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('•'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            StorageKeys.quarantineOf(key),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  l10n.tutorPrivacyScopePreserved,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
