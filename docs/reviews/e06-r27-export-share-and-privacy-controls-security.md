# E06-R27 — Security review

- **Reviewer:** independent security pass
- **Reviewed head:** `e4b2bde5`
- **Risk:** high
- **Verdict:** BLOCKER / MAJOR findings recorded in
  `e06-r27-export-share-and-privacy-controls-review.md`.

The export has no direct network or cloud-upload path. The required correction
is to close the message-argument export boundary, avoid representing weak
confidence as a certain card fact, and ensure a write failure cannot retain a
redacted export file.
