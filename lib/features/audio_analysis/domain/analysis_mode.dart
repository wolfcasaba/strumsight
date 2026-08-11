/// Intent of an audio-analysis run (SDD Ch7 §6.1).
enum AnalysisMode { freePlay, practiceTarget, songReference, importedRecording }

/// Origin of the audio payload, kept separate from [AnalysisMode].
enum AnalysisInputSource {
  microphone,
  importedFile,
  practiceSession,
  songSession,
}
