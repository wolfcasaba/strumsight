# E08-R17 — Review

Brief: `docs/rounds/e08-r17-daily-quest-generator.md`
Diff: `6e4dba07...ef458418`
Reviewer: független Codex / `gpt-5.6-sol` · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A H4 self-heal után a `ef458418` Terra javítócommit mindhárom capability-
tengelyt külön, két-entrys candidate poolban méri. A kamera→account,
account→cloud és cloud→camera mutáció most egyenként a saját A3-celláját viszi
pirosra; a korábbi max-3 truncation többé nem rejti el a hibásan eligible
questet. F1 és F2 zárt, a correctness verdict APPROVED.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Teljes snapshot determinisztikus, kipinnelt seed | ✅ | 100 iteráció + két golden FNV kulcs; a korábbi `Random()` mutáció piros |
| A2 | 1–3 elem és legalább egy short | ✅ | 0/1/3/4 cellák és immutability cella zöld |
| A3 | Kamera/fiók/felhő külön fail-closed | ✅ | három izolált két-entrys pool; mindhárom cross-wiring mutáció célzottan piros |
| A4 | Nincs permission/gateway hívás | ✅ | csak caller-fed booleanok; nincs plugin, auth vagy network import |
| A5 | Planned rest optional + rest-eligible | ✅ | A5 cella zöld |
| A6 | Terv érintetlen | ✅ | implementer-fázisok scope-auditja zöld; nincs practice-generator diff/import |
| A7 | Üres/új/hiányzó terv fallback | ✅ | A7 cella zöld |
| A8 | Seed dokumentált | ✅ | `dailyQuestSeedMaterial` + FNV doc-comment és brief §10 |

## Scope-audit és jelzés

A végső Terra wrapper-jelzés `status=done`, `continuations=0`,
`scope_audit=ok`, `scope_audit_base=327b7471`, `scope_audit_changed=1`. A
reviewer ugyanarra a fázisra kézzel is ezt mérte:

```text
Legacy scope audit OK (327b7471101a..ef458418cba2, 1 changed path(s), 0 generated/ignored)
```

A jelzett `dirty_files=1` ellenére a jelzés előtti implementer-log
`git status --short` kimenete és a jelzés utáni reviewer-ellenőrzés is üres;
a commit után tracked vagy untracked eltérés nem maradt. A teljes ág auditját
a merge-elt H4 self-heal saját `HANDOFF.md`, `docs/LESSONS.md` és tooling őre
miatt fázisonként kell értelmezni: a kezdeti implementer- és az első fixer-
scope auditja szintén `ok`, az orchestrátor ADR-je és a review-jelentések nem
implementer-írások.

## Leletek

### F1 — MAJOR — Capability-tengelyeket elfedő candidate pool

- **Státusz:** FIXED (`ef458418`).
- **Javítás:** camera/account/cloud külön poolja pontosan egy local short és
  egy capability entry; a vizsgált flag false, a másik kettő true.
- **Re-review:** camera→account, account→cloud és cloud→camera egyenként
  exit 1-gyel, a megfelelő A3-cellán bukott; restore után 9/9 zöld és tiszta
  klón.

### F2 — MAJOR — Shipping default katalógus mérés nélkül

- **Státusz:** FIXED (`a8980cab`).
- **Javítás:** közvetlen exact ID-, egyediség-, short-, rest- és capability-
  contract cella méri a production factoryt; a korábbi empty-factory mutáció
  piros.

### N1 — NOTE — A 64 bites FNV signed `int` goldenje runtime-contract

A két golden érték a jelen Dart VM szemantikát rögzíti. Ha a generator később
web shipping út lesz, külön cross-runtime parity mérés indokolt.

## Gate-bizonyíték

Végső izolált klón: `/tmp/review-e08-r17-fix2.huVtks/repo`, exact
`ef458418`.

| Gate | Eredmény |
|---|---|
| format | 1767 fájl, 0 változás |
| analyze | No issues found |
| célzott teszt | 9/9 zöld |
| architecture | OK, 12 allowlisted deviation |
| secrets | 3172 fájl, 0 finding |
| l10n | 1532 message parity |
| kamera→account mutáció | PIROS az A3-camera cellán |
| account→cloud mutáció | PIROS az A3-account cellán |
| cloud→camera mutáció | PIROS az A3-cloud cellán |
| restore | teljes célzott suite 9/9 zöld; `git diff --exit-code` 0 |

## Merge-döntés

Correctness **APPROVED**. Nyitott BLOCKER/MAJOR nincs; merge csak a végső
branch SHA-n zöld Full Gate/Router CI és a landoló kombinált-HEAD gate után.
