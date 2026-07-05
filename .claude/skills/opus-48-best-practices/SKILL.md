---
name: opus-48-best-practices
description: Best practices for getting maximum value out of Claude Opus 4.8 (model ID claude-opus-4-8) — covers the five effort levels (low, medium, high, xhigh, max) and the new `high` default, adaptive thinking, fast mode, mid-conversation system messages, the lower 1,024-token prompt-cache minimum, dynamic workflows / codebase-scale migrations in Claude Code, session recaps, focus mode, task briefing patterns, subagent delegation, and verification loops. Use this skill whenever starting a new Claude Code session with Opus 4.8, configuring effort, troubleshooting slow or over-thinking behavior, migrating prompts from Opus 4.7, running long agentic tasks, or any time token usage or response quality needs tuning. Apply it proactively even if the user does not explicitly mention Opus 4.8 — if they are working in Claude Code or doing long agentic work, these practices apply.
---

# Opus 4.8 Best Practices

A compact field guide for getting the most out of Claude Opus 4.8 (`claude-opus-4-8`) in Claude Code and agentic workflows. Based on Anthropic's official "What's new in Claude Opus 4.8" docs and the Opus 4.8 launch post. Opus 4.8 is Anthropic's most capable generally available model — it builds directly on Opus 4.7.

## Core mental model

**Treat Opus 4.8 as an engineer you delegate to, not a pair-programmer you guide line by line.**

Opus 4.8 reasons after each user turn and runs long agentic loops autonomously, so fragmented back-and-forth multiplies token usage and can hurt output quality. Front-load the brief, then let it run.

Practical implications:
- Write the task, constraints, acceptance criteria, and relevant file paths in the first turn
- Batch questions into single messages rather than dripping them out
- Reduce total user turns per task
- Use auto mode to cut out permission friction on trusted tasks

---

## 1. Effort levels (5 total) — default is now `high`

Opus 4.8 has **five** effort levels. The default changed from Opus 4.7: it is now **`high`** on all surfaces, including the Claude API and Claude Code (4.7 defaulted to `xhigh`). If you set effort explicitly, your setting is unchanged.

| Level | Use when |
|-------|----------|
| `low` | Cost/latency-critical, tightly scoped work. 4.8 scopes strictly to what's asked. |
| `medium` | Simple transforms, formatting, cost-sensitive calls. |
| `high` (default) | **Balanced default for most coding and agentic work.** |
| `xhigh` | Hard problems — API design, schema migration, large codebase review. |
| `max` | Genuinely hard problems only. Prone to overthinking. Use deliberately. |

**Set it:** `/effort xhigh` mid-session.

**Practical recipe:**
- Leave it at `high` for normal work
- Raise to `xhigh` for hard codebase-wide work; `max` only for the hardest subproblem, then drop back
- Drop to `medium`/`low` for trivial transforms

**Key 4.8 behavior:** the model respects effort levels strictly, especially at the low end — at `low`/`medium` it scopes to exactly what was asked rather than going above and beyond. Good for latency/cost, but on moderately complex tasks there's a risk of under-thinking.

**If output feels shallow on a complex task:** raise the effort to `high`/`xhigh`. Don't prompt around it.
**If you're burning tokens:** lower the effort before touching prompts.

---

## 2. Adaptive thinking (only supported thinking mode)

Extended Thinking with a fixed budget is **not supported**. `thinking: {type: "enabled", budget_tokens: N}` returns a 400 error. Use adaptive thinking instead:

```python
# After (Opus 4.7 and later)
thinking = {"type": "adaptive"}
output_config = {"effort": "high"}
```

With adaptive thinking enabled, Opus 4.8 triggers reasoning **only when it judges the turn needs it** — on simple lookups and short agentic steps it responds directly; on complex multi-step problems it reasons first. This wastes **fewer thinking tokens at the same effort level** than 4.7 on bimodal workloads.

To nudge it via prompt:
- **More thinking:** "Think carefully and step-by-step before responding; this problem is harder than it looks."
- **Less thinking:** "Prioritize responding quickly rather than thinking deeply. When in doubt, respond directly."

