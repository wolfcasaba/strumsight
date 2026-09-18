# StrumSight — Serena project overview (pointer memory)

Offline, on-device guitar chord + strum-direction detector. Flutter (Dart ^3.12.2),
Material 3, Riverpod 3 hand-written providers (NO codegen), go_router, feature-first
tree under `lib/features/<feature>/`, ARB i18n (en, hu; generated
`lib/l10n/app_localizations.dart` is gitignored — run `flutter gen-l10n` after merges).

The binding rules live in the repo, not here:
- `HANDOFF.md` — live status, what is next (read first every session)
- `AGENTS.md` — agent rulebook (scope, gate §12, git, roles §15)
- `.claude/skills/strumsight-tooling/SKILL.md` — when to use Serena vs the Dart MCP
  server vs golden tests vs integration_test, with the measured traps of this box

Serena-specific: the Dart language server here is the project's own SDK (3.12.2) via a
junction under `~/.serena/language_servers/static/DartLanguageServer/dart-sdk`; the
60 s initial-analysis timeout warning at activation is expected, symbols resolve fine
afterwards. Run only ONE Serena instance per checkout — the Dart analysis server
crashes under concurrent agent runs.
