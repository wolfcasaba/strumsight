import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _pauseKey = ValueKey('ss-session-transport-pause');
const _finishKey = ValueKey('ss-session-transport-finish');
const _finishLabel = 'Finish';

Widget _harness(
  SsSessionTransportStatus status, {
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onFinish,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SsSessionTransport(
        status: status,
        pauseLabel: 'Pause',
        resumeLabel: 'Resume',
        finishLabel: _finishLabel,
        idleLabel: 'Ready',
        disabledLabel: 'Unavailable',
        onPause: onPause,
        onResume: onResume,
        onFinish: onFinish,
      ),
    ),
  );
}

/// A signature that must be pairwise distinct across all six states for A3.
({
  bool pauseVisible,
  bool pauseEnabled,
  IconData? pauseIcon,
  bool finishVisible,
  String extraMarker,
})
_signature(WidgetTester tester) {
  final pauseFinder = find.byKey(_pauseKey);
  final finishFinder = find.byKey(_finishKey);
  final pauseVisible = pauseFinder.evaluate().isNotEmpty;
  final finishVisible = finishFinder.evaluate().isNotEmpty;

  IconData? pauseIcon;
  bool pauseEnabled = false;
  if (pauseVisible) {
    final button = tester.widget<IconButton>(pauseFinder);
    pauseEnabled = button.onPressed != null;
    pauseIcon = (button.icon as Icon).icon;
  }

  var extraMarker = 'none';
  if (tester
      .widgetList(find.byKey(const ValueKey('ss-session-transport-rest-idle')))
      .isNotEmpty) {
    extraMarker = 'rest-idle';
  } else if (tester
      .widgetList(
        find.byKey(const ValueKey('ss-session-transport-rest-disabled')),
      )
      .isNotEmpty) {
    extraMarker = 'rest-disabled';
  } else if (tester
      .widgetList(
        find.byKey(const ValueKey('ss-session-transport-count-in-marker')),
      )
      .isNotEmpty) {
    extraMarker = 'count-in-marker';
  } else if (tester
      .widgetList(
        find.byKey(const ValueKey('ss-session-transport-finishing-marker')),
      )
      .isNotEmpty) {
    extraMarker = 'finishing-marker';
  }

  return (
    pauseVisible: pauseVisible,
    pauseEnabled: pauseEnabled,
    pauseIcon: pauseIcon,
    finishVisible: finishVisible,
    extraMarker: extraMarker,
  );
}

void main() {
  group('SsSessionTransport', () {
    const activeStatuses = [
      SsSessionTransportStatus.countIn,
      SsSessionTransportStatus.active,
      SsSessionTransportStatus.paused,
      SsSessionTransportStatus.finishing,
    ];

    for (final status in activeStatuses) {
      testWidgets(
        'A2: Pause and Finish are both visible and directly actionable in '
        'the $status state',
        (tester) async {
          final handle = tester.ensureSemantics();
          var finishCount = 0;

          await tester.pumpWidget(
            _harness(status, onFinish: () => finishCount++),
          );

          expect(
            find.byKey(_pauseKey),
            findsOneWidget,
            reason: 'Pause must never be hidden in an active session state',
          );
          expect(
            find.byKey(_finishKey),
            findsOneWidget,
            reason: 'Finish must never be hidden in an active session state',
          );
          // The caption itself must be reachable in semantics WITHOUT first
          // opening a menu — an overflow menu's own tooltip is its "show
          // menu" affordance, not the caller-supplied Finish caption
          // (lessons/L403: a type/key-level check alone missed exactly this).
          expect(
            tester.getSemantics(find.byKey(_finishKey)).tooltip,
            _finishLabel,
            reason:
                'Finish must expose its own caption directly, not behind '
                'an overflow menu disclosure step',
          );
          // A single tap must invoke onFinish directly — an overflow menu
          // would only open on the first tap and require a second tap on
          // the revealed item.
          await tester.tap(find.byKey(_finishKey));
          expect(finishCount, 1);

          handle.dispose();
        },
      );
    }

    testWidgets('idle and disabled show neither Pause nor Finish', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(SsSessionTransportStatus.idle));
      expect(find.byKey(_pauseKey), findsNothing);
      expect(find.byKey(_finishKey), findsNothing);

      await tester.pumpWidget(_harness(SsSessionTransportStatus.disabled));
      expect(find.byKey(_pauseKey), findsNothing);
      expect(find.byKey(_finishKey), findsNothing);
    });

    testWidgets('tapping Pause invokes onPause only while active', (
      tester,
    ) async {
      var pauseCount = 0;
      await tester.pumpWidget(
        _harness(SsSessionTransportStatus.active, onPause: () => pauseCount++),
      );
      await tester.tap(find.byKey(_pauseKey));
      expect(pauseCount, 1);
    });

    testWidgets('tapping the paused Pause key invokes onResume', (
      tester,
    ) async {
      var resumeCount = 0;
      await tester.pumpWidget(
        _harness(
          SsSessionTransportStatus.paused,
          onResume: () => resumeCount++,
        ),
      );
      await tester.tap(find.byKey(_pauseKey));
      expect(resumeCount, 1);
    });

    testWidgets('tapping Finish invokes onFinish', (tester) async {
      var finishCount = 0;
      await tester.pumpWidget(
        _harness(
          SsSessionTransportStatus.active,
          onFinish: () => finishCount++,
        ),
      );
      await tester.tap(find.byKey(_finishKey));
      expect(finishCount, 1);
    });

    testWidgets('A3: all six transport states are pairwise distinguishable', (
      tester,
    ) async {
      final signatures = <SsSessionTransportStatus, Object?>{};

      for (final status in SsSessionTransportStatus.values) {
        await tester.pumpWidget(_harness(status));
        signatures[status] = _signature(tester);
      }

      final distinctSignatures = signatures.values.toSet();
      expect(
        distinctSignatures.length,
        SsSessionTransportStatus.values.length,
        reason:
            'every transport state must render a unique signature; '
            'collisions: $signatures',
      );
    });
  });
}
