// Nothing a learner reads may be a persistence code.
//
// This is the guard that makes `curriculum_names.dart`'s fallback unreachable in
// shipped content. The fallback exists because a token on screen is worse than a
// vague label — a learner cannot tell a token from a typo — but it must never
// actually be what anybody sees. So these cells walk the SHIPPED course and fail
// if any id falls through, which turns "added a rung and forgot to name it" into a
// red test instead of `mission.xyz` appearing in front of a beginner.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/curriculum/data/beginner_course.dart';
import 'package:strumsight/features/curriculum/presentation/curriculum_names.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// Every skill id the ladder can put on screen: the ones a rung trains (shown as
/// what has been measured) and the ones a gate names (shown after "Needs first").
Set<String> _referencedSkillIds() => {
  for (final mission in beginnerCourse().missionsInOrder) ...[
    ...mission.trainedSkillIds,
    ...mission.unlock.prerequisiteSkillIds,
  ],
};

void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    group('${locale.languageCode}: every shipped id has a name', () {
      late AppLocalizations l10n;

      setUp(() async {
        l10n = await AppLocalizations.delegate.load(locale);
      });

      test('every mission', () {
        final unnamed = <String>[];
        for (final mission in beginnerCourse().missionsInOrder) {
          final name = curriculumMissionName(l10n, mission.missionId);
          if (name == l10n.curriculumUnnamedStep || name == mission.missionId) {
            unnamed.add(mission.missionId);
          }
        }
        expect(
          unnamed,
          isEmpty,
          reason:
              'a rung with no name shows a persistence code or a placeholder to '
              'a beginner; name it in the curriculum arb segment',
        );
      });

      test('every stage', () {
        final unnamed = <String>[];
        for (final stage in beginnerCourse().stages) {
          final name = curriculumStageName(l10n, stage.stageId);
          if (name == l10n.curriculumUnnamedStep || name == stage.stageId) {
            unnamed.add(stage.stageId);
          }
        }
        expect(unnamed, isEmpty);
      });

      test('every skill the ladder can name', () {
        final unnamed = <String>[];
        for (final skillId in _referencedSkillIds()) {
          final name = curriculumSkillName(l10n, skillId);
          if (name == l10n.curriculumUnnamedSkill || name == skillId) {
            unnamed.add(skillId);
          }
        }
        expect(
          unnamed,
          isEmpty,
          reason:
              '"Needs first: chord.emToAm" tells a learner nothing they can act '
              'on; name every referenced skill',
        );
      });

      test('no name is a persistence code in disguise', () {
        // A name that still contains a dotted id has been half-converted: the
        // visible half would read as the internals it was meant to replace.
        final suspicious = <String>[];
        for (final mission in beginnerCourse().missionsInOrder) {
          final name = curriculumMissionName(l10n, mission.missionId);
          if (name.contains('mission.') ||
              name.contains('chord.') ||
              name.contains('rhythm.') ||
              name.contains('strumPattern.') ||
              name.contains('songPerformance.')) {
            suspicious.add('${mission.missionId} -> $name');
          }
        }
        for (final skillId in _referencedSkillIds()) {
          final name = curriculumSkillName(l10n, skillId);
          if (name.contains('.')) suspicious.add('$skillId -> $name');
        }
        expect(suspicious, isEmpty);
      });

      test('names are distinct, so two rungs cannot read as the same one', () {
        final names = [
          for (final mission in beginnerCourse().missionsInOrder)
            curriculumMissionName(l10n, mission.missionId),
        ];
        expect(
          names.toSet(),
          hasLength(names.length),
          reason:
              'two rungs sharing a name would make the ladder ambiguous about '
              'which one a tap opens',
        );
      });
    });
  }

  test('the supported locales are the two this app ships', () {
    // The loop above is only a guarantee for the locales it runs over, so the set
    // it runs over is pinned: a third locale must make this fail rather than
    // silently skip the whole guard.
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'hu'},
    );
  });
}
