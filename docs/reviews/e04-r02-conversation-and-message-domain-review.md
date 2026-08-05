# Review — E04-R02 (Tutor conversation & message domain)

- **Kör:** E04-R02 · **Branch:** `codex/e04-r02-conversation-and-message-domain`
- **Implementer:** Codex (`gpt-5.6-terra`, örökölt kézi override) ·
  **Reviewer/orchestrátor:** Claude (Opus 4.8), független, read-only
- **Reviewelt HEAD:** `e6cccbe` · **Baseline:** `main` @ `dd7712d`
- **Dátum:** 2026-08-04
- **Verdikt:** **APPROVED** — 0 BLOCKER, 0 MAJOR, 0 MINOR, 3 NOTE

## 1. Jelzés + handoff

`.codex-round-status`: `status=done`, `head=e6cccbe`, worktree tiszta (a
`dirty_files=1` a jelzéskori időzítés maradványa; a review-kori `git status`
tiszta). A §10 handoff kitöltve, tényszerű (RED = fordítási hiba az impl előtt,
GREEN = 39/39, coverage 246/253 = 97,23% domain-only). **Semmit nem fogadtam el
bemondásra** — a gate-et, coverage-et és a mutáció-diszkriminációt magam mértem.

## 2. Gate-újrafuttatás (izolált /tmp klón)

`git clone --branch … /tmp/review-e04-r02`, `tools/prepare-flutter-generated.sh`,
majd:

```
tools/round-gate.sh test/features/ai_tutor/domain test/features/ai_tutor/data
```

→ **MINDEN GATE ZÖLD**: format, analyze, test (domain), test (data), architecture
(„Architecture dependencies OK (12 allowlisted deviation(s))"). 39 célzott teszt.

## 3. Scope-audit

`git diff --name-status main..HEAD` — **minden fájl az engedélyezett listán belül**:
7 új `lib/features/ai_tutor/{domain/models,data/local}` fájl, 3 új teszt, és a
brief (§10 handoff). **`public.dart` ÜRES** (`library;`, nulla direktíva) →
a §0.0 (5) halasztás betartva, a lezárt R01 `ai_tutor_boundary_test.dart`
**érintetlen és zöld**. `tool/`, `.github/`, más feature belső contractja:
**érintetlen**. Listán kívüli fájl: nincs.

## 4. Acceptance criteria (tételesen, bizonyítékkal)

| # | Kritérium | Bizonyíték | ✔ |
|---|---|---|---|
| 1 | Typed ID validáció (trim/üres/max), literális kódkészlet | `tutor_conversation_test.dart:13/35/49/62/82` — `tutorId.empty`/`tooLong`, max-hossz trim után | ✔ |
| 2 | Conversation+message round-trip bit-stabil; ordering stabil | codec round-trip teszt + **Probe C** (ordering mutáció → RED) | ✔ |
| 3 | Unknown-block mátrix (ismert→dekódol; ismeretlen→placeholder, tesztelt); nincs néma eldobás/crash | `unknown blocks` group (decode placeholder + re-encode) + **Probe A** (data-loss mutáció → RED) | ✔ |
| 4 | Cancelled ÉS failed külön, round-tripel | `codec_test.dart:87` külön delivery-state round-trip | ✔ |
| 5 | UTC timestamp policy; nagy Unicode round-trip | `_requiredUtcTimestamp` `Z`-kényszer + non-UTC reject teszt; `codec_test.dart:68` Unicode | ✔ |
| 6 | Domain Flutter-független (kör-lokális purity-scanner zöld); ≥90% coverage | **Probe B** (flutter import a domainbe → purity teszt RED); független coverage **94,88%** (domain+data, 408/430) | ✔ |

## 5. Próbatesztek (eldobható mutációk — a klónban, visszaállítva)

A brief §6 megköveteli, hogy a reviewer a codec egy központi invariánsát
eldobható mutációval pirosra váltsa. Három mutációt futtattam, mindegyik a helyes
tesztet vitte RED-be (a klón utána `git status` tiszta):

1. **Unknown-block adatvesztés** — a `_blockToMap` unknown-ága a `rawJson`-t
   eldobja (`{'type': originalType}`): analyze tiszta (csak unused-var warning),
   a teszt RED: *„unknown blocks re-encodes a decoded unknown block instead of
   dropping it"*. → a forward-compat invariáns gépi mérce alatt.
2. **Valódi purity-sértés** — `import 'package:flutter/material.dart';` a
   `tutor_content_block.dart`-ba: a kör-lokális scanner RED: *„Domain purity …
   no framework, storage, or cross-feature imports"*. → a §0.0 (2) feloldás
   (a `tool/check_architecture.dart` NEM fedi az ai_tutor-t, ezért kör-lokális
   scanner) **valóban gépi mérce**, nem díszlet.
3. **Ordering neutralizálása** — `_orderMessages` kihagyása: RED: *„orders
   messages by stable sequence"*. → a stabil sequence-rendezés mérve.

## 6. Architektúra + termékhatárok (AGENTS.md §5/§6)

- Domain Flutter-/Riverpod-/Dio-/storage-mentes (Probe B + architecture gate).
- Nincs `public.dart` cross-feature szivárgás (üres boundary).
- Nincs mic/audio/hálózat/secret érintés — tiszta value-domain (§0.0 (3) N/A).
- Determinisztikus: nincs `DateTime.now()`/`Random()`/`Stopwatch()` a domainben
  (a purity-scanner ezt is méri); az idő paraméter, UTC-re normalizálva.
- Immutable modellek, `List.unmodifiable` mindenhol, value-equal `==`/`hashCode`.

## 7. NOTE-ok (nem blokkolnak, follow-up)

- **NOTE-1:** `TutorTurn` és `TutorResponseMode` a conversation-codecben NINCS
  szerializálva (ez a kör a conversation-envelope-ot perzisztálja; a turn
  orchestration-korreláció). A turn csak value-equality teszttel fedett, codec
  round-trip nélkül — a jövő turn-perzisztencia köre pótolja.
- **NOTE-2:** Az unknown-block kulcssorrend a bemenet beszúrási sorrendjét
  őrzi (nem rendezett), míg az ismert blockoké fix. Round-trip-stabil és
  forward-compat szempontból helyes; kanonizálás nem lehetséges ismeretlen
  struktúrán. Csak megjegyzés.
- **NOTE-3:** `public.dart` boundary-export a §0.0 (5) szerint R13/R17+-ra
  halasztva; a §4 ai-router TOML `allowed_paths` továbbra is listázza a
  `public.dart`-ot (nem használt engedély — a scope-auditot nem sérti).

## 8. Merge-döntés

Zöld kapu (ADR 0052): lokális gate zöld (független klón), scope tiszta, minden
acceptance mérve, 3 mutáció diszkriminál. Hátravan: az exact-`headSha` CI
(`build-apk.yml`, run 30961670640) success. Annak zöldjével → squash-merge külön
jóváhagyás nélkül; utána a merge-elt `main`-en a gate független újrafuttatása.
