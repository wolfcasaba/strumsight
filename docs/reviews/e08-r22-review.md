# E08-R22 — Review

Brief: `docs/rounds/e08-r22-reward-inbox-and-celebration.md` (§0.0 pre-flight + §0.0.1 mid-round l10n-fragment revision)
Diff: `git diff 241834e3..6a8c865c` (pre-flight commit → round-branch tip), branch `minimax/e08-r22-reward-inbox-and-celebration`
Reviewer: Claude Sonnet 5 (`--effort high`) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Egy kör-közbeni javítás történt, mindkettő mérve, dokumentálva, és a
javítás a review-independens gate-újrafutáson igazoltan zöld:

- **Gate-alak-false-positive (nem valódi hiba):** a wrapper `gate_shape`
  őre `VIOLATION`-t jelzett, mert az implementer egy `cat
  tools/round-gate.sh | head -80; echo "---"; ls -la tools/` parancsot
  futtatott (a SCRIPT FORRÁSÁNAK olvasása, nem a gate futtatása) — a
  heurisztika `round-gate\.sh[^\n]*\| *head` mintája erre is illeszkedik.
  A log 7 tényleges `tools/round-gate.sh <teszt> 2>&1` hívása mind
  csonkítás/lánc nélküli volt. Verifikálva: `grep` a nyers log
  `tool_use` Bash-parancsaira (lásd alább).
