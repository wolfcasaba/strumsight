---
name: silent-task-verification
description: Verify and log execution outcomes in heartbeat/cron tasks even when surfacing NO_REPLY to the user
version: 1.0.0
---

> **使用前确认**：是否已了解本 skill 的适用场景？触发词是否匹配？
---|---------|
| 命令执行失败 | 检查依赖是否安装、路径是否正确 |
| API 调用失败 | 检查网络连接、API Key 配置、请求参数 |
| 文件不存在 | 确认工作目录和相对路径是否正确 |

category: workflow
---

# Silent Task Verification

Pattern: cron/heartbeat tasks with `--save-only` flag (producing `NO_REPLY`) must still verify script execution occurred, not assume silence equals success. The agent should explicitly log execution outcome even when surfacing nothing to user.

## Why This Matters

Silent output (`NO_REPLY`) is appropriate for routine checks with no action taken. However, **silence ≠ success**. A script may:
- Fail to run due to missing dependencies
- Hit a permission error
- Produce empty results that were misinterpreted as "nothing needed"

Without explicit logging, there is **zero traceability** for what actually happened.

## Verification Checklist

Before surfacing `NO_REPLY`, confirm:

1. **Script executed** — no missing file / interpreter / permission errors
2. **Logic ran** — conditions were actually evaluated
3. **Result is genuinely "do nothing"** — not an error disguised as empty result
4. **Outcome logged** — execution record written to tool-records or daily log

## Logging Template

```bash
# After script execution, write a log entry
LOG_FILE="$HOME/.openclaw/workspace/memory/tool-records/$(date +%Y-%m-%d).md"
TS=$(date '+%Y-%m-%d %H:%M')

echo "[$TS] heartbeat_check: ran=t/f result=<outcome> status=<success|error|skipped>" >> "$LOG_FILE"
```

## Minimal Logging One-Liner

```bash
# Capture result inline — works in most cron/heartbeat contexts
RESULT=$(python3 /path/to/check.py 2>&1); STATUS=$?; echo "[$(date)] exit=$STATUS result=$RESULT" >> ~/.openclaw/workspace/memory/tool-records/$(date +%Y-%m-%d).md
```

## Anti-Pattern

```
❌ Script runs with --save-only
   → NO_REPLY surfaced
   → No log written
   → Silent failure on next invocation — zero evidence of what happened
```

## Correct Pattern

```
✅ Script runs
   → Result captured
   → Exit code verified
   → Outcome logged to tool-records/
   → NO_REPLY surfaced (if genuinely no action needed)
```

## Rule of Thumb

**Any automated task that runs without human oversight must leave an execution trail, regardless of whether it reports to the user.**