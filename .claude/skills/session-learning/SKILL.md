---
name: session-learning
description: Active learning loop for recipewiser-mobile — at session start surface relevant prior lessons (auto-memory + Viking), after any non-trivial fix extract+log the lesson into the file-memory, and sync cross-project ones to the shared Viking brain. Prevents lesson loss across sessions and shares lessons with the web app + Hermes.
trigger_keywords:
  - "tanulj"
  - "rögzítsd"
  - "tanulság"
  - "új lesson"
  - "session vége"
auto_invoke:
  - session_start (MEMORY.md is auto-loaded → viking_search recent)
  - after_bugfix (any commit with "fix(" prefix → evaluate for logging)
  - after_verify_fail (any `flutter test` / `flutter analyze` fail with a new root cause → evaluate)
---

# Session Learning Skill (mobile)

Active memory system for recipewiser-mobile. Two memory layers:
- **Local file-memory** (per-project, auto-loaded): `~/.claude-rc-mobile/projects/-home-ubuntu-recipewiser-mobile/memory/` — `MEMORY.md` index + one file per fact (frontmatter `name`/`description`/`metadata.type`). See the Memory section in the system prompt for the exact format.
- **Viking shared brain** (cross-project, `mcp__viking__*`): the SAME memory the web app (`~/Recipewiser`) and the Hermes bot use. Cross-cutting lessons go here so all three learn. See the `viking-shared-brain` memory + CLAUDE.md.

Runs in 3 modes:

## Mode 1: SESSION START (auto)

`MEMORY.md` is already injected into context at session start. On top of that, BEFORE diving into the task:

```
1. Skim the injected MEMORY.md index — note any file relevant to the task.
2. mcp__viking__viking_search(query="<first user message keywords>", limit=5)
3. If the request names a specific feature/file, Read the matching memory file
   and grep the codebase (or `SCOPE=<name> node tools/flutter-rag.mjs "<query>"`).
4. Verify anything a recalled memory claims about a file/flag still exists before acting on it.
```

This surfaces non-obvious knowledge deliberately instead of rediscovering it.

## Mode 2: AFTER A FIX / PATTERN DISCOVERY (semi-auto)

After a non-trivial change, evaluate if it is lesson-worthy.

**Lesson-worthy criteria (ANY one triggers logging):**

- Bug fix that took > 2 iterations to find
- A pattern reused across 2+ files / features
- A gotcha that surprised you (non-obvious from the code) — esp. the silent `try/catch(_){}` no-op class, wrong Supabase table/column names, Riverpod 3 footguns
- A `flutter test` / `flutter analyze` failure with a new root cause
- A build/env/ops fix (OOM on this ARM box, win32/device_info_plus, golden-test env flakiness)
- Anything the user explicitly says "tanulj ebből" / "rögzítsd"

**Action:**

1. Write a memory file in the local file-memory dir using the project memory format
   (frontmatter `name`/`description`/`metadata.type: feedback|project|reference`; body with
   **Why:** / **How to apply:** for feedback/project; link related with `[[slug]]`).
2. Add a one-line pointer to `MEMORY.md`.
3. If the lesson is cross-project (applies to the web app too, or is a backend/Supabase/AI-route
   truth, or a workflow rule), ALSO call `mcp__viking__viking_remember` so the web app + Hermes inherit it.
   Tag with the feature/module name.

Don't duplicate what the repo already records (code structure, git history, CLAUDE.md). If asked to
remember something obvious, capture what was *non-obvious* about it instead.

## Mode 3: SESSION END (manual)

When the user says "session vége" / "/learn-session":

1. `git log --oneline origin/master..HEAD` to see what was done this session.
2. For each commit ask: "Is there a generalizable lesson here?"
3. Log the ones that pass the criteria (Mode 2).
4. `mcp__viking__viking_session_commit` to persist the Viking session (entity extraction + long-term save).

## Promotion rules

If a lesson is referenced in **3+** future sessions:
1. Add a one-line summary to `CLAUDE.md` (e.g. a "Common pitfalls" note).
2. Keep the detailed memory file as the reference.
3. Avoid CLAUDE.md bloat — the 3-use threshold matters.

## Anti-patterns to avoid

- ❌ Logging every commit — only lesson-worthy ones (criteria above).
- ❌ Writing lessons that just restate the commit message — focus on the WHY / root cause.
- ❌ Long generic lessons — one insight per file, keep it tight.
- ❌ Forgetting Viking sync for cross-project lessons — without it the web app + Hermes won't learn.
- ❌ Trusting optimistic UI as proof a backend write worked — a wrong table name silently no-ops (see CLAUDE.md). Prove persistence before logging "fixed".
- ❌ Promoting too eagerly to CLAUDE.md — respect the 3-use threshold.
