import '../../practice_generator/public.dart'
    show
        CapabilitySupport,
        ExerciseCapabilities,
        ExerciseCapability,
        allCapabilitiesUnsupported;

/// What THIS environment can actually measure, as the curriculum's gate needs it.
///
/// ## Why the default is "unsupported" and every `supported` is argued
///
/// `missionAvailability` refuses to offer a mission whose success criteria this
/// environment cannot measure, because offering it would mean scoring nothing or
/// scoring something else (design §4). That protection is only worth having if
/// the capability map is honest, and the failure mode is asymmetric: claiming a
/// capability we do not have hands the learner a score that means nothing, while
/// withholding one we do have merely hides a rung. So the map starts from
/// [allCapabilitiesUnsupported] and each `supported` below carries its reason.
///
/// Pure: no Flutter, no providers, no I/O. The one runtime fact it needs —
/// whether audio is arriving — is passed in.
ExerciseCapabilities curriculumDeviceCapabilities({
  required bool microphoneListening,
}) {
  final capabilities = allCapabilitiesUnsupported();

  void support(ExerciseCapability capability) =>
      capabilities[capability] = CapabilitySupport.supported;

  // --- always true of this app ---------------------------------------------

  // The whole recognition path is on-device DSP; there is no cloud inference in
  // the scoring loop.
  support(ExerciseCapability.supportsOffline);
  // Both are shipped app-wide settings, not per-exercise features.
  support(ExerciseCapability.supportsLeftHandedUi);
  support(ExerciseCapability.supportsReducedMotion);
  // The rhythm exercise repeats a bar for the length of an attempt.
  support(ExerciseCapability.supportsLoop);

  // --- true only while audio is arriving ------------------------------------

  if (microphoneListening) {
    support(ExerciseCapability.requiresMicrophone);
    // MEASURED, not assumed. Strum direction: the engine publishes a strum only
    // once its direction is confirmed, and onset placement was measured at
    // 0.0-3.4 ms against synthesised ground truth. Chords: 7/7 on the seven
    // labelled real-guitar recordings
    // (`test/tooling/live_chord_wav_probe_test.dart`), and 7/7 on modelled audio
    // including the minors the course teaches first.
    support(ExerciseCapability.supportsDirectionScoring);
    support(ExerciseCapability.supportsChordScoring);
    // The engine reports bpm, measured within 1% on two labelled recordings.
    support(ExerciseCapability.supportsTempo);
  }

  // --- deliberately left unsupported ---------------------------------------
  //
  // `requiresCamera`: there is no camera-based scoring in this app.
  //
  // `supportsPitchScoring`: the tuner measures pitch, but no exercise has ever
  // been SCORED on pitch here, and the real-audio probe found median deviations
  // of +4.3 cents on material that decoded badly — so there is no evidence that
  // a pitch score would mean what a learner would read into it.
  //
  // `requiresBackingTrack` / `requiresSongAsset`: a mission needing either is
  // about content this function cannot see. Whoever adds such a rung must teach
  // this function how to check for it, rather than have it guess true.

  return capabilities;
}
