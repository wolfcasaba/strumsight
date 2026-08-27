import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/settings/screens/vision_privacy_screen.dart';
import 'package:strumsight/features/vision/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../core/storage/in_memory_key_value_store.dart';

void main() {
  testWidgets(
    'delete all needs confirmation before raw Vision data is removed',
    (tester) async {
      final store = InMemoryKeyValueStore();
      final repository = VisionSessionRepository(store: store);
      await repository.save(
        _result(),
        modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
      );
      store.writeLog.clear();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: VisionPrivacyScreen(
            repository: repository,
            export: VisionExport(store: store),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('visionPrivacyDeleteAll')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('visionPrivacyDeleteAllConfirm')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.readString(StorageKeys.visionSessionHistory), isNotNull);
      expect(store.writeLog, isEmpty, reason: 'cancel must not call deletion');

      await tester.tap(find.byKey(const Key('visionPrivacyDeleteAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('visionPrivacyDeleteAllConfirm')));
      await tester.pumpAndSettle();
      expect(store.readString(StorageKeys.visionSessionHistory), isNull);
      expect(store.readString(StorageKeys.visionCalibration), isNull);
    },
  );
}

VisionSessionResult _result() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('privacy-screen'),
    startedAt: DateTime.utc(2026, 8, 8),
  ),
  endedAt: DateTime.utc(2026, 8, 8, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 0,
);
