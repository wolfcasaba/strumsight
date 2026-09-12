/// Which channel the beat may be delivered in, right now.
///
/// ## Why this is a decision and not a setting
///
/// Three of the four rhythm modes declare `needsMetronome: true`, and the app ships
/// a metronome — but the click goes into the same room the microphone is scoring.
/// `test/features/live/metronome_click_pollution_test.dart` measured what that
/// costs, feeding the SHIPPED click through the real pipeline:
///
///   - **The chord survives.** This was the risk I expected and the measurement
///     falsified: the click is a 1000 Hz sine, 1000 Hz is about B5, and B is a
///     chord tone of both E minor and G — yet chord identity never changed at any
///     click level, confirmed-frame counts moved by at most 1 in ~200, and clicks
///     alone name no chord at all, even at full scale.
///   - **The onset detector hears every click.** Clicks alone, with no guitar in
///     the signal: **15 reported strums from 16 clicks**, at every level down to a
///     gain of 0.1. A click lands exactly on the beat, which is exactly where the
///     grid expects a stroke — so a learner who played nothing would be credited
///     with a full, perfectly timed attempt.
///
/// So the channel depends on what is being measured at that instant, and the rule is
/// small enough to state exhaustively and test exhaustively. That is why it lives
/// here as a pure function rather than inside a widget's tick callback, where the
/// one case that matters would be the hardest to reach.
///
/// Pure Dart: no Flutter, no clock (AGENTS.md §6).
library;

/// How a beat may be delivered.
enum CurriculumPulse {
  /// Nothing at all.
  none,

  /// The audible click.
  click,

  /// The audible click, accented for beat 1 of the bar.
  accentClick,

  /// A haptic pulse: felt, and inaudible to the microphone.
  haptic,

  /// A stronger haptic pulse for beat 1 of the bar.
  accentHaptic;

  bool get isAudible =>
      this == CurriculumPulse.click || this == CurriculumPulse.accentClick;

  bool get isHaptic =>
      this == CurriculumPulse.haptic || this == CurriculumPulse.accentHaptic;
}

/// What the learner is doing at this beat.
enum CurriculumPulsePhase {
  /// Being counted in. Nothing here is scored: `RhythmCountIn.countsTowardAttempt`
  /// drops every stroke before bar 1.
  countIn,

  /// The app is playing the pattern for the learner to hear
  /// (`rhythm_demonstration.dart`). Nothing is scored, and the pattern itself is the
  /// sound.
  demonstration,

  /// The scored attempt. Anything the microphone hears can be credited to a slot.
  scoredAttempt,

  /// A calibration run, which measures the gap between what the learner SEES and
  /// what the engine REPORTS.
  calibration,
}

/// The pulse allowed at this beat, or [CurriculumPulse.none].
///
/// [muted] is the learner's own metronome preference, and it silences BOTH
/// channels. One switch, deliberately: someone who turns the metronome off wants no
/// pulse, and a second preference for a channel they cannot compare would be a
/// setting nobody can answer.
CurriculumPulse curriculumPulseFor({
  required CurriculumPulsePhase phase,
  required bool isDownbeat,
  required bool muted,
}) {
  if (muted) return CurriculumPulse.none;
  switch (phase) {
    case CurriculumPulsePhase.countIn:
      // Audible, and this is where every metronome-practice method puts the pulse:
      // establish the beat BEFORE anything has to be played on it. Safe because
      // nothing here is scored.
      return isDownbeat ? CurriculumPulse.accentClick : CurriculumPulse.click;
    case CurriculumPulsePhase.demonstration:
      // NOTHING from the metronome. Not for safety — nothing is scored here — but
      // because the demonstration's own strokes are already clicks, and a beat click
      // in the SAME timbre on top of them would make the pattern unreadable: the
      // learner could not tell which click was a stroke and which was the pulse.
      // Metre is carried instead by accenting beat 1 of each demonstrated bar.
      return CurriculumPulse.none;
    case CurriculumPulsePhase.scoredAttempt:
      // Felt, not heard. An audible click here would be counted as a stroke on the
      // very beat it marks — 15 false strums from 16 clicks, measured.
      return isDownbeat ? CurriculumPulse.accentHaptic : CurriculumPulse.haptic;
    case CurriculumPulsePhase.calibration:
      // NOTHING. Two reasons, and either alone is sufficient. The calibrator
      // registers taps from `latestStrumTime`, and the measurement above says
      // clicks produce those — so an audible pulse would have the device
      // calibrating against its own metronome. And any pulse at all gives the
      // learner something other than the pendulum to follow, when the pendulum is
      // precisely the thing being calibrated against.
      return CurriculumPulse.none;
  }
}