- **Valódi l10n-regresszió, egy kör-közbeni javító futással zárva:** az
  első implementer-futás (`e197d69e`-ig) a 12 új kulcsot a GENERÁLT
  aggregátumba (`lib/l10n/app_{en,hu}.arb`) írta a forrás-fragmentum
  (`lib/l10n/features/gamification_{en,hu}.arb`) helyett — ugyanaz a
  hibaosztály, mint az E08-R20 §0.0.1 (L396). A `flutter gen-l10n`
  friss futása felülírta volna az aggregátumot, a kulcsok eltűntek volna
  → `analyze` 11 `undefined_getter` hibát adott volna. Egy §0.0.1
  mid-round brief-revízió (`37714ae5`, `allowed_paths` bővítve a
  fragmentum-fájlokkal + `tool/gen_l10n_segments.dart`-tal) + egy javító
  kör (`4e697358`…`6a8c865c`) a kulcsokat a forrásba tette, az
  aggregátumot `tool/gen_l10n_segments.dart --write`-tal regenerálta, és
  a §10 handoffot az igazolt zöld gate-re írta át. A javítás után
  **saját, izolált /tmp klónban futtatott gate mind a 6 lépésen zöld**
  (lásd „Gate-bizonyíték ellenőrzése").

### F-NOTE — a gate_shape false-positive megérdemelne egy szűkebb regex-et

- **Fájl:** `tools/mm-round.sh:382` (és `tools/codex-round.sh:334` — azonos minta)
- **Megfigyelés:** a `round-gate\.sh[^\n]*(\| *(tail|head)|&&)` egysoros
  regex nem különbözteti meg a gate TÉNYLEGES futtatását (csonkítva) a
  script FORRÁSÁNAK puszta elolvasásától (`cat tools/round-gate.sh |
  head`). Ez a kör esetében ártalmatlan false-positive volt (a mérce
  maga megkülönböztethető volt a 7 tényleges hívás vizsgálatával), de
  jövőbeli körökben egy automatikus H-döntést hozhat téves alapon, ha
  valaki a `gate_shape` mezőt vakon HALT-jelzésként kezelné.
- **Kötelező javítás:** nem e kör dolga (`tools/` tilos zóna) — follow-up
  a lánc-eszközök karbantartóinak: a regex csak akkor illeszkedjen, ha a
  `round-gate.sh` szó a parancs ELSŐ tokenje (tényleges hívás), ne
  bármilyen egysoros előfordulásra.
- **Státusz:** NOTE, nem blokkol — a review saját független gate-futása
  a tényleges bizonyíték, nem a `gate_shape` mező.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Aktív gyakorlás közben SEMMILYEN ünneplés nem jelenik meg | ✅ | `celebration_coordinator_test.dart` 3 cella zöld + **reviewer-saját valódi-sértés próba**: `if (isActiveSession)` → `if (false)` a 215. soron → 7 teszt PIROSRA vált (A1×3, A1-real-violation, A3×1 kaszkád, A8×1 kaszkád, §6.1 fölött+session×1); visszaállítás után 18/18 zöld |
| A2 | A session végén a jutalmak ÖSSZEVONTAN jelennek meg | ✅ | `A2: three events delivered while inactive drain into one summary` zöld |
| A3 | A jutalom a főkönyvben van, MIELŐTT a postaládába kerül | ✅ | `RewardEvent` konstruktor eldobja az üres `sourceLedgerId`-t (kötelező, nem-üres mező — a „már jóváírt" tény típus-szinten kikényszerítve, nem csak konvencióval); a koordinátor importjai között nincs `RewardLedgerRepository` (`head -20 celebration_coordinator.dart` — csak a saját domain-fájl) |
| A4 | A postaláda-elem NEM jár le, nincs begyűjtés-gomb | ✅ | `RewardInboxItem` mezői: `id, event, addedAt, seen` — nincs `expiresAt`/`claimedAt`/`claimState`; `grep -ni "claim\|collect\|expir"` a screen/sheet fájlokban csak doc-comment negatív állítást ad (a kód TÉNYLEGESEN nem ajánl ilyen műveletet) |
| A5 | Háttérben/bezárt folyamatban keletkezett jutalom megjelenik | ✅ | `A5: events arriving after the app wakes up follow the same rules` zöld |
| A6 | A prioritási sorrend determinisztikus és tesztelt | ✅ | `rewardPriorityIndex` explicit `switch` (nem `Map`-bejárás) — `masteryMilestone(3) > levelUp(2) > {quest,challenge}(1) > daily(0)`; 2 teszt (mindkét beszúrási irányból) zöld |
| A7 | Reduced motion: statikus, de teljes információ | ✅ | `MediaQuery.disableAnimationsOf(context)` (`reward_summary_sheet.dart:60`) + `AnimatedSize` — a `summary.events` teljes payloadot ad, nincs csonkítás; teszt zöld |
| A8 | A postaláda tartós app-újraindítás után | ✅ | `toJson`/`fromJson` round-trip 2 teszt zöld |
| §6.1 | Küszöb-hármas: alatt/rajta/fölött, inkluzív határ | ✅ | 4 dedikált teszt (alatt-összevon, rajta-összevon [inkluzív], fölött-külön, fölött+session→inbox) mind zöld |

## Scope-audit

```
python3 tools/scope-audit.py --repo <impl-workdir> --brief docs/rounds/e08-r22-reward-inbox-and-celebration.md --base 241834e3
→ Legacy scope audit OK (241834e3abf1..6a8c865c5b2a, 11 changed path(s), 0 generated/ignored)
```

Engedélyezett fájlokon kívüli változás: **nincs**. A `§0.0.1` mid-round
revízió (`37714ae5`) a `lib/l10n/features/gamification_{en,hu}.arb` és a
`tool/gen_l10n_segments.dart` útvonalakat előre, dokumentáltan bővítette
be az `allowed_paths`-ba — az E08-R20 §0.0.1 azonos mintáját követve —,
tehát a fragmentum-fájlok módosítása scope-on BELÜLI, nem H3.

`git diff 241834e3..6a8c865c --stat`: 11 fájl, mind a (revideált)
`allowed_paths` listán — 4 új domain/application/presentation fájl, 1
barrel-bővítés (4 sor), 4 ARB (2 aggregátum + 2 fragmentum), 1 teszt, 1
brief.

## Architektúra és termékhatárok

- `celebration_coordinator.dart` egyetlen importja `../domain/profile/
  reward_inbox_item.dart` — nincs Flutter-, Riverpod- vagy
  `RewardLedgerRepository`-import (ADR 0389 1–2. döntés tartva; pure Dart
  application-réteg, a többi gamification application-fájl mintáját
  követve).
- `dart run tool/check_architecture.dart` → „Architecture dependencies OK
  (12 allowlisted deviation(s))" — a `git diff` a `tool/`-ban (az
  architektúra-allowlistben) semmit nem módosított, tehát mind a 12
  meglévő, e körtől független deviáció.
- `dart run tool/ci/check_secrets.dart` → 0 találat.
- Haptika/hang: `RewardSummaryFeedback.hapticsEnabled/soundEnabled`
  caller-fed bool paraméterek, alapértéken `true` — nincs élő
  settings-provider-import, az ADR 0389 6. döntésének megfelelően (a
  valós wiring Kör 27 dolga).

## Megállapítások

Nincs nyitott BLOCKER/MAJOR/MINOR. Lásd fent az F-NOTE-ot (gate_shape
regex, follow-up a lánc-eszközök karbantartóinak, nem e kör rése).

## Gate-bizonyíték ellenőrzése

Saját, izolált klón (`git clone --branch minimax/e08-r22-reward-inbox-and-celebration https://github.com/wolfcasaba/strumsight.git /tmp/review-e08-r22`, HEAD `6a8c865c`), `tools/prepare-flutter-generated.sh` után:

| Gate | Állított eredmény | Ellenőrizve |
|---|---|---|
| format | zöld | ✅ saját futás |
| analyze | zöld (0 issue) | ✅ saját futás |
| test `celebration_coordinator_test.dart` | 18/18 zöld | ✅ saját futás, **plusz** reviewer-saját valódi-sértés próba (fent) |
| architecture | zöld (12 allowlisted deviation) | ✅ saját futás |
| secrets | zöld (3210 file, 0 finding) | ✅ saját futás |
| l10n | zöld (aggregate freshness OK, parity OK en→hu, 1584 message) | ✅ saját futás |
| scope-audit | OK, 11 changed, 0 violation | ✅ saját futás (`tools/scope-audit.py`) |
| CI (teljes suite + property + APK) | — | ⏳ merge előtt dispatch-elendő, lásd Merge-döntés |

## Merge-döntés

A helyi gate mind a 6 eleme zöld, saját kézzel, izolált klónban
igazolva; a scope-audit tiszta; az acceptance criteria mind bizonyítékkal
zárt (beleértve a reviewer-saját A1 valódi-sértés próbáját). ADR 0052
szerint a helyi kapu elégséges a CI-dispatch elindításához — a **teljes
suite + randomizált property + APK/full-gate CI-futás** a merge
előfeltétele, azt az orchestrátor a review után dispatch-eli és a merge
SHA-ján ellenőrzi (lásd a kör-jelentésben).
