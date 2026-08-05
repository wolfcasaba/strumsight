/// Tutor Home screen (E04-R18 §3).
///
/// The entry surface for the AI Tutor feature. Shows the localized
/// hero + a "Start conversation" CTA that pushes the Chat route. The
/// screen does NOT own any state; everything is delegated to the
/// router (navigation) and the controller (data).
///
/// Registered in [app_router.dart] behind the `aiTutorEnabled` flag.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';

class TutorHomeScreen extends StatelessWidget {
  const TutorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTutorHomeTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 24),
              Text(
                l10n.aiTutorHomeIntro,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('tutorHomeStartCta'),
                icon: const Icon(Icons.chat),
                label: Text(l10n.aiTutorHomeStart),
                onPressed: () => context.go(AppRoutes.tutorChat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
