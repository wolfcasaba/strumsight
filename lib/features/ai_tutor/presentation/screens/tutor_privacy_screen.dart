/// Tutor Privacy (consent) screen (E04-R22 §3, design-system migration
/// E15-R09).
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
///
/// The three [SwitchListTile] consent axes are the batch brief's own named
/// exception (§3: "a privacy- és adat-képernyő consent-kapcsolói és
/// szövegei érintetlenek") — kept as plain Material widgets rather than
/// [SsSwitchRow], since ADR 0132's consent semantics are the sensitive
/// part of this screen and this round changes appearance, not behaviour.
/// Everything else uses [SsSection]/[SsSpacing] tokens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/components/surfaces/ss_section.dart';
import '../../../../core/design_system/foundations/ss_spacing.dart';
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
            padding: const EdgeInsets.all(SsSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.tutorPrivacyIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: SsSpacing.space4),
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
                const SizedBox(height: SsSpacing.space6),
                SsSection(
                  title: l10n.tutorPrivacyScopeTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        l10n.tutorPrivacyScopeBody,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: SsSpacing.space3),
                      for (final key in StorageKeys.tutorAiData)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SsSpacing.space1,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('•'),
                              const SizedBox(width: SsSpacing.space2),
                              Expanded(child: Text(key)),
                            ],
                          ),
                        ),
                      for (final key in StorageKeys.tutorAiData)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: SsSpacing.space1,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text('•'),
                              const SizedBox(width: SsSpacing.space2),
                              Expanded(
                                child: Text(
                                  StorageKeys.quarantineOf(key),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: SsSpacing.space2),
                      Text(
                        l10n.tutorPrivacyScopePreserved,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