Note: thinking is **off** unless explicitly set to `{type: "adaptive"}` in an API request (in Claude Code it's managed for you).

---

## 3. Auto mode (permission automation)

A safer middle ground than blanket permission skipping. Each proposed command runs through a classifier: safe → auto-approved, unsafe → still prompts you.

**Toggle it:** `Shift+Tab` in Claude Code.

**When to use:** long-running tasks with full context up front, parallel Claudes, refactors, deep research, feature builds.
**When NOT to use:** production-critical ops, anything touching billing/auth/prod DB without explicit review.

---

## 4. /fewer-permission-prompts (skill, not command)

A **skill** you invoke. It scans session history, finds bash/MCP commands you keep approving, and suggests adding them to your allow list. Run it once after a typical session, accept the genuinely safe ones, re-run every few weeks.

---

## 5. Session management: /recap and /focus

- **`/recap`** — short summary of what the agent just did and what's coming next. Essential for long-running sessions and reviewing async work.
- **`/focus`** — hides intermediate work, shows only the final result.

Complementary: `/focus` during the run, `/recap` after.

---

## 6. Verification loops (worth 2–3x output quality)

Giving Claude a way to verify its own work is worth 2–3x in output quality, and matters more in 4.8 because it runs longer autonomous loops.

| Task | Verification |
|------|--------------|
| Code changes | Run tests, type-check, lint |
| Performance work | Run benchmarks, compare before/after |
| Data transform | Sample rows, check schema, diff counts |
| Refactor | Full test suite + manual spot-check |
| API integration | Hit the endpoint with real payloads |
| Content generation | Grep for forbidden patterns, count sections |

Spell out the verification step in your brief. Example: *"After implementing, run `pnpm test` and iterate until all tests pass. If a test seems wrong, flag it rather than deleting it."*

---

## 7. What's new in Opus 4.8 (vs 4.7)

- **Effort default is now `high`** (was `xhigh`). See section 1.
- **Fewer wasted thinking tokens** at the same effort level (smarter per-turn thinking decisions).
- **Better tool triggering** — less likely to skip a tool call the task required (a 4.7 complaint).
- **Better compaction handling & long-context quality** — long agentic traces stay on task with fewer derailments after compaction, and fewer compactions overall.
- **Dynamic Workflows in Claude Code** — can carry out **codebase-scale migrations across hundreds of thousands of lines of code**, from kickoff to merge, using the existing test suite as the bar.
- **Mid-conversation system messages** — you can send `role: "system"` right after a user turn to append updated instructions without restating the full system prompt, preserving prompt-cache hits on earlier turns (no beta header needed).
- **Lower prompt-cache minimum: 1,024 tokens** (down from 4.7). Prompts too short to cache before can now cache with no code changes.
- **Fast mode** — research preview on the Claude API: set `speed: "fast"` for up to **2.5x** higher output tokens/sec at premium pricing.
- **Refusal `stop_details`** — now publicly documented; describes the category of a refusal so apps can route the user appropriately.

### Inherited from 4.7 (unchanged — no code changes needed)
- **Sampling params not supported:** setting `temperature`, `top_p`, or `top_k` to a non-default value returns a 400 error. Omit them; guide behavior via prompting.
- **Adaptive thinking is the only thinking-on mode** (fixed budgets → 400 error).
- **1M token context window**, **128k max output tokens**.

---

## 8. Behavior carried over from 4.7 worth remembering

- **Shorter by default on simple lookups, longer on open-ended analysis.** State a length if you need one. Positive examples beat "don't do this".
- **Fewer tool calls, more reasoning.** Ask explicitly if you want more aggressive search/file-reading.
- **Judicious about subagents.** For parallel fan-out, spell it out:
  > "Do not spawn a subagent for work you can complete directly in a single response. Spawn multiple subagents in the same turn when fanning out across items or reading multiple files."
- **Literal instruction-following.** Vague prompts produce narrow output. Be specific.

---

## 9. CLAUDE.md strategy

Put strategic context in `CLAUDE.md` once (loaded every session); per-session write only the specific task. This stops you paying the "remember what we're building" tax every turn.

---

## Quick reference cheat sheet

```
Model ID:              claude-opus-4-8
Default effort:        high   (changed from xhigh in 4.7)
Hard codebase work:    xhigh
Hardest subproblem:    max (then drop back)
Thinking:              adaptive only. Fixed budgets -> 400. Nudge via prompts.
Auto mode:             Shift+Tab
Permission cleanup:    run /fewer-permission-prompts skill
Session summary:       /recap     Hide intermediate: /focus
Prompt-cache minimum:  1,024 tokens (lower than 4.7)
Fast mode (API):       speed:"fast" -> up to 2.5x, premium pricing
Big migrations:        Dynamic Workflows (codebase-scale, test suite = bar)
Strategic context:     CLAUDE.md
Verification:          required for 2-3x quality boost
Subagents:             explicit -- "spawn when fanning out"
```

---

## Common failure modes & fixes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| "Feels slow" | Running `max`/`xhigh` by reflex | Drop to `high` (the default) |
| Shallow answers on complex task | Effort too low (`low`/`medium` scope strictly) | Raise to `high`/`xhigh` |
| Burning tokens on trivial tasks | Effort too high | Drop to `medium`/`low` |
| Narrow/literal output | Vague prompt | Specify intent, constraints, acceptance criteria |
| Skipped a needed tool call | Rare in 4.8, but possible | Name the tool/step explicitly in the brief |
| 400 error on `thinking` param | Fixed thinking budgets removed | Use `thinking:{type:"adaptive"}` + effort |
| 400 error on temperature/top_p/top_k | Sampling params unsupported | Omit them; guide via prompting |

---

## Source

- [Introducing Claude Opus 4.8](https://www.anthropic.com/news/claude-opus-4-8) (Anthropic)
- [What's new in Claude Opus 4.8](https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-8) (Anthropic docs)
- [Migrating to Claude Opus 4.8](https://platform.claude.com/docs/en/about-claude/models/migration-guide) (Anthropic docs)
- [Effort](https://platform.claude.com/docs/en/build-with-claude/effort) · [Adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/adaptive-thinking) · [Fast mode](https://platform.claude.com/docs/en/build-with-claude/fast-mode)
