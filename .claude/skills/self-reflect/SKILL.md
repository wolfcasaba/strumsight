---
name: self-reflect
description: Autonomous self-reflection — mines patterns from past sessions, discovers blind spots, auto-generates new learning rules. Can run manually or via weekly cron.
version: 1.0.0
author: system
---

# Self-Reflect Skill

Autonomous self-improvement by mining failures and patterns.

## When to trigger
- Weekly cron (Sundays 03:00)
- After a session with 3+ tool errors
- After a session where user corrected you 2+ times
- When explicitly asked: "reflektálj" / "mit tanultál?"

## Steps

### Step 1: Gather evidence
Run these in parallel:
- viking_search("AVOID") — find all stored avoid-patterns
- viking_search("POSITIVE") — find all reinforced patterns
- viking_search("correction") — find user corrections
- session_search("mistake OR error OR wrong") — find failures

### Step 2: Analyze patterns
Ask viking_reasoning:
- "What are my 3 biggest blind spots based on stored AVOID patterns?" (level=high)
- "What do I do well based on POSITIVE patterns?" (level=medium)
- "What corrections from the user have I received more than once?" (level=high)

### Step 3: Generate new rules
For each blind spot discovered:
- Check: is this already in META_LEARNING.md?
- If NO: append as new numbered rule
- Store: viking_remember(content="RULE: [description]", category="pattern")

For each repeated success:
- Store: viking_conclude("REINFORCED: [pattern] — proven effective")

### Step 4: Cleanup
- Remove obsolete AVOID patterns (if user later said it's OK)
- Merge duplicate patterns
- Cap patterns at 50 total (beyond that, consolidate)

### Step 5: Report (optional)
If triggered by cron → send Telegram summary:
"Heti tanulás összefoglaló:
- X új szabályt tanultam
- Y mintát megerősítettem  
- Z vakfoltot fedeztem fel
- Top tanulság: [legfontosabb]"
