#!/usr/bin/env python3
"""Munkastílus-elemzés egy MiniMax-kör stream-json logjából (ADR 0069).

    python3 tools/mm-trace.py /tmp/mm-<kör>.log [--steps N]

Nem a KIMENETET nézi (azt a review nézi), hanem a MUNKAMÓDSZERT: mire megy el a
lépés, hol hibázik a tool-használatban, mit olvas újra fölöslegesen, mikor futtat
gate-et. Ebből lesznek a brief-szabályok.
"""

import json
import sys
from collections import Counter, defaultdict

log_path = sys.argv[1]
show_steps = 0
if "--steps" in sys.argv:
    show_steps = int(sys.argv[sys.argv.index("--steps") + 1])

tools = Counter()
reads = Counter()
writes = Counter()
edits = Counter()
bash_cmds = []
errors = []
steps = []
usage = {"in": 0, "out": 0, "cache_read": 0, "turns": 0}
pending = {}

for line in open(log_path, errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue

    message = event.get("message") or {}
    if message.get("usage"):
        u = message["usage"]
        usage["turns"] += 1
        usage["in"] += u.get("input_tokens", 0)
        usage["out"] += u.get("output_tokens", 0)
        usage["cache_read"] += u.get("cache_read_input_tokens", 0)

    for block in message.get("content", []) or []:
        if not isinstance(block, dict):
            continue
        kind = block.get("type")
        if kind == "tool_use":
            name = block.get("name", "?")
            args = block.get("input") or {}
            tools[name] += 1
            pending[block.get("id")] = (name, args)
            path = args.get("file_path") or args.get("path") or ""
            if name == "Read":
                reads[path] += 1
            elif name == "Write":
                writes[path] += 1
            elif name in ("Edit", "MultiEdit"):
                edits[path] += 1
            elif name == "Bash":
                bash_cmds.append(args.get("command", ""))
            detail = path or args.get("command") or args.get("pattern") or ""
            steps.append(f"{name}: {str(detail)[:100]}")
        elif kind == "tool_result" and block.get("is_error"):
            name, args = pending.get(block.get("tool_use_id"), ("?", {}))
            content = block.get("content")
            if isinstance(content, list):
                content = " ".join(
                    c.get("text", "") for c in content if isinstance(c, dict)
                )
            errors.append((name, str(args.get("file_path") or args.get("command") or "")[:70],
                           str(content)[:200].replace("\n", " ")))

print("=== tool-használat ===")
for name, count in tools.most_common():
    print(f"  {count:4}  {name}")

print("\n=== token-mérleg ===")
print(f"  asszisztens-lépés: {usage['turns']}")
print(f"  output token:      {usage['out']:,}")
print(f"  cache-read input:  {usage['cache_read']:,}")

print("\n=== többször olvasott fájlok (fölösleges újraolvasás?) ===")
repeats = [(p, c) for p, c in reads.most_common() if c > 1]
print("  (nincs)" if not repeats else "")
for path, count in repeats[:12]:
    print(f"  {count}x  {path.split('/')[-1]}")

print("\n=== ugyanarra a fájlra Write UTÁN Edit (átírás-körök) ===")
churn = [(p, writes[p], edits[p]) for p in set(writes) | set(edits) if writes[p] + edits[p] > 1]
print("  (nincs)" if not churn else "")
for path, w, e in sorted(churn, key=lambda x: -(x[1] + x[2]))[:12]:
    print(f"  write={w} edit={e}  {path.split('/')[-1]}")

print("\n=== hibás tool-hívások ===")
print(f"  összesen: {len(errors)}")
for name, target, text in errors[:12]:
    print(f"  - {name} [{target}]\n      {text}")

gate_words = ("flutter test", "flutter analyze", "dart format")
gates = [c for c in bash_cmds if any(w in c for w in gate_words)]
print("\n=== gate-futtatások sorrendben ===")
for cmd in gates:
    print(f"  {cmd[:120]}")

signals = [c for c in bash_cmds if "codex-signal" in c]
print("\n=== kör-jelzések ===")
print("  (még nincs)" if not signals else "")
for cmd in signals:
    print(f"  {cmd[:160]}")

if show_steps:
    print(f"\n=== utolsó {show_steps} lépés ===")
    for step in steps[-show_steps:]:
        print(f"  {step}")
