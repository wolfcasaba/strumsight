# E06-R27 — Independent review

- **Review base:** `6e13e635`
- **Reviewed head:** `e4b2bde5`
- **Scope audit:** PASS — 20 changed paths, all covered by the brief or review exemption.
- **Independent gate:** PASS — `tools/round-gate.sh test/features/audio_analysis test/property test/app test/features/share` (format, analyze, four test targets, architecture, secrets, l10n).
- **Verdict:** CHANGES REQUESTED — 1 BLOCKER, 2 MAJOR.

## Findings

### BLOCKER — export allowlist is open through message arguments

`RedactionPolicy` copies arbitrary `AnalysisInsight.messageArgs` and
`AnalysisWarning.messageArgs`, while the codec emits those maps unchanged.
Both source types accept an unrestricted `Map<String, String>`, so a filename,
raw-audio payload, device id, or diagnostic value can be carried through an
otherwise allowlisted export. The property fixture only creates known keys and
does not falsify this path.

Required correction: omit arbitrary message arguments or use a finite,
message-key-specific argument allowlist. Add tests injecting forbidden strings
through **both** insight and warning arguments.

### MAJOR — available metrics can still be low-confidence facts on the card

`ShareCardBuilder` admits every `CapabilityStatus.available` metric without
checking its `confidence`. `AnalysisMetricResult` permits available metrics at
zero confidence, so the card represents an uncertain value as an ordinary
fact. Apply an explicit confidence rule (exclude or visibly mark it) and add
the boundary tests.

### MAJOR — write failure can strand a redacted temp export

`ExportAnalysisUseCase.share` writes the file before entering
`ShareService.shareExportFile`'s `try/finally`. A partial or failing write
therefore never reaches the service cleanup contract. Make cleanup cover file
creation/write/share and test a forced write failure.

## Notes

- No new Dio, HTTP, core-network import, or cloud upload was found.
- `fileNameGenerator` is injectable but accepts unchecked separators; retain
  injection only for trusted composition or constrain generated names.
